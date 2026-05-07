const socket = io();
let currentUser = null;
let currentToken = localStorage.getItem('token');

if (currentToken) {
    checkAuth();
}

function switchAuthTab(tab) {
    document.querySelectorAll('.tab').forEach(t => t.classList.remove('active'));
    event.target.classList.add('active');
    if (tab === 'login') {
        document.getElementById('login-form').style.display = 'block';
        document.getElementById('register-form').style.display = 'none';
    } else {
        document.getElementById('login-form').style.display = 'none';
        document.getElementById('register-form').style.display = 'block';
    }
}

async function doLogin() {
    const email = document.getElementById('login-email').value;
    const promoCode = document.getElementById('login-promo').value;
    
    const res = await fetch('/api/auth/login', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ email, promoCode })
    });
    
    const data = await res.json();
    if (data.token) {
        setAuth(data);
    } else {
        alert(data.error || 'Erro ao logar');
    }
}

async function doRegister() {
    const name = document.getElementById('reg-name').value;
    const email = document.getElementById('reg-email').value;
    const promoCode = document.getElementById('reg-promo').value;
    
    const res = await fetch('/api/auth/register', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ name, email, promoCode })
    });
    
    const data = await res.json();
    if (data.token) {
        setAuth(data);
    } else {
        alert(data.error || 'Erro ao cadastrar');
    }
}

function setAuth(data) {
    localStorage.setItem('token', data.token);
    currentUser = data.user;
    showDashboard();
}

async function checkAuth() {
    const res = await fetch('/api/me', {
        headers: { 'Authorization': `Bearer ${localStorage.getItem('token')}` }
    });
    if (res.ok) {
        currentUser = await res.json();
        showDashboard();
    } else {
        localStorage.removeItem('token');
    }
}

function showDashboard() {
    document.getElementById('auth-section').style.display = 'none';
    document.getElementById('dashboard-section').style.display = 'block';
    document.getElementById('user-name').innerText = currentUser.name;
    loadSessions();
    socket.emit('bind-session', currentUser.id);
}

function logout() {
    localStorage.removeItem('token');
    location.reload();
}

async function createSession() {
    const res = await fetch('/api/create-session', {
        method: 'POST',
        headers: { 
            'Content-Type': 'application/json',
            'Authorization': `Bearer ${localStorage.getItem('token')}`
        }
    });
    const data = await res.json();
    console.log('Session created:', data);
}

async function loadSessions() {
    const res = await fetch('/api/active-sessions', {
        headers: { 'Authorization': `Bearer ${localStorage.getItem('token')}` }
    });
    const sessions = await res.json();
    const list = document.getElementById('sessions-list');
    list.innerHTML = '';
    sessions.forEach(s => {
        const item = document.createElement('div');
        item.className = 'session-item';
        item.innerHTML = `
            <span>WhatsApp (${s.id})</span>
            <span class="status-badge status-${s.status}">${s.status}</span>
            <button onclick="window.location.href='/crm.html?sessionId=${s.id}'">Abrir CRM</button>
        `;
        list.appendChild(item);
    });
}

socket.on('qr-generated', (data) => {
    document.getElementById('qr-container').style.display = 'block';
    document.getElementById('qr-image').src = data.qr;
});

socket.on('client-ready', () => {
    document.getElementById('qr-container').style.display = 'none';
    loadSessions();
});
