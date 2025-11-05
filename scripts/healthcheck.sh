#!/bin/bash

# 简化版健康检查脚本 - 用于容器健康状态监控
# 注意：此脚本已被Dockerfile中的HEALTHCHECK指令替代

set -e

# 设置默认值
SERVER_PORT=${SERVER_PORT:-8388}

# 日志函数 - 仅输出关键信息，避免过多日志
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [Health Check] $1"
}

# 简化的端口检查 - 只检查端口连接性
check_port() {
    if nc -z 127.0.0.1 $SERVER_PORT; then
        return 0
    else
        return 1
    fi
}

# 简化的配置文件检查
check_config() {
    CONFIG_FILE="/etc/shadowsocks/config.json"
    if [ -f "$CONFIG_FILE" ]; then
        # 只检查文件权限，不检查内容（避免暴露密码）
        if [ $(stat -c %a "$CONFIG_FILE") = "600" ]; then
            return 0
        fi
    fi
    return 1
}

# 主健康检查函数
main() {
    # 简化为只检查必要项
    check_port && check_config
    
    # 只返回退出码，不输出详细日志（避免在容器健康检查中产生过多日志）
    return $?
}

# 执行健康检查
main