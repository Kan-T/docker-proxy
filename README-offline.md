# Docker Proxy 离线部署指南

## 简介

本指南提供了在没有互联网连接或网络环境极其受限的情况下部署Docker代理服务的完整解决方案。

## 准备工作

### 所需文件

- `docker-compose-offline.yml` - 简化的离线部署配置
- Docker环境 - 已安装Docker和Docker Compose

## 方法一：从可访问互联网的机器获取镜像

### 1. 在有网络的机器上下载镜像

```bash
# 拉取所需镜像
docker pull teddysun/shadowsocks-libev:latest
docker pull nginx:1.25-alpine  # 如果需要使用轻量级配置

# 保存镜像为tar文件
docker save -o shadowsocks-libev.tar teddysun/shadowsocks-libev:latest
docker save -o nginx-alpine.tar nginx:1.25-alpine  # 如果需要
```

### 2. 传输镜像到目标机器

使用U盘、移动硬盘等物理介质将tar文件传输到目标机器。

### 3. 在目标机器上加载镜像

```bash
# 加载镜像
docker load -i shadowsocks-libev.tar
docker load -i nginx-alpine.tar  # 如果需要
```

## 方法二：使用国内镜像加速站点

如果可以短暂连接特定的国内镜像站点：

```bash
# 临时配置Docker使用国内镜像
export DOCKER_BUILDKIT=0
export COMPOSE_DOCKER_CLI_BUILD=0

# 使用Docker Hub国内加速
docker pull registry.docker-cn.com/teddysun/shadowsocks-libev:latest

# 重命名镜像以匹配配置文件
docker tag registry.docker-cn.com/teddysun/shadowsocks-libev:latest teddysun/shadowsocks-libev:latest
```

## 方法三：手动构建最小化镜像

在有网络的环境中，创建一个简单的Dockerfile并构建：

```dockerfile
# 极简Shadowsocks Dockerfile
FROM alpine:3.17

RUN apk add --no-cache shadowsocks-libev

EXPOSE 8388/tcp 8388/udp

ENV PASSWORD=your_secure_password METHOD=aes-256-gcm TIMEOUT=300

CMD ss-server -s 0.0.0.0 -p 8388 -k $PASSWORD -m $METHOD -t $TIMEOUT -u
```

构建并保存：

```bash
docker build -t shadowsocks:minimal .
docker save -o shadowsocks-minimal.tar shadowsocks:minimal
```

然后在目标机器上加载并修改`docker-compose-offline.yml`中的镜像名称。

## 离线部署步骤

### 1. 确保已加载所需镜像

```bash
docker images
```

确认`teddysun/shadowsocks-libev:latest`镜像已存在。

### 2. 创建必要目录

```bash
mkdir -p logs
```

### 3. 设置环境变量（重要）

创建`.env`文件或在启动命令中设置密码环境变量：

```bash
# 创建.env文件
cat > .env << EOF
PASSWORD=your_secure_password  # 使用强密码
EOF

# 或直接在命令中设置
PASSWORD=your_secure_password docker compose -f docker-compose-offline.yml up -d
```

**注意：** 生产环境中必须设置强密码，配置文件已移除默认密码以提高安全性。

### 4. 启动服务

```bash
docker compose -f docker-compose-offline.yml up -d
```

### 5. 验证服务

```bash
# 检查服务状态
docker compose -f docker-compose-offline.yml ps

# 查看日志
docker compose -f docker-compose-offline.yml logs
```

## 故障排查

### 镜像加载失败

- 确保tar文件没有损坏
- 确保Docker版本兼容性
- 尝试使用不同的压缩工具重新保存镜像

### 服务启动失败

- 检查端口是否被占用：`netstat -tulpn | grep 8388`
- 检查密码格式是否正确
- 查看详细日志：`docker logs shadowsocks`

## 安全注意事项

- **必须设置密码**：部署前必须设置强密码，不再提供默认密码
- **使用防火墙**：仅开放必要的端口，限制访问来源IP
- **定期更新**：当有条件连接网络时，及时更新镜像以修复安全漏洞
- **密码管理**：避免在命令历史中明文记录密码

## 扩展选项

### 添加基本的负载均衡

如果需要简单的负载均衡，可以使用已加载的nginx镜像：

1. 创建nginx配置文件 `nginx-offline.conf`：

```nginx
events {
    worker_connections  1024;
}

stream {
    upstream shadowsocks {
        server shadowsocks:8388;
    }

    server {
        listen 80;
        proxy_pass shadowsocks;
    }
}
```

2. 修改`docker-compose-offline.yml`添加nginx服务：

```yaml
  nginx:
    image: nginx:1.25-alpine
    container_name: nginx
    restart: unless-stopped
    ports:
      - "8080:80"
    volumes:
      - ./nginx-offline.conf:/etc/nginx/nginx.conf:ro
    depends_on:
      - shadowsocks
```

## 维护与更新

当网络条件改善时，可以：

1. 更新镜像：`docker pull teddysun/shadowsocks-libev:latest`
2. 备份配置和数据
3. 重启服务以应用更新

## 总结

本指南提供了三种在离线环境中部署Docker代理服务的方法：
1. 从有网络的机器预下载镜像
2. 使用国内镜像加速站点
3. 手动构建最小化镜像

请根据您的具体情况选择合适的方法。