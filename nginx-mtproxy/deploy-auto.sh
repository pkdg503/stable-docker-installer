# 用正确的内容替换 deploy-auto.sh
cat > deploy-auto.sh << 'EOF'
#!/bin/bash

# nginx-mtproxy 自动部署脚本 - 支持 curl 管道运行

# ========== 配置区域 ==========
CONTAINER_COUNT=1
DOMAINS="cloudflare.com"
HTTP_PORTS="8081"
HTTPS_PORTS="8443"
NAME_PREFIX="nginx-mtproxy"
AUTO_REMOVE="no"
# ========== 配置结束 ==========

# 颜色定义
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

IMAGE_NAME="ellermister/nginx-mtproxy:latest"

show_header() {
    echo -e "${GREEN}"
    echo "========================================"
    echo "🚀 nginx-mtproxy 自动部署脚本"
    echo "========================================"
    echo -e "${NC}"
    echo -e "${CYAN}📋 配置信息:${NC}"
    echo -e "  容器数量: ${CONTAINER_COUNT}"
    echo -e "  伪装域名: ${DOMAINS}"
    echo -e "  HTTP端口: ${HTTP_PORTS}"
    echo -e "  HTTPS端口: ${HTTPS_PORTS}"
    echo ""
}

check_docker() {
    echo -e "${BLUE}🔍 检查 Docker 环境...${NC}"
    if ! command -v docker &> /dev/null; then
        echo -e "${RED}❌ Docker 未安装${NC}"
        exit 1
    fi
    echo -e "${GREEN}✅ Docker 环境检查通过${NC}"
}

pull_image() {
    echo -e "${BLUE}🔍 检查 Docker 镜像...${NC}"
    if docker image inspect "$IMAGE_NAME" &> /dev/null; then
        echo -e "${GREEN}✅ 镜像已存在${NC}"
    else
        echo -e "${YELLOW}📥 拉取镜像...${NC}"
        if docker pull "$IMAGE_NAME"; then
            echo -e "${GREEN}✅ 镜像拉取成功${NC}"
        else
            echo -e "${RED}❌ 镜像拉取失败${NC}"
            exit 1
        fi
    fi
}

# ... 其余函数保持不变，使用你原来的完整代码 ...

main() {
    show_header
    check_docker
    pull_image
    parse_config
    deploy_containers
}

main
EOF

# 推送到 GitHub
git add deploy-auto.sh
git commit -m "修复自动部署脚本：移除创建文件的代码"
git push
