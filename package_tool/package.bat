@echo off
setlocal enabledelayedexpansion

REM ============================================================
REM  package_tool - one-click Godot Windows Desktop export
REM  Output: <project_root>\package\MyGame.exe  (git-ignored)
REM ============================================================

REM ---- Config ----
REM  Engine path resolve order:
REM    1) environment variable GODOT_BIN   (recommended, per-machine)
REM    2) fallback default below
if not defined GODOT_BIN set "GODOT_BIN=D:\godot\Godot_v4.7.2-stable_win64\Godot_v4.7.2-stable_win64_console.exe"
set "GODOT_EXE=%GODOT_BIN%"
set "PRESET=Windows Desktop"
set "OUTPUT_BASENAME=my_game"

REM  Export templates (auto-installed if missing)
set "TEMPLATE_VERSION=4.7.2.stable"
set "TEMPLATE_URL=https://github.com/godotengine/godot/releases/download/4.7.2-stable/Godot_v4.7.2-stable_export_templates.tpz"

REM ---- Resolve paths ----
set "SCRIPT_DIR=%~dp0"
pushd "%SCRIPT_DIR%.." || (echo [ERROR] cannot enter project root & exit /b 1)
set "PROJECT_ROOT=%CD%"
popd
set "OUTPUT_DIR=%PROJECT_ROOT%\package"

REM ---- Timestamped version name: <base>_v<MMdd>_<HH> (locale-independent) ----
for /f %%i in ('powershell -NoProfile -Command "Get-Date -Format MMdd_HH"') do set "TS=%%i"
set "VERSION_NAME=%OUTPUT_BASENAME%_v%TS%"
set "BUILD_DIR=%OUTPUT_DIR%\%VERSION_NAME%"
set "OUTPUT_PATH=%BUILD_DIR%\%VERSION_NAME%.exe"

echo [package_tool] Project : %PROJECT_ROOT%
echo [package_tool] Engine  : %GODOT_EXE%
echo [package_tool] Output  : %OUTPUT_PATH%

if not exist "%GODOT_EXE%" (
  echo [ERROR] Godot engine not found: %GODOT_EXE%
  exit /b 1
)

REM ---- Sync export preset to project root (root copy is git-ignored) ----
copy /Y "%SCRIPT_DIR%export_presets.cfg" "%PROJECT_ROOT%\export_presets.cfg" >nul
if errorlevel 1 (
  echo [ERROR] failed to copy export_presets.cfg
  exit /b 1
)

REM ---- Ensure export templates (auto-download+install if missing) ----
powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%install_templates.ps1" -Version "%TEMPLATE_VERSION%" -Url "%TEMPLATE_URL%"
if errorlevel 1 (
  echo [ERROR] export templates install failed.
  exit /b 1
)

REM ---- Ensure output dir ----
if not exist "%BUILD_DIR%" mkdir "%BUILD_DIR%"

echo [package_tool] Exporting "%PRESET%" ...
"%GODOT_EXE%" --headless --path "%PROJECT_ROOT%" --export-release "%PRESET%" "%OUTPUT_PATH%"
set "ERR=%ERRORLEVEL%"

if not "%ERR%"=="0" (
  echo.
  echo [ERROR] Export failed ^(exit code %ERR%^).
  echo         If it mentions export templates, install them via:
  echo         Godot Editor -^> Editor -^> Manage Export Templates.
  exit /b %ERR%
)

echo.
echo [package_tool] Done -^> %OUTPUT_PATH%
endlocal
