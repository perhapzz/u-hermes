@echo off
setlocal EnableDelayedExpansion
chcp 65001 >nul 2>&1
title U-Hermes Portable Setup

set "SCRIPT_DIR=%~dp0"
set "APP_DIR=%SCRIPT_DIR%app"
set "RUNTIME_DIR=%APP_DIR%\runtime"
set "PACKAGES_DIR=%APP_DIR%\packages"

set "PYTHON_TAG=20260510"
set "PYTHON_VERSION=3.11.15"
set "GH_ACCEL=https://ghfast.top/"
set "GH_RAW=https://github.com/"
set "PYTHON_RELEASE_PATH=astral-sh/python-build-standalone/releases/download/%PYTHON_TAG%"
set "PIP_MIRROR=https://pypi.tuna.tsinghua.edu.cn/simple"

echo.
echo   ========================================
echo     U-Hermes Portable Setup
echo   ========================================
echo.
echo   System: Windows x64

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

REM ---- 1. Download Python (Windows x64) ----
set "PYTHON_DIR=%RUNTIME_DIR%\python-win-x64"
set "PYTHON_BIN=%PYTHON_DIR%\python.exe"

if exist "%PYTHON_BIN%" (
    echo   [OK] Python (win-x64) already exists
    goto python_done
)

echo   [DOWNLOAD] Downloading Python %PYTHON_VERSION% (win-x64)...
set "PY_FILENAME=cpython-%PYTHON_VERSION%+%PYTHON_TAG%-x86_64-pc-windows-msvc-install_only_stripped.tar.gz"
set "PY_RELEASE=%PYTHON_RELEASE_PATH%/%PY_FILENAME%"

if not exist "%PYTHON_DIR%" mkdir "%PYTHON_DIR%" 2>nul

set "TMP_FILE=%TEMP%\uhermes-python-%RANDOM%.tar.gz"

if not "%IN_CHINA%"=="true" goto download_direct
echo     Trying ghfast.top mirror...
curl -fSL --max-time 300 "%GH_ACCEL%%GH_RAW%%PY_RELEASE%" -o "%TMP_FILE%" >nul 2>&1
if not errorlevel 1 goto download_ok
echo     Mirror failed, trying direct...

:download_direct
curl -fSL "%GH_RAW%%PY_RELEASE%" -o "%TMP_FILE%"
if errorlevel 1 (
    echo   [ERROR] Python download failed
    pause
    exit /b 1
)

:download_ok

echo     Extracting...
tar -xzf "%TMP_FILE%" -C "%PYTHON_DIR%"
del /f /q "%TMP_FILE%" 2>nul

REM Handle nested python/ directory from tar extraction
if not exist "%PYTHON_BIN%" (
    if exist "%PYTHON_DIR%\python\python.exe" (
        echo     Fixing directory structure...
        xcopy /s /e /q /y "%PYTHON_DIR%\python\*" "%PYTHON_DIR%\" >nul
        rmdir /s /q "%PYTHON_DIR%\python" 2>nul
    )
)

if not exist "%PYTHON_BIN%" (
    echo   [ERROR] Python extraction failed
    pause
    exit /b 1
)

echo   [OK] Python (win-x64) downloaded

:python_done

REM ---- 2. Install hermes-agent ----
"%PYTHON_BIN%" -c "import sys; sys.path.insert(0,r'%PACKAGES_DIR%'); import run_agent" >nul 2>&1
if not errorlevel 1 (
    echo   [OK] hermes-agent already installed
    goto agent_done
)

echo   [DOWNLOAD] Installing hermes-agent...
if not exist "%PACKAGES_DIR%" mkdir "%PACKAGES_DIR%" 2>nul

set "PIP_INDEX="
if "%IN_CHINA%"=="true" set "PIP_INDEX=-i %PIP_MIRROR%"

"%PYTHON_BIN%" -m pip install "%SCRIPT_DIR%agent" ^
    --target "%PACKAGES_DIR%" --no-user --disable-pip-version-check --quiet %PIP_INDEX%
if errorlevel 1 (
    echo   [ERROR] hermes-agent install failed
    pause
    exit /b 1
)
echo   [OK] hermes-agent installed

:agent_done

REM ---- 3. Install webui dependencies ----
set "WEBUI_REQS=%SCRIPT_DIR%webui\requirements.txt"
if exist "%WEBUI_REQS%" (
    echo   [DOWNLOAD] Installing webui dependencies...
    "%PYTHON_BIN%" -m pip install -r "%WEBUI_REQS%" ^
        --target "%PACKAGES_DIR%" --no-user --disable-pip-version-check --quiet %PIP_INDEX%
    echo   [OK] webui deps installed
)

REM ---- 4. Init data dirs ----
if not exist "%SCRIPT_DIR%data\.hermes" mkdir "%SCRIPT_DIR%data\.hermes" 2>nul
if not exist "%SCRIPT_DIR%data\logs" mkdir "%SCRIPT_DIR%data\logs" 2>nul

REM ---- Done ----
echo.
echo   ========================================
echo     Setup complete!
echo   ========================================
echo.
echo   Launch: double-click Windows-Start.bat
echo.
echo   Directory structure:
echo     webui\              -- Web UI source (in repo)
echo     app\runtime\        -- Python %PYTHON_VERSION%
echo     app\packages\       -- hermes-agent + dependencies
echo     data\               -- Runtime state
echo   ========================================
echo.
pause
