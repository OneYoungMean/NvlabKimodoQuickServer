@echo off
setlocal EnableExtensions EnableDelayedExpansion

set "INPUT_MODEL=%~1"
set "MODEL_NAME=%INPUT_MODEL%"
if not defined MODEL_NAME (
  echo [ERROR] Empty model name.
  exit /b 1
)

if /I "%MODEL_NAME%"=="soma" set "MODEL_NAME=Kimodo-SOMA-RP-v1"
if /I "%MODEL_NAME%"=="soma-rp" set "MODEL_NAME=Kimodo-SOMA-RP-v1"
if /I "%MODEL_NAME%"=="kimodo-soma-rp" set "MODEL_NAME=Kimodo-SOMA-RP-v1"
if /I "%MODEL_NAME%"=="g1" set "MODEL_NAME=Kimodo-G1-RP-v1"
if /I "%MODEL_NAME%"=="g1-rp" set "MODEL_NAME=Kimodo-G1-RP-v1"
if /I "%MODEL_NAME%"=="kimodo-g1-rp" set "MODEL_NAME=Kimodo-G1-RP-v1"
if /I "%MODEL_NAME%"=="soma-seed" set "MODEL_NAME=Kimodo-SOMA-SEED-v1"
if /I "%MODEL_NAME%"=="kimodo-soma-seed" set "MODEL_NAME=Kimodo-SOMA-SEED-v1"
if /I "%MODEL_NAME%"=="g1-seed" set "MODEL_NAME=Kimodo-G1-SEED-v1"
if /I "%MODEL_NAME%"=="kimodo-g1-seed" set "MODEL_NAME=Kimodo-G1-SEED-v1"
if /I "%MODEL_NAME%"=="smplx" set "MODEL_NAME=Kimodo-SMPLX-RP-v1"
if /I "%MODEL_NAME%"=="smplx-rp" set "MODEL_NAME=Kimodo-SMPLX-RP-v1"
if /I "%MODEL_NAME%"=="kimodo-smplx-rp" set "MODEL_NAME=Kimodo-SMPLX-RP-v1"

if not "%MODEL_NAME:~0,7%"=="Kimodo-" (
  echo [ERROR] Unsupported model alias: %INPUT_MODEL%
  exit /b 1
)

set "MODEL_DIR_NAME=%MODEL_NAME%"
set "MODEL_REPO_NAME=%MODEL_NAME%"
if /I "%MODEL_NAME%"=="Kimodo-SOMA-RP-v1" set "MODEL_REPO_NAME=Kimodo-SOMA-RP-v1.1"

endlocal & (
  set "MODEL_NAME=%MODEL_NAME%"
  set "MODEL_DIR_NAME=%MODEL_DIR_NAME%"
  set "MODEL_REPO_NAME=%MODEL_REPO_NAME%"
)
exit /b 0

