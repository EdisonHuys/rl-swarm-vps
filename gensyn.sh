#!/bin/bash
set -euo pipefail

log_file="./deploy_rl_swarm_vps.log"
max_retries=10
retry_count=0

# CPU 监控配置
CPU_THRESHOLD=30        # CPU 使用率阈值（百分比）
MONITOR_INTERVAL=60     # 监控间隔（秒）
LOW_CPU_DURATION=1800   # 低CPU持续时间（秒，30分钟 = 1800秒）
CONTAINER_NAME="swarm-cpu"

info() {
    echo -e "[$(date +"%Y-%m-%d %T")] [INFO] $*" | tee -a "$log_file"
}

error() {
    echo -e "[$(date +"%Y-%m-%d %T")] [ERROR] $*" >&2 | tee -a "$log_file"
    if [ $retry_count -lt $max_retries ]; then
        retry_count=$((retry_count+1))
        info "自动重试 ($retry_count/$max_retries)..."
        exec "$0" "$@"
    else
        echo -e "[$(date +"%Y-%m-%d %T")] [ERROR] 达到最大重试次数 ($max_retries 次)，请手动重启 Docker 并检查环境" >&2 | tee -a "$log_file"
        exit 1
    fi
}

# 检查 Docker 是否安装
check_docker() {
    if ! command -v docker &> /dev/null; then
        error "Docker 未安装，请先安装 Docker (https://www.docker.com)"
    fi
    if ! command -v docker-compose &> /dev/null; then
        error "Docker Compose 未安装，请先安装 Docker Compose"
    fi
}

# 检查必要的命令是否可用
check_dependencies() {
    local missing_deps=()
    
    # 检查基本命令
    if ! command -v awk &> /dev/null; then
        missing_deps+=("awk")
    fi
    
    if ! command -v grep &> /dev/null; then
        missing_deps+=("grep")
    fi
    
    if ! command -v cut &> /dev/null; then
        missing_deps+=("cut")
    fi
    
    # 检查CPU监控相关命令（至少需要一个）
    local cpu_monitor_available=false
    if command -v top &> /dev/null; then
        cpu_monitor_available=true
    fi
    if command -v vmstat &> /dev/null; then
        cpu_monitor_available=true
    fi
    if [ -f /proc/loadavg ]; then
        cpu_monitor_available=true
    fi
    
    if [ "$cpu_monitor_available" = false ]; then
        missing_deps+=("CPU监控工具(top/vmstat/proc)")
    fi
    
    # 如果有缺失的依赖，报错
    if [ ${#missing_deps[@]} -gt 0 ]; then
        error "缺少必要的依赖: ${missing_deps[*]}"
    fi
}

# 获取当前 CPU 使用率
get_cpu_usage() {
    # 使用 top 命令获取 CPU 使用率，兼容不同系统的输出格式
    local cpu_usage
    
    # 检测操作系统类型
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS 系统
        if command -v top &> /dev/null; then
            # macOS 的 top 命令输出格式不同
            cpu_usage=$(top -l 1 | grep "CPU usage" | awk '{print $3}' | sed 's/%//' | cut -d'.' -f1)
        else
            cpu_usage=0
        fi
    else
        # Linux 系统
        # 尝试多种方式获取CPU使用率
        if command -v top &> /dev/null; then
            # 方法1: 使用 top 命令
            cpu_usage=$(top -bn1 | grep -i "cpu(s)" | head -1 | awk '{print $2}' | sed 's/%us,//' | cut -d'%' -f1 | cut -d'.' -f1)
            
            # 如果上面的方法失败，尝试其他格式
            if [[ ! "$cpu_usage" =~ ^[0-9]+$ ]] || [ "$cpu_usage" -gt 100 ]; then
                # 方法2: 使用 vmstat
                if command -v vmstat &> /dev/null; then
                    cpu_usage=$(vmstat 1 2 | tail -1 | awk '{print 100-$15}')
                # 方法3: 使用 /proc/loadavg 估算
                elif [ -f /proc/loadavg ]; then
                    local load_avg
                    load_avg=$(cat /proc/loadavg | awk '{print $1}')
                    cpu_usage=$(echo "$load_avg * 25" | bc -l | cut -d'.' -f1)
                else
                    cpu_usage=0
                fi
            fi
        else
            # 如果没有 top 命令，使用其他方法
            if command -v vmstat &> /dev/null; then
                cpu_usage=$(vmstat 1 2 | tail -1 | awk '{print 100-$15}')
            elif [ -f /proc/loadavg ]; then
                local load_avg
                load_avg=$(cat /proc/loadavg | awk '{print $1}')
                cpu_usage=$(echo "$load_avg * 25" | bc -l | cut -d'.' -f1)
            else
                cpu_usage=0
            fi
        fi
    fi
    
    # 确保返回有效的数字
    if [[ ! "$cpu_usage" =~ ^[0-9]+$ ]] || [ "$cpu_usage" -gt 100 ]; then
        cpu_usage=0
    fi
    
    echo "$cpu_usage"
}

# 检查容器是否运行
is_container_running() {
    docker ps --format "table {{.Names}}" | grep -q "^${CONTAINER_NAME}$"
}

# 重启容器
restart_container() {
    info "🔄 检测到CPU使用率持续低于${CPU_THRESHOLD}%，重启容器..."
    
    # 停止当前容器
    if is_container_running; then
        info "停止当前容器..."
        docker-compose stop $CONTAINER_NAME || true
        sleep 5
    fi
    
    # 重新构建并启动容器
    info "重新构建并启动容器..."
    if docker-compose build $CONTAINER_NAME && docker-compose --profile swarm up -d $CONTAINER_NAME; then
        info "✅ 容器重启成功"
        return 0
    else
        error "❌ 容器重启失败"
        return 1
    fi
}

# CPU 监控循环
monitor_cpu() {
    info "🔍 开始CPU监控 - 阈值: ${CPU_THRESHOLD}%, 监控间隔: ${MONITOR_INTERVAL}秒"
    info "📊 当连续${LOW_CPU_DURATION}秒CPU使用率低于${CPU_THRESHOLD}%时，将自动重启容器"
    
    local low_cpu_start_time=""
    local current_time
    
    while true; do
        # 检查容器是否在运行
        if ! is_container_running; then
            info "⚠️ 容器未运行，尝试重启..."
            restart_container
            sleep 30
            continue
        fi
        
        # 获取当前CPU使用率
        local cpu_usage
        cpu_usage=$(get_cpu_usage)
        current_time=$(date +%s)
        
        # 检查CPU使用率是否有效
        if [[ ! "$cpu_usage" =~ ^[0-9]+$ ]] || [ "$cpu_usage" -gt 100 ]; then
            info "⚠️ 无法获取有效CPU使用率，跳过本次检查"
            sleep $MONITOR_INTERVAL
            continue
        fi
        
        info "📈 当前CPU使用率: ${cpu_usage}%"
        
        # 检查CPU使用率是否低于阈值
        if [ "$cpu_usage" -lt "$CPU_THRESHOLD" ]; then
            # 如果还没有开始计时，记录开始时间
            if [ -z "$low_cpu_start_time" ]; then
                low_cpu_start_time=$current_time
                info "⏱️ CPU使用率低于${CPU_THRESHOLD}%，开始计时..."
            else
                # 计算已经持续的时间
                local elapsed_time=$((current_time - low_cpu_start_time))
                local remaining_time=$((LOW_CPU_DURATION - elapsed_time))
                
                if [ $remaining_time -gt 0 ]; then
                    info "⏳ CPU使用率持续低于${CPU_THRESHOLD}%，还需${remaining_time}秒触发重启..."
                else
                    # 达到重启条件
                    info "🚨 CPU使用率已持续${LOW_CPU_DURATION}秒低于${CPU_THRESHOLD}%，触发重启"
                    restart_container
                    low_cpu_start_time=""  # 重置计时器
                    sleep 60  # 重启后等待1分钟再继续监控
                fi
            fi
        else
            # CPU使用率高于阈值，重置计时器
            if [ -n "$low_cpu_start_time" ]; then
                info "✅ CPU使用率回升至${cpu_usage}%，重置低CPU计时器"
                low_cpu_start_time=""
            fi
        fi
        
        sleep $MONITOR_INTERVAL
    done
}

# 打开 Docker（仅适用于 macOS）
start_docker() {
    info "正在启动 Docker..."
    if [[ "$OSTYPE" == "darwin"* ]]; then
        if ! open -a Docker; then
            error "无法启动 Docker 应用，请检查 Docker 是否安装或手动启动"
        fi
    else
        # Linux 系统通常 Docker 作为服务运行
        if ! systemctl is-active --quiet docker; then
            info "启动 Docker 服务..."
            sudo systemctl start docker || error "无法启动 Docker 服务"
        fi
    fi
    
    # 等待 Docker 启动
    info "等待 Docker 启动完成..."
    sleep 10
    
    # 检查 Docker 是否运行
    if ! docker info &> /dev/null; then
        error "Docker 未正常运行，请检查 Docker 状态"
    fi
}

# 运行 Docker Compose 容器
run_docker_compose() {
    local attempt=1
    local max_attempts=$max_retries
    while [ $attempt -le $max_attempts ]; do
        info "尝试运行容器 $CONTAINER_NAME (第 $attempt 次)..."
        if docker-compose build $CONTAINER_NAME && docker-compose --profile swarm up -d $CONTAINER_NAME; then
            info "✅ 容器 $CONTAINER_NAME 运行成功"
            return 0
        else
            info "Docker 构建失败，重试中..."
            sleep 2
            ((attempt++))
        fi
    done
    error "Docker 构建超过最大重试次数 ($max_attempts 次)"
}

# 信号处理函数
cleanup() {
    info "🛑 收到退出信号，正在清理..."
    if is_container_running; then
        info "停止容器..."
        docker-compose stop $CONTAINER_NAME || true
    fi
    info "✅ 清理完成"
    exit 0
}

# 检查磁盘空间
check_disk_space() {
    local min_space_gb=5  # 最小需要5GB空间
    local available_space_gb
    
    # 检测操作系统类型并使用相应的命令
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS 系统
        available_space_gb=$(df -g . | awk 'NR==2 {print $4}')
    else
        # Linux 系统
        available_space_gb=$(df -BG . | awk 'NR==2 {print $4}' | sed 's/G//')
    fi
    
    # 确保获取到有效数字
    if [[ ! "$available_space_gb" =~ ^[0-9]+$ ]]; then
        error "无法获取磁盘空间信息"
    fi
    
    if [ "$available_space_gb" -lt "$min_space_gb" ]; then
        error "磁盘空间不足！可用空间: ${available_space_gb}GB，需要至少: ${min_space_gb}GB"
    fi
    
    info "✅ 磁盘空间检查通过，可用空间: ${available_space_gb}GB"
}

# 日志轮转
rotate_log() {
    local log_file="$1"
    local max_size_mb=100  # 最大100MB
    
    if [ -f "$log_file" ]; then
        local size_mb
        
        # 检测操作系统类型并使用相应的命令
        if [[ "$OSTYPE" == "darwin"* ]]; then
            # macOS 系统
            size_mb=$(du -m "$log_file" | cut -f1)
        else
            # Linux 系统
            size_mb=$(du -m "$log_file" | cut -f1)
        fi
        
        # 确保获取到有效数字
        if [[ ! "$size_mb" =~ ^[0-9]+$ ]]; then
            info "⚠️ 无法获取日志文件大小，跳过轮转"
            return
        fi
        
        if [ "$size_mb" -gt "$max_size_mb" ]; then
            local backup_file="${log_file}.$(date +%Y%m%d_%H%M%S)"
            mv "$log_file" "$backup_file"
            info "📄 日志文件过大 (${size_mb}MB)，已轮转到: $backup_file"
        fi
    fi
}

# 主逻辑
main() {
    # 设置信号处理
    trap cleanup SIGINT SIGTERM
    
    # 日志轮转
    rotate_log "$log_file"
    
    # 检查 Docker 环境
    check_docker

    # 检查依赖
    check_dependencies

    # 启动 Docker
    start_docker

    # 检查磁盘空间
    check_disk_space

    # 进入目录
    info "进入 rl-swarm-vps 目录..."
    cd ~/rl-swarm-vps || error "进入 rl-swarm-vps 目录失败"

    # 运行容器
    info "🚀 运行 $CONTAINER_NAME 容器..."
    run_docker_compose
    
    # 等待容器完全启动
    info "⏳ 等待容器完全启动..."
    sleep 30
    
    # 开始CPU监控
    monitor_cpu
}

# 执行主逻辑
main "$@"
