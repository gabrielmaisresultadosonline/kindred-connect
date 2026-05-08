#!/bin/bash
echo "🚀 Iniciando Atualização Total e Profissional v3.0..."
cd ~/kindred-connect

# 1. Atualizar o Servidor (Backend)
cat << 'SERVER_CODE' > Server/index.js
import express from 'express';
import http from 'http';
import { Server } from 'socket.io';
import cors from 'cors';
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
const db = {
    load: (f) => { try { return JSON.parse(fs.readFileSync(\`./data/\${f}.json\`)); } catch { return []; } },
    save: (f, d) => { if(!fs.existsSync('./data')) fs.mkdirSync('./data'); fs.writeFileSync(\`./data/\${f}.json\`, JSON.stringify(d, null, 2)); },
    ensure: (f) => { if(!fs.existsSync(\`./data/\${f}.json\`)) db.save(f, []); }
};

['flows', 'ai_config', 'scheduled_messages', 'kanban'].forEach(db.ensure);

// Auto-conectar sessões existentes ao iniciar
async function restoreSessions() {
    const authPath = './.wwebjs_auth';
    if (fs.existsSync(authPath)) {
        const folders = fs.readdirSync(authPath);
        for (const folder of folders) {
            if (folder.startsWith('session-')) {
                const sessionId = folder.replace('session-', '');
                console.log('Restaurando sessão:', sessionId);
                initWhatsApp(sessionId);
            }
        }
    }
}

async function initWhatsApp(sessionId) {
    if (clients.has(sessionId)) return;
    
    const client = new Client({
        authStrategy: new LocalAuth({ clientId: sessionId }),
        puppeteer: { 
            headless: true, 
            args: ['--no-sandbox', '--disable-setuid-sandbox', '--disable-dev-shm-usage', '--disable-gpu'] 
        }
    });

    client.on('qr', async (qr) => {
        const src = await qrcode.toDataURL(qr);
        io.to(sessionId).emit('qr', src);
    });

    client.on('ready', () => {
        console.log('WhatsApp Pronto:', sessionId);
        io.to(sessionId).emit('ready');
    });

    client.on('message', async (msg) => {
        io.to(sessionId).emit('new-message', { from: msg.from, body: msg.body, fromMe: msg.fromMe });
    });

    client.initialize().catch(err => console.error('Erro Init:', sessionId, err));
    clients.set(sessionId, client);
}

app.post('/api/whatsapp/connect', async (req, res) => {
    const { sessionId } = req.body;
    initWhatsApp(sessionId);
    res.json({ ok: true });
});

app.get('/api/whatsapp/chats', async (req, res) => {
    const client = clients.get(req.query.sessionId);
    if (!client || !client.info) return res.json([]);
    const chats = await client.getChats();
    res.json(chats.slice(0, 50).map(c => ({ 
        id: c.id._serialized, 
        name: c.name, 
        pic: 'https://ui-avatars.com/api/?name=' + encodeURIComponent(c.name || 'User') 
    })));
});

app.post('/api/whatsapp/send', async (req, res) => {
    const { sessionId, to, message } = req.body;
    const client = clients.get(sessionId);
    if (client) { await client.sendMessage(to, message); res.json({ ok: true }); }
    else res.status(404).json({ error: 'Sessão não ativa' });
});

app.get('/api/db/:file', (req, res) => res.json(db.load(req.params.file)));
app.post('/api/db/:file', (req, res) => { db.save(req.params.file, req.body); res.json({ok:true}); });

server.listen(PORT, '0.0.0.0', () => {
    console.log('🚀 ZAPMRO ONLINE');
    restoreSessions();
});
SERVER_CODE

# 2. Atualizar o Dashboard (Frontend)
cat << 'DASHBOARD_CODE' > Public/dashboard.html
<!DOCTYPE html>
<html lang="pt-br">
<head>
    <meta charset="UTF-8">
    <title>ZAPMRO | Painel Profissional</title>
    <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/css/bootstrap.min.css" rel="stylesheet">
    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css">
    <style>
        :root { --primary: #128c7e; --dark: #111b21; --bg: #f0f2f5; }
        body { background: var(--bg); display: flex; height: 100vh; font-family: 'Segoe UI', sans-serif; margin: 0; }
        .sidebar { width: 260px; background: var(--dark); color: white; display: flex; flex-direction: column; flex-shrink: 0; }
        .menu-item { padding: 15px 25px; cursor: pointer; transition: 0.3s; display: flex; align-items: center; gap: 15px; }
        .menu-item:hover, .menu-item.active { background: var(--primary); color: white; }
        .main { flex: 1; display: flex; flex-direction: column; overflow: hidden; }
        .content-tab { display: none; height: 100%; flex-direction: column; }
        .content-tab.active { display: flex; }
        .chat-container { display: flex; height: 100%; background: white; }
        .chat-list { width: 350px; border-right: 1px solid #ddd; overflow-y: auto; }
        .chat-view { flex: 1; display: flex; flex-direction: column; background: #e5ddd5; }
        .msg-box { flex: 1; padding: 20px; overflow-y: auto; display: flex; flex-direction: column; gap: 10px; }
        .msg { padding: 8px 12px; border-radius: 8px; max-width: 70%; box-shadow: 0 1px 1px rgba(0,0,0,0.1); }
        .msg.sent { align-self: flex-end; background: #dcf8c6; }
        .msg.received { align-self: flex-start; background: white; }
        .qr-modal { position: fixed; top: 0; left: 0; width: 100%; height: 100%; background: rgba(0,0,0,0.9); z-index: 9999; display: none; align-items: center; justify-content: center; color: white; text-align: center; }
    </style>
</head>
<body>
    <div id="qr-modal" class="qr-modal">
        <div class="bg-white p-5 rounded text-dark">
            <h3>Conectar WhatsApp</h3>
            <div id="qr-loading" class="my-4"><div class="spinner-border text-primary"></div><p class="mt-2">Gerando QR Code...</p></div>
            <img id="qr-img" style="display:none; width:250px; margin-bottom:20px; border:1px solid #ddd; padding:10px;">
            <p class="text-muted">Abra o WhatsApp > Configurações > Aparelhos Conectados</p>
            <button class="btn btn-secondary" onclick="document.getElementById('qr-modal').style.display='none'">Fechar</button>
        </div>
    </div>

    <div class="sidebar">
        <div class="p-4 text-center"><h3>ZAPMRO</h3></div>
        <div class="menu-item active" onclick="switchTab('chats')"><i class="fas fa-comments"></i> Conversas</div>
        <div class="menu-item" onclick="switchTab('kanban')"><i class="fas fa-columns"></i> CRM Kanban</div>
        <div class="menu-item" onclick="switchTab('ai')"><i class="fas fa-robot"></i> Inteligência IA</div>
        <div class="menu-item mt-auto" onclick="logout()"><i class="fas fa-sign-out-alt"></i> Sair</div>
    </div>

    <div class="main">
        <div class="bg-white p-3 border-bottom d-flex justify-content-between align-items-center">
            <h5 id="tab-title" class="m-0">Central de Mensagens</h5>
            <button class="btn btn-success btn-sm" onclick="connect()">CONECTAR WHATSAPP</button>
        </div>

        <!-- ABA CHATS -->
        <div id="tab-chats" class="content-tab active">
            <div class="chat-container">
                <div id="chat-list" class="chat-list"></div>
                <div class="chat-view">
                    <div id="msgs" class="msg-box"></div>
                    <div class="p-3 bg-light d-flex gap-2">
                        <input type="text" id="msg-inp" class="form-control" placeholder="Digite uma mensagem...">
                        <button onclick="send()" class="btn btn-success"><i class="fas fa-paper-plane"></i></button>
                    </div>
                </div>
            </div>
        </div>

        <!-- ABA KANBAN -->
        <div id="tab-kanban" class="content-tab p-4">
            <h3>CRM Kanban</h3>
            <div class="row g-3 mt-2">
                <div class="col-md-4"><div class="card p-3 bg-light"><h6>Lead</h6><div id="kb-todo"></div></div></div>
                <div class="col-md-4"><div class="card p-3 bg-light"><h6>Em Atendimento</h6><div id="kb-doing"></div></div></div>
                <div class="col-md-4"><div class="card p-3 bg-light"><h6>Finalizado</h6><div id="kb-done"></div></div></div>
            </div>
        </div>

        <!-- ABA AI -->
        <div id="tab-ai" class="content-tab p-4">
            <div class="card p-4 shadow-sm">
                <h3>Agente de Inteligência Artificial</h3>
                <hr>
                <div class="mb-3"><label>Chave API OpenAI</label><input type="password" id="ai-key" class="form-control"></div>
                <div class="mb-3"><label>Prompt de Instrução</label><textarea id="ai-prompt" class="form-control" rows="5"></textarea></div>
                <button class="btn btn-primary" onclick="saveAI()">Salvar Configurações</button>
            </div>
        </div>
    </div>

    <script src="/socket.io/socket.io.js"></script>
    <script>
        const user = JSON.parse(localStorage.getItem('user'));
        const sid = user.id;
        const socket = io();
        let active = null;

        socket.emit('join', sid);
        socket.on('qr', src => { 
            document.getElementById('qr-modal').style.display='flex'; 
            document.getElementById('qr-loading').style.display='none';
            document.getElementById('qr-img').style.display='block';
            document.getElementById('qr-img').src=src; 
        });
        socket.on('ready', () => { 
            document.getElementById('qr-modal').style.display='none'; 
            loadChats(); 
        });
        socket.on('new-message', m => { if(m.from === active || m.fromMe) append(m); });

        function switchTab(t) {
            document.querySelectorAll('.content-tab').forEach(el => el.classList.remove('active'));
            document.querySelectorAll('.menu-item').forEach(el => el.classList.remove('active'));
            document.getElementById('tab-'+t).classList.add('active');
            event.currentTarget.classList.add('active');
            document.getElementById('tab-title').innerText = t === 'chats' ? 'Central de Mensagens' : (t === 'kanban' ? 'CRM Kanban' : 'Inteligência Artificial');
        }

        function connect() { 
            document.getElementById('qr-modal').style.display='flex';
            document.getElementById('qr-loading').style.display='block';
            document.getElementById('qr-img').style.display='none';
            fetch('/api/whatsapp/connect', {method:'POST', headers:{'Content-Type':'application/json'}, body:JSON.stringify({sessionId:sid})}); 
        }

        async function loadChats() {
            const r = await fetch('/api/whatsapp/chats?sessionId='+sid);
            const chats = await r.json();
            document.getElementById('chat-list').innerHTML = chats.map(c => `<div class="p-3 border-bottom cursor-pointer hover-bg" onclick="sel('${c.id}', '${c.name}')"><b>${c.name||c.id}</b></div>`).join('');
        }

        function sel(id, name) { active = id; document.getElementById('msgs').innerHTML = ''; document.getElementById('tab-title').innerText = 'Chat: ' + name; }
        
        async function send() {
            const m = document.getElementById('msg-inp').value;
            if(!m || !active) return;
            fetch('/api/whatsapp/send', {method:'POST', headers:{'Content-Type':'application/json'}, body:JSON.stringify({sessionId:sid, to:active, message:m})});
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
        
        // Carrega inicial
        loadChats();
    </script>
</body>
</html>
DASHBOARD_CODE

# 3. Reiniciar PM2
pm2 restart zapmro || pm2 start Server/index.js --name "zapmro"
pm2 save
echo "✅ TUDO ATUALIZADO E RODANDO v3.0!"
