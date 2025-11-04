# 使用Ubuntu作为基础镜像，它有预编译的shadowsocks-libev包
FROM ubuntu:22.04

# 添加构建参数支持版本管理
ARG IMAGE_VERSION=latest
LABEL maintainer="Docker Proxy Service <docker-proxy@example.com>"
LABEL version="${IMAGE_VERSION}"
LABEL build-date="$(date -u +'%Y-%m-%dT%H:%M:%SZ')"

# 使用国内Ubuntu软件源加速构建
RUN sed -i 's/archive.ubuntu.com/mirrors.aliyun.com/g' /etc/apt/sources.list && \
    sed -i 's/security.ubuntu.com/mirrors.aliyun.com/g' /etc/apt/sources.list

# 安装shadowsocks-libev和其他必要工具
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        shadowsocks-libev \
        supervisor \
        curl \
        netcat-openbsd \
        jq \
        procps \
        && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# 创建必要的目录
RUN mkdir -p \
    /etc/shadowsocks \
    /var/log/supervisor \
    /var/log/shadowsocks \
    /var/run/shadowsocks && \
    # 设置权限以防止未授权访问
    chmod 750 /etc/shadowsocks /var/log/shadowsocks

# 复制配置文件模板 - 使用非root用户运行会更安全
COPY config/shadowsocks.json.template /etc/shadowsocks/
COPY config/supervisord.conf /etc/supervisor/conf.d/

# 复制启动脚本
COPY scripts/start.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/start.sh && \
    # 安全最佳实践：确保配置文件模板不包含敏感信息
    sed -i 's/"password": "[^"]*"/"password": "{{PASSWORD}}"/' /etc/shadowsocks/shadowsocks.json.template

# 添加监控脚本
COPY scripts/monitor.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/monitor.sh

# 设置环境变量默认值 - 注意：敏感信息如密码不应在Dockerfile中硬编码
# 生产环境必须通过环境变量或secrets提供PASSWORD等敏感信息
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

# 优化健康检查，减少外部依赖
HEALTHCHECK --interval=30s --timeout=5s --start-period=60s --retries=3 \
  CMD sh -c "nc -z 0.0.0.0 8388 && ss-server -c /etc/shadowsocks/shadowsocks.json -t 1 > /dev/null 2>&1"

# 设置工作目录
WORKDIR /etc/shadowsocks

# 添加卷定义
VOLUME ["/var/log/shadowsocks", "/etc/shadowsocks"]

# 启动脚本 - 使用supervisor管理多个进程
CMD ["/usr/local/bin/start.sh"]