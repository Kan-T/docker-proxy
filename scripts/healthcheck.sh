#!/bin/bash

# Shadowsocks代理服务健康检查脚本
# 用于Docker容器健康状态监控

set -e

# 设置默认值
SERVER_PORT=${SERVER_PORT:-8388}
INSTANCE_ID=${INSTANCE_ID:-1}

# 日志函数
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [Health Check] $1"
}

# 检查ss-server进程是否运行
check_ss_process() {
    if pgrep -x "ss-server" > /dev/null; then
        log "Shadowsocks服务进程运行正常"
        return 0
    else
        log "错误: Shadowsocks服务进程未运行"
        return 1
    fi
}

# 检查端口是否在监听
check_port() {
    if nc -z 0.0.0.0 $SERVER_PORT; then
        log "Shadowsocks端口 $SERVER_PORT 监听正常"
        return 0
    else
        log "错误: 无法连接到Shadowsocks端口 $SERVER_PORT"
        # 尝试使用netstat检查
        if netstat -tuln | grep -q ":$SERVER_PORT "; then
            log "警告: 端口 $SERVER_PORT 已监听但无法通过nc连接"
            return 0
        fi
        return 1
    fi
}

# 检查监控服务是否运行
check_monitor() {
    if pgrep -f "monitor.sh" > /dev/null; then
        log "监控服务运行正常"
        return 0
    else
        log "警告: 监控服务未运行"
        return 1
    fi
}

# 检查日志是否在更新（过去5分钟内）
check_logs() {
    LOG_FILE="/var/log/shadowsocks/ss-server.log"
    if [ -f "$LOG_FILE" ]; then
        LOG_MODIFIED=$(stat -c %Y "$LOG_FILE")
        CURRENT_TIME=$(date +%s)
        TIME_DIFF=$((CURRENT_TIME - LOG_MODIFIED))
        
        if [ $TIME_DIFF -lt 300 ]; then # 5分钟内
            log "日志文件正常更新"
            return 0
        else
            log "警告: 日志文件超过5分钟未更新"
            # 非致命错误，继续检查
            return 0
        fi
    else
        log "警告: 日志文件不存在"
        # 非致命错误，继续检查
        return 0
    fi
}

# 执行配置文件验证
check_config() {
    CONFIG_FILE="/etc/shadowsocks/shadowsocks.json"
    if [ -f "$CONFIG_FILE" ]; then
        if command -v jq &> /dev/null; then
            if jq empty "$CONFIG_FILE" 2>/dev/null; then
                log "配置文件格式正确"
                return 0
            else
                log "错误: 配置文件格式错误"
                return 1
            fi
        else
            log "跳过配置验证: jq工具不可用"
            return 0
        fi
    else
        log "错误: 配置文件不存在"
        return 1
    fi
}

# 主健康检查函数
main() {
    log "开始健康检查 [实例ID: $INSTANCE_ID]"
    
    # 致命检查项（必须全部通过）
    CHECKS=(
        "check_ss_process"
        "check_port"
        "check_config"
    )
    
    # 警告检查项（可能不通过但不致命）
    WARNING_CHECKS=(
        "check_monitor"
        "check_logs"
    )
    
    # 执行致命检查
    for check in "${CHECKS[@]}"; do
        if ! $check; then
            log "健康检查失败: $check"
            exit 1
        fi
    done
    
    # 执行警告检查
    WARNING_COUNT=0
    for check in "${WARNING_CHECKS[@]}"; do
        if ! $check; then
            WARNING_COUNT=$((WARNING_COUNT + 1))
        fi
    done
    
    if [ $WARNING_COUNT -gt 0 ]; then
        log "健康检查通过，但有 $WARNING_COUNT 个警告"
    else
        log "健康检查全部通过"
    fi
    
    exit 0
}

# 执行健康检查
main