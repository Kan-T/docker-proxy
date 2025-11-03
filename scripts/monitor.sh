#!/bin/bash

# Shadowsocks代理服务监控脚本
# 提供性能指标收集和监控功能

echo "启动监控服务..."

# 设置默认环境变量
METRICS_PORT=${METRICS_PORT:-9090}
INSTANCE_ID=${INSTANCE_ID:-1}
LOG_LEVEL=${LOG_LEVEL:-info}

# 创建指标目录
mkdir -p /var/run/shadowsocks/metrics

# 收集系统资源使用情况
collect_system_metrics() {
    local timestamp=$(date +%s)
    
    # CPU和内存使用情况
    local cpu_usage=$(top -bn1 | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk '{print 100 - $1}')
    local mem_total=$(free -m | awk '/Mem:/ {print $2}')
    local mem_used=$(free -m | awk '/Mem:/ {print $3}')
    local mem_usage=$(awk "BEGIN {printf \"%.2f\", $mem_used/$mem_total*100}")
    
    # 连接数统计
    local tcp_connections=$(netstat -ant | grep ESTABLISHED | wc -l)
    local udp_connections=$(netstat -anu | grep ESTABLISHED | wc -l)
    
    # 写入指标文件
    cat > /var/run/shadowsocks/metrics/system.json << EOF
{
  "timestamp": $timestamp,
  "instance_id": "$INSTANCE_ID",
  "cpu_usage_percent": $cpu_usage,
  "memory_usage_percent": $mem_usage,
  "memory_used_mb": $mem_used,
  "memory_total_mb": $mem_total,
  "tcp_connections": $tcp_connections,
  "udp_connections": $udp_connections
}
EOF
    
    if [ "$LOG_LEVEL" = "debug" ]; then
        echo "[$(date)] 系统指标: CPU ${cpu_usage}%, 内存 ${mem_usage}%, TCP连接 $tcp_connections, UDP连接 $udp_connections"
    fi
}

# 收集Shadowsocks服务指标
collect_ss_metrics() {
    local timestamp=$(date +%s)
    
    # 获取ss-server进程ID
    local ss_pid=$(pgrep ss-server)
    
    if [ -n "$ss_pid" ]; then
        # 获取进程资源使用情况
        local ss_cpu=$(ps -p $ss_pid -o %cpu | tail -1 | tr -d ' ')
        local ss_mem=$(ps -p $ss_pid -o %mem | tail -1 | tr -d ' ')
        
        # 写入指标文件
        cat > /var/run/shadowsocks/metrics/ss.json << EOF
{
  "timestamp": $timestamp,
  "instance_id": "$INSTANCE_ID",
  "process_id": $ss_pid,
  "cpu_usage_percent": $ss_cpu,
  "memory_usage_percent": $ss_mem,
  "status": "running"
}
EOF
    else
        cat > /var/run/shadowsocks/metrics/ss.json << EOF
{
  "timestamp": $timestamp,
  "instance_id": "$INSTANCE_ID",
  "status": "stopped"
}
EOF
    fi
    
    if [ "$LOG_LEVEL" = "debug" ]; then
        echo "[$(date)] Shadowsocks指标: 进程ID $ss_pid, 状态 ${ss_status:-unknown}"
    fi
}

# 启动简单的HTTP服务器提供指标
start_metrics_server() {
    (while true; do
        local metrics=$(cat /var/run/shadowsocks/metrics/system.json /var/run/shadowsocks/metrics/ss.json | jq -s '{system: .[0], ss: .[1]}')
        nc -l -p $METRICS_PORT -c "echo -e 'HTTP/1.1 200 OK\r\nContent-Type: application/json\r\n\r\n$metrics'"
    done) &
    
    METRICS_PID=$!
    echo "指标服务启动在端口 $METRICS_PORT，PID: $METRICS_PID"
}

# 主监控循环
main() {
    # 初始化指标文件
    collect_system_metrics
    collect_ss_metrics
    
    # 启动指标服务器
    start_metrics_server
    
    # 定期收集指标
    while true; do
        collect_system_metrics
        collect_ss_metrics
        sleep 60  # 每分钟收集一次
    done
}

# 清理函数
trap "echo '停止监控服务...'; kill $METRICS_PID 2>/dev/null; exit 0" SIGTERM SIGINT

# 启动监控
main