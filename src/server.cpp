#include "server.h"
#include "db.h"
#include "../vendor/httplib.h"
#include "../vendor/sha256.h"

#include <mutex>
#include <unordered_map>
#include <random>
#include <sstream>
#include <iomanip>
#include <vector>
#include <algorithm>
#include <cstdio>

namespace {

struct Session {
    int64_t userId;
    std::string username;
};

std::mutex gSessionsMutex;
std::unordered_map<std::string, Session> gSessions;

std::mutex gClientsMutex;
std::vector<httplib::ws::WebSocket *> gClients;

std::string makeToken() {
    static std::random_device rd;
    static std::mt19937_64 gen(rd());
    std::ostringstream oss;
    oss << std::hex << std::setw(16) << std::setfill('0') << gen()
        << std::setw(16) << std::setfill('0') << gen();
    return oss.str();
}

std::string passwordHash(const std::string &username, const std::string &password) {
    return Sha256::hash(username + ":" + password + ":chatroom-salt");
}

std::string jsonEscape(const std::string &s) {
    std::ostringstream oss;
    for (unsigned char c : s) {
        switch (c) {
            case '"': oss << "\\\""; break;
            case '\\': oss << "\\\\"; break;
            case '\n': oss << "\\n"; break;
            case '\r': oss << "\\r"; break;
            case '\t': oss << "\\t"; break;
            default:
                if (c < 0x20) {
                    oss << "\\u" << std::hex << std::setw(4) << std::setfill('0') << (int)c;
                } else {
                    oss << (char)c;
                }
        }
    }
    return oss.str();
}

std::string jsonResponse(bool ok, const std::string &message) {
    std::ostringstream oss;
    oss << "{\"ok\":" << (ok ? "true" : "false")
        << ",\"msg\":\"" << jsonEscape(message) << "\"}";
    return oss.str();
}

std::string messageJson(const MessageRecord &m) {
    std::ostringstream oss;
    oss << "{\"username\":\"" << jsonEscape(m.username)
        << "\",\"content\":\"" << jsonEscape(m.content)
        << "\",\"time\":\"" << jsonEscape(m.time) << "\"}";
    return oss.str();
}

bool getSession(const std::string &token, Session &out) {
    std::lock_guard<std::mutex> lock(gSessionsMutex);
    auto it = gSessions.find(token);
    if (it == gSessions.end()) return false;
    out = it->second;
    return true;
}

void broadcast(const std::string &text) {
    std::lock_guard<std::mutex> lock(gClientsMutex);
    for (auto *client : gClients) {
        client->send(text);
    }
}

std::string param(const httplib::Request &req, const std::string &key) {
    if (req.has_param(key)) return req.get_param_value(key.c_str());
    return "";
}

}  // namespace

void runServer(const ServerOptions &options) {
    Database db(options.dbPath);
    if (!db.init()) {
        std::fprintf(stderr, "数据库初始化失败\n");
        return;
    }

    httplib::Server svr;
    svr.set_mount_point("/", options.webDir);

    svr.Post("/api/register", [&](const httplib::Request &req, httplib::Response &res) {
        std::string username = param(req, "username");
        std::string password = param(req, "password");
        std::string msg;
        bool ok = true;

        if (username.size() < 3 || username.size() > 32) {
            ok = false; msg = "用户名需 3-32 个字符";
        } else if (password.size() < 4 || password.size() > 64) {
            ok = false; msg = "密码需 4-64 个字符";
        } else if (db.userExists(username)) {
            ok = false; msg = "用户名已存在";
        } else if (!db.createUser(username, passwordHash(username, password))) {
            ok = false; msg = "注册失败，请重试";
        } else {
            msg = "注册成功";
        }
        res.set_content(jsonResponse(ok, msg), "application/json; charset=utf-8");
    });

    svr.Post("/api/login", [&](const httplib::Request &req, httplib::Response &res) {
        std::string username = param(req, "username");
        std::string password = param(req, "password");
        UserRecord user;
        bool ok = db.verifyUser(username, passwordHash(username, password), user);

        if (!ok) {
            res.set_content(jsonResponse(false, "用户名或密码错误"), "application/json; charset=utf-8");
            return;
        }

        std::string token = makeToken();
        {
            std::lock_guard<std::mutex> lock(gSessionsMutex);
            gSessions[token] = Session{user.id, user.username};
        }

        std::ostringstream oss;
        oss << "{\"ok\":true,\"msg\":\"登录成功\",\"token\":\"" << token
            << "\",\"username\":\"" << jsonEscape(user.username) << "\"}";
        res.set_content(oss.str(), "application/json; charset=utf-8");
    });

    svr.Post("/api/logout", [&](const httplib::Request &req, httplib::Response &res) {
        std::string token = param(req, "token");
        {
            std::lock_guard<std::mutex> lock(gSessionsMutex);
            gSessions.erase(token);
        }
        res.set_content(jsonResponse(true, "已退出"), "application/json; charset=utf-8");
    });

    svr.Get("/api/history", [&](const httplib::Request &req, httplib::Response &res) {
        std::string token = param(req, "token");
        Session session;
        if (!getSession(token, session)) {
            res.status = 401;
            res.set_content(jsonResponse(false, "未登录或登录已过期"), "application/json; charset=utf-8");
            return;
        }

        auto messages = db.getRecentMessages(100);
        std::ostringstream oss;
        oss << "{\"ok\":true,\"messages\":[";
        for (size_t i = 0; i < messages.size(); ++i) {
            if (i) oss << ",";
            oss << messageJson(messages[i]);
        }
        oss << "]}";
        res.set_content(oss.str(), "application/json; charset=utf-8");
    });

    svr.Post("/api/send", [&](const httplib::Request &req, httplib::Response &res) {
        std::string token = param(req, "token");
        std::string content = param(req, "content");
        Session session;
        if (!getSession(token, session)) {
            res.status = 401;
            res.set_content(jsonResponse(false, "未登录或登录已过期"), "application/json; charset=utf-8");
            return;
        }

        content.erase(0, content.find_first_not_of(" \t\r\n"));
        if (content.empty() || content.size() > 1000) {
            res.set_content(jsonResponse(false, "消息不能为空且不超过 1000 字符"), "application/json; charset=utf-8");
            return;
        }

        int64_t id = db.insertMessage(session.userId, session.username, content);
        if (id < 0) {
            res.set_content(jsonResponse(false, "发送失败"), "application/json; charset=utf-8");
            return;
        }

        MessageRecord saved;
        if (!db.getMessageById(id, saved)) {
            res.set_content(jsonResponse(false, "发送失败"), "application/json; charset=utf-8");
            return;
        }
        broadcast(messageJson(saved));
        res.set_content(jsonResponse(true, "已发送"), "application/json; charset=utf-8");
    });

    svr.WebSocket("/ws", [&](const httplib::Request &req, httplib::ws::WebSocket &ws) {
        std::string token = param(req, "token");
        Session session;
        if (!getSession(token, session)) {
            ws.close();
            return;
        }

        {
            std::lock_guard<std::mutex> lock(gClientsMutex);
            gClients.push_back(&ws);
        }

        std::string incoming;
        while (ws.read(incoming)) {
        }

        {
            std::lock_guard<std::mutex> lock(gClientsMutex);
            gClients.erase(std::remove(gClients.begin(), gClients.end(), &ws), gClients.end());
        }
    });

    std::printf("聊天室已启动: http://%s:%d\n", options.host.c_str(), options.port);
    std::printf("按 Ctrl+C 停止服务\n");
    svr.listen(options.host, options.port);
}
