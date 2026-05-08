#!/bin/bash
PROJECT_DIR=~/kindred-connect
cd $PROJECT_DIR

# 1. Garantir que o index.js use 0.0.0.0 (escuta em todos os IPs)
cat << 'SERVER_FIX' > Server/index.js
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

app.post('/api/create-session', (req, res) => {
    const { sessionId } = req.body;
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
    client.initialize();
    res.json({ ok: true });
});

io.on('connection', (s) => {
    s.on('join', (id) => s.join(id));
});

// ESCUTAR EM 0.0.0.0 É O SEGREDO
server.listen(PORT, '0.0.0.0', () => {
    console.log('🚀 ZAPMRO ONLINE EM: http://167.88.42.133:3000');
});
SERVER_FIX

# 2. Liberar portas no Firewall (Hostinger/Ubuntu)
sudo ufw allow 3000/tcp
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw disable && sudo ufw enable -f

# 3. Reiniciar App
pm2 delete zapmro 2>/dev/null
pm2 start Server/index.js --name "zapmro"
pm2 save

echo "✅ PORTA 3000 LIBERADA E SERVIDOR RECONFIGURADO!"
echo "🔗 TENTE AGORA: http://167.88.42.133:3000"
