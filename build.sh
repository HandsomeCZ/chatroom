#!/usr/bin/env bash
# 编译聊天室（在 Linux / WSL 中使用）
set -e
cd "$(dirname "$0")"

echo "[1/3] 编译 SQLite ..."
gcc -O2 -c vendor/sqlite3.c -o sqlite3.o -DSQLITE_THREADSAFE=1

echo "[2/3] 编译 C++ 源码 ..."
g++ -std=c++14 -O2 -pthread \
    -o chatroom \
    src/main.cpp src/server.cpp src/db.cpp \
    sqlite3.o

echo "[3/3] 完成"
echo "可执行文件: ./chatroom"
echo "运行方式: ./chatroom --port 8080"
