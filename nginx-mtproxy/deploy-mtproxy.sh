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
declare -A https_links_map  # 使用关联数组存储链接信息
IMAGE_NAME="ellermister/nginx-mtproxy:latest"

# 显示标题函数
show_header() {
    echo -e "${GREEN}"
    echo "========================================"
    echo "🚀 nginx-mtproxy 批量部署脚本"
    echo "========================================"
    echo -e "${NC}"
}

# 检查并拉取镜像
check_and_pull_image() {
    echo -e "\n${BLUE}🔍 检查 Docker 镜像...${NC}"
    
    # 检查镜像是否存在
    if docker image inspect "$IMAGE_NAME" &> /dev/null; then
        echo -e "${GREEN}✅ 镜像已存在: ${IMAGE_NAME}${NC}"
        
        # 检查是否为最新版本
        echo -e "${YELLOW}⏳ 检查镜像更新...${NC}"
        docker pull "$IMAGE_NAME" | grep -q "Image is up to date"
        
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}✅ 镜像已是最新版本${NC}"
        else
            echo -e "${GREEN}🔄 镜像已更新到最新版本${NC}"
        fi
    else
        echo -e "${YELLOW}📥 拉取镜像: ${IMAGE_NAME}${NC}"
        if docker pull "$IMAGE_NAME"; then
            echo -e "${GREEN}✅ 镜像拉取成功${NC}"
        else
            echo -e "${RED}❌ 镜像拉取失败，请检查网络连接和镜像名称${NC}"
            exit 1
        fi
    fi
    
    # 显示镜像信息
    local image_info=$(docker image inspect "$IMAGE_NAME" --format '{{.RepoTags}} {{.Created}}' 2>/dev/null || echo "未知")
    echo -e "${CYAN}📋 镜像信息: ${image_info}${NC}"
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

# 显示现有容器状态
show_existing_containers() {
    local existing_count=$(docker ps -a --filter "name=nginx-mtproxy" --format "{{.Names}}" | wc -l)
    
    if [ "$existing_count" -gt 0 ]; then
        echo -e "\n${YELLOW}📊 当前已存在的 nginx-mtproxy 容器（共 ${existing_count} 个）：${NC}"
        docker ps -a --filter "name=nginx-mtproxy" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
        echo ""
    else
        echo -e "\n${GREEN}📊 当前没有 nginx-mtproxy 容器${NC}"
    fi
}

# 检查并停止/删除现有容器函数
check_existing_container() {
    local container_name=$1
    
    if docker ps -a --format "table {{.Names}}" | grep -q "^${container_name}$"; then
        echo -e "${YELLOW}⚠️  发现已存在的容器: ${container_name}${NC}"
        
        # 显示容器状态
        local status=$(docker ps -a --filter "name=${container_name}" --format "{{.Status}}")
        local ports=$(docker ps -a --filter "name=${container_name}" --format "{{.Ports}}")
        echo -e "${CYAN}   状态: ${status}${NC}"
        echo -e "${CYAN}   端口: ${ports}${NC}"
        
        read -p "是否删除此容器？(y/N，默认不删除): " delete_choice
        delete_choice=${delete_choice:-n}
        
        if [[ $delete_choice =~ ^[Yy]$ ]]; then
            echo -e "${YELLOW}🛑 停止并删除容器 ${container_name}...${NC}"
            docker stop "$container_name" > /dev/null 2>&1
            docker rm "$container_name" > /dev/null 2>&1
            echo -e "${GREEN}✅ 容器 ${container_name} 已删除${NC}"
            return 0
        else
            echo -e "${YELLOW}⏭️  跳过容器 ${container_name}${NC}"
            return 1
        fi
    fi
    return 0
}

# 检查端口是否被占用
check_port_available() {
    local port=$1
    local current_container=$2
    
    # 检查其他容器是否占用该端口
    local occupying_container=$(docker ps --format "table {{.Names}}\t{{.Ports}}" | grep ":${port}->" | awk '{print $1}' | grep -v "^${current_container}$")
    
    if [ -n "$occupying_container" ]; then
        echo -e "${RED}❌ 端口 ${port} 已被容器 ${occupying_container} 占用${NC}"
        return 1
    fi
    
    # 检查系统进程是否占用该端口
    if ss -tulpn 2>/dev/null | grep -q ":${port} "; then
        local process_info=$(ss -tulpn 2>/dev/null | grep ":${port} " | head -1 | cut -d' ' -f6)
        echo -e "${RED}❌ 端口 ${port} 已被系统进程占用: ${process_info}${NC}"
        return 1
    fi
    
    # 对于 macOS 系统，使用 netstat 检查
    if command -v netstat &> /dev/null; then
        if netstat -an | grep -q ".${port} .*LISTEN"; then
            echo -e "${RED}❌ 端口 ${port} 已被占用${NC}"
            return 1
        fi
    fi
    
    return 0
}

# 获取下一个可用的容器名称
get_next_container_name() {
    local base_name="nginx-mtproxy"
    local index=0
    local container_name="${base_name}${index}"
    
    while docker ps -a --format "table {{.Names}}" | grep -q "^${container_name}$"; do
        index=$((index + 1))
        container_name="${base_name}${index}"
    done
    echo "$container_name"
}

# 解析逗号分隔的输入
parse_comma_separated_input() {
    local input="$1"
    local default_value="$2"
    local -n result_array=$3
    
    # 如果输入为空，使用默认值
    if [ -z "$input" ]; then
        input="$default_value"
    fi
    
    # 清除空格并按逗号分割
    IFS=',' read -ra result_array <<< "${input// /}"
}

# 获取服务器IP地址
get_server_ip() {
    local ip
    # 尝试多种方法获取公网IP
    ip=$(curl -s -4 --connect-timeout 5 ip.sb 2>/dev/null || 
         curl -s -4 --connect-timeout 5 ifconfig.me 2>/dev/null || 
         curl -s -4 --connect-timeout 5 icanhazip.com 2>/dev/null ||
         hostname -I 2>/dev/null | awk '{print $1}' ||
         echo "YOUR_SERVER_IP")
    echo "$ip"
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
    
    # 获取伪装域名
    read -p "请输入伪装域名（默认 cloudflare.com）: " domain
    domain=${domain:-cloudflare.com}
    
    # 获取起始HTTP端口
    while true; do
        read -p "请输入起始 HTTP 端口（默认 8081）: " start_http_port
        start_http_port=${start_http_port:-8081}
        
        if [[ "$start_http_port" =~ ^[0-9]+$ ]] && [ "$start_http_port" -ge 1024 ] && [ "$start_http_port" -le 65535 ]; then
            break
        else
            echo -e "${RED}❌ 请输入 1024-65535 之间的有效端口号${NC}"
        fi
    done
    
    # 获取起始HTTPS端口
    while true; do
        read -p "请输入起始 HTTPS 端口（默认 8443）: " start_https_port
        start_https_port=${start_https_port:-8443}
        
        if [[ "$start_https_port" =~ ^[0-9]+$ ]] && [ "$start_https_port" -ge 1024 ] && [ "$start_https_port" -le 65535 ]; then
            if [ "$start_https_port" -eq "$start_http_port" ]; then
                echo -e "${RED}❌ HTTPS 端口不能与 HTTP 端口相同${NC}"
            else
                break
            fi
        else
            echo -e "${RED}❌ 请输入 1024-65535 之间的有效端口号${NC}"
        fi
    done
    
    # 获取容器名称前缀
    read -p "请输入容器名称前缀（默认 nginx-mtproxy）: " name_prefix
    name_prefix=${name_prefix:-nginx-mtproxy}
    
    # 显示配置预览
    echo -e "\n${GREEN}📊 配置预览：${NC}"
    echo -e "  ${CYAN}容器数量: ${container_count}${NC}"
    echo -e "  ${CYAN}伪装域名: ${domain}${NC}"
    echo -e "  ${CYAN}起始HTTP端口: ${start_http_port}${NC}"
    echo -e "  ${CYAN}起始HTTPS端口: ${start_https_port}${NC}"
    echo -e "  ${CYAN}容器前缀: ${name_prefix}${NC}"
    
    # 生成所有容器配置
    container_configs=()
    for ((i=0; i<container_count; i++)); do
        local http_port=$((start_http_port + i))
        local https_port=$((start_https_port + i))
        local container_name="${name_prefix}${i}"
        
        # 检查端口是否可用
        while ! check_port_available "$http_port" "$container_name"; do
            echo -e "${YELLOW}⚠️  HTTP 端口 ${http_port} 不可用，尝试 ${http_port}+1${NC}"
            http_port=$((http_port + 1))
        done
        
        # 修复这里的语法错误：使用 do 而不是 then
        while ! check_port_available "$https_port" "$container_name" || [ "$https_port" -eq "$http_port" ]; do
            echo -e "${YELLOW}⚠️  HTTPS 端口 ${https_port} 不可用，尝试 ${https_port}+1${NC}"
            https_port=$((https_port + 1))
        done
        
        container_configs+=("$container_name:$http_port:$https_port:$domain")
    done
    
    # 显示部署配置预览
    echo -e "\n${GREEN}📊 部署配置预览：${NC}"
    for config in "${container_configs[@]}"; do
        IFS=':' read -r name http_port https_port domain <<< "$config"
        echo -e "  ${CYAN}● ${name}: ${http_port}->80, ${https_port}->443, 域名: ${domain}${NC}"
    done
    
    read -p "确认开始部署？(Y/n，默认确认): " confirm_deploy
    confirm_deploy=${confirm_deploy:-y}
    
    if [[ ! $confirm_deploy =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}⏹️  取消部署${NC}"
        exit 0
    fi
}

# 获取容器HTTPS链接
get_https_link() {
    local container_name=$1
    local secret=$2
    local https_port=$3
    local domain=$4
    
    # 获取服务器IP
    local server_ip=$(get_server_ip)
    
    # 生成HTTPS链接
    local https_link="https://${domain}:${https_port}/${secret}/"
    
    echo "$https_link"
}

# 从单个容器日志中提取HTTPS链接信息
extract_https_info_from_logs() {
    local container_name=$1
    local max_attempts=3
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        # 获取容器日志的最后20行
        local container_logs=$(docker logs "$container_name" 2>&1 | tail -20)
        
        # 从日志中提取secret和链接信息
        if echo "$container_logs" | grep -q "Secret:"; then
            local secret=$(echo "$container_logs" | grep "Secret:" | awk '{print $2}' | head -1)
            local link_info=$(echo "$container_logs" | grep -E "https?://" | head -1 | tr -d '[:space:]')
            
            if [ -n "$secret" ] && [ -n "$link_info" ]; then
                echo -e "${GREEN}✅ 成功获取 ${container_name} 的配置信息${NC}"
                echo "$link_info"
                return 0
            fi
        fi
        
        # 如果没找到，等待后重试
        if [ $attempt -lt $max_attempts ]; then
            sleep 2
        fi
        attempt=$((attempt + 1))
    done
    
    echo -e "${YELLOW}⚠️  无法从 ${container_name} 的日志中获取HTTPS链接，使用生成的链接${NC}"
    return 1
}

# 批量获取所有容器的HTTPS链接信息
batch_get_https_links() {
    echo -e "\n${BLUE}🔍 批量获取容器HTTPS链接信息...${NC}"
    
    local total_containers=${#deployed_containers[@]}
    local current=1
    
    for config in "${deployed_containers[@]}"; do
        IFS=':' read -r container_name http_port https_port secret domain <<< "$config"
        
        echo -e "${YELLOW}⏳ 获取 ${container_name} 的链接信息 (${current}/${total_containers})...${NC}"
        
        # 生成基础HTTPS链接
        local base_https_link=$(get_https_link "$container_name" "$secret" "$https_port" "$domain")
        
        # 尝试从日志中获取实际链接
        local log_link_info=$(extract_https_info_from_logs "$container_name")
        
        # 存储链接信息
        if [ -n "$log_link_info" ] && [ "$log_link_info" != "null" ]; then
            https_links_map["$container_name"]="$log_link_info"
            echo -e "${GREEN}✅ 从日志获取: ${log_link_info}${NC}"
        else
            https_links_map["$container_name"]="$base_https_link"
            echo -e "${CYAN}📋 使用生成链接: ${base_https_link}${NC}"
        fi
        
        current=$((current + 1))
    done
    
    echo -e "${GREEN}✅ 所有容器链接信息获取完成${NC}"
}

# 部署单个容器函数
deploy_single_container() {
    local config=$1
    local container_number=$2
    local total_containers=$3
    
    IFS=':' read -r container_name http_port https_port domain <<< "$config"
    
    echo -e "\n${BLUE}📦 部署第 ${container_number}/${total_containers} 个容器: ${container_name}${NC}"
    
    # 检查容器是否已存在
    if ! check_existing_container "$container_name"; then
        return 1
    fi
    
    # 再次确认端口可用性
    if ! check_port_available "$http_port" "$container_name"; then
        return 1
    fi
    if ! check_port_available "$https_port" "$container_name"; then
        return 1
    fi
    
    # 生成随机 secret
    secret=$(head -c 16 /dev/urandom | xxd -ps)
    
    echo -e "${GREEN}🔧 容器配置：${NC}"
    echo -e "  ${CYAN}🔑 Secret: ${secret}${NC}"
    echo -e "  ${CYAN}🌐 伪装域名: ${domain}${NC}"
    echo -e "  ${CYAN}🔌 端口映射: ${http_port}->80, ${https_port}->443${NC}"
    
    # 部署容器
    echo -e "${YELLOW}⏳ 正在启动容器...${NC}"
    
    if docker run --name "$container_name" -d \
        -e secret="$secret" \
        -e domain="$domain" \
        -e ip_white_list="OFF" \
        -p "${http_port}:80" \
        -p "${https_port}:443" \
        "$IMAGE_NAME"; then
        
        # 等待容器启动
        echo -e "${YELLOW}⏳ 等待容器启动...${NC}"
        sleep 3
        
        # 检查容器状态
        local status=$(docker ps --filter "name=${container_name}" --format "{{.Status}}")
        if [ -n "$status" ]; then
            echo -e "${GREEN}✅ 容器 ${container_name} 部署成功！状态: ${status}${NC}"
            deployed_containers+=("$container_name:$http_port:$https_port:$secret:$domain")
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
        # 批量获取所有容器的HTTPS链接信息
        batch_get_https_links
        
        # 显示部署详情表格
        echo -e "\n${YELLOW}📋 部署详情：${NC}"
        printf "${CYAN}%-20s %-12s %-12s %-15s %-34s %s${NC}\n" "容器名称" "HTTP端口" "HTTPS端口" "伪装域名" "Secret" "HTTPS链接"
        echo "${CYAN}────────────────────────────────────────────────────────────────────────────────────────────────────────────${NC}"
        
        for config in "${deployed_containers[@]}"; do
            IFS=':' read -r name http_port https_port secret domain <<< "$config"
            
            # 从关联数组中获取HTTPS链接
            local https_link="${https_links_map[$name]}"
            
            printf "%-20s %-12s %-12s %-15s %-34s %s\n" "$name" "$http_port" "$https_port" "$domain" "$secret" "$https_link"
        done
        
        # 显示管理命令
        echo -e "\n${GREEN}🔧 管理命令：${NC}"
        echo -e "查看所有容器: ${YELLOW}docker ps -a --filter 'name=nginx-mtproxy'${NC}"
        echo -e "查看日志:      ${YELLOW}docker logs <容器名称>${NC}"
        echo -e "停止容器:      ${YELLOW}docker stop <容器名称>${NC}"
        echo -e "启动容器:      ${YELLOW}docker start <容器名称>${NC}"
        echo -e "删除容器:      ${YELLOW}docker rm -f <容器名称>${NC}"
        
        echo -e "\n${YELLOW}💡 提示：${NC}"
        echo -e "  • 请妥善保存上面的 Secret 和 HTTPS 链接信息"
        echo -e "  • 可以使用 HTTPS 链接直接配置客户端"
        echo -e "  • 确保服务器防火墙已开放相关端口"
        
    fi
}

# 主函数
main() {
    show_header
    check_docker_environment
    check_and_pull_image
    show_existing_containers
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
