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
const io = new Server(server, { 
    cors: { origin: "*" },
    maxHttpBufferSize: 1e8 // 100mb
});
const PORT = 3000;

app.use(cors());
app.use(express.json());
app.use(express.static('Public'));

const clients = new Map();

// Helper para pegar foto de perfil com cache ou fallback
async function getProfilePic(client, contactId) {
    try {
        const url = await client.getProfilePicUrl(contactId);
        return url || 'https://ui-avatars.com/api/?name=' + encodeURIComponent(contactId) + '&background=random';
    } catch (e) {
        return 'https://ui-avatars.com/api/?name=User&background=ccc';
    }
}

app.post('/api/whatsapp/connect', async (req, res) => {
    try {
        const { sessionId } = req.body;
        if (!sessionId) return res.status(400).json({ error: 'ID da sessão é obrigatório' });

        if (clients.has(sessionId)) {
            const existing = clients.get(sessionId);
            if (existing.info) return res.json({ ok: true, status: 'CONNECTED' });
        }

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

        client.on('ready', async () => {
            console.log(`Session ${sessionId} ready`);
            io.to(sessionId).emit('ready');
        });

        client.on('message', async (msg) => {
            const chat = await msg.getChat();
            io.to(sessionId).emit('new-message', {
                from: msg.from,
                body: msg.body,
                fromMe: msg.fromMe,
                timestamp: msg.timestamp,
                author: msg.author,
                type: msg.type
            });
        });
        
        // Novo: Evento para carregar mídia sob demanda
        client.on('message_create', async (msg) => {
            if (msg.fromMe) {
                 io.to(sessionId).emit('new-message', {
                    from: msg.to,
                    body: msg.body,
                    fromMe: true,
                    timestamp: msg.timestamp
                });
            }
        });

        client.initialize().catch(e => console.error('Init error:', e));
        clients.set(sessionId, client);
        res.json({ ok: true });
    } catch (e) {
        res.status(500).json({ error: e.message });
    }
});

app.get('/api/whatsapp/chats', async (req, res) => {
    const { sessionId } = req.query;
    const client = clients.get(sessionId);
    if (!client) return res.status(404).json({ error: 'Sessão não encontrada' });
    
    try {
        const chats = await client.getChats();
        const simplified = await Promise.all(chats.slice(0, 50).map(async c => {
            const pic = await getProfilePic(client, c.id._serialized);
            return {
                id: c.id._serialized,
                name: c.name,
                unreadCount: c.unreadCount,
                timestamp: c.timestamp,
                isGroup: c.isGroup,
                pic: pic
            };
        }));
        res.json(simplified);
    } catch (e) {
        res.status(500).json({ error: e.message });
    }
});

app.get('/api/whatsapp/history', async (req, res) => {
    const { sessionId, chatId } = req.query;
    const client = clients.get(sessionId);
    if (!client) return res.status(404).json({ error: 'Sessão não encontrada' });

    try {
        const chat = await client.getChatById(chatId);
        const msgs = await chat.fetchMessages({ limit: 50 });
        res.json(msgs.map(m => ({
            id: m.id._serialized,
            body: m.body,
            from: m.from,
            fromMe: m.fromMe,
            timestamp: m.timestamp,
            type: m.type,
            hasMedia: m.hasMedia
        })));
    } catch (e) {
        res.status(500).json({ error: e.message });
    }
});

app.post('/api/whatsapp/send', async (req, res) => {
    const { sessionId, to, message } = req.body;
    const client = clients.get(sessionId);
    if (!client) return res.status(404).json({ error: 'Sessão não encontrada' });
    
    try {
        const result = await client.sendMessage(to, message);
        res.json({ ok: true, id: result.id._serialized });
    } catch (e) {
        res.status(500).json({ error: e.message });
    }
});

io.on('connection', s => {
    s.on('join', id => {
        s.join(id);
        console.log(`Socket joined session: ${id}`);
    });
});

server.listen(PORT, '0.0.0.0', () => console.log('🚀 ZAPMRO PROFESSIONAL ONLINE'));
