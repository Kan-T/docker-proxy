# GitHub Actions 自动部署流程指南

本文档详细介绍Docker Proxy服务的GitHub Actions自动部署流程，包括工作原理、配置方法和使用说明。

## 1. 自动部署流程概述

GitHub Actions自动部署流程实现了以下功能：

- **代码提交自动触发**：推送代码到main分支时自动启动构建流程
- **质量保障**：包含代码检查和测试步骤
- **生产环境支持**：支持生产环境的自动化部署
- **部署审批**：生产环境部署需要手动审批，确保安全性
- **通知机制**：部署完成后自动发送通知

## 2. 工作流程架构

### 2.1 主要阶段

1. **代码检查和测试**：验证代码质量和功能正确性
2. **环境部署**：根据分支自动部署到相应环境，在ECS上直接构建和部署Docker镜像
3. **部署通知**：发送部署结果通知

### 2.2 触发条件

- `push`事件：推送代码到`main`分支
- `pull_request`事件：创建或更新针对`main`分支的PR

## 3. 环境部署规则

| 分支 | 自动部署到 | 是否需要审批 | 触发条件 |
|------|------------|------------|----------|
| `main` | 生产环境 | 是 | 代码推送 |

## 4. 配置和设置

### 4.1 前提条件

- GitHub仓库已配置
- AWS账号已设置，包含ECS集群和服务
- 已创建必要的IAM角色和权限

### 4.2 GitHub Secrets配置

请参考[GitHub Actions Secrets 配置指南](../.github/github-actions-secrets-guide.md)完成所有必要的密钥配置。

### 4.3 阿里云环境准备

1. **ECS实例准备**：
   - 为生产环境创建ECS实例
   - 安装Docker、Docker Compose和Git
   - 配置安全组，开放必要端口(8388)
   - 创建部署目录：`/data/docker-proxy/prod`

2. **RAM用户权限配置**：
   ```bash
   # 创建RAM用户并授权
   aliyun ram CreateUser --UserName github-actions-deploy --DisplayName "GitHub Actions部署用户"
   aliyun ram CreateAccessKey --UserName github-actions-deploy
   # 仅授予ECS管理权限
   aliyun ram AttachPolicyToUser --PolicyName AliyunECSFullAccess --PolicyType System --UserName github-actions-deploy
   ```

3. **ECS构建环境优化**：
   - 配置Docker国内镜像源以加速构建
   - 确保足够的磁盘空间用于代码仓库和镜像构建

## 5. 部署流程使用说明

### 5.1 生产环境部署

1. 确保代码已在`main`分支上
2. 推送代码到`main`分支，触发GitHub Actions工作流
3. 完成前置步骤后，工作流暂停等待生产部署审批
4. 至少两名审批人登录GitHub审核部署请求
5. 所有审批通过后，自动部署到生产环境
6. 部署完成后发送通知

## 6. 故障排查

### 6.1 常见问题及解决方案

#### 工作流启动失败
- 检查GitHub Secrets是否正确配置
- 验证仓库权限设置
- 查看Actions日志获取详细错误信息

#### 代码克隆失败
- 检查GitHub个人访问令牌(PAT)是否有效
- 验证网络连接和代理设置
- 确保ECS实例可以访问GitHub

#### 镜像构建失败
- 检查Dockerfile语法是否正确
- 验证依赖项是否可用
- 检查ECS实例磁盘空间是否充足
- 查看构建日志中的错误信息

#### 部署超时
- 检查ECS实例状态和网络连接
- 验证容器健康检查设置
- 查看ECS控制台的事件日志

#### 权限错误
- 确认RAM用户权限是否正确配置
- 验证是否有ECS RunCommand权限
- 检查GitHub Secrets配置是否正确

### 6.2 日志查看

1. **GitHub Actions日志**：
   - 访问GitHub仓库 → Actions → 选择具体工作流运行
   - 查看每个步骤的详细日志输出

2. **阿里云日志服务SLS**：
   ```bash
   # 查看容器日志
   aliyun log GetLogStoreLogs --ProjectName docker-proxy-{env} --LogStoreName container-logs
   ```

3. **ECS实例状态**：
   ```bash
   # 查看ECS实例状态
   aliyun ecs DescribeInstances --InstanceIds '["i-xxxxx"]' --RegionId {region}
   
   # 查看容器运行状态
   aliyun ecs RunCommand --InstanceId 'i-xxxxx' --RegionId {region} --CommandContent 'docker ps'
   ```

## 7. 安全最佳实践

1. **最小权限原则**：
   - 为每个环境使用独立的RAM用户
   - 仅授予必要的ECS API权限
   - 定期审查并更新权限设置

2. **部署策略**：
   - 严格执行测试环境验证后再部署生产
   - 生产环境部署必须多人审批
   - 部署前备份关键配置和数据

3. **监控和审计**：
   - 启用阿里云操作审计(ActionTrail)记录所有API调用
   - 配置云监控告警监控ECS实例和容器状态
   - 设置异常部署通知告警

4. **代码安全**：
   - 定期更新依赖包和基础镜像
   - 实施代码审查流程
   - 确保GitHub个人访问令牌(PAT)有适当的权限限制
   - 定期轮换访问凭证

5. **版本管理**：
   - 使用Git标签标记稳定版本
   - 定期清理旧的构建缓存
   - 实施镜像清理策略以节省磁盘空间

## 8. 性能优化

1. **Docker构建优化**：
   - 在ECS上配置Docker层缓存
   - 确保Dockerfile指令顺序合理，最大化缓存利用率
   - 使用国内镜像源加速依赖下载

2. **并行执行**：
   - 合理安排工作流任务依赖，并行执行独立任务
   - 考虑使用矩阵构建优化多环境测试

3. **资源配置**：
   - 根据项目规模调整ECS实例资源配置
   - 优化容器启动时间，减少部署等待时间
   - 为构建过程预留足够的磁盘空间

## 9. 扩展功能

### 9.1 自定义通知渠道

当前通知仅输出到GitHub日志，可扩展以下通知渠道：

#### Slack通知

在`.github/workflows/deploy.yml`的`notify`作业中添加：

```yaml
- name: Slack通知
  if: steps.status.outputs.deployed == 'true'
  uses: rtCamp/action-slack-notify@v2
  env:
    SLACK_WEBHOOK: ${{ secrets.SLACK_WEBHOOK }}
    SLACK_TITLE: 部署通知
    SLACK_MESSAGE: |
      仓库: ${{ github.repository }}
      分支: ${{ github.ref_name }}
      提交: ${{ github.sha }}
      部署状态: 成功
```

#### 邮件通知

```yaml
- name: 邮件通知
  if: steps.status.outputs.deployed == 'true'
  uses: dawidd6/action-send-mail@v3
  with:
    server_address: ${{ secrets.MAIL_SERVER }}
    server_port: 587
    username: ${{ secrets.MAIL_USERNAME }}
    password: ${{ secrets.MAIL_PASSWORD }}
    subject: Docker Proxy部署通知
    body: 部署成功！详见: https://github.com/${{ github.repository }}/actions/runs/${{ github.run_id }}
    to: ${{ secrets.NOTIFY_EMAIL }}
    from: GitHub Actions
```

### 9.2 自动化测试增强

可扩展工作流添加更多自动化测试：

- 单元测试覆盖率报告
- 集成测试
- 端到端测试
- 性能测试

### 9.3 多区域部署

扩展部署脚本支持多区域部署：

```bash
# 在deploy-to-ecs.sh中添加多区域支持
REGIONS=("cn-hangzhou" "cn-shanghai")

for REGION in "${REGIONS[@]}"; do
  echo "部署到区域: $REGION"
  # 执行部署命令，使用当前区域
  aliyun ecs RunCommand \
    --RegionId "$REGION" \
    --InstanceId "$INSTANCE_ID" \
    --CommandContent "cd /data/docker-proxy/{env} && docker-compose pull && docker-compose up -d"
done
```

## 10. 回滚策略

如果部署失败需要回滚，请执行以下步骤：

1. **手动回滚**：
   ```bash
   # 登录到ECS实例执行回滚
   aliyun ecs RunCommand \
     --RegionId {region} \
     --InstanceId "i-xxxxx" \
     --CommandContent "cd /data/docker-proxy/prod && git checkout {previous-commit-hash} && docker-compose down && docker-compose build && docker-compose up -d"
   ```

2. **自动化回滚**：
   可在GitHub Actions工作流中添加回滚步骤，检测到部署失败时自动回滚到上一个稳定版本。

## 11. 维护和升级

1. **定期更新**：
   - 定期更新GitHub Actions依赖版本
   - 升级基础镜像和软件包
   - 更新安全扫描工具和规则

2. **版本管理**：
   - 使用标签标记稳定版本
   - 定期清理过期镜像和资源
   - 保留关键版本的配置和文档

3. **监控维护**：
   - 定期检查监控系统和告警配置
   - 更新日志保留策略
   - 优化资源使用和成本