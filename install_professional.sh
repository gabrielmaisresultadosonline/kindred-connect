#!/bin/bash
# Script de Instalação e Atualização Profissional ZAPMRO
# Este script automatiza o upload do código e reinicialização do serviço

cd ~/kindred-connect

echo "🚀 Iniciando atualização profissional..."

# 1. Garante que as pastas necessárias existem
mkdir -p Server Public data Public/uploads

# 2. Atualiza o código do Servidor (Backend)
cat << 'INDEX_JS' > Server/index.js
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
INDEX_JS

# 3. Atualiza o código do Dashboard (Frontend)
cat << 'DASH_HTML' > Public/dashboard.html
<!DOCTYPE html>
<html lang="pt-br">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>ZAPMRO CLOUD | Painel Profissional</title>
    <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/css/bootstrap.min.css" rel="stylesheet">
    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css">
    <style>
        :root { 
            --primary: #128c7e; 
            --primary-dark: #075e54; 
            --sidebar-bg: #111b21;
            --sidebar-hover: #202c33;
            --bg-light: #f0f2f5;
            --chat-bg: #e5ddd5;
        }
        body { background: var(--bg-light); height: 100vh; display: flex; font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; overflow: hidden; margin: 0; }
        .sidebar { width: 260px; background: var(--sidebar-bg); display: flex; flex-direction: column; color: #d1d7db; flex-shrink: 0; }
        .sidebar-header { padding: 25px; text-align: center; border-bottom: 1px solid #222e35; }
        .sidebar-header h4 { color: #fff; font-weight: 800; margin: 0; letter-spacing: 1px; }
        .sidebar-menu { flex: 1; overflow-y: auto; padding-top: 10px; }
        .menu-item { padding: 12px 25px; display: flex; align-items: center; gap: 15px; cursor: pointer; transition: 0.2s; font-size: 0.95rem; }
        .menu-item:hover { background: var(--sidebar-hover); color: #fff; }
        .menu-item.active { background: var(--primary); color: #fff; border-right: 4px solid #fff; }
        .menu-item i { width: 20px; text-align: center; font-size: 1.1rem; }
        .main-container { flex: 1; display: flex; flex-direction: column; overflow: hidden; }
        .top-bar { height: 60px; background: #fff; display: flex; align-items: center; justify-content: space-between; padding: 0 30px; border-bottom: 1px solid #ddd; }
        .content-area { flex: 1; overflow-y: auto; position: relative; }
        .tab-content { display: none; height: 100%; flex-direction: column; animation: fadeIn 0.3s; }
        .tab-content.active { display: flex; }
        @keyframes fadeIn { from { opacity: 0; } to { opacity: 1; } }
        .whatsapp-container { display: flex; height: 100%; }
        .chat-list { width: 350px; background: #fff; border-right: 1px solid #ddd; display: flex; flex-direction: column; }
        .chat-search { padding: 10px; background: #fff; border-bottom: 1px solid #eee; }
        .chat-items { flex: 1; overflow-y: auto; }
        .chat-item { padding: 12px 15px; display: flex; align-items: center; gap: 12px; border-bottom: 1px solid #f2f2f2; cursor: pointer; transition: 0.2s; }
        .chat-item:hover { background: #f5f6f6; }
        .chat-item.active { background: #eff2f5; }
        .chat-item img { width: 45px; height: 45px; border-radius: 50%; object-fit: cover; }
        .chat-info { flex: 1; min-width: 0; }
        .chat-name { font-weight: 600; color: #111b21; margin-bottom: 2px; }
        .chat-last-msg { font-size: 0.85rem; color: #667781; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
        .chat-view { flex: 1; display: flex; flex-direction: column; background: var(--chat-bg); position: relative; }
        .chat-header { height: 60px; background: #f0f2f5; display: flex; align-items: center; padding: 0 20px; gap: 15px; border-bottom: 1px solid #ddd; }
        .chat-header img { width: 40px; height: 40px; border-radius: 50%; }
        .chat-messages { flex: 1; overflow-y: auto; padding: 20px; display: flex; flex-direction: column; gap: 8px; }
        .msg { max-width: 65%; padding: 8px 12px; border-radius: 8px; font-size: 0.95rem; box-shadow: 0 1px 1px rgba(0,0,0,0.1); position: relative; }
        .msg.sent { align-self: flex-end; background: #dcf8c6; }
        .msg.received { align-self: flex-start; background: #fff; }
        .msg-time { font-size: 0.7rem; color: #667781; margin-top: 4px; text-align: right; }
        .chat-input { padding: 10px 20px; background: #f0f2f5; display: flex; align-items: center; gap: 15px; }
        .chat-input input { flex: 1; border-radius: 20px; border: none; padding: 10px 15px; outline: none; }
        .kanban-board { display: flex; gap: 20px; padding: 20px; overflow-x: auto; height: 100%; }
        .kanban-column { min-width: 280px; width: 280px; background: #ebedef; border-radius: 10px; display: flex; flex-direction: column; padding: 12px; }
        .kanban-column-header { display: flex; justify-content: space-between; align-items: center; margin-bottom: 15px; }
        .kanban-column-title { font-weight: 700; color: #444; font-size: 0.9rem; text-transform: uppercase; }
        .kanban-card { background: #fff; padding: 12px; border-radius: 8px; margin-bottom: 10px; box-shadow: 0 2px 4px rgba(0,0,0,0.05); cursor: grab; }
        .qr-overlay { position: fixed; top: 0; left: 0; width: 100%; height: 100%; background: rgba(17, 27, 33, 0.95); z-index: 9999; display: none; align-items: center; justify-content: center; }
        .qr-card { background: #fff; padding: 40px; border-radius: 20px; text-align: center; max-width: 400px; width: 90%; }
        .qr-card img { width: 250px; height: 250px; margin-bottom: 20px; }
        .btn-wa { background: var(--primary); color: #fff; border: none; font-weight: 600; }
        .btn-wa:hover { background: var(--primary-dark); color: #fff; }
        .cursor-pointer { cursor: pointer; }
    </style>
</head>
<body>
    <div class="sidebar">
        <div class="sidebar-header"><h4>ZAPMRO CLOUD</h4><div class="small text-muted mt-1">PROFISSIONAL v2.0</div></div>
        <div class="sidebar-menu">
            <div class="menu-item active" onclick="switchTab('dashboard')"><i class="fas fa-chart-line"></i> Dashboard</div>
            <div class="menu-item" onclick="switchTab('chats')"><i class="fas fa-comment-alt"></i> Conversas</div>
            <div class="menu-item" onclick="switchTab('kanban')"><i class="fas fa-th-large"></i> CRM Kanban</div>
            <div class="menu-item" onclick="switchTab('flows')"><i class="fas fa-project-diagram"></i> Fluxos</div>
            <div class="menu-item" onclick="switchTab('ai')"><i class="fas fa-robot"></i> Inteligência Artificial</div>
            <div class="menu-item" onclick="switchTab('scheduling')"><i class="fas fa-calendar-alt"></i> Agendamentos</div>
            <div class="menu-item text-danger mt-auto" onclick="logout()"><i class="fas fa-sign-out-alt"></i> Sair</div>
        </div>
    </div>
    <div class="main-container">
        <div class="top-bar"><h5 id="page-title" class="m-0">Dashboard</h5><div class="d-flex align-items-center gap-3"><span id="status-badge" class="badge bg-danger">Desconectado</span><button class="btn btn-sm btn-wa" onclick="connectWhatsApp()">Conectar</button></div></div>
        <div class="content-area">
            <div id="tab-dashboard" class="tab-content active p-4">
                <div class="row g-3">
                    <div class="col-md-3"><div class="card border-0 shadow-sm p-3"><div class="text-muted small">Total Mensagens</div><h3 class="m-0">1.284</h3></div></div>
                    <div class="col-md-3"><div class="card border-0 shadow-sm p-3"><div class="text-muted small">Novos Leads</div><h3 class="m-0">42</h3></div></div>
                    <div class="col-md-3"><div class="card border-0 shadow-sm p-3"><div class="text-muted small">Respostas IA</div><h3 class="m-0">856</h3></div></div>
                    <div class="col-md-3"><div class="card border-0 shadow-sm p-3"><div class="text-muted small">Status</div><h3 class="m-0 text-success">Online</h3></div></div>
                </div>
            </div>
            <div id="tab-chats" class="tab-content">
                <div class="whatsapp-container">
                    <div class="chat-list"><div class="chat-search"><input type="text" class="form-control form-control-sm" placeholder="Pesquisar..."></div><div id="chat-items-list" class="chat-items"></div></div>
                    <div class="chat-view">
                        <div id="chat-header-info" class="chat-header d-none"><img src="" id="active-chat-pic"><div class="fw-bold" id="active-chat-name"></div></div>
                        <div id="chat-messages-area" class="chat-messages"></div>
                        <div class="chat-input d-none" id="chat-input-area"><input type="text" id="chat-input-field" placeholder="Digite uma mensagem..." onkeydown="if(event.key==='Enter') sendMessage()"><button class="btn btn-wa rounded-circle" onclick="sendMessage()"><i class="fas fa-paper-plane"></i></button></div>
                    </div>
                </div>
            </div>
            <div id="tab-kanban" class="tab-content"><div class="kanban-board" id="kanban-board"></div></div>
            <div id="tab-ai" class="tab-content p-4"><div class="card border-0 shadow-sm p-4"><h3>Configuração de IA</h3><hr><div class="mb-3"><label>API Key (OpenAI)</label><input type="password" id="ai-api-key" class="form-control"></div><button class="btn btn-wa" onclick="saveAI()">Salvar</button></div></div>
        </div>
    </div>
    <div id="qr-overlay" class="qr-overlay"><div class="qr-card"><h4>Conectar WhatsApp</h4><div id="qr-container"><div class="spinner-border text-primary"></div></div><img id="qr-img" style="display:none; width: 250px;"><div class="mt-3"><button class="btn btn-outline-secondary" onclick="closeQR()">Cancelar</button></div></div></div>
    <script src="/socket.io/socket.io.js"></script>
    <script>
        const user = JSON.parse(localStorage.getItem('user'));
        if(!user) window.location.href = 'index.html';
        const sid = user.id;
        const socket = io();
        let activeChat = null;
        socket.emit('join', sid);
        socket.on('qr', src => { document.getElementById('qr-container').style.display = 'none'; document.getElementById('qr-img').style.display = 'block'; document.getElementById('qr-img').src = src; });
        socket.on('ready', () => { document.getElementById('qr-overlay').style.display = 'none'; document.getElementById('status-badge').className = 'badge bg-success'; document.getElementById('status-badge').innerText = 'Conectado'; loadChats(); });
        socket.on('new-message', msg => { if(activeChat === msg.from || msg.fromMe) appendMessage(msg); });
        function switchTab(tabId) { document.querySelectorAll('.tab-content').forEach(t => t.classList.remove('active')); document.querySelectorAll('.menu-item').forEach(m => m.classList.remove('active')); document.getElementById('tab-' + tabId).classList.add('active'); event.currentTarget.classList.add('active'); if(tabId === 'chats') loadChats(); }
        async function connectWhatsApp() { document.getElementById('qr-overlay').style.display = 'flex'; fetch('/api/whatsapp/connect', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ sessionId: sid }) }); }
        function closeQR() { document.getElementById('qr-overlay').style.display = 'none'; }
        async function loadChats() {
            const res = await fetch(\`/api/whatsapp/chats?sessionId=\${sid}\`);
            const chats = await res.json();
            document.getElementById('chat-items-list').innerHTML = chats.map(c => \`<div class="chat-item" onclick="selectChat('\${c.id}', '\${c.name}', '\${c.pic}')"><img src="\${c.pic}"><div class="chat-info"><div class="chat-name">\${c.name}</div></div></div>\`).join('');
        }
        function selectChat(id, name, pic) { activeChat = id; document.getElementById('chat-header-info').classList.remove('d-none'); document.getElementById('chat-input-area').classList.remove('d-none'); document.getElementById('active-chat-pic').src = pic; document.getElementById('active-chat-name').innerText = name; document.getElementById('chat-messages-area').innerHTML = ''; }
        async function sendMessage() {
            const input = document.getElementById('chat-input-field');
            const msg = input.value;
            if(!msg || !activeChat) return;
            input.value = '';
            appendMessage({ body: msg, fromMe: true, timestamp: Date.now()/1000 });
            fetch('/api/whatsapp/send', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ sessionId: sid, to: activeChat, message: msg }) });
        }
        function appendMessage(msg) {
            const area = document.getElementById('chat-messages-area');
            const div = document.createElement('div');
            div.className = \`msg \${msg.fromMe ? 'sent' : 'received'}\`;
            div.innerHTML = \`<div>\${msg.body}</div>\`;
            area.appendChild(div);
            area.scrollTop = area.scrollHeight;
        }
        function logout() { localStorage.clear(); window.location.href = 'index.html'; }
    </script>
</body>
</html>
DASH_HTML

# 4. Reinicia o Processo
pm2 stop zapmro 2>/dev/null
pm2 delete zapmro 2>/dev/null
pm2 start Server/index.js --name "zapmro"
pm2 save

echo "✅ ATUALIZAÇÃO PROFISSIONAL CONCLUÍDA!"
echo "🚀 Acesse o sistema na porta 3000"
