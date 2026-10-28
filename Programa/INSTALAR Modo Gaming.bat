@echo off
REM ============================
REM INSTALAR MODO GAMING
REM Instala el icono de la bandeja para cambiar de modo con un clic.
REM Pide administrador UNA sola vez. Para actualizar, vuelve a ejecutarlo.
REM Para desinstalar: Configuracion > Aplicaciones > Modo Gaming.
REM ============================
title INSTALAR MODO GAMING
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0instalar.ps1"
echo.
pause
