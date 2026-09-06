# Codex Hybrid

用 Codex CLI 的 Sol 做主控，用 Luna 和用户已经配置好的外部 CLI 执行子任务：

| 命令 | 主控 | 子任务后端 | 适合场景 |
| --- | --- | --- | --- |
| 推荐手动模式 | `gpt-5.6-sol` | `luna_worker`，按需调用 Claude Code/OpenCode | 不接管已有订阅和 Provider 配置 |
| 兼容安装模式 | `gpt-glm` | `glm_worker`（Z.AI GLM） | 保留旧版自动安装和 Provider 管理 |
| 兼容安装模式 | `gpt-opencode` | OpenCode CLI | 保留旧版独立 OpenCode 配置 |

两条命令的流程相同，只有子任务后端不同：

```text
用户任务 -> Codex Sol 分析/拆分 -> 执行后端修改 -> Sol 检查/测试/整合
```

默认模型：Sol `gpt-5.6-sol`、Luna `gpt-5.6-luna`。GLM 模型由 Claude Code/OpenCode 的现有配置决定。

## 推荐：手动协作模式

如果 Codex CLI、Claude Code 和 OpenCode 已经安装并完成登录，推荐直接使用项目中的 Skill 和 Agent 模板，不运行 `install.sh`，也不让本项目接管 Provider、订阅或 API Key。

协作关系：

```text
Codex CLI / Sol 主控
  -> 默认交给 Luna 执行边界明确的任务
  -> 需要时手动调用 claude 或 opencode
  -> Sol 重新检查 diff、运行测试并验收
```

相关文件：

- `skills/hybrid-dev/SKILL.md`：Sol 的路由、文件所有权和验收协议；
- `agents/sol.toml`：Sol 主控定义；
- `agents/luna-worker.toml`：Luna 默认执行代理定义。

外部 CLI 的模型和订阅由你自行切换。例如在 Sol 的任务简报确认后执行：

```powershell
claude -p "按任务简报实现；只修改 owned_files；完成后报告验证结果。"
opencode run --dir "$PWD" "按任务简报实现；只修改 owned_files；完成后报告验证结果。"
```

如果你希望让 Codex 自动识别这套协议，可以把 `skills/hybrid-dev` 安装到自己的 Codex skills 目录，并把两个 Agent 模板复制到 Codex 的 agents 目录；不需要填写 GLM Key。

## 1. 环境要求

- 推荐手动模式支持 Codex CLI、Claude Code 和 OpenCode 能正常运行的 Windows/macOS/Linux 环境；Windows 不强制要求 WSL。
- 已安装并登录 Codex CLI。
- Claude Code/OpenCode 的登录和模型配置由用户自行维护。

下面的 `install.sh` 是旧版兼容安装路径，仍要求 Bash、`git`、`rg`，Windows 通常需要 WSL2。

OpenCode CLI 不必预先安装；安装器会自动安装。若本机还没有 Codex CLI：

```bash
curl -fsSL https://chatgpt.com/codex/install.sh | sh
codex
```

首次运行 `codex` 时完成登录，然后继续安装本项目。

## 2. 安装

### macOS / Linux

```bash
git clone https://github.com/sekaiai/codex-hybrid.git
cd codex-hybrid
bash ./install.sh
```

安装器会隐藏读取 Z.AI API Key，并生成两个全局命令。

非交互安装：

```bash
ZAI_API_KEY='你的密钥' bash ./install.sh
```

### Windows 10/11（WSL2）

管理员 PowerShell 执行一次：

```powershell
wsl --install
```

重启后进入 Ubuntu/WSL：

```bash
sudo apt update
sudo apt install -y git ripgrep curl
curl -fsSL https://chatgpt.com/codex/install.sh | sh
codex
git clone https://github.com/sekaiai/codex-hybrid.git
cd codex-hybrid
bash ./install.sh
```

Windows 项目路径需要使用 WSL 路径：

```bash
cd /mnt/c/Users/你的用户名/path/to/project
gpt-glm "检查并修复测试"
gpt-opencode "把主体实现交给 OpenCode worker，并由 Sol 验证"
```

### 命令找不到

安装器优先写入 `codex` 所在的可写目录；否则写入 `$HOME/.local/bin`。找不到命令时执行：

```bash
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc
source ~/.zshrc
```

Bash 将 `~/.zshrc` 换成 `~/.bashrc`。也可以安装时指定目录：

```bash
CODEX_HYBRID_BIN_DIR="$HOME/.local/bin" bash ./install.sh
```

## 3. 使用

先进入目标项目目录，再运行其中一个命令：

```bash
cd /path/to/project
gpt-glm "任务描述"
gpt-opencode "任务描述"
```

### 使用 GLM 后端

```bash
# Sol 拆分任务，GLM 实现主体，Luna 做测试和文档
gpt-glm "实现订单导出；让 glm_worker 负责主体代码，luna_worker 负责测试和文档，最后统一验证"

# 跨文件重构
gpt-glm "重构支付模块，保持外部 API 不变，补齐回归测试"

# 只分析，不修改
gpt-glm "分析认证流程和安全风险，不修改文件"
```

### 使用 OpenCode 后端

```bash
# Sol 拆分任务，OpenCode 实现主体，Sol 最后验证
gpt-opencode "实现用户搜索，把主体实现交给 OpenCode worker，返回后运行测试并检查 diff"

# 限定 OpenCode 的文件范围
gpt-opencode "阅读 SPEC.md，只允许修改 src/search.ts 和 tests/search.test.ts，交给 OpenCode worker 实现"

# 让 OpenCode 做第二意见
gpt-opencode "让 OpenCode worker 审查当前改动，只报告高风险问题，Sol 汇总结论"
```

注意：`gpt-opencode` 不是直接把用户任务交给 OpenCode。它先启动 Codex Sol，再由 Sol 按任务简报调用 OpenCode worker；OpenCode 不负责最终整合和验收。

## 4. 配置 GLM

### 修改模型

默认模型是 `glm-5.2`。重新安装即可切换：

```bash
bash ./install.sh --glm-model glm-4.7
```

或：

```bash
GLM_MODEL=glm-4.7 bash ./install.sh
```

更新密钥和模型：

```bash
ZAI_API_KEY='新密钥' bash ./install.sh --glm-model glm-5.2
```

### 配置位置

`CODEX_HOME` 未设置时，默认目录是 `~/.codex`：

| 文件 | 作用 |
| --- | --- |
| `~/.codex/sol-luna.config.toml` | `gpt-glm` 的 Sol profile |
| `~/.codex/sol-opencode.config.toml` | `gpt-opencode` 的 Sol profile |
| `~/.codex/agents/glm_worker.toml` | GLM worker 模型和执行规则 |
| `~/.codex/agents/luna_worker.toml` | Luna worker 执行规则 |
| `~/.codex/secrets/zai_api_key` | Z.AI 密钥，权限为 `600` |

查看 GLM 当前配置：

```bash
rg 'model|model_provider' "${CODEX_HOME:-$HOME/.codex}/agents/glm_worker.toml"
```

## 5. 配置 OpenCode

### 安装 OpenCode

安装器默认自动安装，顺序为 Homebrew、npm、OpenCode 官方安装脚本。已有 OpenCode 或不希望自动安装时：

```bash
bash ./install.sh --skip-opencode-install
```

也可以手动安装：

```bash
brew install anomalyco/tap/opencode
# 或
npm install -g opencode-ai@latest
```

### 实际模型配置

配置文件：

```text
${CODEX_HOME:-$HOME/.codex}/opencode/opencode.json
```

安装器生成的核心配置如下，模型名随 `--glm-model` 更新：

```json
{
  "$schema": "https://opencode.ai/config.json",
  "enabled_providers": ["zai-coding-plan"],
  "disabled_providers": [],
  "model": "zai-coding-plan/glm-5.2",
  "provider": {
    "zai-coding-plan": {
      "options": {
        "apiKey": "{env:ZHIPU_API_KEY}"
      }
    }
  }
}
```

`gpt-opencode` 使用独立的 `sol-opencode` profile，并通过受管 worker 执行：

```text
Codex Sol -> codex-hybrid-opencode-worker -> opencode run --model zai-coding-plan/glm-5.2
```

Sol profile 为嵌套 OpenCode 调用开启工作区写入和网络访问，但仍受 Codex 审批策略和工作区边界约束。

检查配置和模型列表：

```bash
cat "${CODEX_HOME:-$HOME/.codex}/opencode/opencode.json"
opencode models zai-coding-plan --refresh
```

## 6. 更新与卸载

更新：

```bash
cd codex-hybrid
git pull
bash ./install.sh
```

卸载本项目管理的配置和命令：

```bash
cd codex-hybrid
bash ./uninstall.sh
```

自定义过命令目录时，卸载使用同一变量：

```bash
CODEX_HYBRID_BIN_DIR="$HOME/.local/bin" bash ./uninstall.sh
```

卸载不会删除共享的 Codex CLI、OpenCode CLI 或备份文件。密钥默认移入备份；永久删除当前密钥：

```bash
bash ./uninstall.sh --purge-secret
```

## 7. 验证与故障排查

检查命令：

```bash
command -v gpt-glm
command -v gpt-opencode
gpt-glm --version
opencode --version
```

离线测试：

```bash
bash ./tests/install-smoke.sh
bash ./tests/launcher-smoke.sh
bash ./tests/transaction-smoke.sh
bash ./tests/uninstall-smoke.sh
```

真实 GLM 网络测试会产生一次模型请求，需显式确认：

```bash
bash ./tests/provider-smoke.sh --confirm-network --model glm-5.2
```

常见问题：

- `gpt-glm: command not found`：把 `$HOME/.local/bin` 加入 `PATH`，然后重新打开终端。
- `gpt-opencode` 提示 CLI 未安装：安装 OpenCode，或去掉 `--skip-opencode-install` 后重新运行安装器。
- OpenCode 请求失败：检查 `~/.codex/secrets/zai_api_key`、网络和 Z.AI Coding Plan 权限。
- 配置冲突：先备份冲突文件，再明确使用 `bash ./install.sh --force`。

更多说明见[使用帮助](docs/使用帮助.md)。

官方文档：[Codex CLI](https://developers.openai.com/codex/cli)、[Codex 配置](https://developers.openai.com/codex/config-reference)、[Windows/WSL](https://developers.openai.com/codex/windows)、[OpenCode CLI](https://opencode.ai/docs/cli/)、[OpenCode 配置](https://opencode.ai/docs/config/)、[Z.AI Provider](https://opencode.ai/docs/providers/#zai)。
