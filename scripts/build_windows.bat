@echo off
setlocal enabledelayedexpansion

set "ROOT_DIR=%~dp0.."
for %%I in ("%ROOT_DIR%") do set "ROOT_DIR=%%~fI"
set "DIST_DIR=%ROOT_DIR%\dist\windows"

if not exist "%DIST_DIR%" mkdir "%DIST_DIR%"

pushd "%ROOT_DIR%"

swift build --disable-sandbox -c release --product SlopSandboxSDL >nul
for /f "delims=" %%i in ('swift build --disable-sandbox -c release --show-bin-path') do set "BIN_DIR=%%i"
set "BIN_PATH=%BIN_DIR%\SlopSandboxSDL.exe"

if not exist "%BIN_PATH%" (
  echo error: SDL binary not found at "%BIN_PATH%"
  popd
  exit /b 1
)

copy /y "%BIN_PATH%" "%DIST_DIR%\SlopSandboxSDL.exe" >nul

if exist "%ROOT_DIR%\assets" (
  if exist "%DIST_DIR%\assets" rmdir /s /q "%DIST_DIR%\assets"
  xcopy "%ROOT_DIR%\assets" "%DIST_DIR%\assets\" /e /i /y >nul
) else (
  if not exist "%DIST_DIR%\assets" mkdir "%DIST_DIR%\assets"
)

if exist "%ROOT_DIR%\config.json" (
  copy /y "%ROOT_DIR%\config.json" "%DIST_DIR%\config.json" >nul
) else (
  > "%DIST_DIR%\config.json" echo {}
)

popd

echo Built Windows dist at: dist\windows
endlocal
