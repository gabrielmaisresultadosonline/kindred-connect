import express from 'express';
import http from 'http';
import { Server } from 'socket.io';
import cors from 'cors';
import dotenv from 'dotenv';
import path from 'path';
import fs from 'fs';
import multer from 'multer';
import axios from 'axios';
import { Client, LocalAuth, MessageMedia } from 'whatsapp-web.js';
import qrcode from 'qrcode';
import ffmpeg from 'fluent-ffmpeg';
import ffmpegPath from 'ffmpeg-static';
import * as proxyManager from './proxyManager.js';

dotenv.config();
ffmpeg.setFfmpegPath(ffmpegPath);

const app = express();
const server = http.createServer(app);
const io = new Server(server, {
    cors: { origin: "*" }
});

const PORT = process.env.PORT || 3000;
const __dirname = path.resolve();

app.use(cors());
app.use(express.json());
app.use(express.static('Public'));

// --- Utility Functions ---

function generateId() {
    return Math.random().toString(36).substr(2, 9);
}

function normalizeBoolean(val, fallback = false) {
    if (typeof val === 'boolean') return val;
    if (val === 'true') return true;
    if (val === 'false') return false;
    return fallback;
}

// --- Persistence Helpers ---

function readJson(file) {
    const filePath = path.join(__dirname, 'data', file);
    if (!fs.existsSync(filePath)) return null;
    return JSON.parse(fs.readFileSync(filePath, 'utf8'));
}

function writeJson(file, data) {
    const filePath = path.join(__dirname, 'data', file);
    fs.writeFileSync(filePath, JSON.stringify(data, null, 2));
}

// --- Auth Middleware & Logic ---

const usersStore = () => readJson('users.json') || [];
const tokensStore = () => readJson('auth_tokens.json') || [];

function createAuthToken(user) {
    const token = generateId() + generateId();
    const tokens = tokensStore();
    tokens.push({ token, userId: user.id, isAdmin: user.isAdmin, expires: Date.now() + 86400000 });
    writeJson('auth_tokens.json', tokens);
    return token;
}

function validateAuthToken(token) {
    const tokens = tokensStore();
    return tokens.find(t => t.token === token && t.expires > Date.now());
}

const requireUser = (req, res, next) => {
    const token = req.headers.authorization?.split(' ')[1];
    const session = validateAuthToken(token);
    if (!session) return res.status(401).json({ error: 'Unauthorized' });
    req.user = usersStore().find(u => u.id === session.userId);
    next();
};

// --- WhatsApp Clients State ---
const clients = new Map();

// --- API Routes ---

app.post('/api/auth/register', (req, res) => {
    const { name, email, promoCode } = req.body;
    if (promoCode !== process.env.TEST_PROMO_CODE) return res.status(400).json({ error: 'Invalid promo code' });
    
    let users = usersStore();
    let user = users.find(u => u.email === email);
    if (!user) {
        user = { id: generateId(), name, email, promoCode, isAdmin: false };
        users.push(user);
        writeJson('users.json', users);
    }
    const token = createAuthToken(user);
    res.json({ token, user });
});

app.post('/api/auth/login', (req, res) => {
    const { email, promoCode } = req.body;
    const user = usersStore().find(u => u.email === email && u.promoCode === promoCode);
    if (!user) return res.status(401).json({ error: 'Invalid credentials' });
    const token = createAuthToken(user);
    res.json({ token, user });
});

app.get('/api/me', requireUser, (req, res) => {
    res.json(req.user);
});

// ... More routes and logic will follow
// Initialize server
server.listen(PORT, () => {
    console.log(`ZAPMRO CLOUD running on port ${PORT}`);
});
