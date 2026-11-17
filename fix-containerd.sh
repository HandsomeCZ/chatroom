#!/usr/bin/env bash
# 修复 docker run 报错: unknown service containerd.services.tasks.v1.Tasks
# 根因: containerd 未正常运行 / docker 与 containerd 版本不匹配 / 旧数据残留
# 运行: bash fix-containerd.sh
set -e

echo "=========================================="
echo "  修复 containerd（docker run 报错）"
echo "=========================================="
echo ""

echo "[检查] sudo 权限"
sudo -v

echo ""
echo "========== 1. 诊断当前状态 =========="
echo "--- docker 版本 ---"
docker --version 2>&1 || true
echo "--- containerd 版本 ---"
containerd --version 2>&1 || echo "  containerd 命令不存在！"
echo "--- containerd 进程 ---"
pgrep -a containerd 2>/dev/null || echo "  没有 containerd 进程在运行！"
echo "--- cgroup 版本 ---"
if [ -d /sys/fs/cgroup/unified ]; then echo "  cgroup v2"; else echo "  cgroup v1"; fi
echo ""

echo "========== 2. 彻底清除旧数据并重装 =========="
echo "  说明：会删除所有本地镜像和容器（你目前只有 hello-world，无需保留数据）"

echo "[1/5] 停止 docker 和 containerd"
sudo pkill -f dockerd 2>/dev/null || true
sudo pkill -f containerd 2>/dev/null || true
sudo systemctl stop docker containerd 2>/dev/null || true
sleep 2

echo "[2/5] 卸载旧的 docker/containerd"
sudo apt remove -y docker.io containerd runc 2>/dev/null || true
sudo apt autoremove -y 2>/dev/null || true

echo "[3/5] 清除所有残留数据"
sudo rm -rf /var/lib/docker
sudo rm -rf /var/lib/containerd
sudo rm -rf /run/containerd
sudo rm -rf /mydocker/*
echo "  已清除"

echo "[4/5] 重新安装 docker.io 和 containerd"
sudo apt update -y
sudo apt install -y docker.io containerd runc

echo "[5/5] 确认版本"
docker --version
containerd --version

echo ""
echo "========== 3. 重写 docker 配置（保留 D 盘数据 + 镜像加速）=========="
DATA_ROOT="/mnt/d/mydocker"
sudo mkdir -p "$DATA_ROOT"
sudo mkdir -p /etc/docker
sudo tee /etc/docker/daemon.json >/dev/null <<'EOF'
{
  "data-root": "/mnt/d/mydocker",
  "storage-driver": "vfs",
  "registry-mirrors": [
    "https://docker.m.daocloud.io",
    "https://docker.xuanyuan.me",
    "https://docker.1ms.run"
  ],
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "20m",
    "max-file": "5"
  }
}
EOF
cat /etc/docker/daemon.json

echo ""
echo "========== 4. 启动 containerd 和 dockerd =========="
if command -v update-alternatives >/dev/null 2>&1; then
    sudo update-alternatives --set iptables /usr/sbin/iptables-legacy 2>/dev/null || true
fi

# 先单独启动 containerd
echo "[1/2] 启动 containerd"
sudo pkill -f containerd 2>/dev/null || true
sleep 1
sudo nohup containerd >/tmp/containerd.log 2>&1 &
sleep 3
if pgrep containerd >/dev/null 2>&1; then
    echo "  OK: containerd 已启动"
else
    echo "  !! containerd 启动失败，日志："
    tail -n 20 /tmp/containerd.log 2>/dev/null || true
fi

# 再启动 dockerd
echo "[2/2] 启动 dockerd"
sudo pkill -f dockerd 2>/dev/null || true
sleep 1
sudo nohup dockerd >/tmp/dockerd.log 2>&1 &
sleep 6
if docker info >/dev/null 2>&1; then
    echo "  OK: dockerd 已启动"
else
    echo "  !! dockerd 启动失败，日志："
    tail -n 20 /tmp/dockerd.log 2>/dev/null || true
fi

echo ""
echo "========== 5. 验证 =========="
if docker info >/dev/null 2>&1; then
    docker info | grep -E 'Docker Root Dir|Storage Driver|Registry Mirrors' || true
    echo ""
    echo "--- 测试运行 hello-world ---"
    docker run hello-world 2>&1 | head -20 || true
else
    echo "  Docker 仍未正常，请把上面的日志贴给我"
fi

echo ""
echo "=========================================="
echo "  修复脚本执行完毕"
echo "=========================================="
