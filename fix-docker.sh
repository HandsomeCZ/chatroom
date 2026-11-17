#!/usr/bin/env bash
# 专门修复 Docker：清残留配置 + 数据盘挪到 D 盘 + 配国内镜像加速
# 前置：docker.io 已是真 Docker（非 podman）
# 运行: bash fix-docker.sh
set -e

D_DRIVE="/mnt/d"
DOCKER_DISK="$D_DRIVE/docker-data.ext4"
DOCKER_MNT="/mnt/docker-data"

echo "=========================================="
echo "  Docker 修复：数据盘到 D 盘 + 镜像加速"
echo "=========================================="
echo ""

echo "[检查] 确认是真 Docker 而非 podman"
if docker info 2>&1 | grep -qi podman; then
    echo "错误：当前仍是 podman，请先运行 install-tools.sh 完成卸载"
    exit 1
fi
echo "  OK: 真 Docker"

echo "[检查] sudo 权限"
sudo -v

# ---------- 1. 停掉当前 docker ----------
echo ""
echo "========== 1. 停止当前 Docker =========="
sudo pkill -f dockerd 2>/dev/null || true
sudo systemctl stop docker 2>/dev/null || true
sleep 2
echo "  已停止"

# ---------- 2. 建立 D 盘 ext4 数据盘 ----------
echo ""
echo "========== 2. 建立 D 盘 ext4 数据盘 =========="
DATA_ROOT=""
STORAGE_DRIVER=""
LOOP_OK=0

if losetup -f >/dev/null 2>&1; then
    echo "  losetup 可用，尝试 ext4 方案"
    if sudo mkdir -p "$DOCKER_MNT" && \
       { [ -f "$DOCKER_DISK" ] || (truncate -s 20G "$DOCKER_DISK" && sudo mkfs.ext4 -q -F "$DOCKER_DISK"); } && \
       { mountpoint -q "$DOCKER_MNT" || sudo mount -o loop "$DOCKER_DISK" "$DOCKER_MNT"; }; then
        LOOP_OK=1
        DATA_ROOT="$DOCKER_MNT/docker"
        STORAGE_DRIVER="overlay2"
        echo "  OK: ext4 数据盘已挂载到 $DOCKER_MNT"
        if ! grep -q 'docker-data.ext4' /etc/fstab 2>/dev/null; then
            echo "$DOCKER_DISK $DOCKER_MNT ext4 loop,defaults 0 0" | sudo tee -a /etc/fstab >/dev/null
            echo "  OK: fstab 已配置（重启自动挂载）"
        fi
    else
        echo "  !! ext4 方案失败，降级到 vfs"
    fi
else
    echo "  !! losetup 不可用，降级到 vfs"
fi

if [ "$LOOP_OK" -eq 0 ]; then
    DATA_ROOT="$D_DRIVE/mydocker"
    STORAGE_DRIVER="vfs"
    sudo mkdir -p "$DATA_ROOT"
    echo "  vfs 数据目录: $DATA_ROOT（仍在 D 盘，不占 C 盘）"
    echo "  警告: vfs 性能较差、占空间多，但能用"
fi

# ---------- 3. 重写 daemon.json（清残留 + 镜像加速）----------
echo ""
echo "========== 3. 重写 Docker 配置 =========="
sudo mkdir -p /etc/docker
sudo tee /etc/docker/daemon.json >/dev/null <<EOF
{
  "data-root": "$DATA_ROOT",
  "storage-driver": "$STORAGE_DRIVER",
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
sudo mkdir -p "$DATA_ROOT"
echo "  新配置："
cat /etc/docker/daemon.json
echo ""

# 若旧目录 /mydocker 有数据且新目录为空，尝试迁移（best effort）
if [ -d "/mydocker" ] && [ -z "$(ls -A "$DATA_ROOT" 2>/dev/null)" ]; then
    echo "  检测到旧数据目录 /mydocker，尝试迁移..."
    sudo cp -a /mydocker/. "$DATA_ROOT/" 2>/dev/null || echo "  迁移跳过（无权限或无数据）"
fi

# ---------- 4. 启动 Docker ----------
echo ""
echo "========== 4. 启动 Docker =========="
if command -v update-alternatives >/dev/null 2>&1; then
    sudo update-alternatives --set iptables /usr/sbin/iptables-legacy 2>/dev/null || true
    sudo update-alternatives --set ip6tables /usr/sbin/ip6tables-legacy 2>/dev/null || true
fi

STARTED=0
if command -v systemctl >/dev/null 2>&1 && sudo systemctl start docker 2>/dev/null; then
    sudo systemctl enable docker 2>/dev/null || true
    STARTED=1
    echo "  systemctl 启动成功"
fi
if [ "$STARTED" -eq 0 ]; then
    echo "  systemctl 不可用，直接启动 dockerd"
    sudo pkill -f dockerd 2>/dev/null || true
    sleep 1
    sudo nohup dockerd >/tmp/dockerd.log 2>&1 &
    sleep 6
fi

# ---------- 5. 验证 ----------
echo ""
echo "========== 5. 验证 =========="
if docker info >/dev/null 2>&1; then
    echo "  Docker 正常运行"
    docker info | grep -E 'Docker Root Dir|Storage Driver|Registry Mirrors' || true
    echo "  Data Root 应为: $DATA_ROOT"
    echo "  Storage Driver 应为: $STORAGE_DRIVER"
else
    echo "  !! dockerd 启动失败，日志："
    tail -n 20 /tmp/dockerd.log 2>/dev/null || true
fi

echo ""
echo "=========================================="
echo "  修复完成"
echo "=========================================="
echo "现在测试拉镜像："
echo "  docker pull hello-world"
echo "  docker run hello-world"
echo ""
