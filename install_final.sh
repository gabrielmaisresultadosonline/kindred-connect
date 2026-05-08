#!/bin/bash
# SCRIPT DE INSTALAÇÃO DEFINITIVA (AUTO-CONTIDO) - ZAPMRO CLOUD
# Este script instala TUDO: dependências, código e PM2 no Ubuntu 24 LTS.

echo "🚀 Iniciando Instalação Total - ZAPMRO CLOUD"

# 1. Limpeza e Instalação do Node.js 20
sudo apt update
sudo apt remove -y nodejs npm
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt install -y nodejs git ffmpeg

# 2. Instalação de dependências de sistema (Puppeteer + Ubuntu 24)
sudo apt install -y libnss3 libatk-bridge2.0-0t64 libatk1.0-0t64 libcups2t64 libdrm2 libxkbcommon0 libxcomposite1 libxdamage1 libxrandr2 libgbm1 libasound2t64 libpango-1.0-0 libcairo2 libxshmfence1

# 3. Preparação das Pastas
PROJECT_DIR=~/kindred-connect
rm -rf \$PROJECT_DIR
mkdir -p \$PROJECT_DIR/Server
mkdir -p \$PROJECT_DIR/Public
mkdir -p \$PROJECT_DIR/data/history
cd \$PROJECT_DIR

# 4. Criar package.json
cat << 'PKG_EOF' > package.json
{
  "name": "kindred-connect",
  "version": "1.0.0",
  "type": "module",
  "main": "Server/index.js",
  "scripts": {
    "start": "node Server/index.js"
  },
  "dependencies": {
    "axios": "^1.6.0",
    "cors": "^2.8.5",
    "dotenv": "^16.0.0",
    "express": "^4.18.0",
    "ffmpeg-static": "^5.2.0",
    "fluent-ffmpeg": "^2.1.2",
    "multer": "^1.4.5",
    "puppeteer-page-proxy": "^1.2.8",
    "qrcode": "^1.5.3",
    "qrcode-terminal": "^0.12.0",
    "socket.io": "^4.7.0",
    "whatsapp-web.js": "^1.23.0"
  }
}
PKG_EOF

# 5. Criar Server Principal (Versão Simplificada para Garantir Início)
cat << 'SERVER_EOF' > Server/index.js
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
const __dirname = path.resolve();

app.use(cors());
app.use(express.json());
app.use(express.static('Public'));

const clients = new Map();

app.post('/api/auth/register', (req, res) => {
    res.json({ user: { id: 'user_' + Math.random().toString(36).substr(2, 5) } });
});

app.post('/api/create-session', (req, res) => {
    const { sessionId } = req.body;
    if (clients.has(sessionId)) return res.json({ success: true });
    const client = new Client({
        authStrategy: new LocalAuth({ clientId: sessionId }),
        puppeteer: { headless: true, args: ['--no-sandbox', '--disable-setuid-sandbox'] }
    });
    client.on('qr', async (qr) => {
        const qrImage = await qrcode.toDataURL(qr);
        io.to(sessionId).emit('qr-generated', { qr: qrImage });
    });
    client.on('ready', () => io.to(sessionId).emit('client-ready'));
    client.initialize();
    clients.set(sessionId, client);
    res.json({ success: true });
});

io.on('connection', (s) => s.on('bind-session', (id) => s.join(id)));
server.listen(PORT, () => console.log('🚀 Servidor rodando na porta 3000'));
SERVER_EOF

# 6. Criar Frontend Básico
cat << 'HTML_EOF' > Public/index.html
<!DOCTYPE html><html><head><meta charset="UTF-8"><title>ZAPMRO</title></head><body>
<h2>ZAPMRO CLOUD</h2>
<button onclick="start()">Iniciar Sistema</button>
<div id="dash" style="display:none">
  <button onclick="conn()">Gerar QR Code WhatsApp</button><br>
  <img id="qr" style="width:250px; margin-top:20px;">
</div>
<script src="/socket.io/socket.io.js"></script>
<script>
let uid; const socket = io();
async function start() {
  const r = await fetch('/api/auth/register', {method:'POST'});
  const d = await r.json(); uid = d.user.id;
  document.getElementById('dash').style.display = 'block';
  socket.emit('bind-session', uid);
}
async function conn() {
  fetch('/api/create-session', {method:'POST', headers:{'Content-Type':'application/json'}, body:JSON.stringify({sessionId:uid})});
}
socket.on('qr-generated', d => document.getElementById('qr').src = d.qr);
socket.on('client-ready', () => alert('WhatsApp Conectado!'));
</script></body></html>
HTML_EOF

# 7. Instalação Final
npm install
sudo npm install -g pm2
pm2 delete zapmro 2>/dev/null
pm2 start Server/index.js --name "zapmro"
pm2 save
echo "✅ TUDO PRONTO! Acesse http://SEU_IP:3000"
pm2 logs zapmro
