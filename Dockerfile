# 使用Ubuntu作为基础镜像，它有预编译的shadowsocks-libev包
FROM ubuntu:22.04

# 设置维护者信息
LABEL maintainer="Docker Proxy Service <docker-proxy@example.com>"

# 安装shadowsocks-libev和其他必要工具
RUN apt-get update && \
    apt-get install -y --no-install-recommends shadowsocks-libev supervisor curl && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# 创建必要的目录
RUN mkdir -p /etc/shadowsocks /var/log/supervisor

# 复制配置文件模板
COPY config/shadowsocks.json.template /etc/shadowsocks/
COPY config/supervisord.conf /etc/supervisor/conf.d/

# 复制启动脚本
COPY scripts/start.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/start.sh

# 设置环境变量默认值
ENV SERVER_PORT=8388 \
    PASSWORD=your_password \
    METHOD=aes-256-gcm \
    TIMEOUT=300 \
    DNS_SERVER=8.8.8.8 \
    UDPSUPPORT=true \
    LOG_LEVEL=info

# 暴露端口
EXPOSE 8388/tcp 8388/udp

# 健康检查
HEALTHCHECK --interval=30s --timeout=5s --start-period=60s --retries=3 \
  CMD ss-tunnel -c /etc/shadowsocks/shadowsocks.json -L 8.8.8.8:53 -b 0.0.0.0 -l 5353 > /dev/null 2>&1 & sleep 5 && curl -s -m 5 https://www.google.com > /dev/null 2>&1 || exit 1

# 设置工作目录
WORKDIR /etc/shadowsocks

# 启动脚本
CMD ["/usr/local/bin/start.sh"]