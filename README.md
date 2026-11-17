# C++ 在线聊天室

一个基于 C++ 的 Web 聊天室，带登录/注册流程，账号信息和聊天记录存入 SQLite 数据库，消息通过 WebSocket 实时推送。

## 技术栈

- 后端：C++14 + cpp-httplib（单头文件 HTTP/WebSocket 框架）
- 数据库：SQLite（源码内嵌，无需单独安装）
- 前端：原生 HTML / CSS / JavaScript

## 目录结构

```
chatroom/
├── build.sh              # 编译脚本
├── chatroom              # 编译后的可执行文件（编译生成）
├── chat.db               # 数据库文件（运行后自动生成）
├── src/
│   ├── main.cpp          # 程序入口
│   ├── server.h/.cpp     # HTTP 路由 + WebSocket + 会话管理
│   └── db.h/.cpp         # 数据库封装
├── vendor/
│   ├── httplib.h         # HTTP 框架（第三方）
│   ├── sqlite3.c/.h      # 数据库源码（第三方）
│   └── sha256.h          # 密码哈希
└── web/
    ├── index.html        # 登录/注册页
    ├── auth.js
    ├── chat.html         # 聊天页
    ├── chat.js
    └── style.css
```

## 编译

需要 g++ 和 gcc（Ubuntu 默认装 g++，gcc 一般也在）：

```bash
cd /mnt/d/mycode/chatroom
bash build.sh
```

编译成功后会生成 `chatroom` 可执行文件。

## 运行

```bash
./chatroom --port 8080
```

然后浏览器打开 `http://localhost:8080`。

指定监听地址（默认 0.0.0.0，即局域网可访问）：

```bash
./chatroom --host 0.0.0.0 --port 8080
```

## 用 VS Code 开发（Remote-WSL）

项目已配好 `.vscode/` 目录，可在 WSL 环境里直接编译和调试：

1. 确保 VS Code 已装 `Remote - WSL` 扩展（已为你安装）。
2. 在 Ubuntu 终端里进入项目并打开：
   ```bash
   cd /mnt/d/mycode/chatroom
   code .
   ```
3. VS Code 会自动切到 WSL 窗口（左下角显示 `WSL: Ubuntu`）。
4. 快捷键：
   - `Ctrl+Shift+B` —— 编译（对应"编译聊天室"任务）
   - `F5` —— 调试（自动先编译，再启动 gdb）

## 使用流程

1. 打开首页，点「注册」创建账号（用户名 3-32 字符，密码 4-64 字符）。
2. 注册后用该账号登录。
3. 进入聊天页，输入消息回车发送，在线用户实时收到。
4. 刷新/重新登录后，最近 100 条历史消息会自动加载。

## 数据库说明

运行后自动生成 `chat.db`，内含两张表：

- `users`：id、username（唯一）、password_hash（加盐 SHA-256）
- `messages`：id、user_id、username、content、created_at

## 注意事项

- 密码用加盐 SHA-256 存储，不适合生产环境的高安全要求，仅作学习/内部使用。
- 会话 token 存在内存里，服务重启后需重新登录（账号和聊天记录不丢）。
