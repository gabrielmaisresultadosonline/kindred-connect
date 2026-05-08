import express from 'express';
import http from 'http';
import { Server } from 'socket.io';
import cors from 'cors';
import path from 'path';
import fs from 'fs';
import pkg from 'whatsapp-web.js';
const { Client, LocalAuth, MessageMedia } = pkg;
import qrcode from 'qrcode';
import dotenv from 'dotenv';
import { createClient } from '@supabase/supabase-js';

dotenv.config();

const app = express();
const server = http.createServer(app);
const io = new Server(server, { cors: { origin: "*" } });
const PORT = 3000;

// Supabase Setup
const supabase = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_PUBLISHABLE_KEY);

app.use(cors());
app.use(express.json());
app.use(express.static('Public'));

const clients = new Map();

// --- WhatsApp Logic ---
async function getClient(sessionId) {
    if (clients.has(sessionId)) return clients.get(sessionId);
    
    const client = new Client({
        authStrategy: new LocalAuth({ clientId: sessionId }),
        puppeteer: { 
            headless: true, 
            args: ['--no-sandbox', '--disable-setuid-sandbox'] 
        }
    });

    client.on('qr', async (qr) => {
        const qrImage = await qrcode.toDataURL(qr);
        io.to(sessionId).emit('qr', qrImage);
    });

    client.on('ready', () => {
        io.to(sessionId).emit('ready');
        console.log('WhatsApp Ready for session:', sessionId);
    });

    client.on('message', async (msg) => {
        // Enviar para o Dashboard em tempo real
        io.to(sessionId).emit('new-message', {
            from: msg.from,
            body: msg.body,
            timestamp: msg.timestamp,
            fromMe: msg.fromMe
        });
    });

    clients.set(sessionId, client);
    await client.initialize();
    return client;
}

// --- API Routes ---

app.post('/api/whatsapp/connect', async (req, res) => {
    const { sessionId } = req.body;
    await getClient(sessionId);
    res.json({ ok: true });
});

app.post('/api/whatsapp/send', async (req, res) => {
    const { sessionId, to, message } = req.body;
    const client = clients.get(sessionId);
    if (!client) return res.status(404).json({ error: 'Sessão não iniciada' });
    
    await client.sendMessage(to, message);
    res.json({ ok: true });
});

app.get('/api/whatsapp/chats', async (req, res) => {
    const { sessionId } = req.query;
    const client = clients.get(sessionId);
    if (!client) return res.status(404).json({ error: 'Sessão não iniciada' });
    
    const chats = await client.getChats();
    res.json(chats.map(c => ({
        id: c.id._serialized,
        name: c.name,
        unreadCount: c.unreadCount
    })));
});

io.on('connection', (s) => {
    s.on('join', (id) => s.join(id));
});

server.listen(PORT, '0.0.0.0', () => {
    console.log('🚀 ZAPMRO PROFESSIONAL ONLINE: http://167.88.42.133:3000');
});
