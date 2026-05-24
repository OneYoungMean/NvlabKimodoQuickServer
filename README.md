# NvlabKimodoQuickServer

## Language
- Chinese: `README_ZH.md`
- English: `README.md`

## Features
- Build runtime environment with `uv` pipeline.
- Start Kimodo bridge server with model options.
- Run TCP example flow (`ping -> generate -> quit`).

## Requirements
- Windows 10/11 x64
- Local tools under `program\exe\`:
  - `uv\uv.exe`
  - `git\cmd\git.exe`
  - `git\mingw32\bin\git-lfs.exe`
- Model root available (recommended): `C:\nvlab\models~`

## Install
```bat
cd /d C:\nvlab\NvlabKimodoQuickServer
bash\setup.bat --output console
```

## Example
```bat
cd /d C:\nvlab\NvlabKimodoQuickServer
run_server.bat --model Kimodo-SOMA-RP-v1 --models-root C:\nvlab\models~ --output console
```

TCP smoke test:
```bat
example\example_run_server_tpose.bat
```

Live console variant:
```bat
example\example_run_server_tpose_console_live.bat
```

## Parameters
- See `PARAMETERS.md`
