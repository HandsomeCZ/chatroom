#include "db.h"

Database::Database(const std::string &path) : db_(nullptr) {
    if (sqlite3_open(path.c_str(), &db_) != SQLITE_OK) {
        sqlite3_close(db_);
        db_ = nullptr;
    }
}

Database::~Database() {
    if (db_) sqlite3_close(db_);
}

bool Database::init() {
    if (!db_) return false;
    const char *sql =
        "CREATE TABLE IF NOT EXISTS users ("
        "  id INTEGER PRIMARY KEY AUTOINCREMENT,"
        "  username TEXT NOT NULL UNIQUE,"
        "  password_hash TEXT NOT NULL"
        ");"
        "CREATE TABLE IF NOT EXISTS messages ("
        "  id INTEGER PRIMARY KEY AUTOINCREMENT,"
        "  user_id INTEGER NOT NULL,"
        "  username TEXT NOT NULL,"
        "  content TEXT NOT NULL,"
        "  created_at TEXT NOT NULL DEFAULT (datetime('now','localtime'))"
        ");";
    char *err = nullptr;
    int rc = sqlite3_exec(db_, sql, nullptr, nullptr, &err);
    if (rc != SQLITE_OK) {
        sqlite3_free(err);
        return false;
    }
    return true;
}

bool Database::createUser(const std::string &username, const std::string &passwordHash) {
    sqlite3_stmt *stmt = nullptr;
    const char *sql = "INSERT INTO users (username, password_hash) VALUES (?, ?);";
    if (sqlite3_prepare_v2(db_, sql, -1, &stmt, nullptr) != SQLITE_OK) return false;
    sqlite3_bind_text(stmt, 1, username.c_str(), -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(stmt, 2, passwordHash.c_str(), -1, SQLITE_TRANSIENT);
    bool ok = sqlite3_step(stmt) == SQLITE_DONE;
    sqlite3_finalize(stmt);
    return ok;
}

bool Database::userExists(const std::string &username) {
    sqlite3_stmt *stmt = nullptr;
    const char *sql = "SELECT 1 FROM users WHERE username = ? LIMIT 1;";
    if (sqlite3_prepare_v2(db_, sql, -1, &stmt, nullptr) != SQLITE_OK) return false;
    sqlite3_bind_text(stmt, 1, username.c_str(), -1, SQLITE_TRANSIENT);
    bool ok = sqlite3_step(stmt) == SQLITE_ROW;
    sqlite3_finalize(stmt);
    return ok;
}

bool Database::verifyUser(const std::string &username, const std::string &passwordHash, UserRecord &out) {
    sqlite3_stmt *stmt = nullptr;
    const char *sql = "SELECT id, username, password_hash FROM users WHERE username = ?;";
    if (sqlite3_prepare_v2(db_, sql, -1, &stmt, nullptr) != SQLITE_OK) return false;
    sqlite3_bind_text(stmt, 1, username.c_str(), -1, SQLITE_TRANSIENT);
    if (sqlite3_step(stmt) != SQLITE_ROW) {
        sqlite3_finalize(stmt);
        return false;
    }
    out.id = sqlite3_column_int64(stmt, 0);
    out.username = reinterpret_cast<const char *>(sqlite3_column_text(stmt, 1));
    out.passwordHash = reinterpret_cast<const char *>(sqlite3_column_text(stmt, 2));
    sqlite3_finalize(stmt);
    return out.passwordHash == passwordHash;
}

int64_t Database::insertMessage(int64_t userId, const std::string &username, const std::string &content) {
    sqlite3_stmt *stmt = nullptr;
    const char *sql = "INSERT INTO messages (user_id, username, content) VALUES (?, ?, ?);";
    if (sqlite3_prepare_v2(db_, sql, -1, &stmt, nullptr) != SQLITE_OK) return -1;
    sqlite3_bind_int64(stmt, 1, userId);
    sqlite3_bind_text(stmt, 2, username.c_str(), -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(stmt, 3, content.c_str(), -1, SQLITE_TRANSIENT);
    int rc = sqlite3_step(stmt);
    sqlite3_finalize(stmt);
    if (rc != SQLITE_DONE) return -1;
    return sqlite3_last_insert_rowid(db_);
}

bool Database::getMessageById(int64_t id, MessageRecord &out) {
    sqlite3_stmt *stmt = nullptr;
    const char *sql = "SELECT id, username, content, created_at FROM messages WHERE id = ?;";
    if (sqlite3_prepare_v2(db_, sql, -1, &stmt, nullptr) != SQLITE_OK) return false;
    sqlite3_bind_int64(stmt, 1, id);
    if (sqlite3_step(stmt) != SQLITE_ROW) {
        sqlite3_finalize(stmt);
        return false;
    }
    out.id = sqlite3_column_int64(stmt, 0);
    out.username = reinterpret_cast<const char *>(sqlite3_column_text(stmt, 1));
    out.content = reinterpret_cast<const char *>(sqlite3_column_text(stmt, 2));
    out.time = reinterpret_cast<const char *>(sqlite3_column_text(stmt, 3));
    sqlite3_finalize(stmt);
    return true;
}

std::vector<MessageRecord> Database::getRecentMessages(int limit) {
    std::vector<MessageRecord> result;
    sqlite3_stmt *stmt = nullptr;
    const char *sql = "SELECT id, username, content, created_at FROM ("
                      "  SELECT * FROM messages ORDER BY id DESC LIMIT ?"
                      ") ORDER BY id ASC;";
    if (sqlite3_prepare_v2(db_, sql, -1, &stmt, nullptr) != SQLITE_OK) return result;
    sqlite3_bind_int(stmt, 1, limit);
    while (sqlite3_step(stmt) == SQLITE_ROW) {
        MessageRecord m;
        m.id = sqlite3_column_int64(stmt, 0);
        m.username = reinterpret_cast<const char *>(sqlite3_column_text(stmt, 1));
        m.content = reinterpret_cast<const char *>(sqlite3_column_text(stmt, 2));
        m.time = reinterpret_cast<const char *>(sqlite3_column_text(stmt, 3));
        result.push_back(std::move(m));
    }
    sqlite3_finalize(stmt);
    return result;
}

std::vector<MessageRecord> Database::getMessagesAfter(int64_t id) {
    std::vector<MessageRecord> result;
    sqlite3_stmt *stmt = nullptr;
    const char *sql = "SELECT id, username, content, created_at FROM messages WHERE id > ? ORDER BY id ASC;";
    if (sqlite3_prepare_v2(db_, sql, -1, &stmt, nullptr) != SQLITE_OK) return result;
    sqlite3_bind_int64(stmt, 1, id);
    while (sqlite3_step(stmt) == SQLITE_ROW) {
        MessageRecord m;
        m.id = sqlite3_column_int64(stmt, 0);
        m.username = reinterpret_cast<const char *>(sqlite3_column_text(stmt, 1));
        m.content = reinterpret_cast<const char *>(sqlite3_column_text(stmt, 2));
        m.time = reinterpret_cast<const char *>(sqlite3_column_text(stmt, 3));
        result.push_back(std::move(m));
    }
    sqlite3_finalize(stmt);
    return result;
}
