# Docker Proxy 部署指南

本指南说明如何将Docker Proxy服务部署到阿里云ECS实例上。当前方案采用**直接在ECS上构建镜像**的方式，以减少流量消耗。

## 环境准备

在开始部署前，请确保ECS实例已满足以下要求：

1. **基础环境**
   - 操作系统：Ubuntu 22.04 或其他支持Docker的Linux系统
   - 内存：至少 1GB RAM
   - 磁盘：至少 10GB 可用空间

2. **必要软件**
   - **Git**：用于克隆代码仓库
     ```bash
     sudo apt update
     sudo apt install -y git
     ```
   - **Docker**：用于构建和运行容器
     ```bash
     # 安装Docker
     curl -fsSL https://get.docker.com -o get-docker.sh
     sudo sh get-docker.sh
     
     # 启动Docker服务
     sudo systemctl enable docker
     sudo systemctl start docker
     ```
   - **Docker Compose**：用于管理多容器应用
     ```bash
     # 安装Docker Compose
     sudo apt install -y docker-compose
     ```

3. **权限配置**
   - 确保root用户或部署用户有权限执行docker命令
     ```bash
     sudo usermod -aG docker $USER
     # 退出并重新登录以应用权限
     ```

4. **网络配置**
   - 确保安全组已开放 8388 端口（服务默认端口）
   - 如使用私有网络，确保可以访问GitHub代码仓库

## 部署方式

### 1. 自动部署（推荐）

本项目使用GitHub Actions自动部署。当代码推送到main分支时，将触发部署流程：

1. 代码检查和测试
2. 手动审批部署（生产环境）
3. 触发ECS部署脚本
4. ECS实例克隆代码并构建运行镜像

### 2. 手动部署

如需手动部署，可在本地执行以下命令：

```bash
# 设置环境变量
export GITHUB_REPOSITORY="your-username/docker-proxy"
export GITHUB_SHA="main"  # 或特定的commit SHA

# 执行部署脚本
./scripts/deploy-to-ecs.sh -e prod -r <阿里云区域ID>
```

## 部署流程说明

新的部署流程（直接在ECS构建）与原流程（通过容器镜像服务）的对比：

| 步骤 | 原流程 | 新流程 |
|------|--------|--------|
| 构建环境 | GitHub Actions | ECS实例本地 |
| 流量消耗 | 高（镜像上传+下载） | 低（仅代码克隆+基础镜像） |
| 部署速度 | 较快 | 首次较慢，后续利用缓存较快 |
| 网络依赖 | 需公网访问容器镜像服务 | 需公网访问GitHub |

## 关键文件说明

- **scripts/deploy-to-ecs.sh**：部署脚本，负责在ECS上设置环境并执行部署
- **docker-compose.yml**：在ECS上自动生成，定义服务配置
- **Dockerfile**：定义镜像构建过程

## 常见问题

1. **部署失败，提示无法克隆代码**
   - 检查ECS实例是否可以访问GitHub
   - 检查网络连接和防火墙设置

2. **镜像构建缓慢**
   - 可考虑配置Docker国内镜像源加速
     ```bash
     sudo mkdir -p /etc/docker
     sudo tee /etc/docker/daemon.json <<-'EOF'
     {
       "registry-mirrors": ["https://<您的加速器地址>"]
     }
     EOF
     sudo systemctl daemon-reload
     sudo systemctl restart docker
     ```

3. **服务启动后无法访问**
   - 检查安全组是否开放8388端口
   - 检查容器是否正常运行：`docker ps | grep docker-proxy`
   - 查看容器日志：`docker logs docker-proxy-prod`

## 流量优化建议

1. 使用Docker缓存机制，减少重复构建时的流量
2. 配置国内镜像源加速基础镜像下载
3. 定期清理不再使用的镜像和容器：`docker system prune -f`

## 更新日志

- 2024-05-XX：切换为直接在ECS构建镜像的部署方式，优化流量消耗