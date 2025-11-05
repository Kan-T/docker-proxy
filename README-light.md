# Docker Proxy 轻量级部署指南

## 简介

本指南提供了一个轻量级的Docker代理服务部署方案，适用于以下场景：
- 网络环境受限，难以从官方源下载和构建大型镜像
- 需要快速部署和启动代理服务
- 不需要复杂的监控和管理功能

## 核心优势

- **预构建镜像**：使用Docker Hub上维护的`teddysun/shadowsocks-libev`预构建镜像
- **简化构建**：避免耗时的`apt-get update`和依赖安装过程
- **体积更小**：使用Alpine基础的Nginx镜像，体积显著减小
- **快速启动**：镜像下载和启动速度更快

## 快速开始

### 1. 准备配置

确保以下目录结构存在：

```
./nginx/
  ├── nginx.conf
  └── conf.d/
      └── default.conf
./logs/
```

### 2. 设置环境变量

创建`.env`文件（必须）：

```env
# 代理服务配置（必须设置密码）
PASSWORD=your_secure_password
METHOD=aes-256-gcm

# 端口配置
PUBLIC_PORT=8388
```

### 3. 启动服务

使用轻量级配置启动服务：

```bash
docker compose -f docker-compose-light.yml up -d
```

### 4. 验证服务

检查服务状态：

```bash
docker compose -f docker-compose-light.yml ps
```

查看日志：

```bash
docker compose -f docker-compose-light.yml logs
```

## 配置说明

### 负载均衡器

- 使用Nginx 1.25 Alpine版本作为负载均衡器
- 默认监听8388端口（可通过PUBLIC_PORT环境变量修改）
- 自动连接到shadowsocks-proxy服务

### Shadowsocks服务

- 使用`teddysun/shadowsocks-libev`预构建镜像
- 支持TCP和UDP协议
- 可通过环境变量自定义配置

## 高级配置

### 调整资源限制

编辑`docker-compose-light.yml`中的`deploy.resources`部分，根据实际需求调整CPU和内存限制：

```yaml
deploy:
  resources:
    limits:
      cpus: '1'
      memory: 512M
```

### 安全加固

1. **必须设置密码**：生产环境中必须设置强密码，配置已不再提供默认密码
2. **限制访问**：在生产环境中使用防火墙限制访问来源IP
3. **密码管理**：避免在命令历史中明文记录密码

## 故障排查

### 常见问题

1. **服务无法启动**：检查端口是否被占用，尝试更换PUBLIC_PORT
2. **连接失败**：验证密码和加密方式是否正确
3. **性能问题**：调整资源限制，增加CPU和内存分配

### 日志查看

查看详细日志以诊断问题：

```bash
docker compose -f docker-compose-light.yml logs --tail=100
```

## 注意事项

- 本轻量级配置移除了监控服务和高级管理功能
- 适用于测试环境和网络受限环境
- 生产环境建议使用完整配置并确保适当的安全措施

## 从轻量级迁移到完整版

当网络环境改善后，可以通过以下命令切换到完整版：

```bash
# 停止轻量级服务
docker compose -f docker-compose-light.yml down

# 启动完整版服务
docker compose up -d
```