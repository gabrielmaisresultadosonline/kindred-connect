import express from 'express';
import http from 'http';
import { Server } from 'socket.io';
import cors from 'cors';
import dotenv from 'dotenv';
import path from 'path';
import fs from 'fs';
import multer from 'multer';
import axios from 'axios';
import { Client, LocalAuth, MessageMedia } from 'whatsapp-web.js';
import qrcode from 'qrcode';
import ffmpeg from 'fluent-ffmpeg';
import ffmpegPath from 'ffmpeg-static';
import * as proxyManager from './proxyManager.js';

dotenv.config();
ffmpeg.setFfmpegPath(ffmpegPath);

const app = express();
const server = http.createServer(app);
const io = new Server(server, {
    cors: { origin: "*" }
});

const PORT = process.env.PORT || 3000;
const __dirname = path.resolve();

app.use(cors());
app.use(express.json());
app.use(express.static('Public'));

// --- Utility Functions ---

function generateId() {
    return Math.random().toString(36).substr(2, 9);
}

function normalizeBoolean(val, fallback = false) {
    if (typeof val === 'boolean') return val;
    if (val === 'true') return true;
    if (val === 'false') return false;
    return fallback;
}

// --- Persistence Helpers ---

function readJson(file) {
    const filePath = path.join(__dirname, 'data', file);
    if (!fs.existsSync(filePath)) return null;
    return JSON.parse(fs.readFileSync(filePath, 'utf8'));
}

function writeJson(file, data) {
    const filePath = path.join(__dirname, 'data', file);
    fs.writeFileSync(filePath, JSON.stringify(data, null, 2));
}

// --- Auth Middleware & Logic ---

const usersStore = () => readJson('users.json') || [];
const tokensStore = () => readJson('auth_tokens.json') || [];

function createAuthToken(user) {
    const token = generateId() + generateId();
    const tokens = tokensStore();
    tokens.push({ token, userId: user.id, isAdmin: user.isAdmin, expires: Date.now() + 86400000 });
    writeJson('auth_tokens.json', tokens);
    return token;
}

function validateAuthToken(token) {
    const tokens = tokensStore();
    return tokens.find(t => t.token === token && t.expires > Date.now());
}

const requireUser = (req, res, next) => {
    const token = req.headers.authorization?.split(' ')[1];
    const session = validateAuthToken(token);
    if (!session) return res.status(401).json({ error: 'Unauthorized' });
    req.user = usersStore().find(u => u.id === session.userId);
    next();
};

// --- WhatsApp Clients State ---
const clients = new Map();

// --- API Routes ---

app.post('/api/auth/register', (req, res) => {
    const { name, email, promoCode } = req.body;
    if (promoCode !== process.env.TEST_PROMO_CODE) return res.status(400).json({ error: 'Invalid promo code' });
    
    let users = usersStore();
    let user = users.find(u => u.email === email);
    if (!user) {
        user = { id: generateId(), name, email, promoCode, isAdmin: false };
        users.push(user);
        writeJson('users.json', users);
    }
    const token = createAuthToken(user);
    res.json({ token, user });
});

app.post('/api/auth/login', (req, res) => {
    const { email, promoCode } = req.body;
    const user = usersStore().find(u => u.email === email && u.promoCode === promoCode);
    if (!user) return res.status(401).json({ error: 'Invalid credentials' });
    const token = createAuthToken(user);
    res.json({ token, user });
});

app.get('/api/me', requireUser, (req, res) => {
    res.json(req.user);
});

// --- WhatsApp Logic ---

async function initializeClient(sessionId) {
    if (clients.has(sessionId)) return clients.get(sessionId);

    const proxy = proxyManager.getProxyForSession(sessionId);
    const client = new Client({
        authStrategy: new LocalAuth({ clientId: sessionId }),
        puppeteer: {
            headless: true,
            args: [
                '--no-sandbox',
                '--disable-setuid-sandbox',
                `--proxy-server=${proxy.host}:${proxy.port}`
            ]
        }
    });

    client.on('qr', async (qr) => {
        const qrImage = await qrcode.toDataURL(qr);
        io.to(sessionId).emit('qr-generated', { qr: qrImage });
    });

    client.on('ready', () => {
        console.log(`Client ${sessionId} is ready!`);
        const sessions = readJson('sessions.json') || [];
        const sessIndex = sessions.findIndex(s => s.id === sessionId);
        if (sessIndex > -1) {
            sessions[sessIndex].status = 'connected';
            sessions[sessIndex].lastConnected = Date.now();
        } else {
            sessions.push({ id: sessionId, status: 'connected', lastConnected: Date.now() });
        }
        writeJson('sessions.json', sessions);
        io.to(sessionId).emit('client-ready', { sessionId });
    });

    client.on('message_create', async (msg) => {
        handleIncomingMessage(sessionId, msg);
    });

    client.on('disconnected', (reason) => {
        console.log(`Client ${sessionId} disconnected:`, reason);
        clients.delete(sessionId);
        io.to(sessionId).emit('session-status', { status: 'disconnected' });
    });

    clients.set(sessionId, client);
    client.initialize().catch(err => {
        console.error(`Failed to initialize client ${sessionId}:`, err);
        clients.delete(sessionId);
    });

    return client;
}

async function handleIncomingMessage(sessionId, msg) {
    // Save to history
    saveMessageToHistory(sessionId, msg.from, msg);
    
    // Emit to UI
    io.to(sessionId).emit('new-message', { chatId: msg.from, message: msg });

    // --- Automation Flows ---
    const flows = (readJson('flows.json') || {})[sessionId] || [];
    const triggerFlow = flows.find(f => 
        f.trigger && msg.body.toLowerCase().includes(f.trigger.toLowerCase())
    );

    if (triggerFlow) {
        for (const action of triggerFlow.actions) {
            if (action.type === 'message') {
                await clients.get(sessionId).sendMessage(msg.from, action.content);
            } else if (action.type === 'wait') {
                await new Promise(r => setTimeout(r, action.duration * 1000));
            }
        }
    }

    // --- AI Processing ---
    const aiConfig = (readJson('ai_config.json') || {})[sessionId];
    if (aiConfig && aiConfig.enabled && !msg.fromMe && !triggerFlow) {
        processAiMessage(sessionId, msg.from, clients.get(sessionId), msg.body);
    }
}

function saveMessageToHistory(sessionId, chatId, msg) {
    const historyDir = path.join(__dirname, 'data', 'history', sessionId);
    if (!fs.existsSync(historyDir)) fs.mkdirSync(historyDir, { recursive: true });
    
    const historyFile = path.join(historyDir, `${chatId.replace(/[^a-zA-Z0-9]/g, '_')}.json`);
    const history = fs.existsSync(historyFile) ? JSON.parse(fs.readFileSync(historyFile, 'utf8')) : [];
    history.push({
        id: msg.id.id,
        body: msg.body,
        from: msg.from,
        to: msg.to,
        fromMe: msg.fromMe,
        timestamp: msg.timestamp,
        type: msg.type
    });
    fs.writeFileSync(historyFile, JSON.stringify(history.slice(-100), null, 2)); // Keep last 100
}

// AI Message Processing
async function processAiMessage(sessionId, chatId, client, userText) {
    const aiConfig = (readJson('ai_config.json') || {})[sessionId];
    if (!aiConfig) return;

    try {
        const apiKey = aiConfig.provider === 'deepseek' ? process.env.DEEPSEEK_API_KEY : process.env.OPENAI_API_KEY;
        const apiUrl = aiConfig.provider === 'deepseek' ? 'https://api.deepseek.com/v1/chat/completions' : 'https://api.openai.com/v1/chat/completions';
        
        const response = await axios.post(apiUrl, {
            model: aiConfig.provider === 'deepseek' ? 'deepseek-chat' : process.env.OPENAI_CHAT_MODEL,
            messages: [
                { role: 'system', content: aiConfig.instructions || 'You are a helpful assistant.' },
                { role: 'user', content: userText }
            ]
        }, {
            headers: { 'Authorization': `Bearer ${apiKey}` }
        });

        const reply = response.data.choices[0].message.content;
        await client.sendMessage(chatId, reply);
    } catch (err) {
        console.error('AI Error:', err.response?.data || err.message);
    }
}

// --- API Routes Continued ---

app.post('/api/create-session', requireUser, async (req, res) => {
    const sessionId = req.user.id; // Using user ID as session ID for simplicity
    await initializeClient(sessionId);
    res.json({ sessionId });
});

app.get('/api/active-sessions', requireUser, (req, res) => {
    const sessions = readJson('sessions.json') || [];
    res.json(sessions.filter(s => clients.has(s.id)));
});

// --- Google Contacts Sync (Placeholder) ---
app.get('/api/google/auth-url', requireUser, (req, res) => {
    // This would typically use googleapis library to generate an auth URL
    res.json({ url: `https://accounts.google.com/o/oauth2/v2/auth?client_id=${process.env.GOOGLE_CLIENT_ID}&redirect_uri=${process.env.GOOGLE_REDIRECT_URI}&response_type=code&scope=https://www.googleapis.com/auth/contacts.readonly` });
});

app.post('/api/google/sync', requireUser, async (req, res) => {
    const { code } = req.body;
    // Here you would exchange the code for tokens and fetch contacts
    res.json({ success: true, message: 'Contacts sync initiated' });
});

// ... Socket.IO Handlers ...
io.on('connection', (socket) => {
    socket.on('bind-session', (sessionId) => {
        socket.join(sessionId);
        if (clients.has(sessionId)) {
            socket.emit('session-status', { status: 'connected' });
        }
    });

    socket.on('get-chats', async (sessionId) => {
        const client = clients.get(sessionId);
        if (client) {
            try {
                const chats = await client.getChats();
                socket.emit('chats-loaded', chats.map(c => ({
                    id: c.id._serialized,
                    name: c.name,
                    unreadCount: c.unreadCount,
                    timestamp: c.timestamp,
                    lastMessage: c.lastMessage ? { body: c.lastMessage.body } : null
                })));
            } catch (err) {
                console.error('Error getting chats:', err);
            }
        }
    });

    socket.on('get-kanban-columns', (sessionId) => {
        const kanban = readJson('kanban.json') || {};
        socket.emit('kanban-columns', kanban[sessionId] || [
            { id: 'todo', name: 'A fazer', chats: [] },
            { id: 'doing', name: 'Em atendimento', chats: [] },
            { id: 'done', name: 'Finalizado', chats: [] }
        ]);
    });

    socket.on('save-kanban-columns', ({ sessionId, columns }) => {
        const kanban = readJson('kanban.json') || {};
        kanban[sessionId] = columns;
        writeJson('kanban.json', kanban);
        socket.emit('kanban-columns-updated');
    });

    socket.on('get-chat-history', ({ sessionId, chatId }) => {
        const historyDir = path.join(__dirname, 'data', 'history', sessionId);
        const historyFile = path.join(historyDir, `${chatId.replace(/[^a-zA-Z0-9]/g, '_')}.json`);
        if (fs.existsSync(historyFile)) {
            const history = JSON.parse(fs.readFileSync(historyFile, 'utf8'));
            socket.emit('chat-history', { chatId, history });
        } else {
            socket.emit('chat-history', { chatId, history: [] });
        }
    });

    socket.on('get-ai-config', (sessionId) => {
        const aiConfig = readJson('ai_config.json') || {};
        socket.emit('ai-config-data', aiConfig[sessionId] || { enabled: false, provider: 'openai' });
    });

    socket.on('save-ai-config', ({ sessionId, config }) => {
        const aiConfig = readJson('ai_config.json') || {};
        aiConfig[sessionId] = config;
        writeJson('ai_config.json', aiConfig);
        socket.emit('ai-config-saved');
    });

    socket.on('get-tags', (sessionId) => {
        const tags = readJson('tags.json') || {};
        socket.emit('tags-list', tags[sessionId] || []);
    });

    socket.on('save-tags', ({ sessionId, tags }) => {
        const allTags = readJson('tags.json') || {};
        allTags[sessionId] = tags;
        writeJson('tags.json', allTags);
        socket.emit('tags-updated');
    });

    socket.on('get-flows', (sessionId) => {
        const flows = readJson('flows.json') || {};
        socket.emit('flows-list', flows[sessionId] || []);
    });

    socket.on('save-flow', ({ sessionId, flow }) => {
        const flows = readJson('flows.json') || {};
        if (!flows[sessionId]) flows[sessionId] = [];
        const index = flows[sessionId].findIndex(f => f.id === flow.id);
        if (index > -1) flows[sessionId][index] = flow;
        else flows[sessionId].push(flow);
        writeJson('flows.json', flows);
        socket.emit('flows-list', flows[sessionId]);
    });

    socket.on('send-message', async ({ sessionId, chatId, content }) => {
        const client = clients.get(sessionId);
        if (client) {
            try {
                await client.sendMessage(chatId, content);
            } catch (err) {
                console.error('Error sending message:', err);
            }
        }
    });
});

const restoreSessions = async () => {
    const sessions = readJson('sessions.json') || [];
    for (const sess of sessions) {
        if (sess.status === 'connected') {
            console.log(`Restoring session ${sess.id}...`);
            await initializeClient(sess.id).catch(e => console.error(`Failed to restore ${sess.id}`, e));
        }
    }
};

restoreSessions();

// Initialize server
server.listen(PORT, () => {
    console.log(`ZAPMRO CLOUD running on port ${PORT}`);
});


