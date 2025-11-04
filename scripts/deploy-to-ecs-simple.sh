#!/bin/bash

# 简化版 ECS部署脚本 (仅支持生产环境)
set -e

echo "======================================="
echo "Docker Proxy 简化部署脚本 (生产环境)"
echo "======================================="

# 参数解析
while getopts "e:h:" opt; do
  case $opt in
    e) ENVIRONMENT=$OPTARG ;;
    h) echo "用法: $0 -e prod" && exit 0 ;;
    *) echo "未知选项" && exit 1 ;;
  esac
done

# 验证必要参数
if [ -z "$ENVIRONMENT" ]; then
  echo "错误: 缺少必要参数"
  echo "用法: $0 -e prod"
  exit 1
fi

# 设置配置
IMAGE_NAME="docker-proxy"
IMAGE_TAG=${IMAGE_TAG:-latest}  # 优先从环境变量获取，支持CI/CD中的自动标签
ECS_HOST=${ECS_HOST:-localhost}  # 将从环境变量获取ECS主机地址
ECS_USER=${ECS_USER:-deploy}  # 默认使用deploy用户
DEPLOY_PATH="/data/docker-proxy/prod"

# 获取GitHub仓库信息
GITHUB_REPO="${GITHUB_REPOSITORY:-docker-proxy}"
GITHUB_REPO="https://github.com/${GITHUB_REPO}.git"
GITHUB_SHA="${GITHUB_SHA:-main}"

echo "部署配置:"
echo "- 环境: $ENVIRONMENT"
echo "- ECS主机: ${ECS_HOST:0:8}************"  # 掩码处理
echo "- 部署用户: $ECS_USER"
echo "- 部署路径: $DEPLOY_PATH"
echo "- 镜像: $IMAGE_NAME:$IMAGE_TAG"
echo "- Git仓库: $GITHUB_REPO"
echo "- Git分支/提交: $GITHUB_SHA"
echo ""

# 创建部署脚本内容
cat > deploy_simple.sh << "DEPLOYEOF"
#!/bin/bash
set -e

# 基本配置
DEPLOY_PATH="$1"
IMAGE_NAME="$2"
IMAGE_TAG="$3"
ENVIRONMENT="$4"
GITHUB_REPO="$5"
GITHUB_SHA="$6"

# 显示基本信息
echo "=== 部署信息 ==="
echo "当前用户: $(whoami)"
echo "部署路径: $DEPLOY_PATH"
echo ""

# 1. 创建部署目录
echo "1. 创建部署目录..."
mkdir -p "$DEPLOY_PATH"
cd "$DEPLOY_PATH" || { echo "无法进入目录 $DEPLOY_PATH"; exit 1; }

# 2. 克隆或更新代码
echo "2. 更新代码仓库..."# 克隆或更新代码仓库 - 幂等操作，支持反复执行
if [ -d ".git" ]; then
  echo "更新现有代码仓库..."
  # 先清理未跟踪文件，确保工作区干净
  git clean -fdx || echo "清理未跟踪文件失败，但继续..."
  git fetch origin --prune
  git reset --hard "$GITHUB_SHA"
  git checkout -f "$GITHUB_SHA" # 确保切换到正确的提交
else
  echo "克隆新的代码仓库..."
  git clone "$GITHUB_REPO" .
  git checkout "$GITHUB_SHA"
fi

# 3. 创建docker-compose配置
echo "3. 创建docker-compose配置..."
cat > docker-compose.yml << COMPOSEEOF
version: '3.8'

services:
  docker-proxy:
    build: .
    image: ${IMAGE_NAME}:${IMAGE_TAG}
    container_name: docker-proxy-${ENVIRONMENT}
    restart: always
    ports:
      - "8388:8388"
    environment:
      - ENVIRONMENT=${ENVIRONMENT}
    volumes:
      - ./config:/etc/shadowsocks
COMPOSEEOF

# 3. 创建docker-compose配置
# 确保配置目录存在
mkdir -p config

# 4. 检查Docker服务状态
echo "4. 检查Docker服务状态..."
if ! docker info > /dev/null 2>&1; then
  echo "⚠️ Docker服务可能未运行，尝试重启Docker服务..."
  # 尝试重启Docker服务（不同系统有不同的重启命令）
  sudo systemctl restart docker || sudo service docker restart || echo "无法重启Docker服务，请手动检查"
  # 等待Docker服务恢复
  sleep 10
  # 再次检查
  if ! docker info > /dev/null 2>&1; then
    echo "❌ Docker服务仍未正常运行，请手动检查Docker服务状态"
    exit 1
  fi
  echo "✅ Docker服务已恢复"
fi

# 5. 停止旧容器 - 支持反复执行，即使容器不存在也不会失败
echo "5. 停止旧容器..."
docker-compose down -v --remove-orphans || true

# 清理可能存在的悬空镜像（可选，但有助于保持环境清洁）
echo "清理悬空镜像..."
docker image prune -f 2>/dev/null || true

# 6. 构建新镜像（添加详细错误处理）
echo "6. 构建Docker镜像..."
# 捕获构建输出并检查错误
BUILD_OUTPUT=$(docker-compose build 2>&1 || echo "BUILD_FAILED")
if echo "$BUILD_OUTPUT" | grep -q "BUILD_FAILED"; then
  echo "❌ Docker构建失败!"
  echo "错误详情:"
  # 显示关键错误信息
  echo "$BUILD_OUTPUT" | grep -E "ERROR|failed|not found|permission denied" || echo "$BUILD_OUTPUT"
  # 针对特定错误提供建议
  if echo "$BUILD_OUTPUT" | grep -q "forwarding Ping: no such job"; then
    echo "建议: 这可能是Docker守护进程问题，请尝试手动重启Docker服务并清理构建缓存"
    echo "命令: sudo systemctl restart docker && docker builder prune -f"
  fi
  exit 1
fi
echo "✅ Docker镜像构建成功"

# 7. 启动新容器
echo "7. 启动新容器..."
docker-compose up -d

# 8. 检查部署状态
echo "8. 检查部署状态..."
sleep 5
docker ps -a | grep docker-proxy

echo ""
if docker-compose ps | grep "Up"; then
  echo "✅ 部署成功! 服务正在运行"
  echo "访问地址: http://$(hostname -I | awk '{print $1}'):8388"
  exit 0
else
  echo "❌ 部署失败! 服务未正常启动"
  echo "查看日志: docker-compose logs --tail 100"
  exit 1
fi
DEPLOYEOF

chmod +x deploy_simple.sh

# 上传并执行部署脚本
echo "上传部署脚本到ECS实例..." 1>&2

# 在GitHub Actions环境中使用更直接的方法，确保错误信息被捕获
echo "尝试SCP上传..." 1>&2
# 直接执行scp，不使用tee，确保错误直接传递
echo "执行命令: scp deploy_simple.sh ${ECS_USER}@${ECS_HOST}:/tmp/deploy_simple.sh" 1>&2
scp -v deploy_simple.sh ${ECS_USER}@${ECS_HOST}:/tmp/deploy_simple.sh
SCP_EXIT_CODE=$?

# 立即检查SCP退出码，确保错误被捕获
if [ $SCP_EXIT_CODE -ne 0 ]; then
  # 使用GitHub Actions的错误标记格式，并输出到标准错误
  echo "##[error] 部署失败: SCP上传脚本失败" 1>&2
  echo "错误: SCP上传失败，退出码: $SCP_EXIT_CODE" 1>&2
  echo "连接信息: ${ECS_USER}@${ECS_HOST}" 1>&2
  echo "故障排除建议:" 1>&2
  echo "1. 检查SSH密钥配置是否正确" 1>&2
  echo "2. 确认ECS_HOST和ECS_USER环境变量设置是否正确" 1>&2
  echo "3. 验证网络连接和防火墙设置" 1>&2
  echo "4. 确认目标服务器上deploy用户有/tmp目录的写入权限" 1>&2
  # 在CI环境中设置错误状态
  if [ -n "$GITHUB_ACTIONS" ]; then
    echo "DEPLOY_STATUS=failure" >> $GITHUB_ENV
  fi
  # 确保退出码被正确传递
  exit $SCP_EXIT_CODE
fi

echo "SCP上传成功!" 1>&2

# 执行部署脚本 - 避免显示命令参数
echo "执行部署脚本到远程服务器..." 1>&2

# 在GitHub Actions环境中使用更直接的方法，确保错误信息被捕获
echo "尝试SSH远程执行..." 1>&2
# 定义基本SSH选项
SSH_OPTIONS="-v -o StrictHostKeyChecking=no -o ConnectTimeout=30"
echo "执行命令: ssh $SSH_OPTIONS ${ECS_USER}@${ECS_HOST} 'chmod +x /tmp/deploy_simple.sh && /tmp/deploy_simple.sh'" 1>&2

# 直接执行SSH，不使用tee，确保错误直接传递
ssh $SSH_OPTIONS ${ECS_USER}@${ECS_HOST} "chmod +x /tmp/deploy_simple.sh && /tmp/deploy_simple.sh '$DEPLOY_PATH' '$IMAGE_NAME' '$IMAGE_TAG' '$ENVIRONMENT' '$GITHUB_REPO' '$GITHUB_SHA'"
DEPLOY_EXIT_CODE=$?

# 检查部署退出码
if [ $DEPLOY_EXIT_CODE -ne 0 ]; then
  # 使用GitHub Actions的错误标记格式，并输出到标准错误
  echo "##[error] 部署失败: 远程执行脚本失败" 1>&2
  echo "错误: 远程执行脚本失败，退出码: $DEPLOY_EXIT_CODE" 1>&2
  echo "连接信息: ${ECS_USER}@${ECS_HOST}" 1>&2
  echo "故障排除建议:" 1>&2
  echo "1. 检查目标服务器上deploy用户权限设置是否正确" 1>&2
  echo "2. 验证与远程服务器的网络连接和SSH配置" 1>&2
  echo "3. 确认远程服务器上Docker服务状态正常" 1>&2
  echo "4. 检查部署路径权限和依赖安装" 1>&2
  # 在CI环境中设置错误状态
  if [ -n "$GITHUB_ACTIONS" ]; then
    echo "DEPLOY_STATUS=failure" >> $GITHUB_ENV
  fi
  # 确保退出码被正确传递
  exit $DEPLOY_EXIT_CODE
fi

echo "SSH远程执行成功!" 1>&2

# 清理本地脚本
rm -f deploy_simple.sh

# 设置CI环境中的部署状态 - 直接在成功路径中设置
if [ $DEPLOY_EXIT_CODE -eq 0 ]; then
  # 在CI环境中设置部署状态
  if [ -n "$GITHUB_ACTIONS" ]; then
    echo "DEPLOY_STATUS=success" >> $GITHUB_ENV
  fi
  
  echo ""
  echo "======================================="
  echo "✅ 部署成功完成!"
  echo "- 镜像标签: $IMAGE_TAG"
  echo "- 环境: $ENVIRONMENT"
  echo "======================================="
  # 确保以成功状态退出
  exit 0
else
  echo ""
  echo "======================================="
  echo "❌ 部署失败，退出码: $DEPLOY_EXIT_CODE"
  echo "请检查:"
  echo "1. deploy用户权限设置"
  echo "2. 远程服务器连接"
  echo "3. Docker服务状态"
  echo "======================================="
  # 在CI环境中设置部署状态
  if [ -n "$GITHUB_ACTIONS" ]; then
    echo "DEPLOY_STATUS=failure" >> $GITHUB_ENV
  fi
  # 确保以失败状态退出
  exit $DEPLOY_EXIT_CODE
fi