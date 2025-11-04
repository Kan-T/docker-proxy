#!/bin/bash

# Shadowsocks代理服务启动脚本 - 支持容器管理
echo "正在启动Shadowsocks代理服务和监控系统..."

# 检查并设置环境变量
export SERVER_PORT=${SERVER_PORT:-8388}
# 不设置默认密码，强制要求通过环境变量提供
if [ -z "$PASSWORD" ]; then
  echo "错误: 未设置PASSWORD环境变量，无法启动服务"
  exit 1
fi
# 生产环境安全检查
if [ "${ENVIRONMENT:-development}" == "production" ] && [ ${#PASSWORD} -lt 12 ]; then
  echo "警告: 生产环境密码长度应不少于12位"
fi
export PASSWORD
export METHOD=${METHOD:-aes-256-gcm}
export TIMEOUT=${TIMEOUT:-300}
export DNS_SERVER=${DNS_SERVER:-8.8.8.8}
export UDPSUPPORT=${UDPSUPPORT:-true}
export LOG_LEVEL=${LOG_LEVEL:-warn}
export INSTANCE_ID=${INSTANCE_ID:-1}
export METRICS_PORT=${METRICS_PORT:-9090}

# 创建必要的日志目录
mkdir -p /var/log/shadowsocks /var/run/shadowsocks
chmod 755 /var/log/shadowsocks /var/run/shadowsocks

# 生成Shadowsocks配置文件
echo "生成Shadowsocks配置文件..."
# 使用here-document但避免将内容打印到日志
cat > /etc/shadowsocks/shadowsocks.json << 'EOF'
{
  "server": "0.0.0.0",
  "server_port": ${SERVER_PORT},
  "password": "${PASSWORD}",
  "method": "${METHOD}",
  "timeout": ${TIMEOUT},
  "dns": "${DNS_SERVER}",
  "mode": "tcp_and_udp",
  "fast_open": false,
  "reuse_port": true,
  "no_delay": true,
  "nameserver": "${DNS_SERVER}",
  "instance_id": "${INSTANCE_ID}"
}
EOF
# 替换变量值但不显示在日志中
# 使用sed替换而不是直接在echo中显示
cat /etc/shadowsocks/shadowsocks.json | \
  sed "s/\${SERVER_PORT}/$SERVER_PORT/g" | \
  sed "s/\${PASSWORD}/$PASSWORD/g" | \
  sed "s/\${METHOD}/$METHOD/g" | \
  sed "s/\${TIMEOUT}/$TIMEOUT/g" | \
  sed "s/\${DNS_SERVER}/$DNS_SERVER/g" | \
  sed "s/\${INSTANCE_ID}/$INSTANCE_ID/g" > \
  /etc/shadowsocks/shadowsocks.json.tmp && \
  mv /etc/shadowsocks/shadowsocks.json.tmp /etc/shadowsocks/shadowsocks.json && \
  chmod 600 /etc/shadowsocks/shadowsocks.json  # 限制配置文件权限

# 生成Supervisor配置文件
echo "生成Supervisor配置文件..."
cat > /etc/supervisor/conf.d/shadowsocks.conf << EOF
[supervisord]
nodaemon=true
logfile=/var/log/supervisor/supervisord.log
pidfile=/var/run/supervisord.pid

[program:shadowsocks]
command=ss-server -c /etc/shadowsocks/shadowsocks.json -v
user=root
autostart=true
autorestart=true
startsecs=10
startretries=3
stopasgroup=true
killasgroup=true
stdout_logfile=/var/log/shadowsocks/ss-server.log
stdout_logfile_maxbytes=50MB
stdout_logfile_backups=5
stderr_logfile=/var/log/shadowsocks/ss-server-error.log
stderr_logfile_maxbytes=50MB
stderr_logfile_backups=5
environment=
    SERVER_PORT=%(ENV_SERVER_PORT)s,
    PASSWORD=%(ENV_PASSWORD)s,
    METHOD=%(ENV_METHOD)s,
    TIMEOUT=%(ENV_TIMEOUT)s,
    LOG_LEVEL=%(ENV_LOG_LEVEL)s

[program:monitor]
command=/usr/local/bin/monitor.sh
user=root
autostart=true
autorestart=true
startsecs=5
startretries=3
stopasgroup=true
killasgroup=true
stdout_logfile=/var/log/shadowsocks/monitor.log
stdout_logfile_maxbytes=50MB
stdout_logfile_backups=5
stderr_logfile=/var/log/shadowsocks/monitor-error.log
stderr_logfile_maxbytes=50MB
stderr_logfile_backups=5
environment=
    METRICS_PORT=%(ENV_METRICS_PORT)s,
    INSTANCE_ID=%(ENV_INSTANCE_ID)s,
    LOG_LEVEL=%(ENV_LOG_LEVEL)s
EOF

# 显示配置信息（不显示密码）
echo "代理服务配置信息:"
echo "- 实例ID: $INSTANCE_ID"
echo "- 服务器端口: $SERVER_PORT"
echo "- 加密方式: $METHOD"
echo "- 超时时间: $TIMEOUT秒"
echo "- DNS服务器: $DNS_SERVER"
echo "- UDP支持: $UDPSUPPORT"
echo "- 日志级别: $LOG_LEVEL"
echo "- 监控端口: $METRICS_PORT"
echo "- 密码: [已隐藏]"

# 验证配置文件格式
if command -v jq &> /dev/null; then
    echo "验证配置文件格式..."
    if jq empty /etc/shadowsocks/shadowsocks.json 2>/dev/null; then
        echo "配置文件格式正确"
    else
        echo "配置文件格式验证失败，但继续启动服务"
    fi
fi

# 启动Supervisor，管理所有进程
echo "启动Supervisor进程管理器..."
echo "服务将通过Supervisor管理，支持自动重启和日志轮转"
supervisord -c /etc/supervisor/conf.d/shadowsocks.conf