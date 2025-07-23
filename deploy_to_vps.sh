#!/bin/bash

# RL Swarm VPS 一键部署脚本
# 使用方法: ./deploy_to_vps.sh <VPS_IP> <USERNAME> [SSH_KEY_PATH]

set -euo pipefail

# 颜色定义
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

log() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }

# 检查参数
if [ $# -lt 2 ]; then
    echo "使用方法: $0 <VPS_IP> <USERNAME> [SSH_KEY_PATH]"
    echo "示例: $0 192.168.1.100 ubuntu ~/.ssh/id_rsa"
    exit 1
fi

VPS_IP=$1
USERNAME=$2
SSH_KEY_PATH=${3:-""}

# 构建SSH命令
if [ -n "$SSH_KEY_PATH" ]; then
    SSH_CMD="ssh -i $SSH_KEY_PATH $USERNAME@$VPS_IP"
    RSYNC_CMD="rsync -avz -e 'ssh -i $SSH_KEY_PATH'"
else
    SSH_CMD="ssh $USERNAME@$VPS_IP"
    RSYNC_CMD="rsync -avz"
fi

log "开始部署到 VPS: $VPS_IP"

# 测试连接
log "测试SSH连接..."
if ! $SSH_CMD "echo '连接成功'" 2>/dev/null; then
    error "无法连接到VPS"
    exit 1
fi
success "SSH连接成功"

# 上传文件
log "上传项目文件..."
$RSYNC_CMD --progress --exclude='.git' --exclude='__pycache__' --exclude='*.pyc' --exclude='.DS_Store' \
    ./ $USERNAME@$VPS_IP:~/projects/rl-swarm-vps/
success "文件上传完成"

# 部署
log "在VPS上部署..."
$SSH_CMD << 'EOF'
cd ~/projects/rl-swarm-vps
chmod +x *.sh
mkdir -p user/logs user/keys

# 安装Docker
if ! command -v docker &> /dev/null; then
    curl -fsSL https://get.docker.com -o get-docker.sh
    sudo sh get-docker.sh
    sudo usermod -aG docker $USER
    newgrp docker
fi

# 安装Docker Compose
if ! command -v docker-compose &> /dev/null; then
    sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    sudo chmod +x /usr/local/bin/docker-compose
fi

# 创建环境变量
cat > .env << 'ENVEOF'
DOCKER=true
GENSYN_RESET_CONFIG=true
CPU_ONLY=1
CONNECT_TO_TESTNET=true
ENVEOF

# 构建并启动
docker-compose build swarm-cpu
docker-compose --profile swarm up -d swarm-cpu

# 创建监控脚本
cat > monitor.sh << 'MONITOREOF'
#!/bin/bash
echo "=== 系统状态 ==="
uptime && free -h && df -h
echo "=== Docker状态 ==="
docker ps && docker stats --no-stream
echo "=== 服务状态 ==="
curl -s http://localhost:3000 || echo "服务未响应"
MONITOREOF
chmod +x monitor.sh

echo "部署完成！"
echo "查看状态: ./monitor.sh"
echo "查看日志: tail -f user/logs/auto_monitor.log"
echo "重启服务: ./restart_rlswarm.sh"
EOF

success "部署完成！"
echo ""
echo "=== 快速命令 ==="
echo "SSH连接: $SSH_CMD"
echo "查看状态: cd ~/projects/rl-swarm-vps && ./monitor.sh"
echo "自动监控: cd ~/projects/rl-swarm-vps && ./auto_run.sh" 