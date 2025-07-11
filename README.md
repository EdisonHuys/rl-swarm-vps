# RL Swarm VPS

基于强化学习的分布式训练系统，支持跳过登录和自动化运行。

## ✨ 主要特性

- 🚀 **跳过登录**: 预配置用户数据，无需手动登录
- 🤖 **自动监控**: 进程异常时自动重启
- 📊 **性能优化**: 从0.5版本移植的性能优化
- 🐳 **Docker支持**: 一键部署到VPS
- 📝 **完整日志**: 详细的运行日志和监控

## 🚀 快速开始

### 本地运行
```bash
# 克隆项目
git clone <your-repo-url>
cd rl-swarm-vps

# 运行（自动跳过登录）
./run_rl_swarm.sh

# 自动监控
./auto_run.sh
```

### VPS部署
```bash
# 一键部署到VPS
./deploy_to_vps.sh your_vps_ip username [ssh_key_path]

# 示例
./deploy_to_vps.sh 192.168.1.100 ubuntu ~/.ssh/id_rsa
```

## 📁 项目结构

```
rl-swarm-vps/
├── user/                    # 用户数据目录
│   ├── modal-login/        # 预配置登录数据
│   ├── configs/            # 配置文件
│   ├── logs/               # 日志文件
│   └── keys/               # 密钥文件
├── auto_run.sh             # 自动监控脚本
├── restart_rlswarm.sh      # 快速重启脚本
├── run_rl_swarm.sh         # 主运行脚本
├── deploy_to_vps.sh        # VPS部署脚本
└── docker-compose.yaml     # Docker配置
```

## 🛠️ 常用命令

### 查看状态
```bash
# 查看容器状态
docker ps

# 查看日志
docker logs -f rl-swarm-vps-swarm-cpu-1

# 系统状态
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

# 系统信息
cat user/logs/system_info.txt
```

## 🔧 故障排除

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

## 📚 文档

- [VPS部署指南](VPS_DEPLOYMENT_GUIDE.md) - 详细的VPS部署说明
- [升级说明](README_UPGRADES.md) - 功能升级和优化说明
- [性能优化](PERFORMANCE_OPTIMIZATIONS.md) - 性能优化详细说明

## 🎯 性能优化

从0.5版本移植的性能优化包括：

- ✅ 架构升级：从 `rgym_exp` 到 `genrl-swarm`
- ✅ 线程管理优化：动态配置支持
- ✅ 模型池优化：更新的模型选择
- ✅ 通信优化：简化的配置参数
- ✅ 依赖管理优化：官方维护的包

## 🔒 安全检查清单

- [ ] 更改SSH默认端口
- [ ] 禁用root登录
- [ ] 设置防火墙
- [ ] 定期备份数据
- [ ] 监控系统资源

## 📋 快速检查清单

- [ ] VPS连接成功
- [ ] Docker安装完成
- [ ] 项目文件上传完成
- [ ] 服务启动成功
- [ ] 端口3000可访问
- [ ] 日志正常生成

## 🤝 贡献

欢迎提交Issue和Pull Request！

## 📄 许可证

本项目采用MIT许可证。

