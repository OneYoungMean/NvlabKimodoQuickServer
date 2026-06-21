# NvlabKimodoQuickServer 参数说明

## 1. `run_server.bat setup` / `run_server.sh setup`
- `--output <console|file>`: 输出模式，默认 `console`。
- `--log <path>`: `file` 模式下日志文件路径，默认 `log\setup.log`。
- `--force`: 强制重新 setup（会归档旧 sentinel）。

## 2. `run_server.bat` / `run_server.sh`
- `--model <name|alias>`: 默认 `Kimodo-SOMA-RP-v1`。
- `--highvram`: 启用 high-vram 模式。
- `--models-root <path>`: 指定模型根目录；bridge 启动时会在这里检查并按需下载模型。
- `--output <console|file>`: 输出模式，默认 `console`。
- `--log <path>`: `file` 模式下主日志路径，默认 `log\bridge_server.log`。
- `bridge_server` 主日志固定为 `log\bridge_server.log`。
- `--force-setup`: 归档 setup sentinel 后重新 setup。

关键运行变量：
- `KIMODO_MODELS_ROOT`: 默认 models 根目录（可被 `--models-root` 覆盖）。
- `KIMODO_IDLE_TIMEOUT_SEC`: 服务空闲退出秒数（当前设定 `600`）。

### 启动与 watchdog
- `KIMODO_WATCHDOG_STARTUP_INTERVAL_SEC`: 启动阶段等待 `serverport` 的轮询间隔（默认 `1` 秒）。
- `KIMODO_WATCHDOG_STARTUP_MAX_FAILS`: 启动阶段等待 `serverport` 的最大轮询次数（默认 `180`）。
- `KIMODO_WATCHDOG_RUNTIME_INTERVAL_SEC`: 运行阶段检查 `log\bridge_server.log` 更新时间间隔（默认 `1` 秒）。
- `KIMODO_WATCHDOG_IDLE_NOLOG_MAX`: 运行阶段日志未更新的最大连续次数（默认 `300`），超过则自动关闭进程。

说明：
- 默认启动等待窗口约 `180s`（`1s * 180`）。
- 不做 `serverport` 回填、不做 TCP 探活；`serverport` 仅由 bridge server 写入。
- `run_server.bat setup` / `run_server.sh setup` 都是同一条 Python 入口的子命令，用于单独执行 setup。
- 模型准备链路已收敛到 `bridge_server`：启动后按 `模型类型 -> 本地存在检查 -> 下载 -> load_model()` 执行。
- 下载进度会持续写入 `log\\bridge_server.log`，这样 watchdog 在下载期间也能看到活跃日志。

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
