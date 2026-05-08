#!/bin/bash
PROJECT_DIR=~/kindred-connect
cd $PROJECT_DIR

echo "🎨 Atualizando Layout Profissional e Corrigindo Backend..."

# 1. Recriar Server/index.js (Completo com Tratamento de Erro)
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
SERVER_EOF

# 2. Recriar Public/index.html (Layout Profissional ZAPMRO)
cat << 'HTML_EOF' > Public/index.html
<!DOCTYPE html>
<html lang="pt-br">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>ZAPMRO CLOUD | Conexão</title>
    <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/css/bootstrap.min.css" rel="stylesheet">
    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css">
    <style>
        body { background: #f0f2f5; font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; height: 100vh; display: flex; align-items: center; justify-content: center; }
        .card-zap { border: none; border-radius: 15px; box-shadow: 0 10px 30px rgba(0,0,0,0.1); width: 100%; max-width: 450px; overflow: hidden; }
        .card-header { background: #128c7e; color: white; padding: 25px; text-align: center; border: none; }
        .card-body { padding: 40px; background: white; text-align: center; }
        .qr-container { background: #f8f9fa; padding: 20px; border-radius: 10px; min-height: 250px; display: flex; align-items: center; justify-content: center; margin-top: 20px; border: 2px dashed #ddd; }
        .btn-zap { background: #25d366; color: white; border: none; padding: 12px 30px; border-radius: 30px; font-weight: bold; width: 100%; transition: 0.3s; }
        .btn-zap:hover { background: #128c7e; transform: translateY(-2px); color: white; }
        #loading { display: none; }
        .status-badge { font-size: 0.8rem; padding: 5px 15px; border-radius: 20px; margin-top: 10px; display: inline-block; }
    </style>
</head>
<body>
    <div class="card-zap">
        <div class="card-header">
            <h3><i class="fab fa-whatsapp me-2"></i>ZAPMRO CLOUD</h3>
            <p class="mb-0">WhatsApp Multi-Device Connection</p>
        </div>
        <div class="card-body">
            <h5 class="mb-4">Conectar Novo Aparelho</h5>
            <button id="btnConnect" onclick="startSession()" class="btn-zap">
                <i class="fas fa-qrcode me-2"></i>GERAR QR CODE
            </button>
            
            <div id="loading" class="mt-3">
                <div class="spinner-border text-success" role="status"></div>
                <p class="mt-2 text-muted">Iniciando Chrome e Gerando QR...</p>
            </div>

            <div class="qr-container" id="qr-box">
                <p id="qr-placeholder" class="text-muted">Clique no botão acima para começar</p>
                <img id="qr-img" style="display:none; width: 100%;">
            </div>

            <div id="status-box"></div>
        </div>
    </div>

    <script src="/socket.io/socket.io.js"></script>
    <script>
        const socket = io();
        const sessionId = 'session_' + Math.random().toString(36).substr(2, 9);
        
        socket.emit('join', sessionId);

        async function startSession() {
            document.getElementById('btnConnect').style.display = 'none';
            document.getElementById('loading').style.display = 'block';
            document.getElementById('qr-placeholder').style.display = 'none';

            try {
                const response = await fetch('/api/create-session', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({ sessionId })
                });
                
                if (!response.ok) throw new Error('Falha no servidor');
                
            } catch (err) {
                alert('Erro ao conectar com o servidor. Verifique o console.');
                document.getElementById('btnConnect').style.display = 'block';
                document.getElementById('loading').style.display = 'none';
            }
        }

        socket.on('qr', (src) => {
            document.getElementById('loading').style.display = 'none';
            const img = document.getElementById('qr-img');
            img.src = src;
            img.style.display = 'block';
            document.getElementById('status-box').innerHTML = '<span class="status-badge bg-info text-white">QR Code Gerado! Escaneie agora.</span>';
        });

        socket.on('ready', () => {
            document.getElementById('qr-box').innerHTML = '<div class="text-success"><i class="fas fa-check-circle fa-5x"></i><h4 class="mt-3">Conectado com Sucesso!</h4></div>';
            document.getElementById('status-box').innerHTML = '<span class="status-badge bg-success text-white">Online</span>';
        });

        socket.on('error', (msg) => {
            alert('Erro: ' + msg);
            location.reload();
        });
    </script>
</body>
</html>
HTML_EOF

# 3. Reiniciar PM2
pm2 delete zapmro 2>/dev/null
pm2 start Server/index.js --name "zapmro"
pm2 save

echo "✅ LAYOUT E BACKEND ATUALIZADOS!"
