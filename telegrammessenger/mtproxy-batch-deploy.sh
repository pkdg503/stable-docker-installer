#!/bin/bash

# 颜色定义
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# 全局变量
declare -a deployed_containers
declare -a container_configs
declare -A tg_links_map
IMAGE_NAME="telegrammessenger/proxy:latest"
CONTAINER_PREFIX="mtproxy"
DEFAULT_DOMAINS=("microsoft.com" "apple.com" "google.com" "cloudflare.com" "amazon.com")

# 显示标题函数
show_header() {
    echo -e "${GREEN}"
    echo "========================================"
    echo "🚀 MTProxy 批量部署脚本"
    echo "========================================"
    echo -e "${NC}"
}

# 检查 Docker 环境
check_docker_environment() {
    echo -e "${BLUE}🔍 检查 Docker 环境...${NC}"
    
    if ! command -v docker &> /dev/null; then
        echo -e "${RED}❌ Docker 未安装，请先安装 Docker${NC}"
        exit 1
    fi
    
    if ! docker info &> /dev/null; then
        echo -e "${RED}❌ Docker 服务未运行，请先启动 Docker${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}✅ Docker 环境检查通过${NC}"
    echo -e "${CYAN}🐳 Docker 版本: $(docker --version | cut -d' ' -f3 | cut -d',' -f1)${NC}"
}

# 检查并安装 xxd
check_and_install_xxd() {
    echo -e "${BLUE}🔍 检查 xxd 工具...${NC}"
    
    if command -v xxd &> /dev/null; then
        echo -e "${GREEN}✅ xxd 已安装${NC}"
        return 0
    fi
    
    echo -e "${YELLOW}📥 安装 xxd 工具...${NC}"
    if command -v apt-get &> /dev/null; then
        apt-get update > /dev/null 2>&1
        if apt-get install -y xxd > /dev/null 2>&1; then
            echo -e "${GREEN}✅ xxd 安装成功${NC}"
        else
            echo -e "${YELLOW}⚠️  xxd 安装失败，使用备用方案${NC}"
        fi
    elif command -v yum &> /dev/null; then
        yum install -y vim-common > /dev/null 2>&1 && echo -e "${GREEN}✅ xxd 安装成功${NC}" || echo -e "${YELLOW}⚠️  xxd 安装失败，使用备用方案${NC}"
    else
        echo -e "${YELLOW}⚠️  无法自动安装 xxd，使用备用方案${NC}"
    fi
}

# 检查并拉取镜像
check_and_pull_image() {
    echo -e "\n${BLUE}🔍 检查 Docker 镜像...${NC}"
    
    # 检查镜像是否存在
    if docker image inspect "$IMAGE_NAME" &> /dev/null; then
        echo -e "${GREEN}✅ 镜像已存在: ${IMAGE_NAME}${NC}"
    else
        echo -e "${YELLOW}📥 拉取镜像: ${IMAGE_NAME}${NC}"
        if docker pull "$IMAGE_NAME"; then
            echo -e "${GREEN}✅ 镜像拉取成功${NC}"
        else
            echo -e "${RED}❌ 镜像拉取失败，请检查网络连接和镜像名称${NC}"
            exit 1
        fi
    fi
    
    # 检查是否为最新版本
    echo -e "${YELLOW}⏳ 检查镜像更新...${NC}"
    docker pull "$IMAGE_NAME" | grep -q "Image is up to date"
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✅ 镜像已是最新版本${NC}"
    else
        echo -e "${GREEN}🔄 镜像已更新到最新版本${NC}"
    fi
}

# 显示现有容器状态
show_existing_containers() {
    local existing_count=$(docker ps -a --filter "name=$CONTAINER_PREFIX" --format "{{.Names}}" | wc -l)
    
    if [ "$existing_count" -gt 0 ]; then
        echo -e "\n${YELLOW}📊 当前已存在的 MTProxy 容器（共 ${existing_count} 个）：${NC}"
        docker ps -a --filter "name=$CONTAINER_PREFIX" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
        echo ""
        return $existing_count
    else
        echo -e "\n${GREEN}📊 当前没有 MTProxy 容器${NC}"
        return 0
    fi
}

# 删除现有容器
delete_existing_containers() {
    local container_count=$1
    
    if [ $container_count -eq 0 ]; then
        return 0
    fi
    
    echo -e "\n${YELLOW}🗑️  选择要删除的容器：${NC}"
    echo -e "  0. 不删除任何容器（默认）"
    echo -e "  1. 删除所有容器"
    echo -e "  2. 选择特定容器删除"
    
    read -p "请输入选择 (0-2): " delete_choice
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

# 检查端口是否被占用
check_port_available() {
    local port=$1
    
    # 检查其他容器是否占用该端口
    if docker ps --format "table {{.Names}}\t{{.Ports}}" | grep -q ":${port}->"; then
        echo -e "${RED}❌ 端口 ${port} 已被占用${NC}"
        return 1
    fi
    
    # 检查系统进程是否占用该端口
    if command -v ss &> /dev/null && ss -tulpn 2>/dev/null | grep -q ":${port} "; then
        echo -e "${RED}❌ 端口 ${port} 已被系统进程占用${NC}"
        return 1
    fi
    
    # 对于 macOS 系统，使用 netstat 检查
    if command -v netstat &> /dev/null && netstat -an 2>/dev/null | grep -q ".${port} .*LISTEN"; then
        echo -e "${RED}❌ 端口 ${port} 已被占用${NC}"
        return 1
    fi
    
    return 0
}

# 解析逗号分隔的输入
parse_comma_separated_input() {
    local input="$1"
    local default_value="$2"
    local -n result_array=$3
    
    if [ -z "$input" ]; then
        input="$default_value"
    fi
    
    IFS=',' read -ra result_array <<< "${input// /}"
}

# 获取服务器IP地址
get_server_ip() {
    local ip
    ip=$(curl -s -4 --connect-timeout 5 ip.sb 2>/dev/null || 
         curl -s -4 --connect-timeout 5 ifconfig.me 2>/dev/null || 
         curl -s -4 --connect-timeout 5 icanhazip.com 2>/dev/null ||
         hostname -I 2>/dev/null | awk '{print $1}' ||
         echo "YOUR_SERVER_IP")
    echo "$ip"
}

# 生成随机secret
generate_secret() {
    if command -v openssl &> /dev/null; then
        openssl rand -hex 16
    elif command -v xxd &> /dev/null; then
        head -c 16 /dev/urandom | xxd -ps
    else
        head -c 16 /dev/urandom | od -An -tx1 | tr -d ' \n'
    fi
}

# 获取批量部署配置
get_batch_config() {
    echo -e "\n${BLUE}📋 批量部署配置${NC}"
    
    # 获取部署数量
    while true; do
        read -p "请输入要部署的容器数量（默认 1）: " container_count
        container_count=${container_count:-1}
        
        if [[ "$container_count" =~ ^[0-9]+$ ]] && [ "$container_count" -ge 1 ] && [ "$container_count" -le 20 ]; then
            break
        else
            echo -e "${RED}❌ 请输入 1-20 之间的有效数字${NC}"
        fi
    done
    
    # 获取基础配置
    echo -e "\n${CYAN}🎯 基础配置（将应用于所有容器）${NC}"
    
    # 获取起始端口
    while true; do
        read -p "请输入起始端口（默认 49286）: " start_port
        start_port=${start_port:-49286}
        
        if [[ "$start_port" =~ ^[0-9]+$ ]] && [ "$start_port" -ge 1024 ] && [ "$start_port" -le 65535 ]; then
            break
        else
            echo -e "${RED}❌ 请输入 1024-65535 之间的有效端口号${NC}"
        fi
    done
    
    # 获取自定义端口
    read -p "请输入自定义端口（用逗号分隔，留空使用自动递增）: " custom_ports_input
    
    # 获取伪装域名
    read -p "请输入伪装域名（多个用逗号分隔，默认 microsoft.com）: " domains_input
    domains_input=${domains_input:-microsoft.com}
    
    # 解析域名数组
    local -a domains_array
    parse_comma_separated_input "$domains_input" "microsoft.com" domains_array
    
    # 显示配置预览
    echo -e "\n${GREEN}📊 配置预览：${NC}"
    echo -e "  ${CYAN}容器数量: ${container_count}${NC}"
    echo -e "  ${CYAN}起始端口: ${start_port}${NC}"
    if [ -n "$custom_ports_input" ]; then
        echo -e "  ${CYAN}自定义端口: ${custom_ports_input}${NC}"
    fi
    echo -e "  ${CYAN}伪装域名: ${domains_array[*]}${NC}"
    
    # 生成所有容器配置
    container_configs=()
    if [ -n "$custom_ports_input" ]; then
        IFS=',' read -ra custom_ports <<< "${custom_ports_input// /}"
        if [ ${#custom_ports[@]} -ne $container_count ]; then
            echo -e "${RED}❌ 自定义端口数量与容器数量不匹配，使用自动递增${NC}"
            unset custom_ports
        fi
    fi
    
    for ((i=0; i<container_count; i++)); do
        local container_name="${CONTAINER_PREFIX}${i}"
        
        # 确定端口
        if [ -n "${custom_ports[$i]}" ]; then
            local port="${custom_ports[$i]}"
        else
            local port=$((start_port + i))
        fi
        
        # 循环使用域名
        local domain_index=$((i % ${#domains_array[@]}))
        local domain="${domains_array[$domain_index]}"
        
        container_configs+=("$container_name:$port:$domain")
    done
    
    # 显示部署配置预览
    echo -e "\n${GREEN}📊 部署配置预览：${NC}"
    for config in "${container_configs[@]}"; do
        IFS=':' read -r name port domain <<< "$config"
        echo -e "  ${CYAN}● ${name}: ${port}->443, 域名: ${domain}${NC}"
    done
    
    read -p "确认开始部署？(Y/n，默认确认): " confirm_deploy
    confirm_deploy=${confirm_deploy:-y}
    
    if [[ ! $confirm_deploy =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}⏹️  取消部署${NC}"
        exit 0
    fi
}

# 部署单个容器函数
deploy_single_container() {
    local config=$1
    local container_number=$2
    local total_containers=$3
    
    IFS=':' read -r container_name port domain <<< "$config"
    
    echo -e "\n${BLUE}📦 部署第 ${container_number}/${total_containers} 个容器: ${container_name}${NC}"
    
    # 检查端口是否可用
    local original_port=$port
    while ! check_port_available "$port"; do
        echo -e "${YELLOW}⚠️  端口 ${port} 不可用，尝试 ${port}+1${NC}"
        port=$((port + 1))
    done
    
    if [ "$port" -ne "$original_port" ]; then
        echo -e "${YELLOW}🔄 端口已调整为: ${port}${NC}"
    fi
    
    # 生成随机 secret
    secret=$(generate_secret)
    
    echo -e "${GREEN}🔧 容器配置：${NC}"
    echo -e "  ${CYAN}🔑 Secret: ${secret}${NC}"
    echo -e "  ${CYAN}🌐 伪装域名: ${domain}${NC}"
    echo -e "  ${CYAN}🔌 端口映射: ${port}->443${NC}"
    
    # 部署容器
    echo -e "${YELLOW}⏳ 正在启动容器...${NC}"
    
    if docker run -d --name "$container_name" \
        -p "${port}:443" \
        -e SECRET="$secret" \
        -e TLS_DOMAIN="$domain" \
        -e IP_WHITE_LIST="OFF" \
        "$IMAGE_NAME"; then
        
        # 等待容器启动
        echo -e "${YELLOW}⏳ 等待容器启动...${NC}"
        sleep 3
        
        # 检查容器状态
        local status=$(docker ps --filter "name=${container_name}" --format "{{.Status}}")
        if [ -n "$status" ]; then
            echo -e "${GREEN}✅ 容器 ${container_name} 部署成功！状态: ${status}${NC}"
            
            # 生成TG链接
            local server_ip=$(get_server_ip)
            local tg_link="https://t.me/proxy?server=${server_ip}&port=${port}&secret=${secret}"
            tg_links_map["$container_name"]="$tg_link"
            
            deployed_containers+=("$container_name:$port:$secret:$domain")
            return 0
        else
            echo -e "${RED}❌ 容器 ${container_name} 启动失败${NC}"
            docker logs "$container_name" --tail 10
            return 1
        fi
    else
        echo -e "${RED}❌ 容器 ${container_name} 部署失败！${NC}"
        return 1
    fi
}

# 显示部署结果
show_deployment_result() {
    local total_attempts=$1
    local successful_deployments=${#deployed_containers[@]}
    
    echo -e "\n${GREEN}"
    echo "========================================"
    echo "🎉 部署完成！"
    echo "========================================"
    echo -e "${NC}"
    echo -e "${GREEN}✅ 成功部署: ${successful_deployments}/${total_attempts} 个容器${NC}"
    
    if [ $successful_deployments -gt 0 ]; then
        # 显示部署详情表格
        echo -e "\n${YELLOW}📋 部署详情：${NC}"
        printf "${CYAN}%-15s %-12s %-20s %-34s %s${NC}\n" "容器名称" "端口" "伪装域名" "Secret" "TG代理链接"
        echo -e "${CYAN}────────────────────────────────────────────────────────────────────────────────────────────────────${NC}"
        
        for config in "${deployed_containers[@]}"; do
            IFS=':' read -r name port secret domain <<< "$config"
            local tg_link="${tg_links_map[$name]}"
            printf "%-15s %-12s %-20s %-34s %s\n" "$name" "$port" "$domain" "$secret" "$tg_link"
        done
        
        # 显示管理命令
        echo -e "\n${GREEN}🔧 管理命令：${NC}"
        echo -e "查看所有容器: ${YELLOW}docker ps -a --filter 'name=$CONTAINER_PREFIX'${NC}"
        echo -e "查看日志:      ${YELLOW}docker logs <容器名称>${NC}"
        echo -e "停止容器:      ${YELLOW}docker stop <容器名称>${NC}"
        echo -e "启动容器:      ${YELLOW}docker start <容器名称>${NC}"
        echo -e "删除容器:      ${YELLOW}docker rm -f <容器名称>${NC}"
        
        echo -e "\n${YELLOW}💡 提示：${NC}"
        echo -e "  • 请妥善保存上面的 Secret 和 TG 代理链接"
        echo -e "  • 可以直接点击TG链接一键配置代理"
        echo -e "  • 确保服务器防火墙已开放相关端口"
    fi
}

# 主函数
main() {
    show_header
    
    # 1. 检查 Docker
    check_docker_environment
    
    # 2. 检查并安装 xxd
    check_and_install_xxd
    
    # 3. 检查并拉取镜像
    check_and_pull_image
    
    # 4. 显示并处理现有容器
    show_existing_containers
    local existing_count=$?
    delete_existing_containers $existing_count
    
    # 获取部署配置并部署
    get_batch_config
    
    local total_containers=${#container_configs[@]}
    local current=1
    
    # 部署所有容器
    for config in "${container_configs[@]}"; do
        deploy_single_container "$config" "$current" "$total_containers"
        current=$((current + 1))
    done
    
    show_deployment_result "$total_containers"
}

# 脚本入口
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main
fi
