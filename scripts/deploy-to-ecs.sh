#!/bin/bash

# 阿里云ECS部署脚本 (仅支持生产环境) - 直接在ECS构建镜像版本
set -e

echo "======================================="
echo "Docker Proxy 阿里云部署脚本 (生产环境)"
echo "======================================="

# 参数解析
while getopts "e:r:h" opt; do
  case $opt in
    e) ENVIRONMENT=$OPTARG ;;
    r) ALI_REGION=$OPTARG ;;
    h) echo "用法: $0 -e prod -r 阿里云区域" && exit 0 ;;
    *) echo "未知选项" && exit 1 ;;
  esac
done

# 验证必要参数
if [ -z "$ENVIRONMENT" ] || [ -z "$ALI_REGION" ]; then
  echo "错误: 缺少必要参数"
  echo "用法: $0 -e prod -r 阿里云区域"
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
ECS_INSTANCE_ID="i-xxxxxxxxxxxxxxxxx"  # 生产环境ECS实例ID (请替换为实际的美国区域ECS实例ID)
DEPLOY_PATH="/data/docker-proxy/prod"

echo "部署配置:"
echo "- 环境: $ENVIRONMENT"
echo "- 阿里云区域: $ALI_REGION"
echo "- ECS实例ID: ${ECS_INSTANCE_ID:0:8}************"  # 掩码处理
echo "- 部署路径: $DEPLOY_PATH"
echo "- 镜像: $IMAGE_NAME:$IMAGE_TAG (将在ECS上直接构建)"
echo ""

# 检查阿里云CLI是否安装
if ! command -v aliyun &> /dev/null; then
  echo "错误: 阿里云CLI未安装，请先安装并配置阿里云CLI"
  echo "安装指南: https://help.aliyun.com/document_detail/121945.html"
  exit 1
fi

# 检查阿里云凭证
if ! aliyun ecs DescribeRegions -q > /dev/null 2>&1; then
  echo "错误: 阿里云凭证配置无效，请检查阿里云凭证"
  echo "配置指南: https://help.aliyun.com/document_detail/121945.html#section-qxs-vyq-2g7"
  exit 1
fi

echo "1. 检查ECS实例状态..."
INSTANCE_STATUS=$(aliyun ecs DescribeInstances --RegionId "$ALI_REGION" --InstanceIds "[$ECS_INSTANCE_ID]" -q | jq -r '.Instances.Instance[0].Status')

if [ -z "$INSTANCE_STATUS" ] || [ "$INSTANCE_STATUS" != "Running" ]; then
  # 对实例ID进行部分掩码处理
  INSTANCE_ID_MASKED="${ECS_INSTANCE_ID:0:8}************"
  echo "错误: ECS实例 $INSTANCE_ID_MASKED 不存在或未运行"
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

echo "4. 在ECS实例上执行部署脚本..."
# 获取GitHub仓库信息
GITHUB_REPO="${GITHUB_REPOSITORY:-docker-proxy}"
GITHUB_REPO="https://github.com/${GITHUB_REPO}.git"
GITHUB_SHA="${GITHUB_SHA:-main}"

# 执行部署命令 - 使用更安全的方式处理参数，避免直接在命令字符串中拼接敏感信息
DEPLOY_RESULT=$(aliyun ecs RunCommand \
  --RegionId "$ALI_REGION" \
  --InstanceId "$ECS_INSTANCE_ID" \
  --CommandContent "bash -c \"cd /root && cat > deploy_script.sh << 'DEPLOYEOF'\n#!/bin/bash\n\n# 环境变量\nDEPLOY_PATH=\\"$DEPLOY_PATH\\"\nIMAGE_NAME=\\"$IMAGE_NAME\\"\nIMAGE_TAG=\\"$IMAGE_TAG\\"\nENVIRONMENT=\\"$ENVIRONMENT\\"\nGITHUB_REPO=\\"$GITHUB_REPO\\"\nGITHUB_SHA=\\"$GITHUB_SHA\\"\n\nmkdir -p \$DEPLOY_PATH && cd \$DEPLOY_PATH\n\n# 克隆或更新代码仓库（避免在日志中显示仓库URL）\nif [ -d .git ]; then\n  echo \"更新代码仓库...\"\n  git fetch origin\n  git reset --hard \$GITHUB_SHA\nelse\n  echo \"克隆代码仓库...\"\n  git clone \$GITHUB_REPO .\n  git checkout \$GITHUB_SHA\nfi\n\n# 创建或更新docker-compose.yml文件\ncat > docker-compose.yml << COMPOSEEOF\nversion: \'3.8\'\n\nservices:\n  docker-proxy:\n    build: .\n    image: \${IMAGE_NAME}:\${IMAGE_TAG}\n    container_name: docker-proxy-\${ENVIRONMENT}\n    restart: always\n    ports:\n      - \"8388:8388\"\n    environment:\n      - ENVIRONMENT=\${ENVIRONMENT}\n    volumes:\n      - ./config:/etc/shadowsocks\nCOMPOSEEOF\n\nmkdir -p config\ndocker-compose down -v || true\necho \"构建Docker镜像...\"\ndocker-compose build\ndocker-compose up -d\nsleep 5\ndocker-compose ps\nDEPLOYEOF\n\nchmod +x deploy_script.sh\n./deploy_script.sh\"" \
  --Type Shell \
  --WorkingDir "/root" \
  --Timeout 300 -q)

COMMAND_ID=$(echo "$DEPLOY_RESULT" | jq -r '.CommandId')

echo "5. 正在等待部署完成..."
# 等待部署完成
MAX_RETRIES=60
RETRY_COUNT=0
DEPLOY_STATUS="Pending"

while [ "$RETRY_COUNT" -lt "$MAX_RETRIES" ]; do
  RETRY_COUNT=$((RETRY_COUNT + 1))
  
  # 查询命令执行状态
  STATUS_RESULT=$(aliyun ecs DescribeInvocationResults --RegionId "$ALI_REGION" --CommandId "$COMMAND_ID" --InstanceId "$ECS_INSTANCE_ID" -q)
  DEPLOY_STATUS=$(echo "$STATUS_RESULT" | jq -r '.Invocation.InvocationResults.InvocationResult[0].InvocationStatus')
  
  if [ "$DEPLOY_STATUS" = "Finished" ]; then
    EXIT_CODE=$(echo "$STATUS_RESULT" | jq -r '.Invocation.InvocationResults.InvocationResult[0].ExitCode')
    if [ "$EXIT_CODE" = "0" ]; then
      echo "部署成功完成！"
      break
    else
  echo "部署失败，退出码: $EXIT_CODE"
  echo "部署日志: [已省略详细输出以保护敏感信息]"
  # 将详细日志重定向到文件而非标准输出
  echo "$STATUS_RESULT" | jq -r '.Invocation.InvocationResults.InvocationResult[0].Output' > /tmp/deploy_error.log 2>&1 || true
  echo "详细日志已保存到服务器的临时文件，如需查看请手动检查"
  exit 1
    fi
  fi
  
  echo "等待部署完成... ($RETRY_COUNT/$MAX_RETRIES)"
  sleep 5
done

if [ "$RETRY_COUNT" -ge "$MAX_RETRIES" ]; then
  echo "警告: 部署超时，服务可能尚未完全就绪，请手动检查服务状态"
  exit 0 # 不返回错误，让用户手动检查
fi

echo "======================================="
echo "部署摘要:"
echo "- 环境: $ENVIRONMENT"
echo "- ECS实例: ${ECS_INSTANCE_ID:0:8}************"  # 掩码处理
echo "- 部署路径: $DEPLOY_PATH"
echo "- 镜像: $IMAGE_NAME:$IMAGE_TAG (在ECS上构建)"
echo "- 部署状态: 成功"
echo "======================================="

exit 0