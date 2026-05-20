# NvlabKimodoQuickServer（中文说明）

这是 Kimodo Bridge Server 的 Windows 离线启动方案（新管线）：
- `setup.bat`（仅环境）
- `download_model.bat`（模型下载/更新）
- `run_server.bat` / `start_server.bat`（启动服务）
- `test\test_run_server_tpose.bat`（冒烟测试）

历史脚本已归档到 `obstacle\`。

## 快速开始

在 `C:\nvlab\NvlabKimodoQuickServer` 下执行：

```bat
setup.bat --output console
start_server.bat --model Kimodo-SOMA-RP-v1 --output console
```

或直接测试：

```bat
test\test_run_server_tpose.bat
```

## 脚本职责

### `setup.bat`

单线程环境构建，仅处理运行环境：
1. 准备 Python 与 `.venv`
2. 安装依赖
3. 运行导入检查
4. 写入 `.setup_new_complete`

参数：
- `--output console|file`
- `--log <path>`
- `--force`

### `download_model.bat`

单线程模型下载与更新。

参数：
- `--model <name>`：指定 Kimodo 模型（支持别名 `soma`/`g1`/`smplx` 等）
- `--highvram`：启用全量文本编码器模式
- 默认（不加 `--highvram`）：使用 `KIMODO-Meta3_llm2vec_NF4`
- `--unlock-stale`：旋转陈旧 git lock
- `--force`：即使文件存在也强制同步
- `--output console|file`
- `--log <path>`

高显存相关仓库：
- `Meta-Llama-3-8B-Instruct`：`https://www.modelscope.cn/models/LLM-Research/Meta-Llama-3-8B-Instruct`
- `LLM2Vec-Meta-Llama-3-8B-Instruct-mntp-supervised`：`https://www.modelscope.cn/models/oneyoungmean/LLM2Vec-Meta-Llama-3-8B-Instruct-mntp-supervised`

### `run_server.bat` / `start_server.bat`

`start_server.bat` 是 `run_server.bat` 的入口封装。

执行流程：
1. 若未 setup，则先跑 `setup.bat`
2. 调用 `download_model.bat`（按 `--model` / `--highvram`）
3. 启动 `kimodo.bridge.bridge_server`

重复启动策略：
- 参数相同且已有服务：直接退出（复用）
- 参数变化：先发送 `quit` 关闭旧服务，再重建并启动

### `test\test_run_server_tpose.bat`

测试流程：
1. 启动 `start_server.bat`
2. 等待 `serverport`
3. 发送 `ping -> generate(tpose) -> quit`
4. 收到 `status=done` 判定成功

超时：
- 需要 setup/下载时：`1800s`
- 已就绪时：`60s`
- 可用 `KIMODO_TEST_WAIT_TIMEOUT_SEC` 覆盖

## 说明

- `download_model.bat` 会先检查 `git` 与 `git lfs`。
- Windows 下若缺失，会在项目 `tools\` 目录自动准备便携版（仅当前脚本上下文注入 PATH，不修改系统/用户全局 PATH）。
- Linux 环境不会自动安装便携 git；若 Linux 缺少 git/git-lfs，请先用系统包管理器安装。
