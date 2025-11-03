# Docker容器管理指南

本文档提供了Docker代理服务的容器管理指南，包括部署、扩展、监控和日志管理等功能。

## 功能概述

- **负载均衡**: 使用Nginx实现TCP/UDP流量负载均衡
- **多实例扩展**: 支持启动多个Shadowsocks实例以提高吞吐量
- **健康检查**: 内置容器健康检查机制，确保服务可靠性
- **监控系统**: 提供性能指标收集和暴露功能
- **日志管理**: 集中管理和轮转日志文件
- **资源限制**: 可配置CPU和内存限制，防止资源滥用

## 快速开始

### 1. 环境准备

确保已安装以下软件：
- Docker 20.10+ 
- Docker Compose 2.0+

### 2. 基本部署

使用Docker Compose启动服务：

```bash
# 基本启动（单实例）
docker-compose up -d

# 启动指定数量的Shadowsocks实例
docker-compose up -d --scale shadowsocks-proxy=3
```

### 3. 配置说明

主要配置文件：
- `docker-compose.yml`: 定义服务、网络、卷和资源限制
- `nginx/nginx.conf`: Nginx负载均衡配置
- `nginx/conf.d/default.conf`: Nginx默认HTTP配置

### 4. 环境变量

Shadowsocks服务支持以下环境变量：

| 环境变量 | 说明 | 默认值 |
|---------|------|--------|
| `SERVER_PORT` | 代理服务端口 | 8388 |
| `PASSWORD` | 连接密码 | your_password |
| `METHOD` | 加密方式 | aes-256-gcm |
| `TIMEOUT` | 连接超时时间(秒) | 300 |
| `DNS_SERVER` | DNS服务器地址 | 8.8.8.8 |
| `LOG_LEVEL` | 日志级别 | info |
| `INSTANCE_ID` | 实例ID | 1 |
| `METRICS_PORT` | 指标服务端口 | 9090 |

## 高级功能

### 扩展服务

可以通过Docker Compose的scale命令轻松扩展Shadowsocks实例数量：

```bash
# 扩展到3个实例
docker-compose up -d --scale shadowsocks-proxy=3

# 减少到2个实例
docker-compose up -d --scale shadowsocks-proxy=2
```

### 监控服务

每个Shadowsocks实例都提供了监控指标，可以通过以下方式访问：

```bash
# 访问特定实例的监控指标
curl http://<容器IP>:9090/

# 通过Docker Compose访问
docker exec -it <容器ID> curl localhost:9090/
```

监控指标包括：
- CPU使用率
- 内存使用率
- TCP/UDP连接数
- 服务状态

### 查看日志

集中管理的日志位于`./logs`目录，也可以通过Docker命令查看：

```bash
# 查看容器日志
docker-compose logs -f shadowsocks-proxy

# 查看特定实例日志
docker-compose logs -f shadowsocks-proxy-1

# 查看监控服务日志
docker-compose logs -f monitor
```

### 健康检查

可以手动执行健康检查或查看Docker的健康状态：

```bash
# 查看服务健康状态
docker-compose ps

# 手动执行健康检查
docker exec <容器ID> /scripts/healthcheck.sh
```

## 维护操作

### 升级服务

```bash
# 停止服务
docker-compose down

# 更新配置（可选）
# ...

# 重新构建镜像（如需要）
docker-compose build

# 启动服务
docker-compose up -d
```

### 数据清理

```bash
# 清理未使用的镜像
docker image prune -a

# 清理日志文件
rm -rf ./logs/*
```

## 最佳实践

1. **生产环境建议**：
   - 设置强密码
   - 配置适当的资源限制
   - 启用日志轮转
   - 定期备份配置

2. **性能优化**：
   - 根据用户数量调整实例数量
   - 监控资源使用情况
   - 优化Nginx负载均衡配置

3. **安全建议**：
   - 定期更新镜像
   - 限制容器网络访问
   - 考虑使用TLS加密流量

## 故障排查

常见问题及解决方案：

1. **服务无法启动**
   - 检查配置文件格式
   - 查看日志文件中的错误信息
   - 确认端口未被占用

2. **连接不稳定**
   - 增加超时时间
   - 检查网络连接质量
   - 考虑扩展实例数量

3. **监控不可用**
   - 确认监控脚本权限正确
   - 检查指标服务端口
   - 查看监控日志文件

