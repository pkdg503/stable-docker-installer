cat > deploy-auto.sh << 'EOF'
#!/bin/bash

# 非交互式自动部署脚本 - 支持 curl 管道运行

# ========== 配置区域 ==========
# 部署容器数量
CONTAINER_COUNT=1

# 伪装域名 (多个用逗号分隔)
DOMAINS="cloudflare.com"

# HTTP 端口 (多个用逗号分隔)
HTTP_PORTS="8081"

# HTTPS 端口 (多个用逗号分隔)  
HTTPS_PORTS="8443"

# 容器名称前缀
NAME_PREFIX="nginx-mtproxy"

# 自动删除已存在容器 (yes/no)
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
}

check_docker() {
    if ! command -v docker &> /dev/null; then
        echo -e "${RED}❌ Docker 未安装${NC}"
        exit 1
    fi
    echo -e "${GREEN}✅ Docker 环境检查通过${NC}"
}

pull_image() {
    echo -e "${BLUE}🔍 检查 Docker 镜像...${NC}"
    if ! docker pull "$IMAGE_NAME" &> /dev/null; then
        echo -e "${RED}❌ 镜像拉取失败${NC}"
        exit 1
    fi
    echo -e "${GREEN}✅ 镜像准备就绪${NC}"
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

get_container_name() {
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
    
    echo -e "${BLUE}📦 开始部署 ${CONTAINER_COUNT} 个容器...${NC}"
    
    for ((i=0; i<CONTAINER_COUNT; i++)); do
        # 获取配置
        local domain_index=$((i % ${#DOMAINS_ARRAY[@]}))
        local domain="${DOMAINS_ARRAY[$domain_index]}"
        
        local http_port_index=$((i % ${#HTTP_PORTS_ARRAY[@]}))
        local base_http_port="${HTTP_PORTS_ARRAY[$http_port_index]}"
        local http_port=$((base_http_port + i))
        
        local https_port_index=$((i % ${#HTTPS_PORTS_ARRAY[@]}))
        local base_https_port="${HTTPS_PORTS_ARRAY[$https_port_index]}"
        local https_port=$((base_https_port + i))
        
        local container_name=$(get_container_name)
        
        # 检查端口
        while ! check_port "$http_port"; do
            http_port=$((http_port + 1))
        done
        
        while ! check_port "$https_port" || [ "$https_port" -eq "$http_port" ]; do
            https_port=$((https_port + 1))
        done
        
        # 处理已存在容器
        if docker ps -a --format "table {{.Names}}" | grep -q "^${container_name}$"; then
            if [ "$AUTO_REMOVE" = "yes" ]; then
                docker stop "$container_name" &> /dev/null
                docker rm "$container_name" &> /dev/null
                echo -e "${YELLOW}♻️  已删除现有容器: ${container_name}${NC}"
            else
                echo -e "${YELLOW}⏭️  跳过已存在容器: ${container_name}${NC}"
                continue
            fi
        fi
        
        # 生成 secret
        local secret=$(head -c 16 /dev/urandom | xxd -ps 2>/dev/null || openssl rand -hex 16)
        
        echo -e "${CYAN}🔧 部署: ${container_name}${NC}"
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
                echo -e "${GREEN}✅ 部署成功${NC}"
                containers_info+=("${container_name}:${http_port}:${https_port}:${domain}:${secret}")
                success_count=$((success_count + 1))
            else
                echo -e "${RED}❌ 启动失败${NC}"
            fi
        else
            echo -e "${RED}❌ 部署失败${NC}"
        fi
        echo "----------------------------------------"
    done
    
    # 显示结果
    echo -e "\n${GREEN}🎉 部署完成！成功: ${success_count}/${CONTAINER_COUNT}${NC}"
    
    if [ $success_count -gt 0 ]; then
        echo -e "\n${YELLOW}📋 部署详情：${NC}"
        printf "${CYAN}%-20s %-12s %-12s %-15s %s${NC}\n" "容器名称" "HTTP端口" "HTTPS端口" "域名" "Secret"
        echo "${CYAN}─────────────────────────────────────────────────────────────────────────${NC}"
        
        for info in "${containers_info[@]}"; do
            IFS=':' read -r name http https domain secret <<< "$info"
            printf "%-20s %-12s %-12s %-15s %s\n" "$name" "$http" "$https" "$domain" "$secret"
        done
    fi
}

main() {
    show_header
    check_docker
    pull_image
    parse_config
    deploy_containers
}

main
EOF

echo "✅ 自动部署脚本已创建"
echo "🚀 使用命令: curl -sSL https://raw.githubusercontent.com/pkdg503/docker-installer/main/nginx-mtproxy/deploy-auto.sh | bash"
