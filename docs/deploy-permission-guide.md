# Docker Proxy 部署权限设置指南

本文档详细说明如何为 `deploy` 用户设置必要的权限，以成功部署 Docker Proxy 服务。

## 一、创建 deploy 用户

首先在 ECS 实例上创建 `deploy` 用户（如果尚未创建）：

```bash
# 切换到 root 用户
# 注意：在实际环境中请使用您的方式切换到 root 权限
sudo -i

# 创建 deploy 用户
useradd -m -s /bin/bash deploy

# 设置密码（按提示输入密码）
passwd deploy
```

## 二、设置免密码 sudo 权限

为了简化部署过程，我们推荐为 `deploy` 用户配置免密码 sudo 权限。

### 方法 1：编辑 sudoers 文件（推荐）

```bash
# 使用 visudo 安全编辑 sudoers 文件
sudo visudo

# 添加以下行到文件末尾（使用 Tab 键分隔）
deploy  ALL=(ALL) NOPASSWD: ALL

# 保存并退出
# 在 vim 中按 Esc 键，然后输入 :wq 并按 Enter
```

### 方法 2：创建 sudoers.d 文件

```bash
# 创建配置文件
sudo bash -c 'echo "deploy  ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/deploy'

# 设置正确的权限
sudo chmod 440 /etc/sudoers.d/deploy
```

## 三、添加 deploy 用户到 docker 组

为了允许 `deploy` 用户执行 docker 命令而不需要 sudo：

```bash
# 将 deploy 用户添加到 docker 组
sudo usermod -aG docker deploy

# 重启 docker 服务（某些系统可能需要）
sudo systemctl restart docker
```

## 四、创建部署目录并设置权限

```bash
# 创建部署目录
sudo mkdir -p /data/docker-proxy/prod

# 设置目录所有者为 deploy 用户
sudo chown -R deploy:deploy /data/docker-proxy/prod

# 设置适当的权限
sudo chmod -R 755 /data/docker-proxy/prod
```

## 五、配置 SSH 密钥认证（可选但推荐）

为了实现无密码 SSH 登录，设置 SSH 密钥认证：

### 在本地机器上：

```bash
# 生成 SSH 密钥对（如果尚未生成）
ssh-keygen -t ed25519 -C "deploy-key"

# 将公钥复制到 ECS 实例
ssh-copy-id deploy@your-ecs-instance-ip
```

### 在 ECS 实例上：

```bash
# 确保 SSH 配置正确
mkdir -p ~/.ssh
chmod 700 ~/.ssh

# 确保 authorized_keys 文件存在且权限正确
chmod 600 ~/.ssh/authorized_keys
```

## 六、环境变量设置

在部署前，确保设置了必要的环境变量：

```bash
# 在本地机器上设置环境变量
export ECS_HOST="your-ecs-instance-ip"
export ECS_USER="deploy"

# 可选：如果使用 GitHub Actions，设置仓库信息
export GITHUB_REPOSITORY="your-username/docker-proxy"
export GITHUB_SHA="main"
```

## 七、执行简化版部署

使用新创建的简化部署脚本：

```bash
# 授予脚本执行权限
chmod +x scripts/deploy-to-ecs-simple.sh

# 执行部署
./scripts/deploy-to-ecs-simple.sh -e prod
```

## 八、故障排除

### 1. 权限被拒绝错误

如果遇到 `Permission denied` 错误：
- 确认 deploy 用户在正确的组中
- 验证目录权限是否正确
- 检查 sudoers 配置是否生效（可通过 `sudo -l` 命令验证）

### 2. Docker 命令失败

如果 Docker 命令失败：
- 确保 deploy 用户在 docker 组中
- 尝试重新登录以刷新组权限
- 检查 Docker 服务是否正在运行

### 3. 免密码 sudo 不工作

如果免密码 sudo 不工作：
- 检查 sudoers 文件中的语法是否正确
- 确保没有其他 sudoers 配置覆盖了您的设置
- 尝试重启 SSH 会话

## 九、安全建议

如果您对给予完全的 NOPASSWD 权限有安全顾虑，可以限制 deploy 用户只能执行特定命令：

```bash
deploy  ALL=(ALL) NOPASSWD: /usr/bin/docker, /usr/bin/docker-compose, /bin/mkdir, /bin/rm, /bin/cp, /usr/bin/git
```

这样可以限制 deploy 用户只能使用部署所需的特定命令，提高安全性。

## 十、完整的一键设置脚本（仅供参考）

以下是一个完整的设置脚本示例（请根据实际情况调整）：

```bash
#!/bin/bash
# 以 root 用户执行此脚本

# 创建 deploy 用户
useradd -m -s /bin/bash deploy

# 设置部署用户密码
echo "deploy:your_secure_password" | chpasswd

# 配置免密码 sudo
echo "deploy  ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/deploy
chmod 440 /etc/sudoers.d/deploy

# 添加到 docker 组
usermod -aG docker deploy

# 创建部署目录
mkdir -p /data/docker-proxy/prod
chown -R deploy:deploy /data/docker-proxy/prod
chmod -R 755 /data/docker-proxy/prod

# 创建 .ssh 目录
mkdir -p /home/deploy/.ssh
chmod 700 /home/deploy/.ssh

# 重启 Docker 服务
systemctl restart docker

echo "✅ 部署用户和权限设置完成!"
```

---

通过以上步骤，您应该能够成功设置部署所需的权限，并使用简化版部署脚本顺利部署 Docker Proxy 服务。