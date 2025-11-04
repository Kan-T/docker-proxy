# 使用Alpine作为基础镜像，显著减小镜像大小并加速构建
FROM alpine:3.18

# 添加构建参数支持版本管理
ARG IMAGE_VERSION=latest
LABEL maintainer="Docker Proxy Service <docker-proxy@example.com>"
LABEL version="${IMAGE_VERSION}"
LABEL build-date="$(date -u +'%Y-%m-%dT%H:%M:%SZ')"

# 使用国内Alpine软件源加速构建
RUN echo "http://mirrors.aliyun.com/alpine/v3.18/main/" > /etc/apk/repositories && \
    echo "http://mirrors.aliyun.com/alpine/v3.18/community/" >> /etc/apk/repositories

# 安装shadowsocks-libev和其他必要工具 - 精简安装包
RUN apk update && \
    apk add --no-cache \
        shadowsocks-libev \
        supervisor \
        curl \
        netcat-openbsd \
        jq \
        procps

# 创建必要的目录 - Alpine中的目录结构略有不同
RUN mkdir -p \
    /etc/shadowsocks \
    /var/log/supervisor \
    /var/log/shadowsocks \
    /var/run/supervisor && \
    # 设置权限以防止未授权访问
    chmod 750 /etc/shadowsocks /var/log/shadowsocks

# 创建非root用户运行服务
RUN addgroup -S shadowsocks && \
    adduser -S -G shadowsocks -h /etc/shadowsocks -s /sbin/nologin shadowsocks && \
    chown -R shadowsocks:shadowsocks /etc/shadowsocks /var/log/shadowsocks

# 复制配置文件模板
COPY config/shadowsocks.json.template /etc/shadowsocks/

# 为Alpine修改supervisord配置路径
COPY config/supervisord.conf /etc/supervisord.conf

# 复制启动脚本
COPY scripts/start.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/start.sh && \
    # 安全最佳实践：确保配置文件模板不包含敏感信息
    sed -i 's/"password": "[^"]*"/"password": "{{PASSWORD}}"/' /etc/shadowsocks/shadowsocks.json.template

# 添加监控脚本
COPY scripts/monitor.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/monitor.sh

# 设置环境变量默认值
ENV SERVER_PORT=8388 \
    PASSWORD= \
    METHOD=aes-256-gcm \
    TIMEOUT=300 \
    DNS_SERVER=8.8.8.8 \
    UDPSUPPORT=true \
    LOG_LEVEL=warn \
    INSTANCE_ID=1 \
    METRICS_PORT=9090

# 暴露端口
EXPOSE 8388/tcp 8388/udp ${METRICS_PORT}/tcp

# 优化健康检查，使用Alpine兼容的命令
HEALTHCHECK --interval=30s --timeout=5s --start-period=60s --retries=3 \
  CMD nc -z 0.0.0.0 8388

# 设置工作目录
WORKDIR /etc/shadowsocks

# 添加卷定义
VOLUME ["/var/log/shadowsocks", "/etc/shadowsocks"]

# 切换到非root用户
USER shadowsocks

# 启动脚本 - 使用supervisor管理多个进程
CMD ["/usr/local/bin/start.sh"]