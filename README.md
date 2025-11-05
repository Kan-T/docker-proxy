# Docker-Shadowsocks代理服务

基于Docker和Shadowsocks-libev的网络代理服务，提供安全、高效的国际网络访问能力。

## 功能特性

- 🔒 **安全加密**: 使用现代加密算法保护数据传输
- 🚀 **高性能**: 基于Shadowsocks-libev，资源占用少，连接速度快
- 📱 **多平台支持**: 兼容所有主流Shadowsocks客户端
- 🐳 **容器化部署**: 基于Docker，部署简单，环境一致性好
- 🔄 **TCP/UDP支持**: 同时支持TCP和UDP协议
- 📊 **详细日志**: 提供可配置的日志级别，便于问题排查
- 🌐 **自动健康检查**: 内置健康检查机制，确保服务稳定性
- ⚙️ **灵活配置**: 支持通过环境变量自定义所有关键参数

## 项目结构

```
docker-proxy/
├── config/                      # 配置文件目录
│   └── shadowsocks.json.template # Shadowsocks配置模板
├── Dockerfile                   # Docker构建文件
├── docker-compose.yml           # Docker Compose配置
├── .env.example                 # 环境变量示例文件
└── .env                         # 环境变量配置文件
```

## 快速开始

### 1. 克隆项目

```bash
git clone <repository-url>
cd docker-proxy
```

### 2. 配置环境变量

复制环境变量示例文件并根据需要修改：

```bash
cp .env.example .env
# 编辑.env文件，设置您的配置，特别是修改默认密码
```

### 3. 构建和运行

使用Docker Compose构建和启动服务：

```bash
docker-compose up -d --build
```

### 4. 验证服务

使用Docker Compose命令检查服务状态：

```bash
docker-compose ps
# 查看容器日志
docker-compose logs shadowsocks-proxy
```

## 环境变量配置

| 变量名 | 描述 | 默认值 | 示例 |
|-------|------|-------|------|
| `SERVER_PORT` | Shadowsocks服务端口 | 8388 | 443 |
| `PASSWORD` | 连接密码 | 必须设置 | SecureP@ss123 |
| `METHOD` | 加密方式 | aes-256-gcm | chacha20-ietf-poly1305 |

## 客户端配置

### 支持的客户端

- **Windows**: Shadowsocks-Windows, Clash
- **macOS**: ShadowsocksX-NG, ClashX
- **Android**: Shadowsocks, Clash for Android
- **iOS**: Shadowrocket, Potatso Lite
- **Linux**: Shadowsocks-qt5, Clash

### 配置示例

| 配置项 | 值 |
|-------|------|
| 服务器地址 | 您的服务器IP地址 |
| 服务器端口 | 8388 (或您在.env中设置的值) |
| 密码 | SecurePassword2024 (或您在.env中设置的值) |
| 加密方式 | aes-256-gcm (或您在.env中设置的值) |
| 代理端口 | 本地客户端端口，如1080 |

### Android客户端配置

#### 1. 安装Shadowsocks Android客户端

1. 在Google Play商店搜索并安装"Shadowsocks"应用（开发者：Max Lv）
2. 或者从[Shadowsocks Android GitHub](https://github.com/shadowsocks/shadowsocks-android/releases)下载APK文件手动安装

#### 2. 配置Shadowsocks客户端

1. 打开Shadowsocks应用
2. 点击右下角的"+"按钮
3. 选择"手动设置"
4. 填写以下信息：
   - 配置名称：可自定义（如"Docker-Proxy"）
   - 服务器：您的服务器IP地址或域名
   - 服务器端口：8388（或您配置的值）
   - 密码：您设置的密码
   - 加密：aes-256-gcm（或您配置的值）
   - 路由：绕过局域网和中国大陆地址
   - UDP转发：开启
5. 点击右上角的"√"保存配置

#### 3. 连接代理服务

1. 在配置列表中选择刚才创建的配置
2. 点击顶部的连接按钮（飞机图标）
3. 首次连接时，系统会请求VPN权限，点击"确定"或"允许"
4. 连接成功后，飞机图标会变为绿色

### iOS客户端配置

#### 1. 安装Shadowrocket客户端

在App Store搜索并安装"Shadowrocket"应用（需要使用非中国大陆Apple ID登录）

#### 2. 配置Shadowrocket客户端

1. 打开Shadowrocket应用
2. 点击右上角的"+"按钮
3. 选择"手动添加"
4. 填写以下信息：
   - 类型：选择"Shadowsocks"
   - 服务器：您的服务器IP地址或域名
   - 端口：8388（或您配置的值）
   - 密码：您设置的密码
   - 加密方式：aes-256-gcm（或您配置的值）
   - 备注：可自定义（如"Docker-Proxy"）
5. 点击右上角的"完成"保存配置

#### 3. 连接代理服务

1. 在配置列表中选择刚才创建的配置
2. 点击应用主界面顶部的开关按钮开启代理
3. 系统会请求VPN权限，点击"允许"
4. 连接成功后，状态栏会显示VPN图标

## 命令行使用示例

使用shadowsocks-libev客户端连接：

```bash
# 安装客户端
brew install shadowsocks-libev  # macOS
apt install shadowsocks-libev   # Ubuntu/Debian

# 启动本地代理
ss-local -s your-server-ip -p 8388 -l 1080 -k "your_password" -m aes-256-gcm

# 使用代理访问网站
curl -x socks5://127.0.0.1:1080 https://www.google.com
```

## 测试

使用以下命令检查服务是否正常运行：

```bash
# 检查容器状态（应显示Up状态和healthy）
docker-compose ps

# 测试端口连接性
nc -zv localhost 8388
```

## 安全注意事项

1. **必须设置密码**: 生产环境中必须设置强密码，避免使用默认值
2. **选择强加密方式**: 推荐使用aes-256-gcm加密算法
3. **使用防火墙**: 仅开放必要的端口，限制访问来源IP以增强安全性
4. **定期更新**: 定期更新Docker镜像以修复安全漏洞

## 故障排除

### 常见问题

1. **无法连接代理服务器**
   - 检查Docker容器是否正在运行: `docker ps`
   - 检查端口映射是否正确
   - 检查防火墙设置和安全组规则

2. **连接被拒绝**
   - 确认密码和加密方式是否正确
   - 检查服务器端口是否开放
   - 查看容器日志获取更多信息

3. **连接速度慢**
   - 检查服务器带宽和负载
   - 尝试使用不同的加密方式
   - 检查网络延迟和路由

### 查看日志

```bash
# 查看容器日志
docker logs shadowsocks-proxy

# 实时查看日志
docker logs -f shadowsocks-proxy
```

## 部署到生产环境

### 阿里云ECS直接构建部署

本项目采用直接在阿里云ECS上构建和部署Docker镜像的方式，通过GitHub Actions实现自动化部署：

1. **ECS环境准备**:
   - 安装Docker、Docker Compose和Git
   - 配置Docker国内镜像源以加速构建
   - 创建部署目录：`/data/docker-proxy/prod`

2. **GitHub Actions自动部署**:
   - 推送代码到`main`分支自动触发部署流程
   - 代码检查和测试通过后，将在ECS上执行部署脚本
   - 部署脚本会自动克隆最新代码并构建运行Docker容器

3. **手动部署（备用）**:

```bash
# 登录ECS实例
ssh user@ecs-instance-ip

# 克隆或更新代码
cd /data/docker-proxy/prod
git pull

# 配置环境变量
cp .env.example .env
# 编辑.env文件设置配置

# 构建并启动服务
docker-compose up -d --build
```

### 安全组配置

确保在ECS安全组中开放相应的代理端口（默认8388），并限制访问来源IP以增强安全性。

### CI/CD详情

详细的GitHub Actions部署流程和配置说明请参考：
- [GitHub Actions部署指南](./docs/github-actions-deployment-guide.md)
- [部署指南](./docs/deployment-guide.md)

## 性能优化

1. **选择合适的加密方式**: 根据服务器CPU性能选择合适的加密算法
2. **调整超时参数**: 根据实际网络环境调整TIMEOUT值
3. **配置DNS缓存**: 使用本地DNS缓存减少查询延迟
4. **资源限制**: 根据服务器配置调整Docker资源限制

## 许可证

[MIT](LICENSE)
