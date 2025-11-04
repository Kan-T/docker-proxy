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

# 获取当前用户信息
echo "当前用户: $USER (UID: $(id -u))"

# 确保父目录存在
PARENT_DIR=$(dirname "$DEPLOY_PATH")
echo "确保父目录存在: $PARENT_DIR"
mkdir -p "$PARENT_DIR"

# 先检查目录是否存在
if [ -d "$DEPLOY_PATH" ]; then
  echo "目录已存在: $DEPLOY_PATH"
  # 检查并显示当前权限
  echo "当前目录权限:"
  ls -la "$(dirname "$DEPLOY_PATH")" | grep "$(basename "$DEPLOY_PATH")"
  
  # 如果有权限问题，尝试重新设置权限
  if [ ! -w "$DEPLOY_PATH" ]; then
    echo "目录无写入权限，尝试修复..."
    if command -v sudo > /dev/null && sudo -n true 2>/dev/null; then
      sudo chown -R "$USER":"$USER" "$DEPLOY_PATH"
      sudo chmod -R u+rw "$DEPLOY_PATH"
    else
      echo "警告: 无sudo权限，无法修复权限"
    fi
  fi
else
  # 目录不存在，创建它
  echo "创建新目录: $DEPLOY_PATH"
  if command -v sudo > /dev/null && sudo -n true 2>/dev/null; then
    echo "使用sudo创建目录..."
    sudo mkdir -p "$DEPLOY_PATH"
    sudo chown -R "$USER":"$USER" "$DEPLOY_PATH"
    sudo chmod -R u+rw "$DEPLOY_PATH"
  else
    echo "直接创建目录..."
    mkdir -p "$DEPLOY_PATH" || {
      echo "错误: 无法创建部署目录 $DEPLOY_PATH，可能需要sudo权限"
      exit 1
    }
    chmod -R u+rw "$DEPLOY_PATH"
  fi
fi

# 再次检查权限
echo "更新后的目录权限:"
ls -la "$(dirname "$DEPLOY_PATH")" | grep "$(basename "$DEPLOY_PATH")"

# 尝试切换目录
cd "$DEPLOY_PATH" || {
  echo "错误: 无法切换到部署目录 $DEPLOY_PATH"
  exit 1
}

echo "当前工作目录: $(pwd)"
echo "目录内容:"
ls -la

# 检查目录是否可写
if [ ! -w "." ]; then
  echo "警告: 当前目录不可写!"
  # 备选方案: 使用临时目录
  TEMP_DEPLOY="/tmp/docker-proxy-$ENVIRONMENT"
  echo "尝试使用临时目录: $TEMP_DEPLOY"
  mkdir -p "$TEMP_DEPLOY"
  cd "$TEMP_DEPLOY"
  echo "切换到临时工作目录: $(pwd)"
  DEPLOY_TEMP_MODE=true
fi

# 克隆或更新代码仓库
if [ -d .git ]; then
  echo "更新代码仓库..."
  # 尝试使用sudo执行git操作
  if command -v sudo > /dev/null && [ "$DEPLOY_TEMP_MODE" != "true" ]; then
    sudo -S git fetch origin || {
      echo "sudo git fetch失败，尝试直接更新..."
      git fetch origin
    }
    sudo -S git reset --hard "$GITHUB_SHA" || {
      echo "sudo git reset失败，尝试直接更新..."
      git reset --hard "$GITHUB_SHA"
    }
  else
    # 直接执行git操作
    git fetch origin
    git reset --hard "$GITHUB_SHA"
  fi
else
  echo "克隆代码仓库..."
  # 尝试使用sudo克隆
  if command -v sudo > /dev/null && [ "$DEPLOY_TEMP_MODE" != "true" ]; then
    sudo -S git clone "$GITHUB_REPO" . || {
      echo "sudo git clone失败，尝试直接克隆..."
      git clone "$GITHUB_REPO" .
    }
    sudo -S git checkout "$GITHUB_SHA" || {
      echo "sudo git checkout失败，尝试直接切换..."
      git checkout "$GITHUB_SHA"
    }
  else
    # 直接执行克隆
    git clone "$GITHUB_REPO" .
    git checkout "$GITHUB_SHA"
  fi
fi

# 如果使用了临时目录，修改部署策略
if [ "$DEPLOY_TEMP_MODE" = "true" ]; then
  echo "在临时目录部署模式下，直接在当前目录构建运行..."
  echo "注意：由于权限限制，将直接在临时目录 $PWD 中部署，而不是目标目录 $DEPLOY_PATH"
  
  # 更新docker-compose配置，确保端口映射正确
  sed -i 's|./config:/etc/shadowsocks|'"$PWD"'/config:/etc/shadowsocks|g' docker-compose.yml
  
  echo "已调整配置，将在临时目录中直接部署..."
fi

# 再次确认当前工作目录
echo "最终工作目录: $(pwd)"

# 创建或更新docker-compose.yml文件
if [ "$DEPLOY_TEMP_MODE" = "true" ]; then
  # 在临时目录模式下，创建docker-compose.yml并使用绝对路径
  echo "在临时目录模式下创建docker-compose.yml，使用绝对路径..."
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
      - ${PWD}/config:/etc/shadowsocks
COMPOSEEOF
else
  # 正常模式下使用相对路径
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
fi

mkdir -p config

# 处理Docker Compose操作，在临时部署模式下避免使用sudo
echo "停止旧容器..."
if [ "$DEPLOY_TEMP_MODE" = "true" ]; then
  # 临时部署模式：直接使用docker-compose，不尝试sudo
  echo "临时部署模式：直接执行docker-compose down..."
  docker-compose down -v || {
    echo "警告: 无法停止旧容器，但继续部署..."
  }
else
  # 正常模式：尝试sudo
  if command -v sudo > /dev/null; then
    sudo -S docker-compose down -v || {
      echo "sudo docker-compose down失败，尝试直接停止..."
      docker-compose down -v || true
    }
  else
    docker-compose down -v || true
  fi
fi

echo "构建Docker镜像..."
if [ "$DEPLOY_TEMP_MODE" = "true" ]; then
  # 临时部署模式：直接使用docker-compose
  echo "临时部署模式：直接执行docker-compose build..."
  docker-compose build
else
  # 正常模式：尝试sudo
  if command -v sudo > /dev/null; then
    sudo -S docker-compose build || {
      echo "sudo docker-compose build失败，尝试直接构建..."
      docker-compose build
    }
  else
    docker-compose build
  fi
fi

echo "启动容器..."
if [ "$DEPLOY_TEMP_MODE" = "true" ]; then
  # 临时部署模式：直接使用docker-compose
  echo "临时部署模式：直接执行docker-compose up -d..."
  docker-compose up -d
else
  # 正常模式：尝试sudo
  if command -v sudo > /dev/null; then
    sudo -S docker-compose up -d || {
      echo "sudo docker-compose up失败，尝试直接启动..."
      docker-compose up -d
    }
  else
    docker-compose up -d
  fi
fi

sleep 5

# 检查服务状态
echo "检查服务状态..."
if [ "$DEPLOY_TEMP_MODE" = "true" ]; then
  # 临时部署模式：直接使用docker-compose
  echo "临时部署模式：检查容器状态..."
  docker-compose ps
  if docker-compose ps | grep "Up"; then
    echo "服务在临时目录部署成功并正在运行"
    echo "注意：服务运行在临时目录 $PWD，而非原始目标目录"
    exit 0
  else
    echo "服务部署失败或未正常启动"
    echo "查看容器日志获取更多信息..."
    docker-compose logs --tail 50
    exit 1
  fi
else
  # 正常模式：尝试sudo
  if command -v sudo > /dev/null; then
    if sudo -S docker-compose ps | grep "Up" || docker-compose ps | grep "Up"; then
      echo "服务部署成功并正在运行"
      exit 0
    else
      echo "服务部署失败或未正常启动"
      echo "查看容器日志获取更多信息..."
      sudo -S docker-compose logs --tail 50 || docker-compose logs --tail 50
      exit 1
    fi
  else
    if docker-compose ps | grep "Up"; then
      echo "服务部署成功并正在运行"
      exit 0
    else
      echo "服务部署失败或未正常启动"
      echo "查看容器日志获取更多信息..."
      docker-compose logs --tail 50
      exit 1
    fi
  fi
fi
DEPLOYEOF

chmod +x deploy_script.sh

# 使用SSH将部署脚本上传到ECS实例并执行
echo "3. 上传并执行部署脚本..."
set +x  # 隐藏敏感信息
scp deploy_script.sh ${ECS_USER}@${ECS_HOST}:/tmp/deploy_script.sh
# 使用更简单直接的方式执行部署
cat > deploy_temp.sh << DEPLOYEOF
#!/bin/bash
set -x

# 初始化临时部署模式变量
DEPLOY_TEMP_MODE=false

# 显示系统信息
echo '=== 系统信息 ==='
whoami
id

# 设置环境变量
export DEPLOY_PATH="$DEPLOY_PATH"
export IMAGE_NAME="$IMAGE_NAME"
export IMAGE_TAG="$IMAGE_TAG"
export ENVIRONMENT="$ENVIRONMENT"
export GITHUB_REPO="$GITHUB_REPO"
export GITHUB_SHA="$GITHUB_SHA"

echo '=== 环境变量 ==='
echo 'DEPLOY_PATH: $DEPLOY_PATH'

# 准备目录
echo '=== 目录准备 ==='

# 方法1: 尝试使用sudo创建目录并设置权限（首选）
if command -v sudo > /dev/null; then
  echo "尝试使用sudo创建目录和设置权限..."
  # 使用-S参数允许从stdin读取密码，尽管在CI环境中通常不提供密码
  # 但这是在ECS上执行，可能已经配置了NOPASSWD
  echo "使用sudo创建目录: $DEPLOY_PATH"
  sudo -S mkdir -p "$DEPLOY_PATH" || {
    echo "sudo创建目录失败，尝试备选方案..."
  }
  
  # 尝试设置所有者为当前用户
  echo "尝试设置目录所有者为当前用户..."
  sudo -S chown -R "$USER":"$USER" "$DEPLOY_PATH" || {
    echo "sudo设置所有者失败，但继续尝试..."
  }
else
  # 备选方法：如果没有sudo或sudo失败，尝试直接创建
  echo "没有sudo命令或sudo失败，尝试直接创建目录..."
  mkdir -p "$DEPLOY_PATH" || {
    echo "警告: 无法创建目录 $DEPLOY_PATH，将尝试使用用户主目录..."
    # 如果无法在指定路径创建，使用用户主目录作为备选
    DEPLOY_PATH="$HOME/docker-proxy-$ENVIRONMENT"
    echo "切换到备选部署路径: $DEPLOY_PATH"
    mkdir -p "$DEPLOY_PATH"
    # 设置临时部署模式标志
    DEPLOY_TEMP_MODE=true
  }
fi

# 导出DEPLOY_TEMP_MODE变量供部署脚本使用
export DEPLOY_TEMP_MODE

echo '父目录权限:'
ls -la "$(dirname "$DEPLOY_PATH")"

echo '设置部署目录权限...'
# 尝试使用sudo修改权限
if command -v sudo > /dev/null; then
  sudo -S chmod -R 775 "$DEPLOY_PATH" || {
    echo "sudo修改权限失败，尝试直接修改..."
    chmod -R 775 "$DEPLOY_PATH" 2>/dev/null || echo "无法修改权限，但继续..."
  }
else
  chmod -R 775 "$DEPLOY_PATH" 2>/dev/null || echo "无法修改权限，但继续..."
fi

echo '=== 部署目录状态 ==='
ls -la "$DEPLOY_PATH" 2>/dev/null || echo '目录为空或不存在'

# 执行部署脚本
echo '=== 开始执行部署脚本 ==='
chmod +x /tmp/deploy_script.sh

# 直接执行部署脚本，不使用sudo，确保在临时部署模式下正常工作
echo "直接执行部署脚本，避免sudo权限问题..."
bash -x /tmp/deploy_script.sh

# 捕获部署脚本执行结果
DEPLOY_RESULT=$?

echo "部署脚本执行完成，退出码: $DEPLOY_RESULT"

# 根据退出码决定返回值
exit $DEPLOY_RESULT
DEPLOYEOF

# 上传并执行部署辅助脚本
scp deploy_temp.sh ${ECS_USER}@${ECS_HOST}:/tmp/deploy_wrapper.sh
ssh ${ECS_USER}@${ECS_HOST} "chmod +x /tmp/deploy_wrapper.sh && bash /tmp/deploy_wrapper.sh"

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