# RL Swarm VPS 快速部署指南

## 快速开始

### 1. 连接VPS
```bash
# 使用SSH连接
ssh username@your_vps_ip

# 或使用SSH密钥
ssh -i ~/.ssh/id_rsa username@your_vps_ip
```

### 2. 一键部署（推荐）
```bash
# 在Mac上执行，自动上传并部署
./deploy_to_vps.sh your_vps_ip username [ssh_key_path]

# 示例
./deploy_to_vps.sh 192.168.1.100 ubuntu ~/.ssh/id_rsa
```

---

## 手动部署步骤

### 1. 上传项目
```bash
# 在Mac终端执行
rsync -avz --progress rl-swarm-vps/ username@your_vps_ip:~/projects/rl-swarm-vps/
```

### 2. 安装Docker
```bash
# 在VPS上执行
sudo apt update
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh
sudo usermod -aG docker $USER
newgrp docker
```

### 3. 安装Docker Compose
```bash
sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose
```

### 4. 部署项目
```bash
cd ~/projects/rl-swarm-vps
chmod +x *.sh
mkdir -p user/logs user/keys

# 创建环境变量
cat > .env << EOF
DOCKER=true
GENSYN_RESET_CONFIG=true
CPU_ONLY=1
CONNECT_TO_TESTNET=true
EOF

# 构建并启动
docker-compose build swarm-cpu
docker-compose --profile swarm up -d swarm-cpu
```

---

## 常用命令

### 查看状态
```bash
# 查看容器状态
docker ps

# 查看日志
docker logs -f rl-swarm-vps-swarm-cpu-1

# 查看系统状态
./monitor.sh
```

### 管理服务
```bash
# 启动服务
docker-compose --profile swarm up -d swarm-cpu

# 停止服务
docker-compose --profile swarm down

# 重启服务
./restart_rlswarm.sh

# 自动监控
./auto_run.sh
```

### 查看日志
```bash
# 训练日志
tail -f user/logs/training_*.log

# 监控日志
tail -f user/logs/auto_monitor.log

# 系统日志
tail -f user/logs/system_info.txt
```

---

## 故障排除

### 常见问题

1. **Docker权限错误**
```bash
sudo usermod -aG docker $USER
newgrp docker
```

2. **端口被占用**
```bash
sudo lsof -i :3000
sudo kill -9 <PID>
./restart_rlswarm.sh
```

3. **容器启动失败**
```bash
docker-compose --profile swarm logs swarm-cpu
docker-compose build --no-cache swarm-cpu
```

4. **内存不足**
```bash
free -h
# 增加swap空间
sudo fallocate -l 2G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
```

---

## 安全检查清单

- [ ] 更改SSH默认端口
- [ ] 禁用root登录
- [ ] 设置防火墙
- [ ] 定期备份数据
- [ ] 监控系统资源

---

## 快速检查清单

- [ ] VPS连接成功
- [ ] Docker安装完成
- [ ] 项目文件上传完成
- [ ] 服务启动成功
- [ ] 端口3000可访问
- [ ] 日志正常生成

完成以上步骤，RL Swarm项目即可在VPS上正常运行！ 