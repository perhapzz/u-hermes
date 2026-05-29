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
set "PYTHONPATH=%PACKAGES_DIR%;%UHERMES_DIR%agent"
set "PATH=%PYTHON_DIR%;%PYTHON_DIR%\Scripts;%PATH%"

REM ---- 4. Find available port ----
set PORT=8787

:find_port
netstat -an 2>nul | findstr ":%PORT% " >nul 2>&1
if not errorlevel 1 (
    echo   Port %PORT% in use, trying next...
    set /a PORT+=1
    if %PORT% gtr 8799 (
        echo   [ERROR] No available port (8787-8799)
        pause
        exit /b 1
    )
    goto find_port
)

set "HERMES_WEBUI_PORT=%PORT%"

REM ---- 5. Start webui ----
echo   Starting Hermes on port %PORT%...
echo.

cd /d "%WEBUI_DIR%"
start "" "%PYTHON_BIN%" bootstrap.py --no-browser --skip-agent-install %PORT%

REM ---- 6. Wait for server, then open browser ----
set TRIES=0
:wait_loop
timeout /t 1 /nobreak >nul
set /a TRIES+=1
curl -s -o nul "http://127.0.0.1:%PORT%/" >nul 2>&1
if not errorlevel 1 (
    start http://127.0.0.1:%PORT%/
    goto server_ready
)
if %TRIES% lss 30 goto wait_loop

:server_ready
echo.
echo   ========================================
echo   U-Hermes is running!
echo     Web UI: http://127.0.0.1:%PORT%/
echo.
echo   Close this window to stop.
echo   ========================================
echo.
pause
taskkill /f /im python.exe /fi "WINDOWTITLE eq U-Hermes*" >nul 2>&1
