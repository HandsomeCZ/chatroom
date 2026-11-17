#include "server.h"

#include <cstdlib>
#include <cstring>
#include <iostream>

int main(int argc, char *argv[]) {
    ServerOptions options;

    for (int i = 1; i < argc; ++i) {
        if (std::strcmp(argv[i], "--port") == 0 && i + 1 < argc) {
            options.port = std::atoi(argv[++i]);
        } else if (std::strcmp(argv[i], "--host") == 0 && i + 1 < argc) {
            options.host = argv[++i];
        }
    }

    std::cout << "===================================" << std::endl;
    std::cout << "        C++ 在线聊天室" << std::endl;
    std::cout << "===================================" << std::endl;

    runServer(options);
    return 0;
}
