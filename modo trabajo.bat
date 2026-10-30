@echo off
REM ============================
REM MODO TRABAJO
REM Todo el CPU posible para trabajar: Turbo eficiente hasta 4.2 GHz con el regulador (max 85 C).
REM Nunca se suspende. No cierra programas ni detiene servicios.
REM Todos los modos usan el mismo motor y la misma foto de tu
REM configuracion original, asi nunca se pisan entre ellos:
REM   motor.ps1 (en esta misma carpeta; la foto queda en %LOCALAPPDATA%\ModoGaming)
REM ============================
title MODO TRABAJO

REM Pedir permisos de administrador automaticamente
net session >nul 2>&1
if errorlevel 1 (
    powershell -NoProfile -Command "try { Start-Process -FilePath '%~f0' -Verb RunAs -ErrorAction Stop; exit 0 } catch { exit 1 }"
    if not errorlevel 1 exit /b
    echo [!] Sin permisos de administrador: se aplicara solo lo basico.
)

set "MOTOR=%~dp0motor.ps1"
REM Si Modo Gaming esta instalado, usar su motor (el mismo que usa el icono de la bandeja)
if exist "%ProgramFiles%\ModoGaming\motor.ps1" set "MOTOR=%ProgramFiles%\ModoGaming\motor.ps1"
if not exist "%MOTOR%" (
    echo [!] No se encontro el motor: %MOTOR%
    echo     motor.ps1 tiene que estar en la misma carpeta que este .bat
    pause
    exit /b 1
)
powershell -NoProfile -ExecutionPolicy Bypass -File "%MOTOR%" -Modo trabajo
echo.
pause
