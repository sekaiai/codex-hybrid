# Sol–Luna–GLM 混合协作方案（可落地版）

> 版本：v0.2（已实施基线）  
> 更新日期：2026-09-03  
> 目标环境：macOS + Codex CLI / IDE 扩展 + 本地 Git 仓库

## 结论先行

把 Codex 的主代理设为 Sol，由 Sol 负责理解需求、分析代码库、拆分任务、分配执行代理、整合结果和最终评审；把明确的小任务交给 Luna，把跨文件主体实现交给 GLM。

~~~text
用户需求
   ↓
Sol（主控：gpt-5.6-sol / xhigh）
   ├─ 需求澄清、代码分析、方案和任务边界
   ├─ 路由与文件所有权分配
   ├─ 结果整合、测试和最终评审
   │
   ├──────────────┬──────────────┐
   ↓              ↓              │
Luna 执行代理   GLM 执行代理       │
小任务/探索/测试  主体编码/跨文件实现  │
   └──────────────┴──────────────┘
                  ↓
        Sol 集成检查 + 最终评审
             ├─ PASS → 完成
             └─ FAIL → 原执行代理修复，最多 3 轮
~~~

这里的“编排”由 Codex 主线程、两个自定义代理和 hybrid-dev 技能共同完成。技能是工作协议和路由规则，不是一个独立的后台调度服务；它不能替代 Sol 的判断，也不能保证执行代理一定正确执行。当前仓库已实现安装、回滚、卸载和离线配置验证；GLM 网络直连仍受“Chat Completion 与 Codex Responses 协议不一致”这一外部兼容性约束，不能在未验证前宣称生产可用。

## 0. 先修正原草案中的关键假设

| 原草案 | v0.2 决策 | 原因 |
| --- | --- | --- |
| GLM 固定为 glm-5.3 | 默认 glm-5.2，通过 GLM_MODEL 或安装参数覆盖 | 当前智谱 Coding Plan 文档列出的可用模型为 glm-5.2、glm-5-Turbo、glm-4.7；不能把未在当前文档确认的 glm-5.3 写死。 |
| https://open.bigmodel.cn/api/v1 + wire_api = responses | 不作为默认直连方案 | 智谱当前 Coding Plan 文档公开的是 OpenAI Chat Completion 专属端点 /api/coding/paas/v4；Codex 自定义服务提供商当前只支持 Responses。两者之间需要 Responses 兼容层，不能把 /api/v1 当作已验证事实。 |
| model_reasoning_effort = max | Codex 配置基线使用 high；安装器先做版本探测 | Codex 配置字段的可移植值以本地 CLI 接受的值为准。智谱原生 API 的 max 是另一层协议参数，不能直接假设能写入 Codex TOML。 |
| 在配置中写 /Users/你的用户名/... | 安装器渲染真实绝对路径，或生成令牌辅助程序 | 占位路径会导致新机器启动时认证失败；auth.command 必须实际输出令牌。 |
| 修改 ~/.codex/config.toml 并覆盖原内容 | 只追加可识别的受管配置块，先备份、原子替换、冲突则中止 | 用户已有的项目信任、MCP、Hook、默认模型和 OMX 配置不能被安装器破坏。 |
| 让两个执行代理随意并行改代码 | 默认串行；只有文件所有权互不重叠时才允许并行写入 | 共享工作目录下并发写同一文件会产生不可审计的覆盖和冲突。 |
| 卸载直接删除 ~/.codex 内容 | 只移除本方案管理的文件；密钥默认移入备份，永久删除必须显式 --purge-secret | 卸载不能影响其他 Codex 配置和用户数据。 |

模型、端点和套餐均属于外部可变项。安装器记录本地 Codex 版本并执行严格配置解析；模型真实可用性和服务提供商网络协议仍必须由显式冒烟测试验证，文档中的默认值不是永久承诺。

## 1. 目标、边界与成功标准

### 1.1 目标

- 新机器通过一条命令完成安装，首次只输入一次智谱 API 密钥。
- Codex CLI 和 IDE 共用同一套用户级代理/技能配置。
- 保留用户已有 config.toml，升级可重复执行，失败可恢复。
- 让 Sol 的路由规则、执行代理的职责、文件所有权、评审和返修次数可审计。
- 不把 API 密钥写入 Git 仓库、命令参数、日志、TOML 或模型目录。
- 安装器可以在隔离的临时 CODEX_HOME 中完成离线配置验证。

### 1.2 非目标

- 不自行实现一个新的代理调度器、队列服务或 IDE 插件。
- 不承诺 GLM 与 OpenAI 模型在所有工具调用、上下文长度和推理参数上完全等价。
- 不用提示词保证并发写入安全；并发安全必须由文件所有权和执行顺序保证。
- 不自动安装 Claude Code、OpenCode 或其他编码工具。
- 不在没有明确策略的情况下，静默把 GLM 任务切换到更贵或行为不同的模型。

### 1.3 完成判定

一次任务只有同时满足以下条件才算完成：

1. Sol 已确认需求、验收条件和任务边界。
2. 每个执行代理都有明确的文件所有权，且没有未解决的共享文件冲突。
3. 执行代理报告了变更文件、测试命令和测试结果。
4. Sol 已亲自检查完整 git diff、未跟踪文件和测试输出。
5. 相关测试、lint、typecheck/build（项目具备时）均通过。
6. Sol 的最终评审明确输出 PASS；最多 3 轮返修不等于自动通过。

## 2. 角色设计与任务路由

### 2.1 角色职责

| 角色 | 默认模型/强度 | 适合的工作 | 不应承担 |
| --- | --- | --- | --- |
| Sol 主控 | gpt-5.6-sol / xhigh | 需求分析、架构决策、风险判断、任务拆分、整合、最终评审 | 把所有机械小任务都亲自执行；未经判断就把高风险任务交给执行代理 |
| Luna 执行代理 | gpt-5.6-luna / medium | 探索、测试补充、文档、单文件机械修改、明确的类型/格式修复 | 数据库迁移、权限/认证、公共 API 变更、核心架构决策 |
| GLM 执行代理 | 默认 glm-5.2 / Codex high | 跨文件主体实现、完整功能、较大重构、前后端联动 | 重新设计 Sol 已确定的架构；修改未授权文件；自行宣布任务通过 |

### 2.2 路由规则

~~~text
需求不清、涉及安全/认证/迁移/公共 API/核心架构
    → Sol 先分析，必要时 Sol 自己完成或先形成明确方案

探索、测试、文档、单文件机械修改、已知根因的简单类型修复
    → Luna 执行代理

跨文件主体编码、完整功能、较大重构、复杂调试后的实现
    → GLM 执行代理

多个相互独立的模块且文件所有权完全不重叠
    → GLM + Luna 可并行

共享入口、共享配置、同一测试文件或同一公共接口
    → 串行执行，由一个代理负责整合
~~~

“文件数量”只能作为参考，不能作为唯一路由条件。一个文件也可能涉及安全、数据一致性或公共 API；这类任务仍由 Sol 先判断。

### 2.3 并发写入协议

- 每个任务开始前，Sol 必须给出 owned_files 和 read_only_files。
- 两个执行代理的 owned_files 交集必须为空，才允许并行写入。
- 共享文件（例如根配置、路由表、公共类型、锁文件、同一测试文件）只能指定一个写入者。
- 默认所有执行代理在同一工作目录工作；需要并行修改同一模块时，改用 Git 工作树或改为串行，不依赖提示词避免冲突。
- 执行代理不得重置、覆盖或清理其他代理的未提交改动。
- Sol 整合前必须重新读取 git status --short 和完整 git diff，不能只相信执行代理的文字摘要。

## 3. 标准执行状态机

~~~text
PRECHECK
   ↓
PLAN（Sol 产出任务简报）
   ↓
DISPATCH（决定 Luna / GLM / Sol）
   ↓
EXECUTE（执行代理按文件所有权工作）
   ↓
INTEGRATE（Sol 检查差异、冲突和测试）
   ↓
REVIEW
  ├─ PASS → DONE
  ├─ FAIL → REPAIR（原执行代理，次数 +1）
  └─ BLOCKED → ESCALATE
                 ↑
          FAIL 达到 3 次也进入 ESCALATE
~~~

### PRECHECK（预检查）

Sol 先确认：

- 当前工作目录、Git 分支和已有脏改动。
- Codex CLI 版本、代理文件是否被发现、Responses 服务提供商是否能解析。
- GLM 模型名称、基础 URL 和 API 密钥是否存在；默认不发送代码内容做网络探测。
- 任务是否涉及外部生产环境、凭据、迁移或不可逆操作。

### PLAN（计划）

Sol 为每个子任务生成任务简报，至少包含目标、上下文、允许修改的文件、禁止修改的文件、验收条件、测试命令、依赖关系和完成报告格式。

### EXECUTE（执行）

执行代理只在被授权的文件范围内工作。完成前必须执行简报中列出的测试；如果测试命令不存在或项目状态阻止测试，必须报告 BLOCKED 或 NOT_RUN，不能写成 PASS。

### INTEGRATE（整合）

Sol 检查：

~~~bash
git status --short
git diff --check
git diff --stat
git diff -- <所有变更文件>
~~~

然后按项目实际情况运行针对性测试、lint、typecheck、build 或冒烟测试。

### REVIEW / REPAIR（评审/修复）

- 评审必须独立于执行代理的实现过程，优先检查行为、边界、回归、权限、错误处理和测试缺口。
- 评审输出至少包含 PASS、FAIL 或 BLOCKED，并按 P0/P1/P2 标记问题。
- FAIL 时只把具体问题交回原执行代理，附上失败证据和验收条件；不让另一个执行代理在同一文件上盲目接管。
- 最多返修 3 轮。第 3 轮仍失败时，任务状态为 ESCALATE，而不是伪装成完成。

## 4. 执行代理通信协议

第一版不强制引入 JSON 调度器，但统一使用下面的文本结构；未来若需要自动统计，可直接把它转成 JSON Schema。

### 4.1 任务简报

~~~text
任务编号：HD-<date>-<number>
角色：luna_worker | glm_worker
目标：一句话说明要交付的结果
上下文：Sol 已确认的背景和约束
owned_files（可修改文件）：
  - path/to/file-a
  - path/to/file-b
read_only_files（只读文件）：
  - path/to/shared-file
禁止修改：
  - 不修改数据库 schema
  - 不新增依赖
验收条件：
  - [ ] 可验证条件 1
  - [ ] 可验证条件 2
命令：
  - npm test -- --runInBand
  - npm run typecheck
依赖：依赖哪些其他任务，或无
停止条件：发现架构冲突、需要扩大文件范围、凭据/生产操作、测试无法运行
报告格式：使用 4.2 的结果格式
~~~

### 4.2 执行代理结果

~~~text
任务编号：...
状态：DONE | BLOCKED | FAILED
摘要：...
变更文件：
  - path/to/file: 做了什么
测试：
  - 命令 → PASS | FAIL | NOT_RUN
检查：
  - lint/typecheck/build → PASS | FAIL | NOT_RUN
验收条件：
  - [x] ...
风险/后续事项：
  - ...
需要 Sol 决策：yes | no
~~~

## 5. hybrid-dev 技能规范

技能放在用户级 $HOME/.agents/skills/hybrid-dev/SKILL.md。Codex 支持通过 $skill-name 显式调用技能，并从用户级 .agents/skills 加载本地技能；修改后若当前会话未刷新，请重启 Codex。

建议的技能内容如下：

~~~markdown
---
name: hybrid-dev
description: 用于由 Sol 负责路由 Luna 和 GLM 执行代理、且需要明确文件所有权、验证和最终评审的软件开发任务。
---

# 混合开发（Hybrid Dev）

你是 Sol 主控。先理解需求和代码库，再决定是否派发执行代理。

## 主控职责

1. 明确目标、约束、验收条件和测试命令。
2. 先检查当前 Git 状态和已有改动。
3. 为每个执行代理指定唯一文件所有权。
4. 将小任务/探索/测试/文档/机械修改派给 luna_worker。
5. 将跨文件主体实现、完整功能和较大重构派给 glm_worker。
6. 只有文件所有权不重叠时才允许并行写入。
7. 所有执行代理返回后，亲自检查完整差异和测试输出。
8. 最终评审必须输出 PASS、FAIL 或 BLOCKED。

## 硬约束

- 不允许两个执行代理同时修改同一文件。
- 执行代理不得扩大文件范围、改变未授权架构或新增未批准依赖。
- 评审不通过时，把问题交还原执行代理；最多返修 3 次。
- 未完成测试、存在 P0/P1 问题或没有最终 PASS 时，不得宣布完成。
- GLM 服务提供商不可用时，默认报告 BLOCKED；只有用户或项目配置明确允许时，才使用安全的 Luna/Sol 回退。
- 涉及密钥、生产环境、迁移、删除或不可逆操作时，先停止并按项目安全规则处理。

## 每个执行代理必须回报

任务编号、状态、变更文件、测试命令及结果、验收条件、风险和需要 Sol 决策的事项。
~~~

技能的描述要保持简短且边界明确，避免让所有普通对话都误触发；实际强制规则应放在正文和项目 AGENTS.md，不要只依赖一句提示词。

## 6. 配置设计

### 6.1 推荐仓库结构

~~~text
codex-hybrid/
├── install.sh
├── uninstall.sh
├── README.md
├── CHANGELOG.md
├── agents/
│   ├── luna-worker.toml
│   └── glm-worker.toml
├── skills/
│   └── hybrid-dev/
│       └── SKILL.md
├── models/
│   ├── glm-5.2.json
│   └── manifest.json
├── lib/
│   ├── common.sh
│   ├── config.sh
│   └── validate.sh
└── tests/
    ├── install-smoke.sh
    ├── rollback-smoke.sh
    ├── uninstall-smoke.sh
    └── workflow-smoke.sh
~~~

models/ 中的 JSON 是本方案的模型配置档案/清单，不冒充跨版本可直接加载的 Codex 模型目录。Codex 的 model_catalog_json 是启动时读取的外部模型目录；当前实现默认不注入模型目录，只有用户显式传入与本地 CLI 匹配的模型目录才启用。

### 6.2 ZAI 服务提供商

安装器向现有 config.toml 追加带标记的受管配置块。下面的路径只是渲染模板，不能原样复制：

~~~toml
# codex-hybrid:begin provider v0.2
[model_providers.zai_coding_plan]
name = "ZAI Coding Plan"
base_url = "https://open.bigmodel.cn/api/coding/paas/v4"
wire_api = "responses"
request_max_retries = 2
stream_idle_timeout_ms = 300000

[model_providers.zai_coding_plan.auth]
command = "/Users/ME/.codex/bin/codex-hybrid-token"
timeout_ms = 5000
refresh_interval_ms = 300000
# codex-hybrid:end provider
~~~

注意：

- auth.command 必须只向 stdout 输出令牌；错误信息写 stderr，不能输出额外日志。
- 不要同时配置 auth、env_key、experimental_bearer_token 和 requires_openai_auth。
- zai_coding_plan 使用独立服务提供商 id，避免覆盖内置 openai、ollama 或 lmstudio。
- 如果检测到同名服务提供商已由用户管理，安装器不得静默覆盖，应显示差异并退出。
- 智谱官方 Coding Plan 当前公开的是 Chat Completion 端点，而 Codex 自定义服务提供商当前使用 Responses；因此本项目的服务提供商配置块只能证明配置语法兼容，不能证明网络协议已兼容。
- 如果运行 `tests/provider-smoke.sh --confirm-network` 返回 404 或协议错误，状态必须记为 BLOCKED；需要新增 Responses 兼容层或等待智谱提供 Responses 端点，不要把失败改写为安装成功。

### 6.3 令牌辅助程序与密钥

~~~text
~/.codex/
├── bin/
│   └── codex-hybrid-token       # 只读密钥并输出到 stdout
├── secrets/
│   └── zai_api_key              # 0600
├── agents/
│   ├── luna-worker.toml
│   └── glm-worker.toml
└── models-glm.json              # 仅当当前 CLI 版本需要时安装
~~~

令牌辅助程序由安装器生成，使用真实绝对路径：

~~~sh
#!/bin/sh
set -eu
exec /bin/cat "/Users/ME/.codex/secrets/zai_api_key"
~~~

目录权限为 0700，密钥文件权限为 0600，辅助程序不包含密钥且权限为 0700 或 0755。第一版采用文件方案，后续可以增加 macOS Keychain 作为可选后端；两种后端必须保持相同的 auth.command 输出契约。

安装输入要求：

- 使用 read -r -s，不把密钥放到命令参数、环境变量、shell history 或临时文件名中。
- 用 printf '%s' 写入，避免额外换行。
- 终端回显关闭后读取，完成后清空 shell 变量。
- 安装日志只记录服务提供商、模型、CLI 版本和文件路径，不记录密钥、请求头或完整错误响应。
- 默认不把密钥发送到任何校验服务；服务提供商冒烟测试需要用户显式执行。

### 6.4 Luna 执行代理

~~~toml
name = "luna_worker"
description = "执行范围明确的小型开发任务、探索、测试、文档和机械性修改。"
model = "gpt-5.6-luna"
model_reasoning_effort = "medium"
sandbox_mode = "workspace-write"

developer_instructions = """
你是 Luna 执行型代理。

严格执行父代理的任务简报，只修改 owned_files，不扩大范围，不重做总体架构。
优先完成小而明确的修改、探索、测试和文档工作。
完成前运行任务简报中的测试；测试不能运行时明确报告 NOT_RUN 或 BLOCKED。
不要修改其他执行代理的文件，不要重置或覆盖已有未提交改动。

最终必须报告：任务编号、状态、修改文件、测试命令及结果、验收条件、风险和需要父代理决策的事项。
"""
~~~

### 6.5 GLM 执行代理

~~~toml
name = "glm_worker"
description = "负责跨文件主体实现、完整功能、复杂调试后的修复和较大重构。"
model_provider = "zai_coding_plan"
model = "glm-5.2"
model_reasoning_effort = "high"
# 可选：仅传入与本地 Codex 版本匹配、已验证的模型目录
# model_catalog_json = "/Users/ME/.codex/models-glm.json"
sandbox_mode = "workspace-write"

developer_instructions = """
你是 GLM 主体实现代理。

严格按照父代理已确认的任务简报编码，只修改 owned_files。
先读取相关代码和现有模式，再做最小、可验证的实现。
禁止擅自改变核心架构、扩大需求、修改未授权文件或新增未批准依赖。
完成实现后运行测试、lint、typecheck 或 build（以项目实际存在的命令为准），并修复自己引入的问题。
如果发现任务简报与代码现实冲突、需要共享文件或需要改变架构，先报告 BLOCKED，不要自行越界。

最终必须报告：任务编号、状态、修改文件、实现内容、测试命令及结果、验收条件、风险和需要父代理决策的事项。
"""
~~~

model_reasoning_effort 的最终允许值必须由安装器针对本地 Codex 版本验证。high 是本方案的兼容基线；如果某个版本的 GLM 模型目录明确支持其他值，应在版本化模型目录和测试中单独记录，不要直接把智谱原生 API 的 max 填入所有 Codex 配置。

### 6.6 Sol 主控设置

Sol 不必额外创建执行代理 TOML。安装器提供两种模式：

1. 默认模式：不改用户当前主模型，只安装服务提供商、执行代理和技能；用户通过 Codex 的模型选择使用 Sol。
2. 显式模式：用户传入 --set-default 后，生成独立的 `sol-luna.config.toml` 配置档案；不重复写入主 `config.toml` 的顶层 model 键：

   ~~~toml
   model = "gpt-5.6-sol"
model_reasoning_effort = "xhigh"
   ~~~

默认模式更安全，因为它不会把用户现有的默认模型、OMX 配置或项目行为静默改掉。启动配置档案使用 `codex --profile sol-luna`。

## 7. 安装器行为

### 7.1 命令接口

~~~bash
# 推荐：先下载后审阅
curl -fsSLO https://raw.githubusercontent.com/ACCOUNT/codex-hybrid/main/install.sh
bash ./install.sh --version v0.2.0

# 一键安装
curl -fsSL https://raw.githubusercontent.com/ACCOUNT/codex-hybrid/v0.2.0/install.sh | bash -s -- --version v0.2.0

# 只检查，不写入
bash ./install.sh --dry-run

# 明确允许把 Sol 设为主模型
bash ./install.sh --set-default

# 可选：覆盖 GLM 执行代理模型
bash ./install.sh --glm-model glm-4.7

# 卸载受管内容；默认保留可恢复备份
bash ./uninstall.sh

# 明确永久删除备份中的 API 密钥
bash ./uninstall.sh --purge-secret
~~~

生产使用时优先采用“下载后审阅”，一键 curl | bash 只适用于用户已经信任的固定 tag。仓库应提供发布校验和或签名，README 中记录如何校验。

### 7.2 安装顺序

1. 检查 macOS、Bash、Codex CLI、CLI 版本范围和必要目录。
2. 读取参数；没有已有密钥时才静默读取一次 API 密钥。
3. 检测现有配置、代理、技能、服务提供商冲突和文件权限。
4. 创建时间戳备份目录：~/.codex/backups/codex-hybrid/<timestamp>/。
5. 在临时目录渲染服务提供商配置块、代理、技能、辅助程序和模型目录。
6. 运行离线 TOML/JSON/代理发现验证。
7. 通过验证后，使用临时文件 + mv 原子写入；不使用跨平台不兼容的 sed -i 原地修改。
8. 对密钥和目录设置权限，清理临时文件和内存变量。
9. 输出安装摘要：版本、CLI 版本、模型、服务提供商、安装文件、备份路径和未执行的网络冒烟测试。

任何一步失败都应停止后续写入，并保留可恢复备份。因为写入采用原子替换，安装器不应在失败时用不确定的模式覆盖用户原配置。

### 7.3 幂等升级与冲突

- 服务提供商配置块、代理和技能都使用版本标识或校验和。
- 重复安装同一版本不产生重复 TOML table、重复代理或重复配置块。
- 升级只替换本方案上一版本管理的内容；用户手动修改过的受管文件先备份并提示，不静默覆盖。
- config.toml 中已有 zai_coding_plan 且不是本方案管理的内容时，默认退出并要求显式处理。
- 用户已有同名技能或代理时，不覆盖；使用唯一名称、报告冲突，或提供显式 --force，且 --force 也必须先备份。
- 使用 mkdir 锁或等价机制防止两个安装器同时修改同一套配置。

### 7.4 卸载规则

- 只移除带本方案标记、且校验和与受管版本匹配的服务提供商配置块、代理、技能和辅助程序。
- 受管文件发生用户修改时，不直接删除，移到备份目录并报告。
- 默认移除激活配置，但把 zai_api_key 移到带权限保护的备份目录；永久删除仅由 --purge-secret 触发。
- 绝不删除整个 ~/.codex、用户的其他代理、MCP、Hook、项目配置或会话数据库。

## 8. 验证与测试计划

安装器完成的判定不是“文件存在”，而是以下验证全部通过。

### 8.1 安装器离线测试

每个测试都在临时 CODEX_HOME 中运行，不触碰真实用户配置；本项目目录本身不要求是 Git 仓库：

- 首次安装：空目录生成服务提供商、两个代理、技能、辅助程序和权限正确的密钥。
- 重复安装：文件内容稳定，没有重复 TOML table 或重复配置块。
- 已有配置：原有模型、MCP、Hook、项目配置和注释仍保留。
- 冲突服务提供商：检测到同名非受管服务提供商后安全退出。
- 升级：只替换受管配置块和受管文件，用户未管理内容不变。
- 回滚：注入无效 TOML/JSON 或模拟 mv 失败，原配置校验和保持不变。
- 卸载：只移除受管内容；用户修改过的文件被保留并提示。
- 密钥审计：仓库、日志、进程参数、临时目录中找不到真实密钥。

### 8.2 Codex 兼容性测试

按实际安装的 Codex CLI 版本执行：

~~~bash
codex --version
codex --strict-config --help
codex features
~~~

然后在隔离 CODEX_HOME 中验证：

- config.toml 能被当前 CLI 解析。
- auth.command 可执行且 stdout 只有令牌。
- 两个自定义代理能被 Codex 发现，字段包含正确的 model、服务提供商、reasoning effort 和 sandbox mode。
- 如果显式传入 model_catalog_json，其结构必须与该 CLI 版本兼容；默认安装不注入模型目录，以免让主配置进入半可用状态。
- 当前 Codex 版本能解析 gpt-5.6-sol、gpt-5.6-luna、glm-5.2 和配置中的 effort 值；模型真实服务可用性仍由网络冒烟测试单独判定。

### 8.3 服务提供商冒烟测试

网络测试不在默认安装流程中自动执行。用户完成安装后，显式运行单独命令：

~~~bash
bash ./tests/provider-smoke.sh --confirm-network --model glm-5.2
~~~

该测试只发送最小的无敏感请求（例如要求返回 OK），不读取或上传当前仓库文件。验证内容：HTTP 成功、Responses 响应可解析、工具/流式行为符合 Codex 需要、错误信息不会泄露密钥。

如果智谱套餐、网络、模型或账号不满足条件，结果为 BLOCKED，不能改写成安装成功。

### 8.4 协作协议测试

用固定样例测试技能/README 中的协议：

- 模糊需求不会直接派给执行代理。
- 小任务路由到 Luna，主体跨文件实现路由到 GLM。
- 同一文件的两个任务被串行化或拒绝并行。
- 执行代理未执行测试时结果不会被判定为 PASS。
- 评审 FAIL 会回到原执行代理，最多 3 次后变为 ESCALATE。
- 任意 P0/P1 未关闭时无法进入 DONE。

## 9. 实施阶段

### 阶段 0：先做兼容性探针

文件：tests/、models/manifest.json、lib/validate.sh

- 固定支持的 macOS 和 Codex CLI 最低版本。
- 记录代理 TOML、服务提供商、auth.command、Responses 和模型目录的真实兼容性。
- 产出至少一个可通过离线验证的 GLM 模型目录固定样例。

### 阶段 1：实现安全安装骨架

文件：install.sh、uninstall.sh、lib/common.sh、lib/config.sh

- 参数解析、锁、备份、受管配置块、原子写入、冲突检测、权限设置和错误退出。
- 先只安装服务提供商/辅助程序，不改变默认主模型。

### 阶段 2：加入代理与技能

文件：agents/luna-worker.toml、agents/glm-worker.toml、skills/hybrid-dev/SKILL.md

- 写入职责、文件所有权、报告格式、评审门槛和回退规则。
- 用隔离 CODEX_HOME 验证发现和启动。

### 阶段 3：加入模型目录与服务提供商冒烟测试

文件：models/、tests/provider-smoke.sh、README.md

- 根据 Codex 版本选择模型目录。
- 用真实 GLM 账号执行一次最小网络测试；不把网络测试放进普通安装。

### 阶段 4：完成回归与发布

文件：tests/install-smoke.sh、tests/rollback-smoke.sh、CHANGELOG.md

- 覆盖首次安装、重复安装、升级、冲突、回滚、卸载和密钥审计。
- 发布固定 tag、校验和、变更日志和兼容矩阵。

## 10. 风险与缓解

| 风险 | 影响 | 缓解 |
| --- | --- | --- |
| 智谱模型名或套餐额度变化 | GLM 执行代理无法启动或成本突增 | 模型可配置；安装前探测；README 记录验证日期和兼容矩阵。 |
| Responses 兼容层不完整 | 工具调用、流式输出或上下文行为异常 | 服务提供商冒烟测试覆盖最小响应、流式和工具调用；失败时标记 BLOCKED。 |
| Codex CLI 升级改变模型目录结构 | 代理启动失败 | 模型目录按 CLI 版本管理；严格解析；没有固定样例就中止安装。 |
| config.toml 合并错误 | 用户所有 Codex 设置不可用 | 只改受管配置块；写入前备份；临时文件校验；原子替换；回滚测试。 |
| API 密钥泄露 | 账号和额度风险 | 文件 0600、辅助程序输出隔离、日志脱敏、不自动上传、不把密钥写入 TOML/argv。 |
| 执行代理并发覆盖文件 | 代码丢失、差异不可审计 | 文件所有权交集检查；默认串行；必要时使用 Git 工作树。 |
| 执行代理误判完成 | 缺陷进入最终结果 | 结果格式 + Sol 亲自检查差异 + 针对性测试 + 最终评审 PASS。 |
| GLM 不可用时静默降级 | 成本、质量和行为不可预期 | 默认严格回退，明确输出 BLOCKED；回退需配置授权。 |
| 一键远程脚本被替换 | 安装供应链风险 | 固定发布 tag、校验和/签名、推荐先下载审阅；不要默认拉取 main。 |

## 11. 架构决策记录（ADR）

### 决策

采用“Sol 主控 + Luna 小任务 + GLM 主体实现 + Sol 最终评审”的本地 Codex 自定义代理方案；通过用户级 .agents/skills/hybrid-dev 固化协作协议，通过受管服务提供商配置块预留智谱接入，但 Chat Completion 到 Codex Responses 的网络兼容性必须单独验证。

### 决策依据

- Sol 负责高质量规划和最终责任闭环。
- Luna 适合低延迟、低成本、明确的小任务。
- GLM 承担长链路主体编码，减少 Sol 在机械实现上的上下文消耗。
- 安装、升级、回滚和密钥安全必须可审计。

### 已考虑的替代方案

- 直接使用 npx @z_ai/coding-helper：它适合配置智谱工具接入，但不负责本方案的 Sol → 执行代理 → 评审编排。
- 让两个模型都直接修改同一工作目录：吞吐看似更高，但无法可靠解决共享文件覆盖和整合责任问题。
- 把 API 密钥直接写入 config.toml：实现简单，但会扩大备份、日志和误提交的泄露面。
- 强制安装器覆盖全局默认模型：操作简单，但会破坏用户已有配置，因此改为默认保留、--set-default 显式启用。

### 选择原因

该方案把“模型选择”“任务路由”“文件所有权”“验证”和“安装安全”分开，任何一层失败都可以明确阻断，而不是依赖一条过长的提示词或不可恢复的全局覆盖。

### 影响

- 需要维护 Codex CLI 版本与模型目录兼容矩阵。
- 并行写入受文件所有权限制，部分任务会串行执行。
- 最终质量仍依赖 Sol 的判断和项目测试，不能仅凭模型名称保证。
- 安装器实现比单纯写几个 TOML 文件复杂，但升级和回滚风险显著降低。

### 后续事项

1. 已完成当前 Codex CLI 0.146.0 的隔离安装、严格配置解析、幂等、冲突回滚、卸载恢复和协议固定样例验证；真实服务提供商冒烟测试未执行。
2. 先确认智谱是否提供 Codex 所需的 Responses 端点；若仍只有 Chat Completion，增加并单独验证 Responses 兼容层。
3. 确认智谱当前 Coding Plan 账号可用的模型列表和工具调用兼容性。
4. 决定是否加入 macOS Keychain 后端，并为模型目录和安装器建立发布版本矩阵。
5. 若未来需要高并发写入，再引入工作树/补丁产物，而不是放宽共享目录写入规则。

## 12. 官方资料与验证日期

以下链接在 2026-09-03 重新核对；模型、套餐、端点和 CLI 行为仍应以安装时官方文档及本地冒烟测试为准。

- [OpenAI 文档：子代理/自定义代理](https://developers.openai.com/codex/subagents)：用户级 ~/.codex/agents/、项目级 .codex/agents/、自定义模型和 model_reasoning_effort。
- [OpenAI 文档：构建技能](https://developers.openai.com/codex/skills)：技能的 $skill-name 调用方式、用户级 $HOME/.agents/skills 路径和变更刷新行为。
- [OpenAI 文档：配置参考](https://developers.openai.com/codex/config-reference)：model_provider、auth.command、model_catalog_json、wire_api 和服务提供商配置约束。
- [智谱 AI：GLM Coding Plan 快速开始](https://docs.bigmodel.cn/cn/coding-plan/quick-start)：当前公开的 Chat Completion 接入端点、支持工具和 API 密钥使用说明。
- [智谱 AI：GLM Coding Plan 相关兼容性问题](https://github.com/zai-org/GLM-5/issues/39)：Codex 直接请求 `/responses` 曾出现 404；在 Responses 兼容层或官方端点确认前，服务提供商冒烟测试结果应保留为 BLOCKED。
- [智谱 AI：GLM Coding Plan 套餐概览](https://docs.bigmodel.cn/cn/coding-plan/overview)：当前套餐模型、额度和使用范围。
- [智谱 AI：GLM-5.2](https://docs.bigmodel.cn/cn/guide/models/text/glm-5.2)：模型能力、上下文和原生 API 的推理参数说明。
