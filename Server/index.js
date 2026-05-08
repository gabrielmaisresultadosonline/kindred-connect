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

// Database Helpers (JSON)
const db = {
    load: (file) => JSON.parse(fs.readFileSync(`./data/${file}.json`, 'utf8') || '[]'),
    save: (file, data) => fs.writeFileSync(`./data/${file}.json`, JSON.stringify(data, null, 2)),
    ensure: (file, defaultVal = '[]') => { if(!fs.existsSync(`./data/${file}.json`)) fs.writeFileSync(`./data/${file}.json`, defaultVal); }
};

['flows', 'ai_config', 'scheduled_messages', 'kanban', 'tags', 'contacts', 'winback_campaigns'].forEach(f => db.ensure(f));

// --- IA LOGIC ---
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
    } catch (e) {
        console.error('AI Error:', e);
    }
}

// --- FLOW LOGIC ---
async function handleFlows(sessionId, chatId, message, client) {
    const flows = db.load('flows').filter(f => f.sessionId === sessionId && f.active);
    for (const flow of flows) {
        if (flow.trigger === message.body.toLowerCase()) {
            for (const step of flow.steps) {
                if (step.delay) await new Promise(r => setTimeout(r, step.delay * 1000));
                await client.sendMessage(chatId, step.content);
            }
        }
    }
}

// --- WHATSAPP CORE ---
async function getProfilePic(client, contactId) {
    try {
        const url = await client.getProfilePicUrl(contactId);
        return url || 'https://ui-avatars.com/api/?name=' + encodeURIComponent(contactId) + '&background=random';
    } catch (e) { return 'https://ui-avatars.com/api/?name=User&background=ccc'; }
}

app.post('/api/whatsapp/connect', async (req, res) => {
    const { sessionId } = req.body;
    if (clients.has(sessionId)) return res.json({ ok: true, status: 'ALREADY_CONNECTED' });

    const client = new Client({
        authStrategy: new LocalAuth({ clientId: sessionId }),
        puppeteer: { headless: true, args: ['--no-sandbox', '--disable-setuid-sandbox'] }
    });

    client.on('qr', async (qr) => {
        const qrImage = await qrcode.toDataURL(qr);
        io.to(sessionId).emit('qr', qrImage);
    });

    client.on('ready', () => io.to(sessionId).emit('ready'));

    client.on('message', async (msg) => {
        io.to(sessionId).emit('new-message', {
            from: msg.from,
            body: msg.body,
            fromMe: msg.fromMe,
            timestamp: msg.timestamp,
            type: msg.type
        });
        
        // Ativar IA e Fluxos
        handleFlows(sessionId, msg.from, msg, client);
        handleAI(sessionId, msg.from, msg, client);
    });

    client.initialize().catch(e => console.error(e));
    clients.set(sessionId, client);
    res.json({ ok: true });
});

// --- API ROUTES ---
app.get('/api/whatsapp/chats', async (req, res) => {
    const client = clients.get(req.query.sessionId);
    if (!client) return res.status(404).send();
    const chats = await client.getChats();
    const result = await Promise.all(chats.slice(0, 40).map(async c => ({
        id: c.id._serialized,
        name: c.name,
        pic: await getProfilePic(client, c.id._serialized),
        unread: c.unreadCount,
        isGroup: c.isGroup
    })));
    res.json(result);
});

app.post('/api/whatsapp/send', async (req, res) => {
    const { sessionId, to, message } = req.body;
    const client = clients.get(sessionId);
    if (client) {
        await client.sendMessage(to, message);
        res.json({ ok: true });
    } else res.status(404).send();
});

// --- KANBAN & CRM ROUTES ---
app.get('/api/crm/kanban', (req, res) => res.json(db.load('kanban')));
app.post('/api/crm/kanban', (req, res) => { db.save('kanban', req.body); res.json({ok:true}); });

// --- AGENDAMENTOS ---
setInterval(async () => {
    const now = Date.now();
    let scheds = db.load('scheduled_messages');
    for (let i = 0; i < scheds.length; i++) {
        const s = scheds[i];
        if (s.time <= now && !s.sent) {
            const client = clients.get(s.sessionId);
            if (client) {
                await client.sendMessage(s.to, s.message);
                s.sent = true;
            }
        }
    }
    db.save('scheduled_messages', scheds);
}, 60000);

io.on('connection', s => s.on('join', id => s.join(id)));
server.listen(PORT, '0.0.0.0', () => console.log('🚀 ZAPMRO CRM & AI ONLINE'));
