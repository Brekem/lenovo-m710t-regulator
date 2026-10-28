@echo off
REM ============================
REM CERRAR TODO LO QUE USA CPU
REM Mide que programas en segundo plano estan usando CPU,
REM te los muestra y los cierra si dices que si.
REM NO cambia ningun ajuste: funciona junto con cualquier modo.
REM Nunca cierra Windows, juegos, launchers, drivers, audio,
REM antivirus, Razer ni Claude.
REM   motor.ps1 (en esta misma carpeta)
REM ============================
title CERRAR TODO LO QUE USA CPU

set "MOTOR=%~dp0motor.ps1"
REM Si Modo Gaming esta instalado, usar su motor (el mismo que usa el icono de la bandeja)
if exist "%ProgramFiles%\ModoGaming\motor.ps1" set "MOTOR=%ProgramFiles%\ModoGaming\motor.ps1"
if not exist "%MOTOR%" (
    echo [!] No se encontro el motor: %MOTOR%
    echo     motor.ps1 tiene que estar en la misma carpeta que este .bat
    pause
    exit /b 1
)
powershell -NoProfile -ExecutionPolicy Bypass -File "%MOTOR%" -Modo cerrarcpu
echo.
pause
