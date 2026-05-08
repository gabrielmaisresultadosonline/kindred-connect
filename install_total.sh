#!/bin/bash
# SCRIPT DE INSTALAÇÃO DEFINITIVA (AUTO-CONTIDO) - ZAPMRO CLOUD
# Este script instala TUDO: dependências, código e PM2 no Ubuntu 24 LTS.

echo "🚀 Iniciando Instalação Total - ZAPMRO CLOUD / KINDRED CONNECT"

# 1. Limpeza e Instalação do Node.js 20
sudo apt update
sudo apt remove -y nodejs npm
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt install -y nodejs git ffmpeg

# 2. Instalação de dependências de sistema (Puppeteer + Ubuntu 24)
sudo apt install -y libnss3 libatk-bridge2.0-0t64 libatk1.0-0t64 libcups2t64 libdrm2 libxkbcommon0 libxcomposite1 libxdamage1 libxrandr2 libgbm1 libasound2t64 libpango-1.0-0 libcairo2 libxshmfence1

# 3. Preparação das Pastas
PROJECT_DIR=~/kindred-connect
rm -rf $PROJECT_DIR
mkdir -p $PROJECT_DIR/Server
mkdir -p $PROJECT_DIR/Public
mkdir -p $PROJECT_DIR/data/history
cd $PROJECT_DIR

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

# 5. Criar Proxy Manager
cat << 'PROXY_EOF' > Server/proxyManager.js
import fs from 'fs';
import path from 'path';
const DATA_FILE = path.join(process.cwd(), 'data/proxy_sessions.json');
const PROXY_CONFIG = { host: 'superproxy.com', port: '8888', username: 'base_user', password: 'base_password' };
function loadData() { try { if (!fs.existsSync(DATA_FILE)) return {}; return JSON.parse(fs.readFileSync(DATA_FILE, 'utf8')); } catch (e) { return {}; } }
function saveData(data) { fs.writeFileSync(DATA_FILE, JSON.stringify(data, null, 2)); }
export function getProxyForSession(waSessionId) {
    const data = loadData();
    if (data[waSessionId]) return data[waSessionId];
    const proxyId = Math.random().toString(36).substr(2, 9);
    data[waSessionId] = { host: PROXY_CONFIG.host, port: PROXY_CONFIG.port, username: PROXY_CONFIG.username, password: PROXY_CONFIG.password };
    saveData(data);
    return data[waSessionId];
}
PROXY_EOF

# 6. Criar Server Principal
cat << 'SERVER_EOF' > Server/index.js
import express from 'express';
import http from 'http';
import { Server } from 'socket.io';
import cors from 'cors';
import dotenv from 'dotenv';
import path from 'path';
import fs from 'fs';
import pkg from 'whatsapp-web.js';
const { Client, LocalAuth } = pkg;
import qrcode from 'qrcode';
import * as proxyManager from './proxyManager.js';

dotenv.config();
const app = express();
const server = http.createServer(app);
const io = new Server(server, { cors: { origin: "*" } });
const PORT = 3000;
const __dirname = path.resolve();

app.use(cors());
app.use(express.json());
app.use(express.static('Public'));

const clients = new Map();
const readJson = (f) => fs.existsSync(path.join(__dirname, 'data', f)) ? JSON.parse(fs.readFileSync(path.join(__dirname, 'data', f))) : null;
const writeJson = (f, d) => fs.writeFileSync(path.join(__dirname, 'data', f), JSON.stringify(d, null, 2));

app.post('/api/auth/register', (req, res) => {
    const { name, email, promoCode } = req.body;
    const users = readJson('users.json') || [];
    const user = { id: Math.random().toString(36).substr(2, 9), name, email, promoCode };
    users.push(user);
    writeJson('users.json', users);
    res.json({ token: 'fake-jwt-'+user.id, user });
});

async function initializeClient(sessionId) {
    if (clients.has(sessionId)) return;
    const client = new Client({
        authStrategy: new LocalAuth({ clientId: sessionId }),
        puppeteer: { headless: true, args: ['--no-sandbox', '--disable-setuid-sandbox'] }
    });
    client.on('qr', async (qr) => {
        const qrImage = await qrcode.toDataURL(qr);
        io.to(sessionId).emit('qr-generated', { qr: qrImage });
    });
    client.on('ready', () => {
        io.to(sessionId).emit('client-ready', { sessionId });
    });
    clients.set(sessionId, client);
    client.initialize().catch(e => console.error(e));
}

app.post('/api/create-session', (req, res) => {
    const { sessionId } = req.body;
    initializeClient(sessionId);
    res.json({ success: true });
});

io.on('connection', (s) => {
    s.on('bind-session', (id) => s.join(id));
});

server.listen(PORT, () => console.log(`🚀 ZAPMRO Rodando na porta ${PORT}`));
SERVER_EOF

# 7. Criar Frontend Básico para Teste
cat << 'HTML_EOF' > Public/index.html
<!DOCTYPE html><html><head><title>ZAPMRO</title></head><body>
<h2>ZAPMRO CLOUD</h2>
<input id="email" placeholder="Email"><button onclick="reg()">Entrar</button>
<div id="dash" style="display:none">
  <button onclick="conn()">Conectar WhatsApp</button>
  <img id="qr" style="width:200px">
</div>
<script src="/socket.io/socket.io.js"></script>
<script>
let uid; const socket = io();
async function reg() {
  const r = await fetch('/api/auth/register', { method: 'POST', headers: {'Content-Type': 'application/json'}, body: JSON.stringify({email: document.getElementById('email').value}) });
  const d = await r.json(); uid = d.user.id;
  document.getElementById('dash').style.display = 'block';
  socket.emit('bind-session', uid);
}
async function conn() { fetch('/api/create-session', { method: 'POST', headers: {'Content-Type': 'application/json'}, body: JSON.stringify({sessionId: uid}) }); }
socket.on('qr-generated', d => document.getElementById('qr').src = d.qr);
socket.on('client-ready', () => alert('WhatsApp Conectado!'));
</script></body></html>
HTML_EOF

# 8. Instalar Dependências Node e PM2
npm install
sudo npm install -g pm2

# 9. Iniciar
pm2 delete zapmro 2>/dev/null
pm2 start Server/index.js --name "zapmro"
pm2 save

echo "✅ INSTALAÇÃO CONCLUÍDA!"
echo "Acesse: http://SEU_IP:3000"
pm2 logs zapmro
