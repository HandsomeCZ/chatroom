#ifndef CHAT_DB_H
#define CHAT_DB_H

#include <string>
#include <vector>
#include <cstdint>
#include "../vendor/sqlite3.h"

struct UserRecord {
    int64_t id;
    std::string username;
    std::string passwordHash;
};

struct MessageRecord {
    int64_t id;
    std::string username;
    std::string content;
    std::string time;
};

class Database {
public:
    explicit Database(const std::string &path);
    ~Database();

    Database(const Database &) = delete;
    Database &operator=(const Database &) = delete;

    bool init();

    bool createUser(const std::string &username, const std::string &passwordHash);
    bool userExists(const std::string &username);
    bool verifyUser(const std::string &username, const std::string &passwordHash, UserRecord &out);

    int64_t insertMessage(int64_t userId, const std::string &username, const std::string &content);
    bool getMessageById(int64_t id, MessageRecord &out);
    std::vector<MessageRecord> getRecentMessages(int limit);
    std::vector<MessageRecord> getMessagesAfter(int64_t id);

private:
    sqlite3 *db_;
};

#endif
