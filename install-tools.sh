#!/usr/bin/env bash
# 在 WSL Ubuntu 中安装 Node.js 与 Docker，尽量不占用 C 盘
# 运行方式: bash install-tools.sh
set -e

D_DRIVE="/mnt/d"
NODE_ARCHIVE="$D_DRIVE/node-v26.13.1-linux-x64.tar.xz"
NODE_DIR="$D_DRIVE/nodejs"
DOCKER_DISK="$D_DRIVE/docker-data.ext4"
DOCKER_MNT="/mnt/docker-data"

echo "=========================================="
echo "  Node.js + Docker 安装脚本（数据放 D 盘）"
echo "=========================================="
echo ""

# ---------- 前置检查 ----------
echo "[检查] 是否在 WSL 的 Ubuntu 中"
if [ ! -d "/mnt/d" ] || [ ! -d "/mnt/c" ]; then
    echo "错误：/mnt/d 或 /mnt/c 不存在，请确认在 WSL Ubuntu 终端中运行（不是 Windows 的 Git Bash）"
    exit 1
fi
echo "  OK: 检测到 WSL 挂载盘"

echo "[检查] 是否有 sudo 权限"
sudo -v

# ---------- 第一部分：Node.js ----------
echo ""
echo "========== 第一部分：安装 Node.js 到 D 盘 =========="

if [ ! -f "$NODE_ARCHIVE" ]; then
    echo "错误：没找到 Node 安装包 $NODE_ARCHIVE"
    echo "请确认 D 盘根目录有 node-v26.13.1-linux-x64.tar.xz"
    exit 1
fi

if command -v node >/dev/null 2>&1 && node --version 2>/dev/null | grep -q v; then
    echo "Node 似乎已安装: $(node --version)，跳过安装"
else
    echo "[1/4] 解压 Node 到 $NODE_DIR"
    mkdir -p "$NODE_DIR"
    tar -xJf "$NODE_ARCHIVE" -C "$NODE_DIR" --strip-components=1

    echo "[2/4] 配置 PATH（写入 ~/.bashrc）"
    if ! grep -q 'nodejs/bin' ~/.bashrc 2>/dev/null; then
        echo '' >> ~/.bashrc
        echo '# Node.js (installed on D drive)' >> ~/.bashrc
        echo 'export PATH="/mnt/d/nodejs/bin:$PATH"' >> ~/.bashrc
    fi
    export PATH="$NODE_DIR/bin:$PATH"
    echo "  PATH 已配置，新开终端自动生效"
fi

echo "[3/4] Node 版本确认"
node --version
npm --version

# ---------- 第二部分：Docker ext4 数据盘 ----------
echo ""
echo "========== 第二部分：在 D 盘创建 Docker 数据盘 =========="

echo "[检查] WSL 内核是否支持 loop 设备挂载"
if echo 'test' > /proc/sys/kernel/loop 2>/dev/null; then
    echo "  OK: 内核支持 loop（可挂载 ext4 虚拟磁盘）"
    LOOP_OK=1
else
    # 更可靠的检测：直接尝试 losetup
    if losetup -f >/dev/null 2>&1; then
        echo "  OK: losetup 可用"
        LOOP_OK=1
    else
        echo "  警告: 内核可能不支持 loop 挂载"
        LOOP_OK=0
    fi
fi

# 实际尝试创建并挂载 ext4 数据盘，成功用 overlay2，失败自动降级到 vfs
LOOP_SETUP_OK=0
if [ "$LOOP_OK" -eq 1 ]; then
    echo "  尝试创建 ext4 数据盘..."
    if sudo mkdir -p "$DOCKER_MNT" && \
       { [ -f "$DOCKER_DISK" ] || (fallocate -l 20G "$DOCKER_DISK" && sudo mkfs.ext4 -q -F "$DOCKER_DISK"); } && \
       { mountpoint -q "$DOCKER_MNT" || sudo mount -o loop "$DOCKER_DISK" "$DOCKER_MNT"; }; then
        LOOP_SETUP_OK=1
        echo "  OK: ext4 数据盘已挂载到 $DOCKER_MNT"

        echo "[配置] 开机自动挂载（写入 /etc/fstab）"
        if ! grep -q 'docker-data.ext4' /etc/fstab 2>/dev/null; then
            echo "$DOCKER_DISK $DOCKER_MNT ext4 loop,defaults 0 0" | sudo tee -a /etc/fstab >/dev/null
            echo "  OK: fstab 已配置"
        fi
    else
        echo "  !! ext4 数据盘创建/挂载失败，将降级到 vfs 方案"
    fi
fi

if [ "$LOOP_SETUP_OK" -eq 1 ]; then
    # 方案 A：原生 ext4 + overlay2（最佳）
    DATA_ROOT="$DOCKER_MNT/docker"
    STORAGE_DRIVER="overlay2"
    echo "[方案 A] ext4 + overlay2，数据目录: $DATA_ROOT"
else
    # 方案 B：直接放 /mnt/d + vfs 驱动（能吃空间，但性能差、占空间多）
    echo "[方案 B] ext4 不可用，降级为 /mnt/d + vfs 驱动"
    DATA_ROOT="$D/mydocker"
    STORAGE_DRIVER="vfs"
    sudo mkdir -p "$DATA_ROOT"
    echo "  警告: vfs 不做分层复用，镜像会占用更多空间且较慢"
    echo "  数据目录: $DATA_ROOT"
fi

# ---------- 第三部分：Docker 引擎 ----------
echo ""
echo "========== 第三部分：安装 Docker 引擎 =========="

if command -v docker >/dev/null 2>&1; then
    echo "Docker 已安装: $(docker --version)，跳过安装"
else
    echo "[1/2] 更新 apt 源"
    sudo apt update -y

    echo "[2/2] 从 Ubuntu 自带源安装 Docker（docker.io）"
    echo "  说明：Docker 官方源在国内常连不上，改用 Ubuntu 自带包，版本够用"
    sudo apt install -y docker.io
fi

# 配置 daemon.json
echo "[配置] Docker daemon（data-root 指向 $DATA_ROOT）"
sudo mkdir -p /etc/docker
sudo tee /etc/docker/daemon.json >/dev/null <<EOF
{
  "data-root": "$DATA_ROOT",
  "storage-driver": "$STORAGE_DRIVER",
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "20m",
    "max-file": "5"
  }
}
EOF
cat /etc/docker/daemon.json

# 把当前用户加入 docker 组（免 sudo）
echo "[配置] 将当前用户加入 docker 组"
sudo usermod -aG docker "$USER"

# 启动 Docker
echo "[启动] 启动 Docker 服务"
if command -v systemctl >/dev/null 2>&1 && sudo systemctl start docker 2>/dev/null; then
    sudo systemctl enable docker 2>/dev/null || true
    echo "  systemctl 启动成功"
else
    echo "  systemctl 不可用，尝试直接启动 dockerd"
    sudo dockerd >/tmp/dockerd.log 2>&1 &
    sleep 3
fi

echo ""
echo "=========================================="
echo "  安装完成！"
echo "=========================================="
echo ""
echo "需要执行以下操作让配置完全生效："
echo "  1. 重新登录终端（让 docker 组生效，或执行: newgrp docker）"
echo "  2. 验证: docker info | grep -E 'Docker Root Dir|Storage Driver'"
echo "     Docker Root Dir 应显示: $DATA_ROOT"
echo "     Storage Driver 应显示: $STORAGE_DRIVER"
echo "  3. 测试: docker run hello-world"
echo ""
