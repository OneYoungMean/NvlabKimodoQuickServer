# NvlabKimodoQuickServer 参数说明

## 1. `run_server.bat setup`
- `--output <console|file>`: 输出模式，默认 `console`。
- `--log <path>`: `file` 模式下日志文件路径，默认 `log\setup.log`。
- `--force`: 强制重新 setup（会归档旧 sentinel）。

## 2. `run_server.bat`
- `--model <name|alias>`: 默认 `Kimodo-SOMA-RP-v1`。
- `--highvram`: 启用 high-vram 模式。
- `--models-root <path>`: 指定外部模型根目录（存在即跳过下载流程）。
- `--output <console|file>`: 输出模式，默认 `console`。
- `--log <path>`: `file` 模式下主日志路径，默认 `log\bridge_server.log`。
- `--cpu-text-encoder <int8>`: CPU / 低显存路径使用的文本编码器，默认 `int8`。`gguf` 已废弃并会直接报错。
- `bridge_server` 主日志固定为 `log\bridge_server.log`。
- `--force-setup`: 归档 setup sentinel 后重新 setup。

关键运行变量：
- `KIMODO_MODELS_ROOT`: 默认 models 根目录（可被 `--models-root` 覆盖）。
- `KIMODO_CPU_TEXT_ENCODER=int8`: 指定 CPU 文本编码器路线，当前仅支持 `int8`。
- `KIMODO_IDLE_TIMEOUT_SEC`: 服务空闲退出秒数（当前设定 `600`）。

INT8 资产说明：
- 默认低显存文本编码器目录为 `models\KIMODO-Meta3_llm2vec_INT8`。
- 若本地已有 `C:\nvlab\LLMVec-GGUF\KIMODO-Meta3_llm2vec_FP16`，可先执行 `tools\build_llm2vec_int8.py` 生成 INT8 资产。
- 对默认 `models\` 目录：若缺少 INT8 资产，会尝试从 `oneyoungmean/KIMODO-Meta3_llm2vec_INT8` 下载。
- 对外部 `--models-root`：不会自动下载，缺失时直接报错。

### 启动与 watchdog
- `KIMODO_WATCHDOG_STARTUP_INTERVAL_SEC`: 启动阶段等待 `serverport` 的轮询间隔（默认 `1` 秒）。
- `KIMODO_WATCHDOG_STARTUP_MAX_FAILS`: 启动阶段等待 `serverport` 的最大轮询次数（默认 `180`）。
- `KIMODO_WATCHDOG_RUNTIME_INTERVAL_SEC`: 运行阶段检查 `log\bridge_server.log` 更新时间间隔（默认 `1` 秒）。
- `KIMODO_WATCHDOG_IDLE_NOLOG_MAX`: 运行阶段日志未更新的最大连续次数（默认 `300`），超过则自动关闭进程。

说明：
- 默认启动等待窗口约 `180s`（`1s * 180`）。
- 不做 `serverport` 回填、不做 TCP 探活；`serverport` 仅由 bridge server 写入。
- `run_server.bat setup` 也是同一条 Python 入口的子命令，用于单独执行 setup。

## 3. `example\example_run_server_tpose.bat`
- 默认流程：后台启动 `run_server` -> 读取 `serverport` -> 发送 `ping/generate(tpose)/quit`。
- 通过判定：客户端退出码 `0` 且出现 `status=done`。

相关环境变量：
- `KIMODO_TEST_OUTPUT=console|file`（默认 `console`）
- `KIMODO_TEST_WAIT_TIMEOUT_SEC`（默认 `600`）
- `KIMODO_TEST_MODEL`
- `KIMODO_TEST_HIGHVRAM=0|1`
- `KIMODO_TEST_MODELS_ROOT=<path>`
- `KIMODO_TEST_SERVER_WINDOW_STYLE=Normal|Hidden|Minimized|Maximized`

## 4. 日志约定
- 默认所有日志写入 `log\`。
- 典型文件：
  - `log\setup.log`
  - `log\bridge_server.log`（run/bridge 主日志）
  - `log\watchdog.log`
  - `log\example_run_server_tpose.log`
  - `log\example_run_server_tpose_client.log`
