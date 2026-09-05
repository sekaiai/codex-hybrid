# Codex Hybrid（Codex 混合协作）

Sol、Luna 和 GLM 的本地协作配置包。

## 功能简介

- Sol 负责理解需求、拆分任务、分配执行代理、整合结果和最终评审。
- Luna 负责探索、测试、文档和边界清晰的小型修改。
- GLM 负责跨文件主体实现、完整功能和较大重构。
- `hybrid-dev` 技能固化任务简报、文件所有权、验证和返修规则。
- 安装器负责服务提供商配置、密钥保护、备份、冲突检测和可恢复卸载。

默认使用：

- Sol：`gpt-5.6-sol`
- Luna：`gpt-5.6-luna`
- GLM：`glm-5.2`

## 快速开始

在 macOS 上执行：

~~~sh
export ZAI_API_KEY='你的 ZAI Coding Plan 密钥'
bash ./install.sh --set-default
codex --profile sol-luna
~~~

详细参数、使用场景、卸载和故障处理请阅读[使用帮助](docs/使用帮助.md)。

## 重要说明

安装器默认不修改当前 `config.toml` 的主模型，只通过 `--set-default` 创建 Sol 配置档案。GLM 模型可以使用 `GLM_MODEL` 或 `--glm-model` 覆盖。

模型目录默认不注入；只有确认目录与本机 Codex 版本兼容时，才通过 `--catalog-path` 显式启用。

当前实现已完成离线配置验证，但 GLM 真实网络请求需要单独确认，不能仅凭配置解析成功认定服务可用。
