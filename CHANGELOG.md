# 更新日志

## 0.3.0 - 2026-09-05

- 增加 `gpt-glm` 和 `gpt-opencode` 两个一键启动命令。
- 增加独立 OpenCode 配置，显式固定 Z.AI Coding Plan 与实际 GLM 模型。
- 安装器在 OpenCode CLI 缺失时使用官方渠道安装，并支持显式跳过。
- 卸载器回收受管 launcher 和 OpenCode 配置，但保留可复用的 OpenCode CLI。
- 安装写入采用失败回滚事务，避免中途错误留下半安装状态。
- 安装与卸载支持 Linux 和 Windows WSL2，并补充全局安装及完整使用示例。
- `gpt-opencode` 改为 Sol 主控调用 OpenCode worker，与 `gpt-glm` 统一为主控分发、执行后端、主控验证流程。

## 0.2.0 - 2026-09-03

- 将 Sol、Luna、GLM 的角色边界落成 Codex 代理配置。
- 增加 ZAI 命令认证辅助程序、600 权限密钥文件和受管服务提供商配置块。
- 增加幂等安装、冲突拒绝、备份、可恢复卸载和隔离冒烟测试。
- 将 Codex 模型目录改为显式启用，避免跨 CLI 版本的结构误配。
- 增加 GLM_MODEL/--glm-model 覆盖，并记录 Chat Completion 与 Codex Responses 的网络兼容性边界。
