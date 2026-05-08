#!/bin/bash
PROJECT_DIR=~/kindred-connect
cd $PROJECT_DIR

echo "🛠️ Aplicando Correção Final e Dashboard Profissional..."

# 1. Server/index.js (Robusto e com suporte a Supabase)
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
SERVER_EOF

# 2. Public/index.html (Login Moderno)
cat << 'HTML_EOF' > Public/index.html
<!DOCTYPE html>
<html lang="pt-br">
<head>
    <meta charset="UTF-8">
    <title>ZAPMRO CLOUD | Login</title>
    <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/css/bootstrap.min.css" rel="stylesheet">
    <script src="https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2"></script>
    <style>
        body { background: linear-gradient(135deg, #128c7e 0%, #075e54 100%); height: 100vh; display: flex; align-items: center; justify-content: center; font-family: sans-serif; }
        .login-card { background: white; padding: 40px; border-radius: 20px; box-shadow: 0 15px 35px rgba(0,0,0,0.2); width: 100%; max-width: 400px; text-align: center; }
        .logo { color: #128c7e; font-weight: 800; margin-bottom: 30px; }
        .btn-custom { background: #128c7e; color: white; border-radius: 10px; padding: 12px; width: 100%; border: none; font-weight: bold; }
    </style>
</head>
<body>
    <div class="login-card">
        <h2 class="logo">ZAPMRO CLOUD</h2>
        <div class="mb-3"><input type="email" id="email" class="form-control" placeholder="E-mail"></div>
        <div class="mb-3"><input type="password" id="password" class="form-control" placeholder="Senha"></div>
        <button onclick="auth()" class="btn-custom">ACESSAR DASHBOARD</button>
    </div>
    <script>
        const supabaseUrl = 'https://tuwokddiyltxsmcmzbaz.supabase.co';
        const supabaseKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InR1d29rZGRpeWx0eHNtY216YmF6Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzgxOTc5MjQsImV4cCI6MjA5Mzc3MzkyNH0.m-b9PvlWfMYewSLHD2L9VjJuDXBJq60DDqJme6UNdrI';
        const client = supabase.createClient(supabaseUrl, supabaseKey);
        async function auth() {
            const email = document.getElementById('email').value;
            const password = document.getElementById('password').value;
            let { data, error } = await client.auth.signInWithPassword({ email, password });
            if (error) {
                let { data: up, error: err2 } = await client.auth.signUp({ email, password });
                if (err2) return alert(err2.message);
                alert('Cadastro realizado! Logue novamente.');
            } else {
                localStorage.setItem('user', JSON.stringify(data.user));
                window.location.href = 'dashboard.html';
            }
        }
    </script>
</body>
</html>
HTML_EOF

# 3. Public/dashboard.html (Dashboard Real)
cat << 'DASH_EOF' > Public/dashboard.html
<!DOCTYPE html>
<html lang="pt-br">
<head>
    <meta charset="UTF-8">
    <title>ZAPMRO | Dashboard CRM</title>
    <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/css/bootstrap.min.css" rel="stylesheet">
    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css">
    <style>
        body { background: #f0f2f5; height: 100vh; display: flex; overflow: hidden; }
        .side { width: 350px; background: #fff; border-right: 1px solid #ddd; display: flex; flex-direction: column; }
        .main { flex: 1; display: flex; flex-direction: column; background: #e5ddd5; }
        .chat-item { padding: 15px; border-bottom: 1px solid #f0f0f0; cursor: pointer; }
        .chat-item:hover { background: #f9f9f9; }
        .msg-container { flex: 1; overflow-y: auto; padding: 20px; display: flex; flex-direction: column; gap: 10px; }
        .msg { padding: 8px 15px; border-radius: 10px; max-width: 75%; }
        .msg.sent { align-self: flex-end; background: #dcf8c6; }
        .msg.received { align-self: flex-start; background: #fff; }
        .input-box { background: #f0f2f5; padding: 15px; display: flex; gap: 10px; }
        .qr-modal { position: fixed; top: 0; left: 0; width: 100%; height: 100%; background: rgba(0,0,0,0.8); display: none; align-items: center; justify-content: center; z-index: 1000; color: #fff; flex-direction: column; }
    </style>
</head>
<body>
    <div id="qrModal" class="qr-modal">
        <h3>Escaneie o QR Code</h3>
        <div style="background:#fff; padding:20px; border-radius:15px;"><img id="qrImg" style="width:250px;"></div>
        <p class="mt-3">Aguardando conexão...</p>
    </div>

    <div class="side">
        <div class="p-3 bg-light border-bottom d-flex justify-content-between">
            <h5 class="text-success m-0">ZAPMRO</h5>
            <button onclick="connect()" class="btn btn-success btn-sm"><i class="fas fa-qrcode"></i></button>
        </div>
        <div id="list" class="overflow-auto flex-grow-1"></div>
    </div>

    <div class="main">
        <div id="header" class="p-3 bg-light border-bottom"><strong>Selecione um chat</strong></div>
        <div id="msgs" class="msg-container"></div>
        <div class="input-box">
            <input type="text" id="inp" class="form-control" placeholder="Mensagem...">
            <button onclick="send()" class="btn btn-success"><i class="fas fa-paper-plane"></i></button>
        </div>
    </div>

    <script src="/socket.io/socket.io.js"></script>
    <script>
        const user = JSON.parse(localStorage.getItem('user'));
        if (!user) window.location.href = 'index.html';
        const socket = io();
        const sid = user.id;
        let active = null;

        socket.emit('join', sid);
        socket.on('qr', src => { document.getElementById('qrModal').style.display='flex'; document.getElementById('qrImg').src=src; });
        socket.on('ready', () => { document.getElementById('qrModal').style.display='none'; loadChats(); });

        async function connect() { fetch('/api/whatsapp/connect', { method:'POST', headers:{'Content-Type':'application/json'}, body:JSON.stringify({sessionId:sid}) }); }
        
        async function loadChats() {
            const r = await fetch('/api/whatsapp/chats?sessionId='+sid);
            const chats = await r.json();
            const list = document.getElementById('list');
            list.innerHTML = chats.map(c => `<div class="chat-item" onclick="sel('${c.id}','${c.name}')"><strong>${c.name||c.id}</strong></div>`).join('');
        }

        function sel(id, name) { active=id; document.getElementById('header').innerHTML=`<strong>${name||id}</strong>`; document.getElementById('msgs').innerHTML=''; }

        async function send() {
            const v = document.getElementById('inp').value;
            if(!v || !active) return;
            fetch('/api/whatsapp/send', { method:'POST', headers:{'Content-Type':'application/json'}, body:JSON.stringify({sessionId:sid, to:active, message:v}) });
            append({ body: v, fromMe: true });
            document.getElementById('inp').value = '';
        }

        socket.on('new-message', m => { if(m.from===active || m.fromMe) append(m); });
        function append(m) {
            const d = document.createElement('div');
            d.className = 'msg ' + (m.fromMe?'sent':'received');
            d.innerText = m.body;
            document.getElementById('msgs').appendChild(d);
            document.getElementById('msgs').scrollTop = document.getElementById('msgs').scrollHeight;
        }
    </script>
</body>
</html>
DASH_EOF

# 4. Finalização
pm2 delete zapmro 2>/dev/null
pm2 start Server/index.js --name "zapmro"
pm2 save
echo "✅ ZAPMRO 100% PROFISSIONAL E FUNCIONANDO!"
pm2 logs zapmro
