---
name: hybrid-dev
description: 用于由 Sol 负责协调、Luna 负责默认执行，并按需调用已配置的 Claude Code 或 OpenCode 的多代理编码任务。用户提出混合执行或要求明确文件所有权的并行编码时触发。
---
# codex-hybrid:managed

# 混合开发（Hybrid Dev）

将本技能作为 Codex CLI 主控的 Sol–Luna–Claude Code/OpenCode 协作契约。Provider、订阅、API Key 和模型切换由用户在各 CLI 中自行管理；本技能不要求写入或修改任何 Provider 配置。

## 必需的任务简报

向执行代理派发任务前，先写出包含以下内容的简明任务简报：

- 目标和验收条件；
- owned_files（执行代理唯一可以修改的文件）；
- read_only_files（可以查看的上下文文件）；
- 验证命令和预期证据；
- 升级汇报条件。

两个执行代理不得同时拥有同一个文件。共享接口由 Sol 在执行代理返回结果后统一修改。

## 路由规则

- Sol（gpt-5.6-sol）负责需求理解、拆解、任务契约、调度、整合、最终评审，以及停止/升级汇报决策。
- Luna（gpt-5.6-luna）是默认执行代理，负责边界明确的实现、测试、文档和低风险重构。
- Claude Code 是可选的外部执行代理。需要时由 Sol 在当前项目目录手动调用 `claude`；它使用用户已经配置好的模型和订阅。
- OpenCode 是可选的外部执行代理。需要时由 Sol 在当前项目目录手动调用 `opencode`；它使用用户已经配置好的模型和订阅。
- GLM 不作为 Codex Provider 的安装前提。GLM 可以通过 Claude Code 或 OpenCode 的现有配置使用。
- 密钥不得出现在提示词、日志、提交记录或执行代理负责的文件中。

## 默认调度顺序

1. Sol 先判断任务边界、风险和文件所有权。
2. 默认把可独立完成的小任务交给 Luna。
3. 只有需要更大主体实现或用户明确指定时，才调用 Claude Code 或 OpenCode。
4. 外部 CLI 返回后，Sol 必须重新读取 diff，并独立运行验证；外部 CLI 的“完成”不等于验收通过。

可选外部调用示例（命令和模型由用户自行调整）：

```powershell
claude -p "按任务简报实现；只修改 owned_files；完成后报告验证结果。"
opencode run --dir "$PWD" "按任务简报实现；只修改 owned_files；完成后报告验证结果。"
```

如果当前环境不能安全地非交互调用外部 CLI，Sol 应报告命令和任务简报，让用户手动运行；不得假设订阅或 Provider 可用。

## 状态机

在任务记录中使用以下状态：

PRECHECK -> PLAN -> DISPATCH -> EXECUTE -> INTEGRATE -> REVIEW -> REPAIR -> DONE

REPAIR 最多执行三次。如果第三次修复后仍不满足验收条件，必须附上失败证据，将任务标记为 ESCALATE，并提出最小的待决策事项。

## 执行代理结果契约

每个执行代理必须返回：

1. 已完成工作的摘要；
2. 修改的文件；
3. 验证命令和结果；
4. 已知风险或缺口；
5. 建议的交接事项。

执行代理发现超出范围的改动时，必须停止并报告，不得继续修改相邻文件。

## 安全默认策略

默认只启用 Sol 和 Luna。只有任务独立、外部服务提供商已配置且允许发送相关仓库上下文时，才加入 GLM。验证安装变更时，优先使用 --dry-run 和隔离的 CODEX_HOME。
