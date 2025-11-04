# GitHub Actions Secrets 和环境配置指南

本文档提供了配置Docker Proxy自动部署所需的GitHub Secrets和环境设置指南。**当前方案已优化为直接在ECS上构建镜像，不再需要容器镜像服务。**

## 必要的GitHub Secrets

请在GitHub仓库的`Settings > Secrets and variables > Actions > Secrets`中添加以下密钥：

### 阿里云相关配置

| 密钥名称 | 描述 | 示例值 | 获取方法 |
|---------|------|-------|--------|
| `ALI_ACCESS_KEY_ID` | 阿里云访问密钥ID | `LTAI5t7Uxxxxxxxxxxxxxxx` | 阿里云控制台 → RAM访问控制 → 用户 → 选择用户 → 安全设置 → 创建/查看AccessKey |
| `ALI_ACCESS_KEY_SECRET` | 阿里云访问密钥密钥 | `QaXxxxxxxxxxxxxxxxxxxxxxxx` | 阿里云控制台 → RAM访问控制 → 用户 → 选择用户 → 安全设置 → 创建/查看AccessKey（仅创建时可见） |
| `ALI_REGION` | 阿里云区域 | `cn-hangzhou` | 阿里云控制台 → 左上角区域选择器中查看，或访问 https://help.aliyun.com/document_detail/40654.html 获取区域列表 | |

> **方案说明**：当前部署方案已优化为直接在ECS上构建镜像，不再需要容器镜像服务。这种方式的优势包括：
> - **减少流量消耗**：无需将镜像上传到镜像仓库再下载，仅需克隆代码
> - **利用Docker缓存**：后续更新可利用Docker缓存机制，显著减少构建时间和流量
> - **简化配置**：减少了对容器镜像服务的依赖和配置

> **如需切换回使用容器镜像服务**：
> 可以参考历史版本的文档或联系开发团队获取相关配置指南。

### 环境URL（用于部署通知）

| 密钥名称 | 描述 | 示例值 | 获取方法 |
|---------|------|-------|--------|
| `PROD_ENV_URL` | 生产环境URL | `https://proxy.example.com` | 根据您的实际生产环境域名设置 |

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

## 阿里云RAM用户和权限配置

为GitHub Actions创建的RAM用户需要以下权限策略：

```json
{
  "Version": "1",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ecs:DescribeInstances",
        "ecs:RunCommand",
        "ecs:DescribeInvocationResults"
      ],
      "Resource": "*"
    }
  ]
}
```

获取方法：
1. 登录阿里云控制台 → 访问控制RAM → 用户 → 创建用户
2. 设置登录名称和显示名称，选择「编程访问」
3. 创建成功后，立即保存访问密钥ID和密钥
4. 为用户添加权限策略：
   - 点击用户列表中的目标用户
   - 点击「权限管理」→「添加权限」
   - 在「新增授权」页面，点击「自定义策略」tab
   - 点击「新建策略」按钮（如果已有策略可跳过）
   - 选择「脚本配置」模式，粘贴上述JSON策略内容
   - 设置策略名称，如「GitHubActions-ECS-Deploy-Policy」
   - 点击「确定」创建策略
   - 返回「新增授权」页面，在搜索框中输入创建的策略名称
   - 勾选策略并点击「确定」完成授权

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

1. **阿里云凭证错误**
   - 检查访问密钥ID和密钥是否正确
   - 确认RAM用户权限配置正确
   - 验证GitHub Actions运行器IP是否在阿里云允许的IP范围内

2. **部署超时**
   - 检查ECS实例网络连接
   - 验证实例安全组配置是否正确
   - 查看ECS命令执行日志获取详细错误信息

3. **代码克隆失败**
   - 检查ECS实例是否可以访问GitHub
   - 验证网络连接和防火墙设置
   - 确认GitHub仓库URL正确

4. **镜像构建失败**
   - 检查Docker环境是否正常运行
   - 查看构建日志获取详细错误信息
   - 确认Dockerfile语法正确

5. **权限不足**
   - 验证RAM用户权限是否完整
   - 确保ECS实例有足够权限执行Docker命令

## 安全最佳实践

1. **最小权限原则**
   - 使用独立的RAM用户进行部署
   - 仅授予必要的阿里云权限

2. **密钥管理**
   - 所有敏感信息通过GitHub Secrets管理
   - 定期轮换阿里云访问密钥

3. **部署审批**
   - 生产环境必须启用手动审批
   - 生产环境至少需要一个审批人

4. **审计日志**
   - 启用阿里云操作审计服务记录所有API操作
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