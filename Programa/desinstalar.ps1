# ============================================================
# DESINSTALADOR DE MODO GAMING
# Vuelve a Windows original y quita programa, tareas y accesos.
# La foto de tu configuracion original se conserva en
# %LOCALAPPDATA%\ModoGaming para que los .bat sigan funcionando.
# ============================================================
$destino = Join-Path $env:ProgramFiles 'ModoGaming'
$esAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $esAdmin) {
    try { Start-Process powershell.exe -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" } catch {}
    exit
}

Write-Host "Cerrando Modo Gaming..."
Get-Process ModoGaming -ErrorAction SilentlyContinue | Stop-Process -Force

Write-Host "Volviendo a Windows original..."
$motor = Join-Path $destino 'motor.ps1'
if (Test-Path $motor) { & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $motor -Modo original | Out-Null }

Write-Host "Quitando tareas programadas..."
Get-ScheduledTask -TaskPath '\ModoGaming\' -ErrorAction SilentlyContinue | Unregister-ScheduledTask -Confirm:$false
try { $s = New-Object -ComObject Schedule.Service; $s.Connect(); $s.GetFolder('\').DeleteFolder('ModoGaming', 0) } catch {}

Write-Host "Quitando accesos y registro..."
Remove-Item (Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu\Programs\Modo Gaming.lnk') -ErrorAction SilentlyContinue
Remove-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -Name ModoGaming -ErrorAction SilentlyContinue
Remove-Item 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\ModoGaming' -Recurse -ErrorAction SilentlyContinue

# Borrar la carpeta del programa cuando este script ya termino
Start-Process cmd.exe -ArgumentList "/c timeout /t 3 /nobreak >nul & rd /s /q `"$destino`"" -WindowStyle Hidden
Write-Host "MODO GAMING DESINSTALADO." -ForegroundColor Cyan
Start-Sleep 2
