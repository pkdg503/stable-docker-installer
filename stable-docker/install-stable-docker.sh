#!/bin/bash

# 颜色定义
RED="\033[0;31m"
GREEN="\033[0;32m"
YELLOW="\033[1;33m"
NC="\033[0m"

echo -e "${GREEN}🚀 开始安装最稳定版 Docker...${NC}"

# 检查 root 权限
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}❌ 请使用 root 权限运行此脚本 (sudo -i)${NC}"
    exit 1
fi

# 1. 更新系统
echo -e "${YELLOW}📦 更新系统包列表...${NC}"
apt update -y || { echo -e "${RED}❌ 更新失败${NC}"; exit 1; }
apt upgrade -y || { echo -e "${RED}❌ 升级失败${NC}"; exit 1; }

# 2. 安装依赖
echo -e "${YELLOW}📦 安装依赖包...${NC}"
apt install -y \
    apt-transport-https \
    ca-certificates \
    curl \
    gnupg \
    lsb-release \
    software-properties-common || { echo -e "${RED}❌ 依赖安装失败${NC}"; exit 1; }

# 3. 添加 Docker 官方 GPG 密钥
echo -e "${YELLOW}🔑 添加 Docker GPG 密钥...${NC}"
curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg || { echo -e "${RED}❌ GPG密钥添加失败${NC}"; exit 1; }

# 4. 添加稳定版仓库
echo -e "${YELLOW}📚 添加 Docker 稳定版仓库...${NC}"
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/debian $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null || { echo -e "${RED}❌ 仓库添加失败${NC}"; exit 1; }

# 5. 更新包列表
echo -e "${YELLOW}🔄 更新包列表...${NC}"
apt update -y || { echo -e "${RED}❌ 包列表更新失败${NC}"; exit 1; }

# 6. 查看可用版本并选择稳定版本
echo -e "${YELLOW}🔍 查找可用 Docker 版本...${NC}"
DOCKER_VERSION=$(apt-cache madison docker-ce | head -n 5 | tail -n 1 | awk -F "|" "{print \$2}" | tr -d " ")
if [ -z "$DOCKER_VERSION" ]; then
    echo -e "${YELLOW}⚠️  无法获取特定版本，安装最新稳定版${NC}"
    apt install -y \
        docker-ce \
        docker-ce-cli \
        containerd.io \
        docker-buildx-plugin \
        docker-compose-plugin || { echo -e "${RED}❌ Docker 安装失败${NC}"; exit 1; }
else
    echo -e "${GREEN}✅ 选择版本: $DOCKER_VERSION${NC}"
    apt install -y \
        docker-ce=$DOCKER_VERSION \
        docker-ce-cli=$DOCKER_VERSION \
        containerd.io \
        docker-buildx-plugin \
        docker-compose-plugin || { echo -e "${RED}❌ Docker 安装失败${NC}"; exit 1; }
fi

# 7. 禁用自动更新
echo -e "${YELLOW}🔒 禁用 Docker 自动更新...${NC}"
apt-mark hold docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# 8. 配置 Docker 守护进程
echo -e "${YELLOW}⚙️  配置 Docker 守护进程...${NC}"
mkdir -p /etc/docker
cat > /etc/docker/daemon.json << EOF
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  },
  "storage-driver": "overlay2",
  "live-restore": true,
  "default-ulimits": {
    "nofile": {
      "Name": "nofile",
      "Hard": 65536,
      "Soft": 65536
    }
  }
}
EOF

# 9. 启动 Docker 服务
echo -e "${YELLOW}🚀 启动 Docker 服务...${NC}"
systemctl start docker || { echo -e "${RED}❌ Docker 启动失败${NC}"; exit 1; }
systemctl enable docker || { echo -e "${RED}❌ Docker 自启设置失败${NC}"; exit 1; }

# 10. 验证安装
echo -e "${YELLOW}✅ 验证安装...${NC}"
docker --version || { echo -e "${RED}❌ Docker 验证失败${NC}"; exit 1; }
docker info | grep -q "Server Version:" || { echo -e "${RED}❌ Docker 服务异常${NC}"; exit 1; }

# 11. 创建 docker 用户组（可选）
if ! getent group docker >/dev/null; then
    echo -e "${YELLOW}👥 创建 docker 用户组...${NC}"
    groupadd docker
fi

echo -e "${GREEN}"
echo "========================================"
echo "🎉 Docker 安装完成！"
echo "========================================"
echo "📋 安装信息:"
echo "   - Docker 版本: $(docker --version | cut -d" " -f3 | cut -d"," -f1)"
echo "   - 自动更新: 已禁用"
echo "   - 存储驱动: overlay2"
echo "   - 日志配置: 10MB 轮转，保留 3 个文件"
echo "   - 服务状态: 运行中"
echo ""
echo "🔧 常用命令:"
echo "   - 查看状态: systemctl status docker"
echo "   - 重启服务: systemctl restart docker"
echo "   - 查看日志: journalctl -u docker"
echo "========================================"
echo -e "${NC}"
