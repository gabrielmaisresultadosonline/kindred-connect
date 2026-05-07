import fs from 'fs';
import path from 'path';

const DATA_FILE = path.join(process.cwd(), 'data/proxy_sessions.json');

const PROXY_CONFIG = {
    host: 'superproxy.com', // Placeholder as per doc
    port: '8888',
    username: 'base_user',
    password: 'base_password',
    limitPerProxy: 3,
    totalLimit: 9
};

function loadData() {
    try {
        if (!fs.existsSync(DATA_FILE)) return {};
        return JSON.parse(fs.readFileSync(DATA_FILE, 'utf8'));
    } catch (e) {
        console.error('Error loading proxy data:', e);
        return {};
    }
}

function saveData(data) {
    try {
        fs.writeFileSync(DATA_FILE, JSON.stringify(data, null, 2));
    } catch (e) {
        console.error('Error saving proxy data:', e);
    }
}

export function generateProxySessionId() {
    return 'px-' + Math.random().toString(36).substr(2, 9);
}

export function getAssignment(waSessionId) {
    const data = loadData();
    if (data[waSessionId]) return data[waSessionId];

    // Simple logic to assign a proxy (placeholder for more complex rotation)
    const proxyId = generateProxySessionId();
    data[waSessionId] = {
        proxyId,
        host: PROXY_CONFIG.host,
        port: PROXY_CONFIG.port,
        username: `${PROXY_CONFIG.username}-session-${proxyId}`,
        password: PROXY_CONFIG.password
    };
    saveData(data);
    return data[waSessionId];
}

export function releaseAssignment(waSessionId) {
    const data = loadData();
    delete data[waSessionId];
    saveData(data);
}

export function getProxyForSession(waSessionId) {
    return getAssignment(waSessionId);
}

export function getStats() {
    const data = loadData();
    return {
        activeAssignments: Object.keys(data).length,
        totalLimit: PROXY_CONFIG.totalLimit
    };
}
