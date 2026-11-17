const token = localStorage.getItem('chat_token');
const username = localStorage.getItem('chat_username');
const messagesEl = document.getElementById('messages');
const statusEl = document.getElementById('connectionStatus');
const inputEl = document.getElementById('messageInput');

let socket = null;
let reconnectTimer = null;

if (!token) {
    window.location.href = '/';
}

document.getElementById('usernameDisplay').textContent = username || '';

function scrollToBottom() {
    messagesEl.scrollTop = messagesEl.scrollHeight;
}

function appendMessage(msg, mine) {
    const row = document.createElement('div');
    row.className = 'message' + (mine ? ' mine' : '');

    const meta = document.createElement('div');
    meta.className = 'msg-meta';
    meta.textContent = msg.username + '  ' + (msg.time || '');

    const bubble = document.createElement('div');
    bubble.className = 'msg-bubble';
    bubble.textContent = msg.content;

    row.appendChild(meta);
    row.appendChild(bubble);
    messagesEl.appendChild(row);
    scrollToBottom();
}

async function loadHistory() {
    try {
        const resp = await fetch('/api/history?token=' + encodeURIComponent(token));
        const data = await resp.json();
        if (!data.ok) {
            if (resp.status === 401) logout();
            return;
        }
        messagesEl.innerHTML = '';
        data.messages.forEach(m => appendMessage(m, m.username === username));
    } catch (err) {
        setStatus('加载历史消息失败', false);
    }
}

function setStatus(text, connected) {
    statusEl.textContent = text;
    statusEl.className = 'connection-status ' + (connected ? 'online' : 'offline');
}

function connectWebSocket() {
    const protocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:';
    const wsUrl = protocol + '//' + window.location.host + '/ws?token=' + encodeURIComponent(token);
    socket = new WebSocket(wsUrl);

    socket.onopen = () => setStatus('已连接', true);

    socket.onmessage = (event) => {
        try {
            const msg = JSON.parse(event.data);
            appendMessage(msg, msg.username === username);
        } catch (err) {
            // 忽略非消息帧
        }
    };

    socket.onclose = () => {
        setStatus('连接已断开，正在重连...', false);
        if (reconnectTimer) clearTimeout(reconnectTimer);
        reconnectTimer = setTimeout(connectWebSocket, 2000);
    };

    socket.onerror = () => {
        if (socket) socket.close();
    };
}

async function sendMessage(event) {
    event.preventDefault();
    const content = inputEl.value.trim();
    if (!content) return;

    const btn = document.getElementById('sendBtn');
    btn.disabled = true;

    try {
        const body = 'token=' + encodeURIComponent(token) + '&content=' + encodeURIComponent(content);
        const resp = await fetch('/api/send', {
            method: 'POST',
            headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
            body: body
        });
        const data = await resp.json();
        if (!data.ok) {
            alert(data.msg || '发送失败');
        } else {
            inputEl.value = '';
        }
    } catch (err) {
        alert('发送失败，请检查连接');
    } finally {
        btn.disabled = false;
        inputEl.focus();
    }
}

async function logout() {
    try {
        await fetch('/api/logout', {
            method: 'POST',
            headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
            body: 'token=' + encodeURIComponent(token)
        });
    } catch (err) {
        // 忽略
    }
    localStorage.removeItem('chat_token');
    localStorage.removeItem('chat_username');
    window.location.href = '/';
}

loadHistory();
connectWebSocket();
inputEl.focus();
