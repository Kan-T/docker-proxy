# GitHub Actions Secrets 和环境配置指南

本文档提供了配置Docker Proxy自动部署所需的GitHub Secrets和环境设置指南。**当前方案已优化为使用SSH直接部署到ECS实例，不再使用阿里云CLI方式。**

## 必要的GitHub Secrets

请在GitHub仓库的`Settings > Secrets and variables > Actions > Secrets`中添加以下密钥：

### 服务器SSH连接信息（新版部署方式）

#### GitHub Secrets（敏感信息）
| 密钥名称 | 描述 | 示例值 | 获取方法 |
|---------|------|-------|--------|
| `ECS_SSH_PRIVATE_KEY` | 用于SSH连接到ECS实例的私钥 | `-----BEGIN RSA PRIVATE KEY-----...` | 本地生成SSH密钥对，将私钥内容复制到此处 |

#### GitHub Variables（非敏感信息）
| 变量名称 | 描述 | 示例值 | 获取方法 |
|---------|------|-------|--------|
| `ECS_HOST` | ECS实例的IP地址或域名 | `47.xx.xx.xx` | 阿里云ECS控制台查看实例公网IP |
| `ECS_USER` | SSH连接的用户名 | `ubuntu` | 默认为root，建议使用专用部署用户 |

#### 如何创建专用部署用户

在ECS实例上创建专用部署用户的步骤：

1. **登录ECS实例**：
   ```bash
   ssh root@你的ECS实例IP
   ```

2. **创建部署用户**（以`deploy`为例）：
   ```bash
   # 创建用户
   useradd -m -s /bin/bash deploy
   
   # 设置密码（可选，SSH密钥认证更安全）
   passwd deploy
   ```

3. **赋予sudo权限**：
   ```bash
   # 将用户添加到sudo组
   usermod -aG sudo deploy
   
   # 或编辑sudoers文件（更精细的权限控制）
   visudo
   # 添加行: deploy ALL=(ALL:ALL) NOPASSWD:/usr/bin/docker,/usr/local/bin/docker-compose
   ```

4. **配置SSH密钥**：
   ```bash
   # 切换到部署用户
   su - deploy
   
   # 创建.ssh目录
   mkdir -p ~/.ssh
   chmod 700 ~/.ssh
   
   # 添加SSH公钥
   echo "你的公钥内容" >> ~/.ssh/authorized_keys
   chmod 600 ~/.ssh/authorized_keys
   ```

5. **测试连接**：
   ```bash
   ssh deploy@你的ECS实例IP
   ```

**安全建议**：
- 专用部署用户应只拥有部署所需的最小权限
- 使用SSH密钥认证而非密码认证
- 考虑禁用root远程SSH登录
- 定期轮换SSH密钥

### 环境URL（用于部署通知）

| 密钥名称 | 描述 | 示例值 | 获取方法 |
|---------|------|-------|--------|
| `PROD_ENV_URL` | 生产环境URL | `https://proxy.example.com` | 根据您的实际生产环境域名设置 |

> **方案说明**：当前部署方案已优化为使用SSH直接连接到ECS实例进行部署，不再使用阿里云CLI。这种方式的优势包括：
> - **简化配置**：无需配置复杂的阿里云RAM权限
> - **更广泛兼容性**：适用于各种云服务商和自托管服务器
> - **更低延迟**：直接通过SSH连接，减少API调用开销

### 旧版阿里云CLI配置（已弃用）

以下密钥在使用SSH部署方式后不再需要，可以安全删除：
- `ALI_ACCESS_KEY_ID`
- `ALI_ACCESS_KEY_SECRET`
- `ALI_REGION`

## GitHub环境配置

请在GitHub仓库的`Settings > Environments`中创建以下环境：

### 生产环境 (production)

- **环境名称**: `production`
- **保护规则设置**:
    - [x] 要求在部署前获得批准
      - 添加必要的审批人员（至少1人）
    - [x] 要求特定分支进行部署
      - 分支: `main`
    - [x] 等待外部状态检查通过
      - 选择至少一个状态检查

## SSH密钥对生成和配置方法

### 生成SSH密钥对

1. 在本地执行以下命令生成SSH密钥对（不要设置密码以避免自动化过程中的交互式提示）：
   ```bash
   ssh-keygen -t rsa -b 4096 -f docker-proxy-deploy-key
   ```

2. 将公钥（`docker-proxy-deploy-key.pub`）添加到ECS实例的`~/.ssh/authorized_keys`文件中
   ```bash
   # 在本地复制公钥内容
   cat docker-proxy-deploy-key.pub
   
   # 登录到ECS实例，将公钥内容添加到authorized_keys文件
   echo "<公钥内容>" >> ~/.ssh/authorized_keys
   chmod 600 ~/.ssh/authorized_keys
   ```

3. 将私钥（`docker-proxy-deploy-key`）的内容复制到GitHub的`ECS_SSH_PRIVATE_KEY`密钥中

### 安全组配置

确保ECS实例的安全组已开放SSH端口（默认22），并允许来自GitHub Actions运行器IP的连接。

1. 登录阿里云ECS控制台
2. 找到目标ECS实例 → 安全组 → 配置规则
3. 添加入站规则：
   - 端口范围：22
   - 授权对象：可以设置为0.0.0.0/0（允许所有IP，不推荐）或特定IP范围
   - 优先级：根据需求设置

## 阿里云ECS实例配置

部署前确保已创建并配置美国区域的ECS实例：

1. 安装必要软件：
   ```bash
   # 安装Git
   sudo apt update
   sudo apt install -y git
   
   # 安装Docker
   curl -fsSL https://get.docker.com -o get-docker.sh
   sudo sh get-docker.sh
   
   # 安装Docker Compose
   sudo apt install -y docker-compose
   ```

2. 配置安全组规则，开放必要端口（至少8388端口）
   - 获取方法：ECS实例详情 → 安全组 → 配置规则 → 添加安全组规则

3. 权限配置
   - 确保root用户或部署用户有权限执行docker命令
     ```bash
     sudo usermod -aG docker $USER
     # 退出并重新登录以应用权限
     ```

4. 创建部署目录：`/data/docker-proxy/prod`

## ECS构建环境优化（可选）

为了优化ECS上的镜像构建速度，可以配置Docker国内镜像源加速：

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

常见的国内镜像加速地址：
- 阿里云容器镜像服务：https://<您的阿里云账户ID>.mirror.aliyuncs.com
- DaoCloud：http://f1361db2.m.daocloud.io
- 七牛云：https://reg-mirror.qiniu.com

## 故障排除

### 常见错误及解决方案

1. **SSH连接错误**
    - 检查`ECS_SSH_PRIVATE_KEY`（Secrets）格式是否正确，确保包含完整的私钥内容
    - 验证`ECS_HOST`和`ECS_USER`（Variables）配置是否正确
    - 确认公钥已正确添加到ECS实例的`authorized_keys`文件

2. **部署超时**
   - 检查ECS实例网络连接
   - 验证实例安全组配置是否允许SSH连接
   - 检查ECS实例负载是否过高

3. **代码克隆失败**
   - 检查ECS实例是否可以访问GitHub
   - 验证网络连接和防火墙设置
   - 确认GitHub仓库URL正确

4. **镜像构建失败**
   - 检查Docker环境是否正常运行
   - 查看构建日志获取详细错误信息
   - 确认Dockerfile语法正确

5. **权限不足**
   - 确保SSH用户有足够权限执行Docker命令（可添加到docker组）
   - 验证部署目录权限设置是否正确

## 安全最佳实践

1. **最小权限原则**
   - 为部署创建专用的SSH用户，限制其权限范围
   - 仅授予该用户执行部署所需的最小权限

2. **密钥管理**
   - 所有敏感信息通过GitHub Secrets管理
   - 定期轮换SSH密钥对（建议每3-6个月）
   - 不要在代码库或日志中暴露私钥信息

3. **部署审批**
   - 生产环境必须启用手动审批
   - 生产环境至少需要一个审批人

4. **审计日志**
   - 配置SSH登录日志记录
   - 定期审查部署历史和操作日志

5. **ECS实例安全**
   - 定期更新ECS实例系统和软件包
   - 配置防火墙规则限制不必要的访问
   - 使用密钥对而非密码登录ECS实例
   - 定期清理不再使用的镜像和容器

6. **代码安全**
   - 确保只有授权用户可以访问GitHub仓库
   - 对代码进行定期安全审查
   - 启用分支保护规则防止未授权的代码合并