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

app.use(cors());
app.use(express.json());
app.use(express.static('Public'));

const clients = new Map();
const db = {
    load: (f) => { try { return JSON.parse(fs.readFileSync('./data/' + f + '.json')); } catch { return []; } },
    save: (f, d) => { if(!fs.existsSync('./data')) fs.mkdirSync('./data'); fs.writeFileSync('./data/' + f + '.json', JSON.stringify(d, null, 2)); },
    ensure: (f) => { if(!fs.existsSync('./data/' + f + '.json')) db.save(f, []); }
};
['flows', 'ai_config', 'scheduled_messages', 'kanban'].forEach(db.ensure);

app.post('/api/whatsapp/connect', (req, res) => {
    const sessionId = req.body.sessionId;
    if(clients.has(sessionId)) return res.json({ok:true});
    const client = new Client({
        authStrategy: new LocalAuth({ clientId: sessionId }),
        puppeteer: { headless: true, args: ['--no-sandbox'] }
    });
    client.on('qr', async (qr) => io.to(sessionId).emit('qr', await qrcode.toDataURL(qr)));
    client.on('ready', () => io.to(sessionId).emit('ready'));
    client.on('message', m => io.to(sessionId).emit('new-message', {from:m.from, body:m.body, fromMe:m.fromMe}));
    client.initialize().catch(console.error);
    clients.set(sessionId, client);
    res.json({ok:true});
});

app.get('/api/whatsapp/chats', async (req, res) => {
    const client = clients.get(req.query.sessionId);
    if(!client || !client.info) return res.json([]);
    try {
        const chats = await client.getChats();
        res.json(chats.slice(0,40).map(c => ({id:c.id._serialized, name:c.name})));
    } catch(e) { res.json([]); }
});

app.post('/api/whatsapp/send', async (req, res) => {
    const client = clients.get(req.body.sessionId);
    if(client) { await client.sendMessage(req.body.to, req.body.message); res.json({ok:true}); }
    else res.status(404).send();
});

app.get('/api/db/:file', (req, res) => res.json(db.load(req.params.file)));
app.post('/api/db/:file', (req, res) => { db.save(req.params.file, req.body); res.json({ok:true}); });

server.listen(3000, '0.0.0.0', () => console.log('🚀 ONLINE NA PORTA 3000'));
