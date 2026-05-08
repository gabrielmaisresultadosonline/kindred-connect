#!/bin/bash
PROJECT_DIR=~/kindred-connect
cd $PROJECT_DIR

echo "🛠️ Transformando ZAPMRO em Ferramenta Profissional..."

# 1. Atualizar Server/index.js para suportar Supabase e Dashboard Completa
cat << 'SERVER_EOF' > Server/index.js
import express from 'express';
import http from 'http';
import { Server } from 'socket.io';
import cors from 'cors';
import path from 'path';
import fs from 'fs';
import pkg from 'whatsapp-web.js';
const { Client, LocalAuth, MessageMedia } = pkg;
import qrcode from 'qrcode';
import dotenv from 'dotenv';
import { createClient } from '@supabase/supabase-js';

dotenv.config();

const app = express();
const server = http.createServer(app);
const io = new Server(server, { cors: { origin: "*" } });
const PORT = 3000;

// Supabase Setup
const supabase = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_PUBLISHABLE_KEY);

app.use(cors());
app.use(express.json());
app.use(express.static('Public'));

const clients = new Map();

// --- WhatsApp Logic ---
async function getClient(sessionId) {
    if (clients.has(sessionId)) return clients.get(sessionId);
    
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
        io.to(sessionId).emit('ready');
        console.log('WhatsApp Ready for session:', sessionId);
    });

    client.on('message', async (msg) => {
        // Enviar para o Dashboard em tempo real
        io.to(sessionId).emit('new-message', {
            from: msg.from,
            body: msg.body,
            timestamp: msg.timestamp,
            fromMe: msg.fromMe
        });
    });

    clients.set(sessionId, client);
    await client.initialize();
    return client;
}

// --- API Routes ---

app.post('/api/whatsapp/connect', async (req, res) => {
    const { sessionId } = req.body;
    await getClient(sessionId);
    res.json({ ok: true });
});

app.post('/api/whatsapp/send', async (req, res) => {
    const { sessionId, to, message } = req.body;
    const client = clients.get(sessionId);
    if (!client) return res.status(404).json({ error: 'Sessão não iniciada' });
    
    await client.sendMessage(to, message);
    res.json({ ok: true });
});

app.get('/api/whatsapp/chats', async (req, res) => {
    const { sessionId } = req.query;
    const client = clients.get(sessionId);
    if (!client) return res.status(404).json({ error: 'Sessão não iniciada' });
    
    const chats = await client.getChats();
    res.json(chats.map(c => ({
        id: c.id._serialized,
        name: c.name,
        unreadCount: c.unreadCount
    })));
});

io.on('connection', (s) => {
    s.on('join', (id) => s.join(id));
});

server.listen(PORT, '0.0.0.0', () => {
    console.log('🚀 ZAPMRO PROFESSIONAL ONLINE: http://167.88.42.133:3000');
});
SERVER_EOF

# 2. Criar Public/index.html (Página de Login/Cadastro Profissional)
cat << 'HTML_EOF' > Public/index.html
<!DOCTYPE html>
<html lang="pt-br">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>ZAPMRO CLOUD | Login Profissional</title>
    <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/css/bootstrap.min.css" rel="stylesheet">
    <script src="https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2"></script>
    <style>
        body { background: #f0f2f5; display: flex; align-items: center; justify-content: center; height: 100vh; }
        .auth-card { background: white; padding: 40px; border-radius: 15px; box-shadow: 0 10px 30px rgba(0,0,0,0.1); width: 100%; max-width: 400px; }
        .btn-zap { background: #128c7e; color: white; border-radius: 30px; padding: 12px; font-weight: bold; width: 100%; border: none; }
        .btn-zap:hover { background: #075e54; color: white; }
        .logo { color: #128c7e; text-align: center; margin-bottom: 30px; font-weight: bold; }
    </style>
</head>
<body>
    <div class="auth-card">
        <div class="logo"><h2>ZAPMRO CLOUD</h2></div>
        <div id="auth-form">
            <div class="mb-3">
                <input type="email" id="email" class="form-control" placeholder="Seu E-mail">
            </div>
            <div class="mb-3">
                <input type="password" id="password" class="form-control" placeholder="Sua Senha">
            </div>
            <button onclick="handleAuth()" id="btnAuth" class="btn-zap">ENTRAR / CADASTRAR</button>
        </div>
    </div>

    <script>
        const supabaseUrl = 'https://tuwokddiyltxsmcmzbaz.supabase.co';
        const supabaseKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InR1d29rZGRpeWx0eHNtY216YmF6Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzgxOTc5MjQsImV4cCI6MjA5Mzc3MzkyNH0.m-b9PvlWfMYewSLHD2L9VjJuDXBJq60DDqJme6UNdrI';
        const supabaseClient = supabase.createClient(supabaseUrl, supabaseKey);

        async function handleAuth() {
            const email = document.getElementById('email').value;
            const password = document.getElementById('password').value;
            const btn = document.getElementById('btnAuth');
            btn.disabled = true;

            const { data: loginData, error: loginError } = await supabaseClient.auth.signInWithPassword({ email, password });
            
            if (loginError) {
                const { data: regData, error: regError } = await supabaseClient.auth.signUp({ email, password });
                if (regError) {
                    alert('Erro: ' + regError.message);
                    btn.disabled = false;
                    return;
                }
                alert('Conta criada! Verifique seu email ou tente logar.');
                btn.disabled = false;
            } else {
                localStorage.setItem('user', JSON.stringify(loginData.user));
                window.location.href = 'dashboard.html';
            }
        }
    </script>
</body>
</html>
HTML_EOF

# 3. Criar Public/dashboard.html (Dashboard CRM Profissional)
cat << 'DASH_EOF' > Public/dashboard.html
<!DOCTYPE html>
<html lang="pt-br">
<head>
    <meta charset="UTF-8">
    <title>Dashboard ZAPMRO</title>
    <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/css/bootstrap.min.css" rel="stylesheet">
    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css">
    <style>
        body { background: #f0f2f5; height: 100vh; display: flex; overflow: hidden; }
        .sidebar { width: 300px; background: white; border-right: 1px solid #ddd; display: flex; flex-direction: column; }
        .content { flex: 1; background: #e5ddd5; display: flex; flex-direction: column; }
        .chat-list { overflow-y: auto; flex: 1; }
        .chat-item { padding: 15px; border-bottom: 1px solid #eee; cursor: pointer; transition: 0.2s; }
        .chat-item:hover { background: #f5f5f5; }
        .chat-header { background: #f0f2f5; padding: 10px 20px; border-bottom: 1px solid #ddd; display: flex; align-items: center; }
        .messages { flex: 1; overflow-y: auto; padding: 20px; display: flex; flex-direction: column; gap: 10px; }
        .msg { padding: 8px 15px; border-radius: 8px; max-width: 70%; font-size: 0.9rem; }
        .msg.sent { align-self: flex-end; background: #dcf8c6; }
        .msg.received { align-self: flex-start; background: white; }
        .input-area { background: #f0f2f5; padding: 15px; display: flex; gap: 10px; }
        .qr-overlay { position: fixed; top: 0; left: 0; width: 100%; height: 100%; background: rgba(0,0,0,0.8); display: none; align-items: center; justify-content: center; z-index: 9999; color: white; flex-direction: column; }
    </style>
</head>
<body>
    <div id="qr-overlay" class="qr-overlay">
        <h3>Escaneie para Conectar</h3>
        <div id="qr-container" style="background: white; padding: 20px; border-radius: 10px;">
            <img id="qr-img" style="width: 250px;">
        </div>
        <p class="mt-3">Aguardando leitura...</p>
    </div>

    <div class="sidebar">
        <div class="p-3 border-bottom d-flex justify-content-between align-items-center">
            <h5 class="mb-0 text-success">ZAPMRO</h5>
            <button onclick="startConnection()" class="btn btn-sm btn-outline-success"><i class="fas fa-plus"></i></button>
        </div>
        <div id="chat-list" class="chat-list">
            <div class="p-3 text-center text-muted">Carregando chats...</div>
        </div>
    </div>

    <div class="content">
        <div id="chat-header" class="chat-header">
            <h6 id="current-chat-name" class="mb-0">Selecione uma conversa</h6>
        </div>
        <div id="messages" class="messages"></div>
        <div class="input-area">
            <input type="text" id="msg-input" class="form-control" placeholder="Digite uma mensagem...">
            <button onclick="sendMsg()" class="btn btn-success"><i class="fas fa-paper-plane"></i></button>
        </div>
    </div>

    <script src="/socket.io/socket.io.js"></script>
    <script>
        const user = JSON.parse(localStorage.getItem('user'));
        if (!user) window.location.href = 'index.html';

        const socket = io();
        const sessionId = user.id;
        let activeChat = null;

        socket.emit('join', sessionId);

        async function startConnection() {
            document.getElementById('qr-overlay').style.display = 'flex';
            await fetch('/api/whatsapp/connect', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ sessionId })
            });
        }

        socket.on('qr', (src) => {
            document.getElementById('qr-img').src = src;
        });

        socket.on('ready', () => {
            document.getElementById('qr-overlay').style.display = 'none';
            loadChats();
        });

        async function loadChats() {
            const r = await fetch(`/api/whatsapp/chats?sessionId=${sessionId}`);
            const chats = await r.json();
            const list = document.getElementById('chat-list');
            list.innerHTML = '';
            chats.forEach(c => {
                const div = document.createElement('div');
                div.className = 'chat-item';
                div.innerHTML = `<strong>${c.name || c.id}</strong>`;
                div.onclick = () => selectChat(c.id, c.name);
                list.appendChild(div);
            });
        }

        function selectChat(id, name) {
            activeChat = id;
            document.getElementById('current-chat-name').innerText = name || id;
            document.getElementById('messages').innerHTML = '';
        }

        async function sendMsg() {
            const input = document.getElementById('msg-input');
            const message = input.value;
            if (!message || !activeChat) return;

            await fetch('/api/whatsapp/send', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ sessionId, to: activeChat, message })
            });

            appendMsg({ body: message, fromMe: true });
            input.value = '';
        }

        socket.on('new-message', (msg) => {
            if (msg.from === activeChat || msg.fromMe) {
                appendMsg(msg);
            }
        });

        function appendMsg(msg) {
            const div = document.createElement('div');
            div.className = `msg ${msg.fromMe ? 'sent' : 'received'}`;
            div.innerText = msg.body;
            document.getElementById('messages').appendChild(div);
            const container = document.getElementById('messages');
            container.scrollTop = container.scrollHeight;
        }
    </script>
</body>
</html>
DASH_EOF

# 4. Finalização e Restart
# Garantir que as pastas existem na VPS
mkdir -p $PROJECT_DIR/Server
mkdir -p $PROJECT_DIR/Public

# Instalar pm2 global se não existir
if ! command -v pm2 &> /dev/null
then
    sudo npm install -g pm2
fi

# Reiniciar
pm2 delete zapmro 2>/dev/null
pm2 start Server/index.js --name "zapmro"
pm2 save
echo "✅ ZAPMRO PROFISSIONAL INSTALADO COM SUCESSO!"
pm2 logs zapmro
