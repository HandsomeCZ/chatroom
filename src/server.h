#ifndef CHAT_SERVER_H
#define CHAT_SERVER_H

#include <string>

struct ServerOptions {
    std::string host = "0.0.0.0";
    int port = 8080;
    std::string webDir = "./web";
    std::string dbPath = "./chat.db";
};

void runServer(const ServerOptions &options);

#endif
