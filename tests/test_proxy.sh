#!/bin/bash

# Shadowsocks代理服务测试脚本
echo "开始测试Shadowsocks代理服务..."

# 设置测试环境
PROXY_HOST="localhost"
PROXY_PORT=8388
PROXY_PASSWORD="SecurePassword2024"
PROXY_METHOD="aes-256-gcm"
TEST_URL="https://www.google.com"

# 检查ss-local是否安装
echo -e "\n=== 测试1: 检查ss-local是否安装 ==="
if ! command -v ss-local &> /dev/null; then
    echo "✗ ss-local未安装，请先安装shadowsocks-libev客户端"
    echo "  在macOS上: brew install shadowsocks-libev"
    echo "  在Ubuntu上: apt install shadowsocks-libev"
    echo "  继续测试基本端口连通性..."
else
    echo "✓ ss-local已安装，可以进行完整功能测试"
fi

# 测试2: 检查代理服务端口是否监听
echo -e "\n=== 测试2: 检查代理服务端口监听 ==="
if nc -z $PROXY_HOST $PROXY_PORT; then
    echo "✓ 代理服务端口$PROXY_PORT正常监听"
else
    echo "✗ 代理服务端口$PROXY_PORT未监听，请检查服务是否启动"
    exit 1
fi

# 测试3: 使用ss-local进行连接测试（如果已安装）
if command -v ss-local &> /dev/null; then
    echo -e "\n=== 测试3: 使用ss-local进行连接测试 ==="
    
    # 启动本地代理客户端
    ss-local -s $PROXY_HOST -p $PROXY_PORT -l 1080 -k "$PROXY_PASSWORD" -m $PROXY_METHOD -v &
    SS_PID=$!
    
    # 等待ss-local启动
    sleep 3
    
    # 测试连接
    echo "正在测试通过Shadowsocks代理访问Google..."
    HTTP_STATUS=$(curl -x socks5://127.0.0.1:1080 -s -o /dev/null -w "%{http_code}" $TEST_URL)
    
    # 停止ss-local
    kill $SS_PID 2>/dev/null
    wait $SS_PID 2>/dev/null
    
    if [[ $HTTP_STATUS -eq 200 ]]; then
        echo "✓ Shadowsocks代理连接成功，返回状态码: $HTTP_STATUS"
    else
        echo "✗ Shadowsocks代理连接失败，返回状态码: $HTTP_STATUS"
        exit 1
    fi
fi

# 测试4: 检查Docker容器状态
echo -e "\n=== 测试4: 检查Docker容器状态 ==="
CONTAINER_NAME="shadowsocks-proxy"
if docker ps | grep -q $CONTAINER_NAME; then
    CONTAINER_STATUS=$(docker inspect --format='{{.State.Status}}' $CONTAINER_NAME)
    echo "✓ Docker容器'$CONTAINER_NAME'状态: $CONTAINER_STATUS"
    
    # 获取容器日志
    echo -e "\n最近的容器日志:"
    docker logs --tail=10 $CONTAINER_NAME
else
    echo "✗ Docker容器'$CONTAINER_NAME'未运行"
    exit 1
fi

echo -e "\n🎉 测试完成！基本功能验证通过。"
echo -e "\n使用说明:"
echo "  1. 安装Shadowsocks客户端（支持多平台）"
echo "  2. 配置服务器信息:"
echo "     - 服务器地址: [您的服务器IP]"
echo "     - 端口: $PROXY_PORT"
echo "     - 密码: $PROXY_PASSWORD"
echo "     - 加密方式: $PROXY_METHOD"
echo "  3. 启动客户端并开始使用"

exit 0