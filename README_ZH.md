# NvlabKimodoQuickServer（中文）

这是 Kimodo 的新桥接运行时管线目录，目标是给 AI/工程脚本一个稳定、可自动化的 setup + download + run + test 入口。

## 作用

- 构建并校验运行环境：`bash\setup.bat`
- 下载/更新模型资源：`bash\download_model.bat`
- 按模型与显存模式启动服务：`run_server.bat`
- 通过 TCP 冒烟测试验证链路：`example\example_run_server_tpose.bat`

## 与旧管线差异（表格）

| 对比项 | 新管线（本目录） | 旧管线（归档在 `obstacle\`） |
|---|---|---|
| setup 职责 | 仅环境构建 | 环境与模型流程耦合在一起 |
| 模型下载时机 | 独立 `download_model.bat`，并在 run/start 内自动调用 | 多数在 setup 链路里触发 |
| 重复启动行为 | 记录参数签名：同参复用、异参先 `quit` 再重启 | 缺少等价的签名重启机制 |
| highvram 控制 | `--highvram` 显式参数 | 旧流程偏文件存在性自动判断 |
| git 依赖处理 | Windows 下可本地便携安装 git/git-lfs | 通常要求系统预装 |
| 测试入口 | `example\example_run_server_tpose.bat` | 旧测试脚本已归档 |

## 快速开始

在 `C:\nvlab\NvlabKimodoQuickServer` 执行：

```bat
bash\setup.bat --output console
run_server.bat --model Kimodo-SOMA-RP-v1 --output console
```

测试：

```bat
example\example_run_server_tpose.bat
```

## 入口脚本

- `bash\setup.bat`
- `bash\download_model.bat`
- `run_server.bat`
- `example\example_run_server_tpose.bat`
- `bash\resolve_model_alias.bat`

## 服务协议

桥接服务模块：
- `kimodo.bridge.bridge_server`

传输方式：
- TCP
- 按行 JSON（newline-delimited JSON）

命令：

1. `ping`
```json
{"cmd":"ping"}
```
返回：`pong` / `loading` / `error`

2. `generate`
```json
{
  "cmd":"generate",
  "prompt":"tpose",
  "duration":5.0,
  "seed":42,
  "diffusion_steps":100,
  "constraints_json":""
}
```
成功返回：`done` + `motion_json_compact`

3. `quit`
```json
{"cmd":"quit"}
```
返回：`bye`

常见状态：
- `initializing`
- `loading`
- `ready`
- `progress`
- `pong`
- `done`
- `bye`
- `error`

## 参数与模型切换

### `bash\setup.bat`
- `--output console|file`
- `--log <path>`
- `--force`

### `bash\download_model.bat`
- `--model <name>`
- `--highvram`
- `--unlock-stale`
- `--force`
- `--output console|file`
- `--log <path>`

### `run_server.bat`
- `--model <name>`
- `--highvram`
- `--output console|file`
- `--log <path>`
- `--force-setup`

模型名示例：
- `Kimodo-SOMA-RP-v1`
- `Kimodo-G1-RP-v1`
- `Kimodo-SMPLX-RP-v1`
- `Kimodo-SOMA-SEED-v1`
- `Kimodo-G1-SEED-v1`
- 以及别名：`soma` / `g1` / `smplx` / `soma-seed`

## 服务启动配置行为

`run_server.bat` 会执行：

1. 校验 setup 哨兵 `.setup.complete`
2. 缺失则先跑 setup
3. 按模型/显存模式下载模型
4. 注入本地运行环境变量（`HF_HOME`、offline flags、`CHECKPOINT_DIR`、`KIMODO_ROOT_PATH` 等）
5. 启动 `python -m kimodo.bridge.bridge_server`

重复启动策略：
- 参数签名相同 + `serverport` 存在：直接复用
- 参数签名变化 + `serverport` 存在：先发 `quit` 再重启

## 测试位置与内容

主测试脚本：
- `example\example_run_server_tpose.bat`

验证内容：
- 拉起服务
- 等待 `serverport`
- 发 `ping -> generate(tpose) -> quit`
- 检查是否出现 `status=done`

超时规则：
- 默认：`600s`
- 可用 `KIMODO_TEST_WAIT_TIMEOUT_SEC` 覆盖

## 日志目录

默认日志统一在 `log\`：
- `log\setup.log`
- `log\download_model.log`
- `log\run_server.log`
- `log\example_run_server_tpose.log`
- `log\example_run_server_tpose_client.log`

运行 example 时会在控制台持续打印完整 client 输出，同时写入日志文件，便于快速定位问题。

## 注意事项

- Windows 下 `download_model.bat` 会先检查 `git/git-lfs`，缺失时可在 `tools\` 下准备便携版，不改全局 PATH。
- ModelScope `.../models/...` 地址会自动归一化到可 clone 的 git URL。
- 当前脚本特意保持单线程，优先稳定性。

## 已知问题

- `.sh` 仅是 Windows 包装入口，不是原生 Linux 启动脚本。
- 网络受限时，git clone/lfs pull 可能失败（特别是大模型仓库）。
- 模型目录半残状态可能需要 `--force` 或 `--unlock-stale`。
- 如果旧服务未正常退出，可能需要手动排查 `serverport` 与旧进程状态。



