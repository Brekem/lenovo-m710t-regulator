# ============================================================
# INSTALADOR DE MODO GAMING
# - Programa y motor en C:\Program Files\ModoGaming (solo administradores pueden modificarlos)
# - Una tarea programada elevada por modo (\ModoGaming\<modo>): cambiar de modo sin UAC
# - Icono en la bandeja que arranca con Windows
# - Aparece en Configuracion > Aplicaciones para desinstalarlo
# ============================================================
param([string]$Usuario, [string]$Sid)

$origen = $PSScriptRoot
$destino = Join-Path $env:ProgramFiles 'ModoGaming'
$esAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $esAdmin) {
    # Fase 1 (usuario normal): pedir administrador una sola vez y luego abrir el programa
    $yo = [Security.Principal.WindowsIdentity]::GetCurrent()
    $args2 = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" -Usuario `"$($yo.Name)`" -Sid `"$($yo.User.Value)`""
    try { $p = Start-Process powershell.exe -Verb RunAs -ArgumentList $args2 -Wait -PassThru }
    catch { Write-Host "[!] Instalacion cancelada: hace falta aceptar el permiso de administrador." -ForegroundColor Yellow; exit 1 }
    if ($p.ExitCode -ne 0) { Write-Host "[!] La instalacion fallo. Revisa: $env:LOCALAPPDATA\ModoGaming\instalacion.log" -ForegroundColor Yellow; exit 1 }
    # Abrir a traves del Explorador: asi el icono no depende de la ventana o programa que ejecuto el instalador
    Start-Process explorer.exe -ArgumentList "`"$(Join-Path $destino 'ModoGaming.exe')`""
    Write-Host ""
    Write-Host "MODO GAMING INSTALADO." -ForegroundColor Cyan
    Write-Host "Busca el icono redondo junto al reloj (si no lo ves, abre la flechita ^ de la barra de tareas)."
    exit 0
}

# Fase 2 (administrador)
$log = Join-Path $env:LOCALAPPDATA 'ModoGaming\instalacion.log'
New-Item -ItemType Directory -Force (Split-Path $log) | Out-Null
Start-Transcript -Path $log -Force | Out-Null
$ErrorActionPreference = 'Stop'
try {
    if (-not $Usuario -or -not $Sid) { throw "Ejecuta el instalador con 'INSTALAR Modo Gaming.bat'." }

    Write-Host "Cerrando el programa si estaba abierto..."
    Get-Process ModoGaming -ErrorAction SilentlyContinue | Stop-Process -Force
    # El regulador (modo dinamico) tiene abierto el lector de temperatura: apagarlo para poder reemplazar los archivos
    $estado = Join-Path $env:LOCALAPPDATA 'ModoGaming\modo_actual.txt'
    $conRegulador = (Test-Path $estado) -and ((Get-Content $estado -Raw).Trim() -notin '', 'original')
    # Primero pedirle que se apague solo (asi devuelve el ventilador de salida a la placa); si no, a la fuerza
    $pararGob = Join-Path $env:LOCALAPPDATA 'ModoGaming\detener_gobernador'
    $gobs = @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue | Where-Object { $_.CommandLine -like '*gobernador.ps1*' })
    if ($gobs.Count -gt 0) {
        New-Item -ItemType File -Force $pararGob | Out-Null
        $hasta = (Get-Date).AddSeconds(8)
        while ((Get-Date) -lt $hasta -and (Get-Process -Id $gobs.ProcessId -ErrorAction SilentlyContinue)) { Start-Sleep -Milliseconds 300 }
    }
    try { Stop-ScheduledTask -TaskPath '\ModoGaming\' -TaskName 'gobernador' -ErrorAction Stop } catch {}
    Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -like '*gobernador.ps1*' } |
        ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
    Remove-Item $pararGob -Force -ErrorAction SilentlyContinue
    Start-Sleep 2

    Write-Host "Copiando archivos a $destino..."
    New-Item -ItemType Directory -Force $destino | Out-Null
    # motor.ps1: en esta carpeta (paquete para compartir) o en la carpeta de arriba (carpeta BATS)
    $motorOrigen = @((Join-Path $origen 'motor.ps1'), (Join-Path (Split-Path $origen) 'motor.ps1')) | Where-Object { Test-Path $_ } | Select-Object -First 1
    if (-not $motorOrigen) { throw "No se encontro motor.ps1 junto al instalador." }
    Copy-Item $motorOrigen $destino -Force
    Copy-Item (Join-Path $origen 'desinstalar.ps1') $destino -Force
    # Regulador termico del modo Gaming dinamico (junto al motor)
    $gobOrigen = Join-Path (Split-Path $motorOrigen) 'gobernador.ps1'
    if (Test-Path $gobOrigen) { Copy-Item $gobOrigen $destino -Force }
    # Lector de temperatura: LibreHardwareMonitorLib (winget install LibreHardwareMonitor.LibreHardwareMonitor)
    # Se copia a Program Files para que el regulador (que corre como administrador) no cargue DLLs de una carpeta del usuario
    # Primero la carpeta lhm que trae el paquete (ModoGaming-Setup.exe); si no, la instalada con winget
    $lhm = Get-Item (Join-Path $origen 'lhm') -ErrorAction SilentlyContinue
    if (-not $lhm) { $lhm = Get-ChildItem (Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Packages\LibreHardwareMonitor.LibreHardwareMonitor*') -Directory -ErrorAction SilentlyContinue | Select-Object -First 1 }
    if ($lhm -and (Test-Path (Join-Path $lhm.FullName 'LibreHardwareMonitorLib.dll'))) {
        $lhmDestino = Join-Path $destino 'lhm'
        New-Item -ItemType Directory -Force $lhmDestino | Out-Null
        Get-ChildItem $lhm.FullName -Filter *.dll -File | Where-Object { $_.Name -notmatch '^(Aga\.Controls|OxyPlot|Microsoft\.Win32\.TaskScheduler)' } | Copy-Item -Destination $lhmDestino -Force
        Write-Host "    lector de temperatura copiado"
    } else { Write-Host "    [!] LibreHardwareMonitor no instalado: Gaming dinamico se quedara fijo en 3.2 GHz" }

    $fuente = Join-Path $origen 'ModoGaming.cs'
    $exeListo = Join-Path $origen 'ModoGaming.exe'
    if (Test-Path $fuente) {
        Write-Host "Compilando ModoGaming.exe..."
        $csc = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
        $salida = & $csc /nologo /target:winexe /optimize+ "/out:$destino\ModoGaming.exe" /r:System.Windows.Forms.dll /r:System.Drawing.dll /r:System.Core.dll $fuente 2>&1
        if ($LASTEXITCODE -ne 0) { throw "Error al compilar:`n$($salida -join "`n")" }
    } elseif (Test-Path $exeListo) {
        Write-Host "Copiando ModoGaming.exe..."
        Copy-Item $exeListo $destino -Force
    } else { throw "Falta ModoGaming.exe o ModoGaming.cs junto al instalador." }
    Get-ChildItem $destino | Unblock-File -ErrorAction SilentlyContinue   # quitar la marca de "descargado de internet"

    Write-Host "Creando tareas programadas (cambiar de modo sin UAC)..."
    $servicio = New-Object -ComObject Schedule.Service
    $servicio.Connect()
    $raiz = $servicio.GetFolder('\')
    try { $raiz.CreateFolder('ModoGaming') | Out-Null } catch {}
    # Solo administradores/sistema pueden modificarlas; tu usuario solo puede ejecutarlas
    $sddl = "D:(A;;FA;;;BA)(A;;FA;;;SY)(A;;GRGX;;;$Sid)"
    $carpeta = $servicio.GetFolder('\ModoGaming')
    $carpeta.SetSecurityDescriptor($sddl, 0)
    $motor = Join-Path $destino 'motor.ps1'
    $principal = New-ScheduledTaskPrincipal -UserId $Usuario -LogonType Interactive -RunLevel Highest
    $ajustes = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Minutes 5) -MultipleInstances IgnoreNew
    foreach ($modo in 'gaming', 'gamingfresco', 'cpuloose', 'dinamico', 'revertircpu', 'altorend', 'ahorro', 'ahorrosinsusp', 'normal', 'original') {
        # conhost --headless: corre sin mostrar ninguna ventana de consola
        $accion = New-ScheduledTaskAction -Execute "$env:WINDIR\System32\conhost.exe" -Argument "--headless powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$motor`" -Modo $modo"
        $tarea = @{ TaskPath = '\ModoGaming\'; TaskName = $modo; Action = $accion; Principal = $principal; Settings = $ajustes; Force = $true }
        # Al iniciar sesion la PC arranca siempre en modo seguro (Normal fresco); el dinamico se pone a mano para jugar
        if ($modo -eq 'normal') { $tarea.Trigger = New-ScheduledTaskTrigger -AtLogOn -User $Usuario }
        Register-ScheduledTask @tarea | Out-Null
        $carpeta.GetTask($modo).SetSecurityDescriptor($sddl, 0)
        Write-Host "    tarea: $modo"
    }
    # Regulador termico: corre mientras dure el modo Gaming dinamico (sin limite de tiempo)
    $gob = Join-Path $destino 'gobernador.ps1'
    $accion = New-ScheduledTaskAction -Execute "$env:WINDIR\System32\conhost.exe" -Argument "--headless powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$gob`""
    $ajustesGob = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit ([TimeSpan]::Zero) -MultipleInstances IgnoreNew
    Register-ScheduledTask -TaskPath '\ModoGaming\' -TaskName 'gobernador' -Action $accion -Principal $principal -Settings $ajustesGob -Force | Out-Null
    $carpeta.GetTask('gobernador').SetSecurityDescriptor($sddl, 0)
    Write-Host "    tarea: gobernador"
    # El regulador vuelve a arrancar ya actualizado (todos los modos menos Windows original)
    if ($conRegulador) {
        try { Start-ScheduledTask -TaskPath '\ModoGaming\' -TaskName 'gobernador' -ErrorAction Stop; Write-Host "    regulador termico reiniciado" } catch {}
    }

    Write-Host "Registrando el programa..."
    $exe = Join-Path $destino 'ModoGaming.exe'
    $uninst = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\ModoGaming'
    New-Item -Path $uninst -Force | Out-Null
    Set-ItemProperty $uninst DisplayName 'Modo Gaming'
    Set-ItemProperty $uninst DisplayVersion '1.2'
    Set-ItemProperty $uninst Publisher 'ibrek'
    Set-ItemProperty $uninst DisplayIcon $exe
    Set-ItemProperty $uninst InstallLocation $destino
    Set-ItemProperty $uninst UninstallString "powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$destino\desinstalar.ps1`""
    Set-ItemProperty $uninst NoModify 1 -Type DWord
    Set-ItemProperty $uninst NoRepair 1 -Type DWord

    $acceso = Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu\Programs\Modo Gaming.lnk'
    $sh = (New-Object -ComObject WScript.Shell).CreateShortcut($acceso)
    $sh.TargetPath = $exe; $sh.WorkingDirectory = $destino; $sh.Description = 'Cambiar de modo de energia y gaming'
    $sh.Save()

    # Iniciar con Windows (HKCU del usuario que instala)
    $run = "Registry::HKEY_USERS\$Sid\Software\Microsoft\Windows\CurrentVersion\Run"
    if (Test-Path $run) { Set-ItemProperty $run ModoGaming "`"$exe`"" }

    Write-Host "INSTALACION COMPLETA." -ForegroundColor Cyan
    Stop-Transcript | Out-Null
    exit 0
}
catch {
    Write-Host "[!] $($_.Exception.Message)" -ForegroundColor Red
    Stop-Transcript | Out-Null
    exit 1
}
