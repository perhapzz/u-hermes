@echo off
chcp 65001 >nul 2>&1
title U-Hermes - Portable AI Agent

echo.
echo   ========================================
echo     U-Hermes v0.1 - Portable AI Agent
echo   ========================================
echo.

set "UHERMES_DIR=%~dp0"
set "APP_DIR=%UHERMES_DIR%app"
set "RUNTIME_DIR=%APP_DIR%\runtime"
set "PACKAGES_DIR=%APP_DIR%\packages"
set "WEBUI_DIR=%UHERMES_DIR%webui"
set "DATA_DIR=%UHERMES_DIR%data"
set "HERMES_HOME=%DATA_DIR%\.hermes"

set "PYTHON_DIR=%RUNTIME_DIR%\python-win-x64"
set "PYTHON_BIN=%PYTHON_DIR%\python.exe"

REM ---- 1. Check runtime ----
if not exist "%PYTHON_BIN%" (
    echo   [ERROR] Python runtime not found
    echo   Please run: setup.bat
    pause
    exit /b 1
)

if not exist "%WEBUI_DIR%\server.py" (
    echo   [ERROR] webui not found
    pause
    exit /b 1
)

for /f "tokens=*" %%v in ('"%PYTHON_BIN%" --version') do set PYTHON_VER=%%v
echo   Python: %PYTHON_VER%
echo.

REM ---- Check packages (fallback pip install if missing) ----
"%PYTHON_BIN%" -c "import sys; sys.path.insert(0,r'%PACKAGES_DIR%'); import run_agent" >nul 2>&1
if errorlevel 1 (
    echo   [WARN] packages not found
    echo   This release should ship with deps pre-installed.
    echo   Falling back to pip install...
    echo.
    if not exist "%PACKAGES_DIR%" mkdir "%PACKAGES_DIR%" 2>nul
    "%PYTHON_BIN%" -m pip install "%UHERMES_DIR%agent" ^
        --target "%PACKAGES_DIR%" --no-user --disable-pip-version-check
    if exist "%WEBUI_DIR%\requirements.txt" (
        "%PYTHON_BIN%" -m pip install -r "%WEBUI_DIR%\requirements.txt" ^
            --target "%PACKAGES_DIR%" --no-user --disable-pip-version-check
    )
    echo   [OK] Dependencies installed
    echo.
)

REM ---- 2. Init data directories ----
if not exist "%HERMES_HOME%" mkdir "%HERMES_HOME%" 2>nul
if not exist "%DATA_DIR%\logs" mkdir "%DATA_DIR%\logs" 2>nul

REM ---- 2a. Detect drive-letter / path change since last run ----
REM    USB drives get different letters on different machines (D:, F:, G: ...).
REM    State files in data\.hermes may cache absolute paths from the previous
REM    run; if the path changed, archive the old state so the agent starts
REM    fresh instead of dereferencing dead paths.
set "PATH_MARKER=%HERMES_HOME%\.last_path"
set "LAST_PATH="
if exist "%PATH_MARKER%" set /p LAST_PATH=<"%PATH_MARKER%"

REM Compare outside the if-block so the variable is actually expanded.
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

REM Write current path marker for next run.
>"%PATH_MARKER%" echo %UHERMES_DIR%

REM ---- 2b. Bootstrap API key (device fingerprint) ----
echo   Binding device fingerprint...
"%PYTHON_BIN%" "%UHERMES_DIR%lib\bootstrap-api.py" "%HERMES_HOME%" 2>nul
echo.

REM ---- 3. Set environment (portable mode) ----
set "HERMES_HOME=%HERMES_HOME%"
set "HERMES_WEBUI_STATE_DIR=%HERMES_HOME%\webui"
set "HERMES_WEBUI_HOST=127.0.0.1"
set "HERMES_WEBUI_AGENT_DIR=%UHERMES_DIR%agent"
set "HERMES_WEBUI_PYTHON=%PYTHON_BIN%"
set "HERMES_DISABLE_LAZY_INSTALLS=1"

REM ---- 3b. Portable workspace (USB-relative, no user home dependency) ----
set "HERMES_WEBUI_DEFAULT_WORKSPACE=%UHERMES_DIR%workspace"
if not exist "%HERMES_WEBUI_DEFAULT_WORKSPACE%" mkdir "%HERMES_WEBUI_DEFAULT_WORKSPACE%" 2>nul

REM ---- 4. Set port ----
set "HERMES_WEBUI_PORT=8787"

REM ---- 5. Start webui ----
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
