import express from 'express';
import http from 'http';
import { Server } from 'socket.io';
import cors from 'cors';
import path from 'path';
import fs from 'fs';
import pkg from 'whatsapp-web.js';
const { Client, LocalAuth } = pkg;
import qrcode from 'qrcode';

const app = express();
const server = http.createServer(app);
const io = new Server(server, { cors: { origin: "*" } });
const PORT = 3000;

app.use(cors());
app.use(express.json());
app.use(express.static('Public'));

const clients = new Map();

app.post('/api/whatsapp/connect', async (req, res) => {
    try {
        const { sessionId } = req.body;
        if (!sessionId) return res.status(400).json({ error: 'ID da sessão é obrigatório' });

        if (clients.has(sessionId)) return res.json({ ok: true });

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

        client.on('ready', () => io.to(sessionId).emit('ready'));
        
        client.on('message', (msg) => {
            io.to(sessionId).emit('new-message', {
                from: msg.from,
                body: msg.body,
                fromMe: msg.fromMe,
                timestamp: msg.timestamp
            });
        });

        client.initialize().catch(e => console.error('Init error:', e));
        clients.set(sessionId, client);
        res.json({ ok: true });
    } catch (e) {
        res.status(500).json({ error: e.message });
    }
});

app.post('/api/whatsapp/send', async (req, res) => {
    const { sessionId, to, message } = req.body;
    const client = clients.get(sessionId);
    if (client) {
        await client.sendMessage(to, message);
        res.json({ ok: true });
    } else {
        res.status(404).json({ error: 'Sessão não encontrada' });
    }
});

app.get('/api/whatsapp/chats', async (req, res) => {
    const { sessionId } = req.query;
    const client = clients.get(sessionId);
    if (client) {
        const chats = await client.getChats();
        res.json(chats.map(c => ({ id: c.id._serialized, name: c.name })));
    } else {
        res.status(404).json({ error: 'Sessão não encontrada' });
    }
});

io.on('connection', s => s.on('join', id => s.join(id)));
server.listen(PORT, '0.0.0.0', () => console.log('🚀 ZAPMRO PROFESSIONAL ONLINE'));
