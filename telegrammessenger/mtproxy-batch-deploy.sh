#!/bin/bash

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 全局变量
IMAGE_NAME="telegrammessenger/proxy:latest"
CONTAINER_PREFIX="mtproxy"
DEFAULT_DOMAINS=("microsoft.com" "apple.com" "google.com" "cloudflare.com" "amazon.com")

# 检查 Docker 是否安装
check_docker() {
    echo -e "${BLUE}🔍 检查 Docker 环境...${NC}"
    if ! command -v docker &> /dev/null; then
        echo -e "${RED}❌ Docker 未安装，请先安装 Docker${NC}"
        exit 1
    fi
    echo -e "${GREEN}✅ Docker 已安装${NC}"
    echo -e "${CYAN}🐳 Docker 版本: $(docker --version | cut -d' ' -f3 | cut -d',' -f1)${NC}"
}

# 检查并安装 xxd
check_xxd() {
    echo -e "${BLUE}🔍 检查 xxd 工具...${NC}"
    if command -v xxd &> /dev/null; then
        echo -e "${GREEN}✅ xxd 已安装${NC}"
        return 0
    fi
    
    echo -e "${YELLOW}📥 安装 xxd 工具...${NC}"
    if command -v apt-get &> /dev/null; then
        apt-get update > /dev/null 2>&1 && apt-get install -y xxd > /dev/null 2>&1
    elif command -v yum &> /dev/null; then
        yum install -y vim-common > /dev/null 2>&1
    elif command -v apk &> /dev/null; then
        apk add vim > /dev/null 2>&1
    fi
    
    if command -v xxd &> /dev/null; then
        echo -e "${GREEN}✅ xxd 安装成功${NC}"
    else
        echo -e "${YELLOW}⚠️  xxd 安装失败，使用备用方案${NC}"
    fi
}

# 检查并拉取镜像
check_image() {
    echo -e "${BLUE}🔍 检查 Docker 镜像...${NC}"
    
    # 检查镜像是否存在
    if docker image inspect "$IMAGE_NAME" &> /dev/null; then
        echo -e "${GREEN}✅ 镜像已存在: ${IMAGE_NAME}${NC}"
    else
        echo -e "${YELLOW}📥 拉取镜像: ${IMAGE_NAME}${NC}"
        if docker pull "$IMAGE_NAME"; then
            echo -e "${GREEN}✅ 镜像拉取成功${NC}"
        else
            echo -e "${RED}❌ 镜像拉取失败${NC}"
            exit 1
        fi
    fi
    
    # 检查更新
    echo -e "${YELLOW}⏳ 检查镜像更新...${NC}"
    docker pull "$IMAGE_NAME" | grep -q "Image is up to date"
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✅ 镜像已是最新版本${NC}"
    else
        echo -e "${GREEN}🔄 镜像已更新到最新版本${NC}"
    fi
}

# 显示现有容器
show_containers() {
    local containers=$(docker ps -a --filter "name=$CONTAINER_PREFIX" --format "{{.Names}}" | sort)
    if [ -z "$containers" ]; then
        echo -e "${GREEN}📊 当前没有运行中的 MTProxy 容器${NC}"
        return 0
    fi
    
    echo -e "${YELLOW}📊 当前运行的 MTProxy 容器：${NC}"
    docker ps -a --filter "name=$CONTAINER_PREFIX" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
    
    return $(echo "$containers" | wc -l)
}

# 删除现有容器
delete_containers() {
    local container_count=$1
    
    if [ $container_count -eq 0 ]; then
        return 0
    fi
    
    echo -e "\n${YELLOW}🗑️  选择要删除的容器：${NC}"
    echo -e "  0. 不删除任何容器"
    echo -e "  1. 删除所有容器"
    echo -e "  2. 选择特定容器删除"
    
    read -p "请输入选择 (0-2，默认0): " delete_choice
    delete_choice=${delete_choice:-0}
    
    case $delete_choice in
        0)
            echo -e "${GREEN}⏭️  跳过容器删除${NC}"
            ;;
        1)
            echo -e "${YELLOW}🛑 删除所有容器...${NC}"
            docker ps -a --filter "name=$CONTAINER_PREFIX" --format "{{.Names}}" | xargs -r docker stop
            docker ps -a --filter "name=$CONTAINER_PREFIX" --format "{{.Names}}" | xargs -r docker rm
            echo -e "${GREEN}✅ 所有容器已删除${NC}"
            ;;
        2)
            echo -e "${YELLOW}🔢 输入要删除的容器编号（用逗号分隔，如: 0,2,3）: ${NC}"
            read -p "容器编号: " container_nums
            IFS=',' read -ra nums <<< "$container_nums"
            for num in "${nums[@]}"; do
                local container_name="${CONTAINER_PREFIX}${num}"
                if docker ps -a --format "{{.Names}}" | grep -q "^${container_name}$"; then
                    echo -e "${YELLOW}🛑 删除容器 ${container_name}...${NC}"
                    docker stop "$container_name" > /dev/null 2>&1
                    docker rm "$container_name" > /dev/null 2>&1
                    echo -e "${GREEN}✅ 容器 ${container_name} 已删除${NC}"
                else
                    echo -e "${RED}❌ 容器 ${container_name} 不存在${NC}"
                fi
            done
            ;;
        *)
            echo -e "${RED}❌ 无效选择${NC}"
            ;;
    esac
}

# 生成随机密钥
generate_secret() {
    if command -v openssl &> /dev/null; then
        openssl rand -hex 16
    else
        # 备用方案
        head -c 16 /dev/urandom | xxd -ps 2>/dev/null || head -c 16 /dev/urandom | od -An -tx1 | tr -d ' \n'
    fi
}

# 获取部署配置
get_deployment_config() {
    echo -e "\n${BLUE}📋 批量部署配置${NC}"
    
    # 获取部署数量
    while true; do
        read -p "请输入要部署的容器数量（默认 1）: " container_count
        container_count=${container_count:-1}
        if [[ "$container_count" =~ ^[0-9]+$ ]] && [ "$container_count" -ge 1 ] && [ "$container_count" -le 20 ]; then
            break
        else
            echo -e "${RED}❌ 请输入 1-20 之间的数字${NC}"
        fi
    done
    
    # 获取起始端口
    while true; do
        read -p "请输入起始端口（默认 49286）: " start_port
        start_port=${start_port:-49286}
        if [[ "$start_port" =~ ^[0-9]+$ ]] && [ "$start_port" -ge 1024 ] && [ "$start_port" -le 65535 ]; then
            break
        else
            echo -e "${RED}❌ 请输入 1024-65535 之间的端口号${NC}"
        fi
    done
    
    # 获取自定义端口
    read -p "请输入自定义端口（用逗号分隔，留空使用自动递增）: " custom_ports_input
    if [ -n "$custom_ports_input" ]; then
        IFS=',' read -ra custom_ports <<< "${custom_ports_input// /}"
        if [ ${#custom_ports[@]} -ne $container_count ]; then
            echo -e "${RED}❌ 自定义端口数量与容器数量不匹配，使用自动递增${NC}"
            unset custom_ports
        fi
    fi
    
    # 获取伪装域名
    read -p "请输入伪装域名（用逗号分隔，默认: ${DEFAULT_DOMAINS[*]}）: " domains_input
    if [ -n "$domains_input" ]; then
        IFS=',' read -ra domains <<< "${domains_input// /}"
    else
        domains=("${DEFAULT_DOMAINS[@]}")
    fi
    
    # 显示配置预览
    echo -e "\n${GREEN}📊 配置预览：${NC}"
    echo -e "  ${CYAN}容器数量: ${container_count}${NC}"
    echo -e "  ${CYAN}起始端口: ${start_port}${NC}"
    echo -e "  ${CYAN}伪装域名: ${domains[*]}${NC}"
    
    # 确认部署
    read -p "确认开始部署？(Y/n，默认确认): " confirm
    confirm=${confirm:-y}
    if [[ ! $confirm =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}⏹️  取消部署${NC}"
        exit 0
    fi
    
    # 返回配置
    echo "${container_count}:${start_port}:${custom_ports_input}:${domains[*]}"
}

# 部署容器
deploy_containers() {
    local container_count=$1
    local start_port=$2
    local custom_ports_input=$3
    local domains=($4)
    
    echo -e "\n${BLUE}🚀 开始部署容器...${NC}"
    
    # 解析自定义端口
    if [ -n "$custom_ports_input" ]; then
        IFS=',' read -ra custom_ports <<< "${custom_ports_input// /}"
    fi
    
    # 部署每个容器
    for ((i=0; i<container_count; i++)); do
        local container_name="${CONTAINER_PREFIX}${i}"
        
        # 确定端口
        if [ -n "${custom_ports[$i]}" ]; then
            local port="${custom_ports[$i]}"
        else
            local port=$((start_port + i))
        fi
        
        # 选择域名（循环使用）
        local domain_index=$((i % ${#domains[@]}))
        local domain="${domains[$domain_index]}"
        
        # 生成密钥
        local secret=$(generate_secret)
        
        echo -e "${YELLOW}📦 部署容器 ${container_name}...${NC}"
        echo -e "  ${CYAN}端口: ${port} -> 443${NC}"
        echo -e "  ${CYAN}域名: ${domain}${NC}"
        echo -e "  ${CYAN}密钥: ${secret}${NC}"
        
        # 部署容器
        if docker run -d --name "$container_name" \
            -p "${port}:443" \
            -e SECRET="$secret" \
            -e TLS_DOMAIN="$domain" \
            -e IP_WHITE_LIST="OFF" \
            "$IMAGE_NAME" > /dev/null 2>&1; then
            
            echo -e "${GREEN}✅ 容器 ${container_name} 部署成功${NC}"
            
            # 生成TG链接
            local server_ip=$(curl -s -4 ip.sb 2>/dev/null || echo "YOUR_SERVER_IP")
            local tg_link="https://t.me/proxy?server=${server_ip}&port=${port}&secret=${secret}"
            echo -e "  ${BLUE}🔗 TG链接: ${tg_link}${NC}"
            
        else
            echo -e "${RED}❌ 容器 ${container_name} 部署失败${NC}"
        fi
        
        echo -e "${BLUE}────────────────────────────────────────${NC}"
    done
}

# 主函数
main() {
    echo -e "${GREEN}"
    echo "========================================"
    echo "🚀 MTProxy 批量部署脚本"
    echo "========================================"
    echo -e "${NC}"
    
    # 执行检查
    check_docker
    check_xxd
    check_image
    
    # 显示并处理现有容器
    show_containers
    local container_count=$?
    delete_containers $container_count
    
    # 获取部署配置
    local config=$(get_deployment_config)
    IFS=':' read -r container_count start_port custom_ports domains <<< "$config"
    
    # 部署容器
    deploy_containers "$container_count" "$start_port" "$custom_ports" "$domains"
    
    # 显示最终结果
    echo -e "\n${GREEN}🎉 部署完成！${NC}"
    echo -e "${YELLOW}📊 最终容器状态：${NC}"
    docker ps --filter "name=$CONTAINER_PREFIX" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
    
    echo -e "\n${GREEN}💡 管理命令：${NC}"
    echo -e "查看所有容器: ${YELLOW}docker ps -a --filter 'name=$CONTAINER_PREFIX'${NC}"
    echo -e "查看容器日志: ${YELLOW}docker logs <容器名>${NC}"
}

# 脚本入口
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main
fi
