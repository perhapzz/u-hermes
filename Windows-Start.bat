@echo off
setlocal EnableDelayedExpansion
chcp 65001 >nul 2>&1
title U-Hermes - Portable AI Agent

REM ============================================================
REM   U-Hermes - all-in-one launcher (Windows)
REM   - First run: downloads Python + installs deps into portable\app\
REM   - Subsequent runs: launches directly
REM ============================================================

REM ---- Path layout ----
set "UHERMES_DIR=%~dp0portable\"
if not exist "%UHERMES_DIR%" (
    echo   [ERROR] portable\ directory not found next to this launcher.
    echo   Expected: %UHERMES_DIR%
    pause
    exit /b 1
)
set "APP_DIR=%UHERMES_DIR%app"
set "RUNTIME_DIR=%APP_DIR%\runtime"
set "PACKAGES_DIR=%APP_DIR%\packages"
set "WEBUI_DIR=%UHERMES_DIR%webui"
set "DATA_DIR=%UHERMES_DIR%data"
set "HERMES_HOME=%DATA_DIR%\.hermes"
set "PYTHON_DIR=%RUNTIME_DIR%\python-win-x64"
set "PYTHON_BIN=%PYTHON_DIR%\python.exe"
set "GIT_DIR=%RUNTIME_DIR%\git-win-x64"
set "GIT_BASH=%GIT_DIR%\bin\bash.exe"

set "PYTHON_TAG=20260510"
set "PYTHON_VERSION=3.11.15"
set "PYTHON_EMBED_VERSION=3.11.9"
set "PYTHON_RELEASE_PATH=astral-sh/python-build-standalone/releases/download/%PYTHON_TAG%"
set "PIP_MIRROR=https://pypi.tuna.tsinghua.edu.cn/simple"

echo.
echo   ========================================
echo     U-Hermes v0.1 - Portable AI Agent
echo   ========================================
echo.

REM ---- Decide: setup needed? ----
set "NEED_SETUP=0"
if not exist "%PYTHON_BIN%" set "NEED_SETUP=1"
if not exist "%GIT_BASH%" set "NEED_SETUP=1"
if "%NEED_SETUP%"=="0" (
    "%PYTHON_BIN%" -c "import sys; sys.path.insert(0,r'%PACKAGES_DIR%'); import run_agent" >nul 2>&1
    if errorlevel 1 set "NEED_SETUP=1"
)

if "%NEED_SETUP%"=="1" (
    call :do_setup
    if errorlevel 1 (
        echo.
        echo   [ERROR] Setup failed.
        pause
        exit /b 1
    )
)

call :do_launch
exit /b

REM ============================================================
REM :do_setup -- first-time download + install
REM ============================================================
:do_setup
echo   [SETUP] First-time setup detected. This will take a few minutes.
echo.

REM ---- Detect China network ----
set "IN_CHINA=false"
curl -s --max-time 3 -o nul "https://pypi.tuna.tsinghua.edu.cn/" >nul 2>&1
if errorlevel 1 goto china_done
curl -s --max-time 3 -o nul "https://github.com/" >nul 2>&1
if errorlevel 1 set "IN_CHINA=true"
:china_done

if "%IN_CHINA%"=="true" (
    echo   Network: China ^(using mirrors^)
) else (
    echo   Network: Direct
)
echo.

set "PIP_INDEX="
if "%IN_CHINA%"=="true" set "PIP_INDEX=-i %PIP_MIRROR%"

REM ---- 1. Download Python (Windows x64) ----
if exist "%PYTHON_BIN%" (
    echo   [OK] Python already exists
    goto python_done
)

echo   [DOWNLOAD] Downloading Python %PYTHON_EMBED_VERSION% ^(embeddable^)...
if not exist "%PYTHON_DIR%" mkdir "%PYTHON_DIR%" 2>nul

set "PY_EMBED_FILE=python-%PYTHON_EMBED_VERSION%-embed-amd64.zip"
set "TMP_ZIP=%TEMP%\uhermes-python-%RANDOM%.zip"

echo     Trying npmmirror.com...
curl.exe -fSL --max-time 60 "https://registry.npmmirror.com/-/binary/python/%PYTHON_EMBED_VERSION%/%PY_EMBED_FILE%" -o "%TMP_ZIP%"
if not errorlevel 1 goto embed_download_ok

echo     Trying huaweicloud mirror...
curl.exe -fSL --max-time 60 "https://mirrors.huaweicloud.com/python/%PYTHON_EMBED_VERSION%/%PY_EMBED_FILE%" -o "%TMP_ZIP%"
if not errorlevel 1 goto embed_download_ok

echo     Trying python.org...
curl.exe -fSL --max-time 120 "https://www.python.org/ftp/python/%PYTHON_EMBED_VERSION%/%PY_EMBED_FILE%" -o "%TMP_ZIP%"
if not errorlevel 1 goto embed_download_ok

echo     Embeddable download failed, trying GitHub standalone...
del /f /q "%TMP_ZIP%" 2>nul
goto try_github_mirrors

:embed_download_ok
echo     Extracting...
tar -xf "%TMP_ZIP%" -C "%PYTHON_DIR%"
del /f /q "%TMP_ZIP%" 2>nul
if not exist "%PYTHON_BIN%" goto try_github_mirrors

REM Enable site-packages in embeddable Python
set "PTH_FILE="
for %%f in ("%PYTHON_DIR%\python*._pth") do set "PTH_FILE=%%f"
if defined PTH_FILE (
    powershell -NoProfile -Command "(Get-Content '%PTH_FILE%') -replace '^#import site','import site' | Set-Content '%PTH_FILE%'"
)

echo     Installing pip...
curl.exe -fSL --max-time 60 "https://bootstrap.pypa.io/get-pip.py" -o "%PYTHON_DIR%\get-pip.py" 2>nul
if errorlevel 1 (
    curl.exe -fSL --max-time 60 "https://mirrors.aliyun.com/pypi/get-pip.py" -o "%PYTHON_DIR%\get-pip.py" 2>nul
)
if exist "%PYTHON_DIR%\get-pip.py" (
    "%PYTHON_BIN%" "%PYTHON_DIR%\get-pip.py" --no-warn-script-location -q %PIP_INDEX%
    del /f /q "%PYTHON_DIR%\get-pip.py" 2>nul
)
"%PYTHON_BIN%" -m pip install setuptools wheel --no-warn-script-location -q %PIP_INDEX%
echo   [OK] Python downloaded from mirror
goto python_done

:try_github_mirrors
echo     Trying GitHub standalone build...
set "PY_FILENAME=cpython-%PYTHON_VERSION%+%PYTHON_TAG%-x86_64-pc-windows-msvc-install_only_stripped.tar.gz"
set "PY_RELEASE=%PYTHON_RELEASE_PATH%/%PY_FILENAME%"
set "TMP_FILE=%TEMP%\uhermes-python-%RANDOM%.tar.gz"

if not "%IN_CHINA%"=="true" goto download_direct

echo     Trying ghfast.top mirror...
curl.exe -fSL --max-time 60 "https://ghfast.top/https://github.com/%PY_RELEASE%" -o "%TMP_FILE%" >nul 2>&1
if not errorlevel 1 goto download_ok

echo     Trying gh-proxy.com mirror...
curl.exe -fSL --max-time 60 "https://gh-proxy.com/https://github.com/%PY_RELEASE%" -o "%TMP_FILE%" >nul 2>&1
if not errorlevel 1 goto download_ok

:download_direct
echo     Direct download ^(may be slow^)...
curl.exe -fSL --max-time 1800 --retry 3 --retry-delay 5 -C - "https://github.com/%PY_RELEASE%" -o "%TMP_FILE%"
if errorlevel 1 (
    echo   [ERROR] Python download failed. Manual URL:
    echo     https://github.com/%PY_RELEASE%
    exit /b 1
)

:download_ok
tar -xzf "%TMP_FILE%" -C "%PYTHON_DIR%"
del /f /q "%TMP_FILE%" 2>nul
if not exist "%PYTHON_BIN%" (
    if exist "%PYTHON_DIR%\python\python.exe" (
        xcopy /s /e /q /y "%PYTHON_DIR%\python\*" "%PYTHON_DIR%\" >nul
        rmdir /s /q "%PYTHON_DIR%\python" 2>nul
    )
)
if not exist "%PYTHON_BIN%" (
    echo   [ERROR] Python extraction failed
    exit /b 1
)
echo   [OK] Python downloaded

:python_done

REM ---- Ensure ._pth has packages and agent paths (relative for portability) ----
set "PTH_FILE="
for %%f in ("%PYTHON_DIR%\python*._pth") do set "PTH_FILE=%%f"
if defined PTH_FILE (
    findstr /C:"packages" "%PTH_FILE%" >nul 2>&1
    if errorlevel 1 (
        echo ..\..\packages>>"%PTH_FILE%"
        echo ..\..\..\agent>>"%PTH_FILE%"
        echo ..\..\..\webui>>"%PTH_FILE%"
    )
)

REM ---- Ensure setuptools available ----
"%PYTHON_BIN%" -c "import setuptools" >nul 2>&1
if errorlevel 1 (
    "%PYTHON_BIN%" -m pip install setuptools wheel --no-warn-script-location -q %PIP_INDEX%
)

REM ---- 2. Install hermes-agent ----
"%PYTHON_BIN%" -c "import sys; sys.path.insert(0,r'%PACKAGES_DIR%'); import run_agent" >nul 2>&1
if not errorlevel 1 goto agent_done

echo   [INSTALL] Installing hermes-agent from portable\agent (with PyPI deps)...
if not exist "%PACKAGES_DIR%" mkdir "%PACKAGES_DIR%" 2>nul
"%PYTHON_BIN%" -m pip install "%UHERMES_DIR%agent" ^
    --target "%PACKAGES_DIR%" --no-user --disable-pip-version-check --quiet %PIP_INDEX%
if errorlevel 1 (
    echo   [ERROR] hermes-agent install failed
    exit /b 1
)
echo   [OK] hermes-agent installed
:agent_done

REM ---- 3. Install webui dependencies ----
set "WEBUI_REQS=%UHERMES_DIR%webui\requirements.txt"
if exist "%WEBUI_REQS%" (
    echo   [INSTALL] Installing webui PyPI dependencies...
    "%PYTHON_BIN%" -m pip install -r "%WEBUI_REQS%" ^
        --target "%PACKAGES_DIR%" --no-user --disable-pip-version-check --quiet %PIP_INDEX%
    echo   [OK] webui deps installed
)

REM ---- 4. Install PortableGit (provides bash/grep/find/git for agent tools) ----
if exist "%GIT_BASH%" goto git_done

echo   [DOWNLOAD] Downloading PortableGit ^(~58 MB, bundled bash/grep/git for agent^)...
set "PG_VER=2.46.0"
set "PG_TAG=v2.46.0.windows.1"
set "PG_FILE=PortableGit-%PG_VER%-64-bit.7z.exe"
set "PG_PATH=git-for-windows/git/releases/download/%PG_TAG%/%PG_FILE%"
set "TMP_PG=%TEMP%\uhermes-pg-%RANDOM%.7z.exe"

if not "%IN_CHINA%"=="true" goto pg_direct

echo     Trying gh-proxy.com mirror...
curl.exe -fSL --max-time 600 "https://gh-proxy.com/https://github.com/%PG_PATH%" -o "%TMP_PG%"
if not errorlevel 1 goto pg_ok

echo     Trying github.moeyy.xyz mirror...
curl.exe -fSL --max-time 600 "https://github.moeyy.xyz/https://github.com/%PG_PATH%" -o "%TMP_PG%"
if not errorlevel 1 goto pg_ok

echo     Trying ghfast.top mirror...
curl.exe -fSL --max-time 600 "https://ghfast.top/https://github.com/%PG_PATH%" -o "%TMP_PG%"
if not errorlevel 1 goto pg_ok

:pg_direct
echo     Direct download ^(may be slow^)...
curl.exe -fSL --max-time 1800 --retry 3 --retry-delay 5 -C - "https://github.com/%PG_PATH%" -o "%TMP_PG%"
if errorlevel 1 (
    echo   [WARN] PortableGit download failed. Agent shell tools will not work.
    echo          Install Git for Windows manually: https://git-scm.com/download/win
    goto git_done
)

:pg_ok
if not exist "%GIT_DIR%" mkdir "%GIT_DIR%" 2>nul
echo     Extracting...
"%TMP_PG%" -o"%GIT_DIR%" -y >nul
del /f /q "%TMP_PG%" 2>nul
if exist "%GIT_BASH%" (
    echo   [OK] PortableGit installed
) else (
    echo   [WARN] PortableGit extraction failed
)

:git_done

echo.
echo   [OK] Setup complete. Starting U-Hermes...
echo.
exit /b 0

REM ============================================================
REM :do_launch -- run the webui server
REM ============================================================
:do_launch
if not exist "%WEBUI_DIR%\server.py" (
    echo   [ERROR] webui not found
    pause
    exit /b 1
)

for /f "tokens=*" %%v in ('"%PYTHON_BIN%" --version') do set PYTHON_VER=%%v
echo   Python: %PYTHON_VER%
echo.

REM ---- Init data directories ----
if not exist "%HERMES_HOME%" mkdir "%HERMES_HOME%" 2>nul
if not exist "%DATA_DIR%\logs" mkdir "%DATA_DIR%\logs" 2>nul

REM ---- Detect drive-letter / path change since last run ----
set "PATH_MARKER=%HERMES_HOME%\.last_path"
set "LAST_PATH="
if exist "%PATH_MARKER%" set /p LAST_PATH=<"%PATH_MARKER%"
if defined LAST_PATH if /i not "%LAST_PATH%"=="%UHERMES_DIR%" (
    echo   [INFO] USB path changed since last run:
    echo          old: %LAST_PATH%
    echo          new: %UHERMES_DIR%
    echo   Archiving old state to data\.hermes.bak ...
    if exist "%DATA_DIR%\.hermes.bak" rmdir /s /q "%DATA_DIR%\.hermes.bak" 2>nul
    move /y "%HERMES_HOME%" "%DATA_DIR%\.hermes.bak" >nul 2>&1
    mkdir "%HERMES_HOME%" 2>nul
    echo   [OK] Fresh state directory created.
    echo.
)
>"%PATH_MARKER%" echo %UHERMES_DIR%

REM ---- Bootstrap API key (device fingerprint) ----
echo   Binding device fingerprint...
"%PYTHON_BIN%" "%UHERMES_DIR%lib\bootstrap-api.py" "%HERMES_HOME%" 2>nul
echo.

REM ---- Environment (portable mode) ----
set "HERMES_HOME=%HERMES_HOME%"
set "HERMES_WEBUI_STATE_DIR=%HERMES_HOME%\webui"
set "HERMES_WEBUI_HOST=127.0.0.1"
set "HERMES_WEBUI_AGENT_DIR=%UHERMES_DIR%agent"
set "HERMES_WEBUI_PYTHON=%PYTHON_BIN%"
set "HERMES_DISABLE_LAZY_INSTALLS=1"

REM ---- Portable Git: tell hermes where bash is, and put Unix tools on PATH ----
REM    Without this, agent shell tools fail (no bash, no grep/find/curl/git).
if exist "%GIT_BASH%" (
    set "HERMES_GIT_BASH_PATH=%GIT_BASH%"
    set "PATH=%GIT_DIR%\bin;%GIT_DIR%\usr\bin;%GIT_DIR%\mingw64\bin;%PATH%"
)

set "HERMES_WEBUI_DEFAULT_WORKSPACE=%UHERMES_DIR%workspace"
if not exist "%HERMES_WEBUI_DEFAULT_WORKSPACE%" mkdir "%HERMES_WEBUI_DEFAULT_WORKSPACE%" 2>nul
set "HERMES_WEBUI_PORT=8787"

REM ---- Auto-launch messaging gateway in a separate window if configured ----
REM Triggered by FEISHU_APP_ID in .env. The gateway loads .env itself via
REM hermes_cli.env_loader, so we only need to pass HERMES_HOME + PYTHONPATH.
set "_GATEWAY_NEEDED=0"
if exist "%HERMES_HOME%\.env" (
    findstr /b /c:"FEISHU_APP_ID=" "%HERMES_HOME%\.env" >nul 2>&1
    if not errorlevel 1 set "_GATEWAY_NEEDED=1"
)
if "%_GATEWAY_NEEDED%"=="1" (
    echo   Starting messaging gateway in background ^(log: data\logs\gateway.log^)...
    set "PYTHONPATH=%PACKAGES_DIR%;%UHERMES_DIR%agent"
    set "PYTHONIOENCODING=utf-8"
    pushd "%UHERMES_DIR%agent"
    start "" /b "%PYTHON_BIN%" -m gateway.run --verbose >"%DATA_DIR%\logs\gateway.log" 2>&1
    popd
    echo.
)

echo   Starting Hermes on port 8787...
echo   Open in browser: http://127.0.0.1:8787/
echo.
echo   ========================================
echo   Close this window to stop the server.
echo   ========================================
echo.

cd /d "%WEBUI_DIR%"
"%PYTHON_BIN%" server.py
echo.
echo   Server stopped.
pause
exit /b 0
