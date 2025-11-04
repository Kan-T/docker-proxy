#!/bin/bash

# ECS部署脚本 (仅支持生产环境) - 使用SSH直接连接ECS实例
set -e

echo "======================================="
echo "Docker Proxy 部署脚本 (生产环境)"
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

# 生成本地镜像名称和标签
IMAGE_NAME="docker-proxy"
IMAGE_TAG="latest"

# 验证环境参数
if [ "$ENVIRONMENT" != "prod" ]; then
  echo "错误: 仅支持生产环境部署"
  echo "请使用: -e prod"
  exit 1
fi

# 设置生产环境配置
ECS_HOST=${ECS_HOST:-localhost}  # 将从环境变量获取ECS主机地址
ECS_USER=${ECS_USER:-root}  # 默认使用root用户
DEPLOY_PATH="/data/docker-proxy/prod"

echo "部署配置:"
echo "- 环境: $ENVIRONMENT"
echo "- ECS主机: ${ECS_HOST:0:8}************"  # 掩码处理
echo "- 部署路径: $DEPLOY_PATH"
echo "- 镜像: $IMAGE_NAME:$IMAGE_TAG (将在ECS上直接构建)"
echo ""

# 检查SSH连接
echo "1. 检查SSH连接..."
if ! ssh -o ConnectTimeout=5 -o BatchMode=yes ${ECS_USER}@${ECS_HOST} 'hostname'; then
  echo "错误: 无法通过SSH连接到ECS实例"
  echo "请检查ECS_HOST环境变量和SSH密钥配置"
  exit 1
fi

echo "2. 准备部署环境..."

# 创建临时部署脚本
cat > deploy_temp.sh << 'EOF'
#!/bin/bash

# 设置变量
DEPLOY_PATH="$1"
IMAGE_NAME="$2"
IMAGE_TAG="$3"
ENVIRONMENT="$4"
GITHUB_REPO="$5"
GITHUB_SHA="$6"

# 创建部署目录
mkdir -p "$DEPLOY_PATH"
cd "$DEPLOY_PATH"

# 克隆或更新代码仓库
if [ -d ".git" ]; then
  echo "更新代码仓库..."
  git fetch origin
  git reset --hard $GITHUB_SHA
else
  echo "克隆代码仓库..."
  git clone $GITHUB_REPO .
  git checkout $GITHUB_SHA
fi

# 创建或更新docker-compose.yml文件
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

# 停止旧容器并移除
if docker-compose down -v; then
  echo "已停止旧容器"
fi

# 构建新镜像
echo "构建Docker镜像..."
docker-compose build

# 启动新容器
docker-compose up -d

# 检查服务状态
sleep 5
docker ps -a | grep docker-proxy-${ENVIRONMENT}

# 返回容器启动状态
if docker-compose ps | grep "Up"; then
  exit 0
else
  exit 1
fi
EOF

chmod +x deploy_temp.sh

# 清理临时脚本
rm -f deploy_temp.sh

echo "2. 在ECS实例上执行部署脚本..."
# 获取GitHub仓库信息
GITHUB_REPO="${GITHUB_REPOSITORY:-docker-proxy}"
GITHUB_REPO="https://github.com/${GITHUB_REPO}.git"
GITHUB_SHA="${GITHUB_SHA:-main}"

# 创建部署脚本内容
cat > deploy_script.sh << "DEPLOYEOF"
#!/bin/bash
set -e

# 输出环境变量用于调试
echo "部署脚本环境变量:"
echo "- DEPLOY_PATH: $DEPLOY_PATH"
echo "- IMAGE_NAME: $IMAGE_NAME"
echo "- IMAGE_TAG: $IMAGE_TAG"
echo "- ENVIRONMENT: $ENVIRONMENT"
echo "- GITHUB_REPO: $GITHUB_REPO"
echo "- GITHUB_SHA: $GITHUB_SHA"

# 确保目录存在并切换到该目录
echo "创建部署目录并设置权限..."
# 首先检查是否有sudo权限
if command -v sudo > /dev/null && sudo -n true 2>/dev/null; then
  echo "使用sudo创建和设置目录权限..."
  sudo mkdir -p "$DEPLOY_PATH"
  sudo chown -R "$USER":"$USER" "$DEPLOY_PATH"
else
  echo "直接创建目录..."
  mkdir -p "$DEPLOY_PATH" || {
    echo "错误: 无法创建部署目录 $DEPLOY_PATH，可能需要sudo权限"
    exit 1
  }
fi

cd "$DEPLOY_PATH" || {
  echo "错误: 无法切换到部署目录 $DEPLOY_PATH"
  exit 1
}
echo "当前工作目录: $(pwd)"
echo "目录权限: $(ls -la | head -n 1)"

# 克隆或更新代码仓库
if [ -d .git ]; then
  echo "更新代码仓库..."
  git fetch origin
  git reset --hard "$GITHUB_SHA"
else
  echo "克隆代码仓库..."
  git clone "$GITHUB_REPO" .
  git checkout "$GITHUB_SHA"
fi

# 创建或更新docker-compose.yml文件
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

mkdir -p config
docker-compose down -v || true
echo "构建Docker镜像..."
docker-compose build
docker-compose up -d
sleep 5
docker-compose ps

# 检查服务状态
if docker-compose ps | grep "Up"; then
  echo "服务部署成功并正在运行"
  exit 0
else
  echo "服务部署失败或未正常启动"
  exit 1
fi
DEPLOYEOF

chmod +x deploy_script.sh

# 使用SSH将部署脚本上传到ECS实例并执行
echo "3. 上传并执行部署脚本..."
set +x  # 隐藏敏感信息
scp deploy_script.sh ${ECS_USER}@${ECS_HOST}:/tmp/deploy_script.sh
ssh ${ECS_USER}@${ECS_HOST} "chmod +x /tmp/deploy_script.sh && \
  export DEPLOY_PATH='$DEPLOY_PATH' && \
  export IMAGE_NAME='$IMAGE_NAME' && \
  export IMAGE_TAG='$IMAGE_TAG' && \
  export ENVIRONMENT='$ENVIRONMENT' && \
  export GITHUB_REPO='$GITHUB_REPO' && \
  export GITHUB_SHA='$GITHUB_SHA' && \
  echo '开始执行部署脚本...' && \
  bash -x /tmp/deploy_script.sh"

DEPLOY_EXIT_CODE=$?
set -x

# 检查部署结果
if [ $DEPLOY_EXIT_CODE -eq 0 ]; then
  echo "部署成功完成！"
else
  echo "部署失败，退出码: $DEPLOY_EXIT_CODE"
  exit 1
fi

# 清理本地部署脚本
rm -f deploy_script.sh

echo "======================================="
echo "部署摘要:"
echo "- 环境: $ENVIRONMENT"
echo "- ECS实例: ${ECS_INSTANCE_ID:0:8}************"  # 掩码处理
echo "- 部署路径: $DEPLOY_PATH"
echo "- 镜像: $IMAGE_NAME:$IMAGE_TAG (在ECS上构建)"
echo "- 部署状态: 成功"
echo "======================================="

exit 0