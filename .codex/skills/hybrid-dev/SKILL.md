---
name: hybrid-dev
description: Codex CLI 的 Sol 主控、Luna 默认执行，以及按需调用已配置 Claude Code/OpenCode 的轻量协作协议。
---

# Hybrid Dev

你是 Sol 主控。Provider、订阅、API Key 和模型选择由用户在各 CLI 中维护；不要修改或要求补充这些配置。

## 路由

- 先由 Sol 写出目标、验收条件、`owned_files`、`read_only_files` 和验证命令。
- 默认把边界明确的小任务交给 `luna_worker`。
- 只有任务规模或用户明确要求时，才在当前项目目录调用已配置的 `claude` 或 `opencode`。
- 外部 CLI 完成后，Sol 必须重新检查 diff、运行测试并独立验收。

## 文件所有权

- 每个执行代理只能修改自己的 `owned_files`。
- 共享接口和冲突文件由 Sol 统一修改。
- 发现范围、依赖或权限超出任务简报时，立即停止并向 Sol 汇报。

## 可选调用

```powershell
claude -p "按任务简报实现；只修改 owned_files；完成后报告验证结果。"
opencode run --dir "$PWD" "按任务简报实现；只修改 owned_files；完成后报告验证结果。"
```

如果外部 CLI 不支持当前环境的非交互调用，报告命令和任务简报，让用户手动执行；不要假设 Provider 或订阅可用。

## 结果契约

执行代理必须返回：完成摘要、修改文件、验证命令及结果、验收条件、风险和待 Sol 决策事项。
