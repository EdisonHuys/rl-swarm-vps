# RL Swarm 原版升级说明

## 新增功能

### 1. 跳过登录功能
原版现在支持跳过 modal-login 登录流程，直接使用预配置的用户数据：

- **预配置文件位置**：
  - `user/modal-login/userData.json` - 用户数据
  - `user/modal-login/userApiKey.json` - API密钥数据

- **自动检测**：脚本会自动检测这些文件是否存在，如果存在则跳过登录流程
- **ORG_ID 自动读取**：从预配置文件中自动读取正确的 ORG_ID
- **API密钥状态检查**：自动检查API密钥是否已激活

### 2. 自动化脚本

#### `auto_run.sh` - 自动监控和重启
```bash
# 启动自动监控（每10秒检查一次，异常时30秒后重启）
./auto_run.sh
```

**功能**：
- 自动监控训练进程状态
- 检测到异常时自动重启
- 完整的日志记录
- 最多重试3次启动

#### `restart_rlswarm.sh` - 快速重启
```bash
# 快速重启整个系统
./restart_rlswarm.sh
```

**功能**：
- 自动释放3000端口
- 停止并重新启动Docker容器
- 一键重启整个系统

#### `swarm_entrypoint.sh` - 容器入口脚本
```bash
# 在容器中使用，提供自动重启功能
./swarm_entrypoint.sh
```

**功能**：
- 主脚本异常退出时自动重启
- 持续监控和重启机制

## 使用方法

### 1. 使用跳过登录功能
```bash
# 直接运行，会自动检测预配置文件
./run_rl_swarm.sh
```

### 2. 使用自动监控
```bash
# 启动自动监控
./auto_run.sh
```

### 3. 使用Docker
```bash
# 启动Docker容器
docker-compose --profile swarm up swarm-cpu

# 或者使用快速重启脚本
./restart_rlswarm.sh
```

## 文件结构

```
rl-swarm-vps/
├── user/
│   ├── modal-login/
│   │   ├── userData.json      # 预配置用户数据
│   │   └── userApiKey.json    # 预配置API密钥
│   ├── keys/                  # 密钥目录
│   ├── configs/
│   │   └── rg-swarm.yaml      # 配置文件
│   └── logs/                  # 日志目录
├── auto_run.sh               # 自动监控脚本
├── restart_rlswarm.sh        # 快速重启脚本
├── swarm_entrypoint.sh       # 容器入口脚本
└── run_rl_swarm.sh          # 主运行脚本（已升级）
```

## 注意事项

1. **预配置文件**：确保 `user/modal-login/` 目录下的文件存在且有效
2. **权限设置**：确保脚本有执行权限 `chmod +x *.sh`
3. **路径配置**：`restart_rlswarm.sh` 中的路径可能需要根据实际情况调整
4. **日志监控**：自动监控的日志保存在 `user/logs/auto_monitor.log`

## 升级说明

本次升级将原版从需要手动登录的版本升级为支持跳过登录的版本，同时添加了完整的自动化功能，使其具备与 0.5 版本相似的自动化能力。

### 性能优化

本次升级还包含了从 0.5 版本移植的性能优化：

1. **架构升级**: 从 `rgym_exp` 升级到 `genrl-swarm` 官方架构
2. **线程管理优化**: 移除硬编码线程限制，支持动态配置
3. **模型池优化**: 使用更新的模型选择策略
4. **通信优化**: 简化配置，使用优化的默认参数
5. **依赖管理优化**: 使用官方维护的依赖包

详细说明请参考 `PERFORMANCE_OPTIMIZATIONS.md` 文件。 