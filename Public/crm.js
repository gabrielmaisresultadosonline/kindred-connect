const socket = io();
const params = new URLSearchParams(window.location.search);
const sessionId = params.get('sessionId');
let currentChatId = null;

if (!sessionId) {
    window.location.href = 'index.html';
}

socket.emit('bind-session', sessionId);
socket.emit('get-chats', sessionId);
socket.emit('get-kanban-columns', sessionId);
socket.emit('get-ai-config', sessionId);

function switchTab(tab) {
    document.querySelectorAll('.tab-btn').forEach(b => b.classList.remove('active'));
    event.target.classList.add('active');
    
    document.getElementById('chat-window').style.display = tab === 'whatsapp' ? 'flex' : 'none';
    document.getElementById('kanban-view').style.display = tab === 'kanban' ? 'flex' : 'none';
    document.getElementById('ai-settings').style.display = tab === 'ai' ? 'block' : 'none';
    document.getElementById('current-view-title').innerText = tab.charAt(0).toUpperCase() + tab.slice(1);
}

socket.on('chats-loaded', (chats) => {
    const list = document.getElementById('chat-list-container');
    list.innerHTML = '';
    chats.forEach(chat => {
        const item = document.createElement('div');
        item.className = 'chat-item';
        item.innerHTML = `
            <strong>${chat.name || chat.id}</strong><br>
            <small>${chat.lastMessage ? chat.lastMessage.body.substring(0, 30) : ''}</small>
        `;
        item.onclick = () => openChat(chat.id);
        list.appendChild(item);
    });
});

function openChat(chatId) {
    currentChatId = chatId;
    socket.emit('get-chat-history', { sessionId, chatId });
}

socket.on('chat-history', ({ chatId, history }) => {
    if (chatId !== currentChatId) return;
    const container = document.getElementById('messages-container');
    container.innerHTML = '';
    history.forEach(msg => {
        renderMessage(msg);
    });
    container.scrollTop = container.scrollHeight;
});

socket.on('new-message', ({ chatId, message }) => {
    if (chatId === currentChatId) {
        renderMessage(message);
        const container = document.getElementById('messages-container');
        container.scrollTop = container.scrollHeight;
    }
});

function renderMessage(msg) {
    const container = document.getElementById('messages-container');
    const div = document.createElement('div');
    div.className = `message ${msg.fromMe ? 'sent' : 'received'}`;
    div.innerText = msg.body;
    container.appendChild(div);
}

function sendMessage() {
    const input = document.getElementById('msg-input');
    const content = input.value;
    if (!content || !currentChatId) return;
    
    socket.emit('send-message', { sessionId, chatId: currentChatId, content });
    renderMessage({ body: content, fromMe: true });
    input.value = '';
    const container = document.getElementById('messages-container');
    container.scrollTop = container.scrollHeight;
}

socket.on('kanban-columns', (columns) => {
    const view = document.getElementById('kanban-view');
    view.innerHTML = '';
    columns.forEach(col => {
        const div = document.createElement('div');
        div.className = 'kanban-column';
        div.innerHTML = `<h3>${col.name}</h3>`;
        col.chats.forEach(chatId => {
            const card = document.createElement('div');
            card.className = 'kanban-card';
            card.innerText = chatId;
            div.appendChild(card);
        });
        view.appendChild(div);
    });
});

socket.on('ai-config-data', (config) => {
    document.getElementById('ai-enabled').checked = config.enabled;
    document.getElementById('ai-provider').value = config.provider;
    document.getElementById('ai-instructions').value = config.instructions || '';
});

function saveAiConfig() {
    const config = {
        enabled: document.getElementById('ai-enabled').checked,
        provider: document.getElementById('ai-provider').value,
        instructions: document.getElementById('ai-instructions').value
    };
    socket.emit('save-ai-config', { sessionId, config });
    alert('Configuração salva!');
}
