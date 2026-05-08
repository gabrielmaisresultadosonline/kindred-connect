import express from 'express';
import http from 'http';
import { Server } from 'socket.io';
import cors from 'cors';
import path from 'path';
import fs from 'fs';
import pkg from 'whatsapp-web.js';
const { Client, LocalAuth, MessageMedia } = pkg;
import qrcode from 'qrcode';
import axios from 'axios';
import { OpenAI } from 'openai';
import multer from 'multer';

const app = express();
const server = http.createServer(app);
const io = new Server(server, { 
    cors: { origin: "*" },
    maxHttpBufferSize: 1e8 
});
const PORT = 3000;

app.use(cors());
app.use(express.json());
app.use(express.static('Public'));

const clients = new Map();
const upload = multer({ dest: 'Public/uploads/' });

const db = {
    load: (file) => {
        try {
            if(!fs.existsSync(\`./data/\${file}.json\`)) return [];
            const data = fs.readFileSync(\`./data/\${file}.json\`, 'utf8');
            return data ? JSON.parse(data) : [];
        } catch (e) { return []; }
    },
    save: (file, data) => {
        if(!fs.existsSync('./data')) fs.mkdirSync('./data');
        fs.writeFileSync(\`./data/\${file}.json\`, JSON.stringify(data, null, 2));
    },
    ensure: (file, defaultVal = '[]') => { 
        if(!fs.existsSync('./data')) fs.mkdirSync('./data');
        if(!fs.existsSync(\`./data/\${file}.json\`)) fs.writeFileSync(\`./data/\${file}.json\`, defaultVal); 
    }
};

['flows', 'ai_config', 'scheduled_messages', 'kanban', 'tags', 'contacts', 'winback_campaigns', 'settings'].forEach(f => db.ensure(f));

async function handleAI(sessionId, chatId, message, client) {
    const aiConfig = db.load('ai_config').find(c => c.sessionId === sessionId);
    if (!aiConfig || !aiConfig.enabled) return;
    try {
        const openai = new OpenAI({ apiKey: aiConfig.apiKey });
        const response = await openai.chat.completions.create({
            model: aiConfig.model || "gpt-3.5-turbo",
            messages: [{ role: "system", content: aiConfig.prompt || "Você é um assistente comercial profissional." }, { role: "user", content: message.body }],
        });
        const reply = response.choices[0].message.content;
        await client.sendMessage(chatId, reply);
    } catch (e) { console.error('AI Error:', e); }
}

async function handleFlows(sessionId, chatId, message, client) {
    const flows = db.load('flows').filter(f => f.sessionId === sessionId && f.active);
    for (const flow of flows) {
        if (flow.trigger && message.body.toLowerCase().includes(flow.trigger.toLowerCase())) {
            for (const step of flow.steps) {
                if (step.delay) await new Promise(r => setTimeout(r, step.delay * 1000));
                await client.sendMessage(chatId, step.content);
            }
        }
    }
}

async function getProfilePic(client, contactId) {
    try {
        const url = await client.getProfilePicUrl(contactId);
        return url || \`https://ui-avatars.com/api/?name=\${encodeURIComponent(contactId)}&background=random\`;
    } catch (e) { return 'https://ui-avatars.com/api/?name=User&background=ccc'; }
}

app.post('/api/whatsapp/connect', async (req, res) => {
    const { sessionId } = req.body;
    if (clients.has(sessionId)) {
        const existing = clients.get(sessionId);
        if (existing.info) return res.json({ ok: true, status: 'CONNECTED' });
    }
    const client = new Client({
        authStrategy: new LocalAuth({ clientId: sessionId }),
        puppeteer: { 
            headless: true, 
            args: ['--no-sandbox', '--disable-setuid-sandbox', '--disable-dev-shm-usage', '--disable-gpu'] 
        }
    });
    client.on('qr', async (qr) => {
        const qrImage = await qrcode.toDataURL(qr);
        io.to(sessionId).emit('qr', qrImage);
    });
    client.on('ready', () => io.to(sessionId).emit('ready'));
    client.on('message', async (msg) => {
        const chat = await msg.getChat();
        io.to(sessionId).emit('new-message', {
            from: msg.from,
            body: msg.body,
            fromMe: msg.fromMe,
            timestamp: msg.timestamp,
            type: msg.type,
            author: msg.author,
            chatName: chat.name
        });
        if (!msg.fromMe) {
            handleFlows(sessionId, msg.from, msg, client);
            handleAI(sessionId, msg.from, msg, client);
        }
    });
    client.on('disconnected', () => {
        clients.delete(sessionId);
        io.to(sessionId).emit('disconnected');
    });
    client.initialize().catch(e => console.error(e));
    clients.set(sessionId, client);
    res.json({ ok: true });
});

app.get('/api/whatsapp/chats', async (req, res) => {
    const { sessionId } = req.query;
    const client = clients.get(sessionId);
    if (!client || !client.info) return res.json([]);
    try {
        const chats = await client.getChats();
        const result = await Promise.all(chats.slice(0, 50).map(async c => ({
            id: c.id._serialized,
            name: c.name || c.id.user,
            pic: await getProfilePic(client, c.id._serialized),
            unread: c.unreadCount,
            isGroup: c.isGroup,
            timestamp: c.timestamp
        })));
        res.json(result);
    } catch (e) { res.json([]); }
});

app.post('/api/whatsapp/send', async (req, res) => {
    const { sessionId, to, message } = req.body;
    const client = clients.get(sessionId);
    if (client && client.info) {
        try {
            await client.sendMessage(to, message);
            res.json({ ok: true });
        } catch (e) { res.status(500).json({ error: e.message }); }
    } else res.status(404).json({ error: 'Client not connected' });
});

app.get('/api/db/:file', (req, res) => res.json(db.load(req.params.file)));
app.post('/api/db/:file', (req, res) => { db.save(req.params.file, req.body); res.json({ok:true}); });

setInterval(async () => {
    const now = Math.floor(Date.now() / 1000);
    let scheds = db.load('scheduled_messages');
    let changed = false;
    for (let s of scheds) {
        if (s.time <= now && !s.sent) {
            const client = clients.get(s.sessionId);
            if (client && client.info) {
                try {
                    await client.sendMessage(s.to, s.message);
                    s.sent = true;
                    changed = true;
                } catch (e) { console.error('Schedule send error:', e); }
            }
        }
    }
    if (changed) db.save('scheduled_messages', scheds);
}, 30000);

io.on('connection', s => {
    s.on('join', id => {
        s.join(id);
        const client = clients.get(id);
        if (client && client.info) s.emit('ready');
    });
});

server.listen(PORT, '0.0.0.0', () => console.log('🚀 ZAPMRO CRM & AI ONLINE'));
