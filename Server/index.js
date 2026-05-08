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

// Garantir que a pasta de dados existe
if (!fs.existsSync('./data')) fs.mkdirSync('./data');

app.post('/api/create-session', async (req, res) => {
    try {
        const { sessionId } = req.body;
        if (!sessionId) return res.status(400).json({ error: 'Session ID is required' });

        if (clients.has(sessionId)) {
            return res.json({ ok: true, message: 'Session already exists' });
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

        client.on('ready', () => {
            console.log('Client ready:', sessionId);
            io.to(sessionId).emit('ready');
        });

        client.on('auth_failure', () => io.to(sessionId).emit('error', 'Falha na autenticação'));
        
        client.initialize().catch(err => {
            console.error('Init Error:', err);
            io.to(sessionId).emit('error', 'Erro ao iniciar Chrome');
        });

        clients.set(sessionId, client);
        res.json({ ok: true });
    } catch (error) {
        console.error('Server Error:', error);
        res.status(500).json({ error: error.message });
    }
});

io.on('connection', (s) => {
    s.on('join', (id) => {
        s.join(id);
        console.log('User joined session:', id);
    });
});

server.listen(PORT, '0.0.0.0', () => {
    console.log('🚀 ZAPMRO ONLINE: http://167.88.42.133:3000');
});
