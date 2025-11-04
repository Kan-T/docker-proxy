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

# 确保配置目录存在
mkdir -p config

# 4. 停止旧容器 - 支持反复执行，即使容器不存在也不会失败
echo "4. 停止旧容器..."
docker-compose down -v --remove-orphans || true

# 清理可能存在的悬空镜像（可选，但有助于保持环境清洁）
echo "清理悬空镜像..."
docker image prune -f 2>/dev/null || true

# 5. 构建新镜像
echo "5. 构建Docker镜像..."
docker-compose build

# 6. 启动新容器
echo "6. 启动新容器..."
docker-compose up -d

# 7. 检查部署状态
echo "7. 检查部署状态..."
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
echo "上传部署脚本到ECS实例..."
scp deploy_simple.sh ${ECS_USER}@${ECS_HOST}:/tmp/deploy_simple.sh

# 执行部署脚本 - 避免显示命令参数
echo "执行部署脚本到远程服务器..."
# 使用-v参数启用SSH详细输出，有助于调试连接问题
# 临时保存ssh输出到变量，然后过滤输出但保留退出码
SSH_OUTPUT=$(ssh -v ${ECS_USER}@${ECS_HOST} "set +x && chmod +x /tmp/deploy_simple.sh && /tmp/deploy_simple.sh '$DEPLOY_PATH' '$IMAGE_NAME' '$IMAGE_TAG' '$ENVIRONMENT' '$GITHUB_REPO' '$GITHUB_SHA'" 2>&1)
DEPLOY_EXIT_CODE=$?

# 打印过滤后的输出（排除identity file信息）
echo "$SSH_OUTPUT" | grep -v "debug1: identity file" || true

# 清理本地脚本
rm -f deploy_simple.sh

# 显示结果 - CI/CD友好的输出
if [ $DEPLOY_EXIT_CODE -eq 0 ]; then
  echo ""
  echo "======================================="
  echo "✅ 部署成功完成!"
  echo "- 镜像标签: $IMAGE_TAG"
  echo "- 环境: $ENVIRONMENT"
  echo "======================================="
  # 在CI环境中设置部署状态
  if [ -n "$GITHUB_ACTIONS" ]; then
    echo "DEPLOY_STATUS=success" >> $GITHUB_ENV
  fi
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
  exit 1
fi

exit 0