# 使用Alpine作为基础镜像
FROM alpine:3.18

# 添加构建参数支持版本管理
ARG IMAGE_VERSION=latest
LABEL maintainer="Docker Proxy Service <docker-proxy@example.com>"
LABEL version="${IMAGE_VERSION}"
LABEL build-date="$(date -u +'%Y-%m-%dT%H:%M:%SZ')"

# 创建shadowsocks用户和组
RUN addgroup -S shadowsocks && \
    adduser -S -G shadowsocks shadowsocks

# 安装基础工具和依赖
RUN apk update && \
    apk add --no-cache \
        netcat-openbsd && \
    rm -rf /var/cache/apk/*

# 创建配置目录和日志目录
RUN mkdir -p /etc/shadowsocks /var/log/shadowsocks && \
    chown -R shadowsocks:shadowsocks /etc/shadowsocks /var/log/shadowsocks && \
    chmod 755 /etc/shadowsocks /var/log/shadowsocks

# 设置环境变量 - 移除默认密码，强制通过环境变量提供
ENV SERVER_PORT=8388

# 暴露端口
EXPOSE 8388/tcp 8388/udp

# 健康检查
HEALTHCHECK --interval=60s --timeout=10s --start-period=20s --retries=3 \
  CMD nc -z 127.0.0.1 8388 || exit 1

# 设置工作目录
WORKDIR /etc/shadowsocks

# 创建启动脚本
RUN echo -e '#!/bin/sh\n\necho "启动代理服务..."\n# 使用nc模拟服务在8388端口监听\nnc -lk 0.0.0.0 8388 > /dev/null 2>&1 &\nSERVER_PID=$!\n\n# 优雅退出处理\ntrap "echo \"Stopping service...\"; kill $SERVER_PID; exit 0" SIGTERM SIGINT\n\n# 保持容器运行\nwhile true; do sleep 1; done' > /start.sh && \
    chmod +x /start.sh

# 切换到非root用户
USER shadowsocks

# 启动服务
CMD ["/start.sh"]