let mode = 'login';

function switchTab(next) {
    mode = next;
    document.getElementById('tabLogin').classList.toggle('active', next === 'login');
    document.getElementById('tabRegister').classList.toggle('active', next === 'register');
    document.getElementById('subtitle').textContent = next === 'login' ? '登录以继续' : '创建一个新账号';
    document.getElementById('submitBtn').textContent = next === 'login' ? '登录' : '注册';
    document.getElementById('password').autocomplete = next === 'login' ? 'current-password' : 'new-password';
    setMsg('', '');
}

function setMsg(text, type) {
    const el = document.getElementById('msg');
    el.textContent = text;
    el.className = 'msg ' + type;
}

async function submitForm(event) {
    event.preventDefault();
    const username = document.getElementById('username').value.trim();
    const password = document.getElementById('password').value;
    const btn = document.getElementById('submitBtn');

    btn.disabled = true;
    setMsg('处理中...', 'info');

    try {
        const body = 'username=' + encodeURIComponent(username) + '&password=' + encodeURIComponent(password);
        const endpoint = mode === 'login' ? '/api/login' : '/api/register';
        const resp = await fetch(endpoint, {
            method: 'POST',
            headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
            body: body
        });
        const data = await resp.json();

        if (!data.ok) {
            setMsg(data.msg || '操作失败', 'error');
            btn.disabled = false;
            return;
        }

        if (mode === 'register') {
            setMsg('注册成功，请登录', 'success');
            switchTab('login');
            btn.disabled = false;
            return;
        }

        localStorage.setItem('chat_token', data.token);
        localStorage.setItem('chat_username', data.username);
        window.location.href = '/chat.html';
    } catch (err) {
        setMsg('无法连接服务器', 'error');
        btn.disabled = false;
    }
}

window.addEventListener('DOMContentLoaded', () => {
    if (localStorage.getItem('chat_token')) {
        window.location.href = '/chat.html';
    }
});
