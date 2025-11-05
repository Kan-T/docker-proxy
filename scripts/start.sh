#!/bin/sh

# 简化版启动脚本 - 仅用于参考，实际使用Dockerfile中的启动脚本
# 注意：此脚本已被Dockerfile中的内置启动脚本替代

echo "此为参考启动脚本，容器实际使用Dockerfile中定义的启动逻辑。"
echo "使用方法: 请确保设置了PASSWORD环境变量后通过docker-compose启动服务。"

# 安全提示
echo "安全提示: 密码不会在日志中显示，配置文件权限已设置为600。"

# 显示基本配置要求
echo "必需环境变量: PASSWORD"
echo "可选环境变量: SERVER_PORT (默认: 8388), METHOD (默认: aes-256-gcm), TIMEOUT (默认: 300)"