#!/bin/bash
# Script de Atualização Total ZAPMRO
# Este script deve ser executado via terminal na sua VPS

echo "🚀 Iniciando Atualização Total..."

# 1. Entrar na pasta do projeto
cd ~/kindred-connect || { echo "❌ Erro: Pasta ~/kindred-connect não encontrada!"; exit 1; }

# 2. Atualizar o Servidor (Server/index.js)
cat << 'SERVER_CODE' > Server/index.js
import express from 'express';
import http from 'http';
import { Server } from 'socket.io';
import cors from 'cors';
import fs from 'fs';
import pkg from 'whatsapp-web.js';
const { Client, LocalAuth } = pkg;
import qrcode from 'qrcode';
import { OpenAI } from 'openai';

const app = express();
const server = http.createServer(app);
const io = new Server(server, { cors: { origin: "*" } });
const PORT = 3000;

app.use(cors());
app.use(express.json());
app.use(express.static('Public'));

const clients = new Map();
const db = {
    load: (f) => { try { return JSON.parse(fs.readFileSync(\`./data/\${f}.json\`)); } catch { return []; } },
    save: (f, d) => { if(!fs.existsSync('./data')) fs.mkdirSync('./data'); fs.writeFileSync(\`./data/\${f}.json\`, JSON.stringify(d, null, 2)); },
    ensure: (f) => { if(!fs.existsSync(\`./data/\${f}.json\`)) db.save(f, []); }
};

['flows', 'ai_config', 'scheduled_messages', 'kanban'].forEach(db.ensure);

app.post('/api/whatsapp/connect', async (req, res) => {
    const { sessionId } = req.body;
    if (clients.has(sessionId)) return res.json({ ok: true });
    
    const client = new Client({
        authStrategy: new LocalAuth({ clientId: sessionId }),
        puppeteer: { headless: true, args: ['--no-sandbox'] }
    });

    client.on('qr', async (qr) => io.to(sessionId).emit('qr', await qrcode.toDataURL(qr)));
    client.on('ready', () => io.to(sessionId).emit('ready'));
    client.on('message', async (msg) => {
        io.to(sessionId).emit('new-message', { from: msg.from, body: msg.body, fromMe: msg.fromMe });
        // Lógica de IA e Fluxos aqui
    });

    client.initialize().catch(console.error);
    clients.set(sessionId, client);
    res.json({ ok: true });
});

app.get('/api/whatsapp/chats', async (req, res) => {
    const client = clients.get(req.query.sessionId);
    if (!client || !client.info) return res.json([]);
    const chats = await client.getChats();
    res.json(chats.slice(0, 50).map(c => ({ id: c.id._serialized, name: c.name, pic: 'https://ui-avatars.com/api/?name=' + c.name })));
});

app.post('/api/whatsapp/send', async (req, res) => {
    const { sessionId, to, message } = req.body;
    const client = clients.get(sessionId);
    if (client) { await client.sendMessage(to, message); res.json({ ok: true }); }
    else res.status(404).send();
});

app.get('/api/db/:file', (req, res) => res.json(db.load(req.params.file)));
app.post('/api/db/:file', (req, res) => { db.save(req.params.file, req.body); res.json({ok:true}); });

server.listen(PORT, '0.0.0.0', () => console.log('🚀 ZAPMRO ONLINE'));
SERVER_CODE

# 3. Atualizar o Dashboard (Public/dashboard.html)
cat << 'DASHBOARD_CODE' > Public/dashboard.html
<!DOCTYPE html>
<html lang="pt-br">
<head>
    <meta charset="UTF-8">
    <title>ZAPMRO | Painel Profissional</title>
    <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/css/bootstrap.min.css" rel="stylesheet">
    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css">
    <style>
        body { background: #f0f2f5; display: flex; height: 100vh; font-family: sans-serif; }
        .sidebar { width: 260px; background: #111b21; color: white; display: flex; flex-direction: column; }
        .menu-item { padding: 15px 25px; cursor: pointer; transition: 0.3s; }
        .menu-item:hover, .menu-item.active { background: #128c7e; }
        .main { flex: 1; display: flex; flex-direction: column; }
        .content { flex: 1; padding: 20px; overflow-y: auto; }
        .chat-container { display: flex; height: 100%; background: white; border-radius: 8px; overflow: hidden; }
        .chat-list { width: 300px; border-right: 1px solid #ddd; overflow-y: auto; }
        .chat-view { flex: 1; display: flex; flex-direction: column; background: #e5ddd5; }
        .msg-box { flex: 1; padding: 20px; overflow-y: auto; display: flex; flex-direction: column; gap: 10px; }
        .msg { padding: 8px 12px; border-radius: 8px; max-width: 70%; }
        .msg.sent { align-self: flex-end; background: #dcf8c6; }
        .msg.received { align-self: flex-start; background: white; }
    </style>
</head>
<body>
    <div class="sidebar">
        <div class="p-4 text-center"><h4>ZAPMRO</h4></div>
        <div class="menu-item active" onclick="tab('chats')"><i class="fas fa-comments"></i> Conversas</div>
        <div class="menu-item" onclick="tab('kanban')"><i class="fas fa-columns"></i> CRM Kanban</div>
        <div class="menu-item" onclick="tab('ai')"><i class="fas fa-robot"></i> Inteligência AI</div>
        <div class="menu-item mt-auto" onclick="logout()"><i class="fas fa-sign-out-alt"></i> Sair</div>
    </div>
    <div class="main">
        <div class="bg-white p-3 border-bottom d-flex justify-content-between">
            <h5 id="title">Conversas</h5>
            <button class="btn btn-sm btn-success" onclick="conn()">Conectar WhatsApp</button>
        </div>
        <div class="content" id="main-content">
            <!-- Chat View Default -->
            <div id="chats-view" class="chat-container">
                <div id="chat-list" class="chat-list"></div>
                <div class="chat-view">
                    <div id="msgs" class="msg-box"></div>
                    <div class="p-3 bg-light d-flex gap-2">
                        <input type="text" id="msg-inp" class="form-control" placeholder="Mensagem...">
                        <button onclick="send()" class="btn btn-success">Enviar</button>
                    </div>
                </div>
            </div>
        </div>
    </div>

    <div id="qr-modal" style="display:none; position:fixed; top:0; left:0; width:100%; height:100%; background:rgba(0,0,0,0.8); z-index:99; align-items:center; justify-content:center;">
        <div class="bg-white p-5 rounded text-center">
            <h5>Escaneie o QR Code</h5>
            <img id="qr-img" style="width:250px; margin:20px 0;">
            <br><button class="btn btn-secondary" onclick="document.getElementById('qr-modal').style.display='none'">Fechar</button>
        </div>
    </div>

    <script src="/socket.io/socket.io.js"></script>
    <script>
        const user = JSON.parse(localStorage.getItem('user'));
        const sid = user.id;
        const socket = io();
        let active = null;

        socket.emit('join', sid);
        socket.on('qr', src => { document.getElementById('qr-modal').style.display='flex'; document.getElementById('qr-img').src=src; });
        socket.on('ready', () => { document.getElementById('qr-modal').style.display='none'; loadChats(); });
        socket.on('new-message', m => { if(m.from === active || m.fromMe) append(m); });

        function conn() { fetch('/api/whatsapp/connect', {method:'POST', headers:{'Content-Type':'application/json'}, body:JSON.stringify({sessionId:sid})}); }
        async function loadChats() {
            const r = await fetch('/api/whatsapp/chats?sessionId='+sid);
            const chats = await r.json();
            document.getElementById('chat-list').innerHTML = chats.map(c => \`<div class="p-3 border-bottom cursor-pointer" onclick="sel('\${c.id}', '\${c.name}')">\${c.name}</div>\`).join('');
        }
        function sel(id, name) { active = id; document.getElementById('msgs').innerHTML = ''; }
        async function send() {
            const m = document.getElementById('msg-inp').value;
            await fetch('/api/whatsapp/send', {method:'POST', headers:{'Content-Type':'application/json'}, body:JSON.stringify({sessionId:sid, to:active, message:m})});
            append({body:m, fromMe:true});
            document.getElementById('msg-inp').value = '';
        }
        function append(m) {
            const d = document.createElement('div');
            d.className = 'msg ' + (m.fromMe ? 'sent' : 'received');
            d.innerText = m.body;
            document.getElementById('msgs').appendChild(d);
            document.getElementById('msgs').scrollTop = document.getElementById('msgs').scrollHeight;
        }
        function logout() { localStorage.clear(); window.location.href='index.html'; }
    </script>
</body>
</html>
DASHBOARD_CODE

# 4. Reiniciar com PM2
pm2 restart zapmro || pm2 start Server/index.js --name "zapmro"
pm2 save

echo "✅ TUDO ATUALIZADO E RODANDO!"
