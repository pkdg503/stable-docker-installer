cat > /tmp/deploy-optimized.sh << 'EOF'
#!/bin/bash

# nginx-mtproxy 一键自动部署脚本
# 使用方法: curl -sSL https://raw.githubusercontent.com/pkdg503/docker-installer/main/nginx-mtproxy/deploy-optimized.sh | bash

set -e

# ========== 用户配置区域 ==========
CONTAINER_COUNT=2                  # 部署容器数量
DOMAINS="microsoft.com,apple.com"  # 伪装域名，用逗号分隔
HTTP_PORTS="45603,45604"          # HTTP端口，用逗号分隔  
HTTPS_PORTS="45605,45606"         # HTTPS端口，用逗号分隔
NAME_PREFIX="mtproxy"              # 容器名称前缀
AUTO_REMOVE="yes"                  # 自动删除已存在容器
# ========== 配置结束 ==========

# 颜色输出
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

IMAGE_NAME="ellermister/nginx-mtproxy:latest"

log() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }

show_header() {
    echo -e "${GREEN}"
    echo "========================================"
    echo "🚀 nginx-mtproxy 一键自动部署"
    echo "========================================"
    echo -e "${NC}"
    
    echo -e "${CYAN}📋 部署配置:${NC}"
    echo -e "  容器数量: ${CONTAINER_COUNT}"
    echo -e "  伪装域名: ${DOMAINS}"
    echo -e "  HTTP端口: ${HTTP_PORTS}"
    echo -e "  HTTPS端口: ${HTTPS_PORTS}"
    echo -e "  容器前缀: ${NAME_PREFIX}"
    echo ""
}

check_docker() {
    log "检查 Docker 环境..."
    if ! command -v docker &> /dev/null; then
        error "Docker 未安装，请先安装 Docker"
        exit 1
    fi
    
    if ! docker info &> /dev/null; then
        error "Docker 服务未运行，请先启动 Docker"
        exit 1
    fi
    log "Docker 版本: $(docker --version | cut -d' ' -f3 | cut -d',' -f1)"
}

pull_image() {
    log "检查 Docker 镜像..."
    if ! docker pull "$IMAGE_NAME" &> /dev/null; then
        error "镜像拉取失败"
        exit 1
    fi
    log "镜像准备就绪"
}

parse_config() {
    IFS=',' read -ra DOMAINS_ARRAY <<< "${DOMAINS// /}"
    IFS=',' read -ra HTTP_PORTS_ARRAY <<< "${HTTP_PORTS// /}"
    IFS=',' read -ra HTTPS_PORTS_ARRAY <<< "${HTTPS_PORTS// /}"
}

check_port() {
    local port=$1
    if ss -tulpn 2>/dev/null | grep -q ":${port} "; then
        return 1
    fi
    return 0
}

get_next_name() {
    local index=0
    local name="${NAME_PREFIX}${index}"
    while docker ps -a --format "table {{.Names}}" | grep -q "^${name}$"; do
        index=$((index + 1))
        name="${NAME_PREFIX}${index}"
    done
    echo "$name"
}

deploy_containers() {
    local success_count=0
    local containers_info=()
    
    log "开始部署 ${CONTAINER_COUNT} 个容器..."
    
    for ((i=0; i<CONTAINER_COUNT; i++)); do
        local domain_index=$((i % ${#DOMAINS_ARRAY[@]}))
        local domain="${DOMAINS_ARRAY[$domain_index]}"
        
        local http_port_index=$((i % ${#HTTP_PORTS_ARRAY[@]}))
        local http_port="${HTTP_PORTS_ARRAY[$http_port_index]}"
        http_port=$((http_port + i))
        
        local https_port_index=$((i % ${#HTTPS_PORTS_ARRAY[@]}))
        local https_port="${HTTPS_PORTS_ARRAY[$https_port_index]}"
        https_port=$((https_port + i))
        
        local container_name=$(get_next_name)
        
        # 检查端口
        while ! check_port "$http_port"; do
            warn "HTTP端口 ${http_port} 被占用，尝试 $((http_port + 1))"
            http_port=$((http_port + 1))
        done
        
        while ! check_port "$https_port" || [ "$https_port" -eq "$http_port" ]; do
            warn "HTTPS端口 ${https_port} 被占用，尝试 $((https_port + 1))"
            https_port=$((https_port + 1))
        done
        
        # 处理已存在容器
        if docker ps -a --format "table {{.Names}}" | grep -q "^${container_name}$"; then
            if [ "$AUTO_REMOVE" = "yes" ]; then
                docker stop "$container_name" &> /dev/null && docker rm "$container_name" &> /dev/null
                warn "已删除现有容器: ${container_name}"
            else
                warn "跳过已存在容器: ${container_name}"
                continue
            fi
        fi
        
        # 生成 secret
        local secret=$(head -c 16 /dev/urandom | xxd -ps 2>/dev/null || openssl rand -hex 16)
        
        echo -e "${CYAN}🔧 部署容器 ${container_name}...${NC}"
        echo -e "  端口: ${http_port}->80, ${https_port}->443"
        echo -e "  域名: ${domain}"
        
        # 部署容器
        if docker run --name "$container_name" -d \
            -e secret="$secret" \
            -e domain="$domain" \
            -e ip_white_list="OFF" \
            -p "${http_port}:80" \
            -p "${https_port}:443" \
            "$IMAGE_NAME" &> /dev/null; then
            
            sleep 2
            if docker ps --filter "name=${container_name}" --format "{{.Names}}" | grep -q "^${container_name}$"; then
                log "✅ 容器 ${container_name} 部署成功"
                containers_info+=("${container_name}:${http_port}:${https_port}:${domain}:${secret}")
                success_count=$((success_count + 1))
            else
                error "容器 ${container_name} 启动失败"
                docker logs "$container_name" --tail 5
            fi
        else
            error "容器 ${container_name} 创建失败"
        fi
        echo "----------------------------------------"
    done
    
    # 显示部署结果
    echo -e "\n${GREEN}🎉 部署完成！成功: ${success_count}/${CONTAINER_COUNT}${NC}"
    
    if [ ${#containers_info[@]} -gt 0 ]; then
        echo -e "\n${YELLOW}📋 部署详情：${NC}"
        printf "${CYAN}%-15s %-10s %-10s %-20s %s${NC}\n" "容器" "HTTP" "HTTPS" "域名" "Secret"
        echo "${CYAN}--------------------------------------------------------------------------------${NC}"
        
        for info in "${containers_info[@]}"; do
            IFS=':' read -r name http https domain secret <<< "$info"
            printf "%-15s %-10s %-10s %-20s %s\n" "$name" "$http" "$https" "$domain" "$secret"
        done
        
        echo -e "\n${GREEN}🔧 管理命令：${NC}"
        echo -e "查看状态: ${YELLOW}docker ps -a | grep ${NAME_PREFIX}${NC}"
        echo -e "查看日志: ${YELLOW}docker logs <容器名>${NC}"
    fi
}

main() {
    show_header
    check_docker
    pull_image
    parse_config
    deploy_containers
}

main "$@"
EOF

# 给执行权限并测试
chmod +x /tmp/deploy-optimized.sh
