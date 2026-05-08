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
