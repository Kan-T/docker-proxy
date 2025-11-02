#!/bin/bash

# Shadowsocks代理服务启动脚本
echo "正在启动Shadowsocks代理服务..."

# 检查并设置环境变量
export SERVER_PORT=${SERVER_PORT:-8388}
export PASSWORD=${PASSWORD:-your_password}
export METHOD=${METHOD:-aes-256-gcm}
export TIMEOUT=${TIMEOUT:-300}
export DNS_SERVER=${DNS_SERVER:-8.8.8.8}
export UDPSUPPORT=${UDPSUPPORT:-true}
export LOG_LEVEL=${LOG_LEVEL:-info}

# 生成Shadowsocks配置文件
echo "生成Shadowsocks配置文件..."
cat > /etc/shadowsocks/shadowsocks.json << EOF
{
  "server": "0.0.0.0",
  "server_port": $SERVER_PORT,
  "password": "$PASSWORD",
  "method": "$METHOD",
  "timeout": $TIMEOUT,
  "dns": "$DNS_SERVER",
  "mode": "tcp_and_udp",
  "fast_open": false,
  "reuse_port": true,
  "no_delay": true
}
EOF

# 显示配置信息
echo "代理服务配置信息:"
echo "- 服务器端口: $SERVER_PORT"
echo "- 加密方式: $METHOD"
echo "- 超时时间: $TIMEOUT秒"
echo "- DNS服务器: $DNS_SERVER"
echo "- UDP支持: $UDPSUPPORT"
echo "- 日志级别: $LOG_LEVEL"

# 检查是否安装了jsonlint-php，如果没有则跳过验证
if command -v jsonlint-php &> /dev/null; then
    echo "验证配置文件格式..."
    if jsonlint-php /etc/shadowsocks/shadowsocks.json 2>/dev/null; then
        echo "配置文件格式正确"
    else
        echo "配置文件格式验证失败，但继续启动服务"
    fi
fi

# 启动Shadowsocks服务
echo "启动Shadowsocks服务..."
ss-server -c /etc/shadowsocks/shadowsocks.json -v