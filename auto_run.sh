#!/bin/bash

set -euo pipefail

# 配置参数
RESTART_DELAY=30                  # 重启延迟时间（秒）
CHECK_INTERVAL=480                 # 检查间隔时间（秒）
LOG_FILE="${HOME}/rl-swarm-vps/logs/auto_monitor.log"  # 日志文件路径
PID_FILE="/home/gensyn/rl_swarm/training.pid"           # 进程 PID 文件路径

# 颜色输出设置
GREEN="\033[32m"                  # 绿色，用于成功信息
BLUE="\033[34m"                   # 蓝色，用于普通信息
RED="\033[31m"                    # 红色，用于错误信息
YELLOW="\033[33m"                 # 黄色，用于警告信息
RESET="\033[0m"                   # 重置颜色

# 检查日志文件路径是否可写
check_log_file() {
    local log_dir
    log_dir=$(dirname "$LOG_FILE")
    if ! mkdir -p "$log_dir" 2>/dev/null || ! touch "$LOG_FILE" 2>/dev/null; then
        echo -e "${RED}❌ 日志文件路径 $LOG_FILE 不可写，仅输出到终端${RESET}"
        LOG_FILE="/dev/null"  # 如果不可写，仅输出到终端
    fi
}

# 重要信息日志（同时输出到终端和日志文件，非缓冲）
log_important() {
    stdbuf -oL echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# 颜色输出函数（使用 stdbuf 确保非缓冲输出）
echo_green() { echo -e "${GREEN}$1${RESET}" | tee -a "$LOG_FILE"; }
echo_blue() { echo -e "${BLUE}$1${RESET}" | tee -a "$LOG_FILE"; }
echo_red() { echo -e "${RED}$1${RESET}" | tee -a "$LOG_FILE"; log_important "$1"; }
echo_yellow() { echo -e "${YELLOW}$1${RESET}" | tee -a "$LOG_FILE"; log_important "$1"; }

# 清理函数：处理脚本退出时的清理工作
cleanup() {
    echo_yellow "🛑 清理"
    if [ -f "$PID_FILE" ]; then
        local pid
        pid=$(cat "$PID_FILE")
        if ps -p "$pid" > /dev/null 2>&1; then
            echo_yellow "终止训练进程 PID: $pid"
            kill -TERM "$pid" 2>/dev/null || true
            sleep 5
            if ps -p "$pid" > /dev/null 2>&1; then
                kill -KILL "$pid" 2>/dev/null || true
            fi
        fi
        rm -f "$PID_FILE"
    fi
    pkill -f "swarm_launcher.py" 2>/dev/null || true
    pkill -f "run_rl_swarm.sh" 2>/dev/null || true
    pkill -f "yarn start" 2>/dev/null || true
    echo_green "✅ 已停止"
    exit 0
}

# 检查进程是否运行
is_process_running() {
    # 方法1: 检查PID文件中的进程
    if [ -f "$PID_FILE" ]; then
        local pid
        pid=$(cat "$PID_FILE" 2>/dev/null || echo "")
        if [[ -n "$pid" ]] && ps -p "$pid" > /dev/null 2>&1; then
            # 检查该进程的子进程是否有 python
            if ! pgrep -P "$pid" -f "python" > /dev/null 2>&1; then
                # 没有python子进程，说明训练已死
                echo_yellow "⚠️ 检测到主shell进程还在但python训练进程已退出，需重启"
                return 1
            fi
            # 检查进程是否为僵尸
            local process_state
            process_state=$(ps -o state= -p "$pid" 2>/dev/null || echo "")
            if [[ "$process_state" != "Z" ]]; then
                return 0  # 进程存在且正常运行
            fi
        fi
    fi
    
    # 方法2: 检查关键进程名称
    if pgrep -f "swarm_launcher.py" > /dev/null 2>&1; then
        return 0  # swarm_launcher.py 进程存在
    fi
    
    # 方法3: 检查Python训练相关进程
    if pgrep -f "python.*train" > /dev/null 2>&1; then
        return 0  # Python训练进程存在
    fi
    
    # 方法4: 检查Docker容器中的训练进程
    if docker ps --format "table {{.Names}}\t{{.Status}}" | grep -q "swarm-cpu.*Up"; then
        # 检查容器内是否有训练进程
        if docker exec swarm-cpu pgrep -f "swarm_launcher.py" > /dev/null 2>&1; then
            return 0  # 容器内训练进程存在
        fi
    fi
    
    return 1  # 进程不存在
}

# 检查训练进程是否健康
is_training_healthy() {
    # 检查日志文件是否有错误信息
    if [ -f "$LOG_FILE" ]; then
        # 检查最近5分钟是否有严重错误
        local recent_errors
        recent_errors=$(tail -n 100 "$LOG_FILE" 2>/dev/null | grep -i "error\|exception\|traceback\|failed\|killed" | wc -l)
        
        if [ "$recent_errors" -gt 5 ]; then
            echo_yellow "⚠️ 检测到大量错误信息，训练可能异常"
            return 1
        fi
    fi
    
    # 检查进程是否响应（通过发送信号0）
    if [ -f "$PID_FILE" ]; then
        local pid
        pid=$(cat "$PID_FILE" 2>/dev/null || echo "")
        if [[ -n "$pid" ]]; then
            if ! kill -0 "$pid" 2>/dev/null; then
                echo_yellow "⚠️ 进程PID $pid 无响应"
                return 1
            fi
        fi
    fi
    
    return 0  # 训练进程健康
}

# 启动训练进程
start_training() {
    echo_blue "🚀 启动 RL Swarm 训练 (Docker 环境)..."
    
    # 清理可能存在的旧PID文件
    if [ -f "$PID_FILE" ]; then
        local old_pid
        old_pid=$(cat "$PID_FILE" 2>/dev/null || echo "")
        if [[ -n "$old_pid" ]] && ps -p "$old_pid" > /dev/null 2>&1; then
            echo_yellow "🛑 终止旧进程 PID: $old_pid"
            kill -TERM "$old_pid" 2>/dev/null || true
            sleep 3
            if ps -p "$old_pid" > /dev/null 2>&1; then
                kill -KILL "$old_pid" 2>/dev/null || true
            fi
        fi
        rm -f "$PID_FILE"
    fi
    
    # 设置环境变量（与 Dockerfile 和 run_rl_swarm.sh 一致）
    #export PYTORCH_MPS_HIGH_WATERMARK_RATIO=0.0
    export OMP_NUM_THREADS=6
    export MKL_NUM_THREADS=6
    #export PYTORCH_ENABLE_MPS_FALLBACK=1
    #export CPU_ONLY=1
    #export HF_HUB_DOWNLOAD_TIMEOUT=300
    export HF_DATASETS_CACHE="/home/gensyn/rl_swarm/.cache/huggingface/datasets"
    export HF_MODELS_CACHE="/home/gensyn/rl_swarm/.cache/huggingface/transformers"
    export CONNECT_TO_TESTNET=true
    export SWARM_CONTRACT="0xFaD7C5e93f28257429569B854151A1B8DCD404c2"
    export HUGGINGFACE_ACCESS_TOKEN="None"
    export GENSYN_RESET_CONFIG=""
    export WANDB_MODE=disabled
    
    # 确保缓存目录存在并设置权限
    mkdir -p "$HF_DATASETS_CACHE" "$HF_MODELS_CACHE"
    chmod -R 777 "$HF_DATASETS_CACHE" "$HF_MODELS_CACHE"
    
    # 尝试启动 run_rl_swarm.sh，最多重试 3 次
    for i in {1..3}; do
        echo_blue "🔄 尝试启动训练进程 (第 $i 次)..."
        
        # 启动进程并捕获PID
        ./run_rl_swarm.sh 2>&1 | tee -a "$LOG_FILE" &
        local pid=$!
        echo "$pid" > "$PID_FILE"
        echo_green "✅ 训练进程已启动，PID: $pid"
        
        # 等待进程稳定
        sleep 15
        
        # 验证进程是否真的在运行
        if ps -p "$pid" > /dev/null 2>&1; then
            # 检查进程状态
            local process_state
            process_state=$(ps -o state= -p "$pid" 2>/dev/null || echo "")
            
            if [[ "$process_state" != "Z" ]]; then
                echo_green "✅ 训练进程启动成功，状态: $process_state"
                return 0  # 启动成功
            else
                echo_red "❌ 进程已变为僵尸状态"
            fi
        else
            echo_red "❌ 进程PID $pid 不存在"
        fi
        
        echo_red "❌ 训练进程启动失败，重试 $i/3"
        rm -f "$PID_FILE"
        sleep 5
    done
    
    echo_red "❌ 训练进程启动失败，达到最大重试次数"
    return 1
}

# 信号处理：捕获 SIGINT 和 SIGTERM 信号以进行清理
trap cleanup SIGINT SIGTERM

# 主监控循环
main() {
    # 检查日志文件路径
    check_log_file
    
    local restart_count=0
    local health_check_count=0
    echo_green "🎯 RL Swarm 自动监控启动 (Docker 环境)"
    echo_blue "⏱️ 检查间隔: ${CHECK_INTERVAL}秒"
    echo_blue "⏰ 重启延迟: ${RESTART_DELAY}秒"
    echo_blue "🎯 防止报错假死"
    echo ""
    if ! start_training; then
        echo_red "❌ 初始启动失败"
        exit 1
    fi
    
    while true; do
        sleep "$CHECK_INTERVAL"
        
        # 检查进程是否运行
        if ! is_process_running; then
            echo_yellow "⚠️ 检测到训练进程已结束"
            restart_count=$((restart_count + 1))
            echo_yellow "🔄 准备第 $restart_count 次重启"
            echo_yellow "⏰ 等待 $RESTART_DELAY 秒后重启..."
            sleep "$RESTART_DELAY"
            if start_training; then
                echo_green "✅ 第 $restart_count 次重启成功"
                health_check_count=0  # 重置健康检查计数
            else
                echo_red "❌ 第 $restart_count 次重启失败，将继续尝试"
            fi
        else
            # 进程在运行，检查是否健康
            health_check_count=$((health_check_count + 1))
            
            # 每1次检查进行一次健康检查
            if [ $((health_check_count % 1)) -eq 0 ]; then
                if ! is_training_healthy; then
                    echo_yellow "⚠️ 训练进程可能异常，准备重启"
                    restart_count=$((restart_count + 1))
                    echo_yellow "🔄 准备第 $restart_count 次重启（健康检查触发）"
                    echo_yellow "⏰ 等待 $RESTART_DELAY 秒后重启..."
                    sleep "$RESTART_DELAY"
                    if start_training; then
                        echo_green "✅ 第 $restart_count 次重启成功"
                        health_check_count=0  # 重置健康检查计数
                    else
                        echo_red "❌ 第 $restart_count 次重启失败，将继续尝试"
                    fi
                else
                    echo_blue "✅ 训练进程运行正常 (健康检查 #$((health_check_count / 10)))"
                fi
            fi
        fi
    done
}

# 启动脚本
main
