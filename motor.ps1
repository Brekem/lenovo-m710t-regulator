# ============================================================
# MOTOR DE MODOS DE ENERGIA / GAMING
# Lo usan todos los .bat de esta carpeta. No lo borres ni lo muevas de aqui.
#
# Como funciona:
#  - La primera vez guarda una FOTO de tu configuracion original
#    (original.json en %LOCALAPPDATA%\ModoGaming).
#  - Cada modo vuelve primero a esa foto y despues aplica lo suyo,
#    asi los modos nunca se pisan entre ellos.
#  - "original" vuelve a la foto y activa tu plan original.
# ============================================================
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('original', 'ahorro', 'ahorrosinsusp', 'normal', 'gaming', 'gamingfresco', 'cpuloose', 'dinamico', 'revertircpu', 'altorend', 'snapshot', 'cerrarcpu')]
    [string]$Modo
)

$dir       = Join-Path $env:LOCALAPPDATA 'ModoGaming'
$snapFile  = Join-Path $dir 'original.json'
$stateFile = Join-Path $dir 'modo_actual.txt'
New-Item -ItemType Directory -Force $dir | Out-Null
# Registro de la ultima ejecucion (lo lee el programa de la bandeja)
try { Start-Transcript -Path (Join-Path $dir 'ultimo.log') -Force | Out-Null } catch {}

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

# Planes de energia
$EQUILIBRADO = '381b4222-f694-41f0-9685-ff5bb260df2e'
$ECONOMIZADOR = 'a1841308-3541-4fab-bc81-f71556f20b4a'
$ALTO        = '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c'
$PLANES = @($EQUILIBRADO, $ECONOMIZADOR, $ALTO)

# Ajustes de energia que tocan los modos (subgrupo + ajuste)
$AJUSTES = [ordered]@{
    CPU_MAX     = '54533251-82be-4824-96c1-47b60b740d00 bc5038f7-23e0-4960-96da-33abaf5935ec'
    CPU_MIN     = '54533251-82be-4824-96c1-47b60b740d00 893dee8e-2bef-41e0-89c6-b55d0929964c'
    CPU_EPP     = '54533251-82be-4824-96c1-47b60b740d00 36687f9e-e3a5-4dbf-b1dc-15eb381c6863'
    CPU_NUCLEOS = '54533251-82be-4824-96c1-47b60b740d00 0cc5b647-c1df-4637-891a-dec35c318583'
    CPU_BOOST   = '54533251-82be-4824-96c1-47b60b740d00 be337238-0d82-4146-a960-4f3749d470c7'   # 0 = Turbo apagado
    CPU_MHZ     = '54533251-82be-4824-96c1-47b60b740d00 75b0ae3f-bce0-45a7-8c89-c9611c25e100'   # MHz maximos (0 = sin limite)
    SUSPENDER   = '238c9fa8-0aad-41ed-83f4-97be242c8f20 29f6c1db-86da-48c5-9fdb-f2b67b1f44da'
    PANTALLA    = '7516b95f-f776-4464-8c53-06167f40cc99 3c0bc021-c8a8-4e07-a973-6b14cbcb2b7e'
    DISCO       = '0012ee47-9041-4b5d-9b77-535fba8b1442 6738e2c4-e8a5-4a42-b16a-e040e769756e'
    USB         = '2a737441-1930-4402-8d77-b2bebba308a3 48e6b7a6-50f5-4782-a5d4-53bb8f07e226'
}

# Servicios que se detienen al jugar (vuelven solos al reiniciar).
# NO se tocan: Xbox/Gaming Services, descargas (DoSvc, wuauserv, InstallService),
# NVIDIA, audio, red ni antivirus. Si usas impresora, quita 'Spooler'.
$SERVICIOS = 'WSearch', 'SysMain', 'DiagTrack', 'Spooler', 'StiSvc', 'UsoSvc', 'igccservice', 'jhi_service', 'PcaSvc', 'lfsvc'

# Programas en segundo plano que se cierran (todos los modos de juego).
# Para cerrar Discord tambien, agrega 'Discord' a la lista.
$CERRAR = 'msedge', 'PhoneExperienceHost', 'EdgeGameAssist', 'Widgets', 'CrossDeviceResume', 'MoNotificationUx'

# Valores del registro que tocan los modos de juego
$REGISTRO = @(
    @{ Ruta = 'HKCU:\System\GameConfigStore'; Nombre = 'GameDVR_Enabled' },
    @{ Ruta = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR'; Nombre = 'AppCaptureEnabled' },
    @{ Ruta = 'HKCU:\Software\Microsoft\GameBar'; Nombre = 'AutoGameModeEnabled' },
    @{ Ruta = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile'; Nombre = 'SystemResponsiveness' },
    @{ Ruta = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization'; Nombre = 'DODownloadMode' },
    # Lo que muestra el interruptor "Ahorro de energia" de Configuracion (1 = activado, 2 = apagado)
    @{ Ruta = 'HKLM:\SYSTEM\CurrentControlSet\Control\Power'; Nombre = 'EnergySaverState' }
)

$RAMMAP = Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Packages\Microsoft.Sysinternals.RAMMap_Microsoft.Winget.Source_8wekyb3d8bbwe\RAMMap64.exe'

# Velocidad maxima del CPU en los modos de juego (gaming, cpu loose, alto rendimiento).
#   99  = SIN Turbo: el i7-7700 se queda en 3.6 GHz y calienta 10-20 C menos.
#   100 = CON Turbo (hasta 4.2 GHz). Vuelve a 100 cuando arregles la temperatura
#         (pasta termica / disipador) y ejecuta otra vez "INSTALAR Modo Gaming.bat".
$CPU_MAX_JUEGO = 99

# Limite de velocidad del CPU en MHz para TODOS los modos menos "Windows original"
# (para que la CPU caliente menos mientras se arregla la pasta termica).
#   3300 = maximo 3.3 GHz (~80-83 C jugando con el disipador actual)
#   3200 = maximo 3.2 GHz (~78-81 C, margen extra para sesiones largas)
#   3000 = maximo 3.0 GHz (~75 C)      0 = sin limite
# Despues de cambiarlo, ejecuta otra vez "INSTALAR Modo Gaming.bat".
$CPU_MHZ_LIMITE = 3300

# Limite del modo "Gaming fresco": todo lo de gaming eficiente pero mas fresco
#   3200 = maximo 3.2 GHz (~80 C jugando; 3.1 no alcanzaba para ARC Raiders)
$CPU_MHZ_FRESCO = 3200

# Limite del modo "CPU suelto": un poco mas de velocidad para 60 FPS fijos
#   3200 = maximo 3.2 GHz (corre bien y no se sobrecalienta; 3.3-3.4 llegaban a 85-88 C)
$CPU_MHZ_LOOSE = 3200

# Turbo maximo del CPU (i7-7700: 4.2 GHz). Solo lo usa "Gaming dinamico": el regulador
# enciende el Turbo por encima de la velocidad base y lo va bajando si el CPU se calienta.
$CPU_TURBO_MHZ = 4200
$TURBO_MODOS   = @('dinamico')

function Limitar-Velocidad($plan, [int]$mhz = $CPU_MHZ_LIMITE) {
    if ($mhz -le 0) { return }
    Poner $plan CPU_MHZ $mhz
    # Tambien en % de la velocidad base (por si el procesador ignora el limite en MHz)
    $base = (Get-CimInstance Win32_Processor | Select-Object -First 1).MaxClockSpeed
    if ($base -gt 0) { Poner $plan CPU_MAX ([math]::Min(99, [math]::Floor($mhz * 100 / $base))) }
    Poner $plan CPU_BOOST 0
}

function Aviso($m) { Write-Host "[!] $m" -ForegroundColor Yellow }
function Ok($m) { Write-Host "    $m" -ForegroundColor Green }

# ---------- energia ----------
function Leer-Ajuste($plan, $nombre) {
    $sub, $set = $AJUSTES[$nombre] -split ' '
    $lineas = @(powercfg /qh $plan $sub $set | Select-String '0x[0-9a-fA-F]{8}\s*$')
    if ($lineas.Count -lt 2) { return $null }
    $hex = { param($l) [Convert]::ToUInt32((($l.Line -split '0x')[-1]).Trim(), 16) }
    @{ AC = (& $hex $lineas[-2]); DC = (& $hex $lineas[-1]) }
}
function Poner($plan, $nombre, $ac, $dc = $null) {
    $sub, $set = $AJUSTES[$nombre] -split ' '
    powercfg /setacvalueindex $plan $sub $set $ac | Out-Null
    if ($null -ne $dc) { powercfg /setdcvalueindex $plan $sub $set $dc | Out-Null }
}
function Plan-Activo { if ((powercfg /getactivescheme) -match '([0-9a-fA-F-]{36})') { $Matches[1] } }
function Activar($plan) { powercfg /setactive $plan | Out-Null }

# Muchas PCs modernas solo traen el plan Equilibrado: crear Economizador y Alto rendimiento
# (copias de los de fabrica de Windows, con su mismo GUID) si no existen
function Asegurar-Planes {
    $lista = powercfg /list | Out-String
    foreach ($p in $ECONOMIZADOR, $ALTO) {
        if ($lista -notmatch $p) { powercfg /duplicatescheme $p $p | Out-Null }
    }
}

# Modo de energia de Windows 11 (Configuracion > Energia). MANDA por encima del plan:
# con "Mejor rendimiento" el Economizador no ahorra nada.
# "Maxima eficiencia" es lo mismo que hace por dentro el interruptor "Ahorro de energia".
$MODO_EFICIENCIA  = '961cc777-2547-4f9d-8174-7d86181b8a7a'
$MODO_EQUILIBRADO = '00000000-0000-0000-0000-000000000000'
$MODO_RENDIMIENTO = 'ded574b5-45a0-4f42-8737-46345c09c238'
Add-Type -Namespace ModoGaming -Name Energia -MemberDefinition @'
[DllImport("powrprof.dll")] public static extern uint PowerGetUserConfiguredACPowerMode(out Guid g);
[DllImport("powrprof.dll")] public static extern uint PowerSetUserConfiguredACPowerMode(ref Guid g);
'@
# Interruptor "Ahorro de energia" de Windows. La unica forma oficial de encenderlo en una PC
# de escritorio es la directiva "Enable Energy Saver to Always Be On" (Power.admx).
# Encendido = directiva en 1. Apagado = sin directiva (como viene Windows).
$DIRECTIVA_AHORRO = 'HKLM:\SOFTWARE\Policies\Microsoft\Power\EnergySaver'
function Poner-AhorroWindows([bool]$encender) {
    if (-not $isAdmin) { if ($encender) { Aviso "Ahorro de energia de Windows NO activado: hace falta administrador." }; return }
    $actual = (Get-ItemProperty $DIRECTIVA_AHORRO -Name EnableEnergySaver -ErrorAction SilentlyContinue).EnableEnergySaver
    if ($encender) {
        if ($actual -eq 1) { return }
        New-Item -Path $DIRECTIVA_AHORRO -Force | Out-Null
        Set-ItemProperty $DIRECTIVA_AHORRO EnableEnergySaver 1 -Type DWord
    } else {
        if ($null -eq $actual) { return }
        Remove-ItemProperty $DIRECTIVA_AHORRO -Name EnableEnergySaver -ErrorAction SilentlyContinue
        if (-not (Get-ItemProperty $DIRECTIVA_AHORRO -ErrorAction SilentlyContinue | Get-Member -MemberType NoteProperty | Where-Object Name -notlike 'PS*')) {
            Remove-Item $DIRECTIVA_AHORRO -ErrorAction SilentlyContinue
        }
    }
    gpupdate /target:computer /force | Out-Null   # aplicar la directiva al momento
}

function Leer-ModoEnergia { $g = [Guid]::Empty; [void][ModoGaming.Energia]::PowerGetUserConfiguredACPowerMode([ref]$g); $g.ToString() }
function Poner-ModoEnergia($guid) { $g = [Guid]$guid; [void][ModoGaming.Energia]::PowerSetUserConfiguredACPowerMode([ref]$g) }

# ---------- registro ----------
function Poner-Reg($ruta, $nombre, $valor) {
    if ($ruta -like 'HKLM:*' -and -not $isAdmin) { return }
    if (-not (Test-Path $ruta)) { New-Item -Path $ruta -Force | Out-Null }
    Set-ItemProperty -Path $ruta -Name $nombre -Value $valor -Type DWord
}

# ---------- foto original ----------
# Si el motor aprendio a tocar un ajuste nuevo despues de tomar la foto, guardar su valor
# original ahora (antes de cambiarlo) para que "Windows original" tambien lo devuelva
function Completar-Foto {
    $foto = Get-Content $snapFile -Raw | ConvertFrom-Json
    $cambio = $false
    foreach ($p in $PLANES) { foreach ($n in $AJUSTES.Keys) {
        if (-not $foto.Energia.PSObject.Properties["$p|$n"]) {
            $v = Leer-Ajuste $p $n
            if ($v) { $foto.Energia | Add-Member -NotePropertyName "$p|$n" -NotePropertyValue ([pscustomobject]$v); $cambio = $true }
        }
    } }
    if ($cambio) { $foto | ConvertTo-Json -Depth 5 | Set-Content $snapFile -Encoding UTF8 }
}

function Tomar-Foto {
    if (Test-Path $snapFile) { Completar-Foto; return }
    $foto = [ordered]@{ Fecha = (Get-Date).ToString('s'); PlanActivo = (Plan-Activo); Energia = [ordered]@{}; Registro = [ordered]@{}; Servicios = @() }
    foreach ($p in $PLANES) { foreach ($n in $AJUSTES.Keys) { $v = Leer-Ajuste $p $n; if ($v) { $foto.Energia["$p|$n"] = $v } } }
    foreach ($r in $REGISTRO) { $foto.Registro["$($r.Ruta)|$($r.Nombre)"] = (Get-ItemProperty $r.Ruta -Name $r.Nombre -ErrorAction SilentlyContinue).($r.Nombre) }
    $foto.Servicios = @(Get-Service $SERVICIOS -ErrorAction SilentlyContinue | Where-Object Status -eq 'Running' | ForEach-Object Name)
    $foto.ModoEnergia = Leer-ModoEnergia
    $foto | ConvertTo-Json -Depth 5 | Set-Content $snapFile -Encoding UTF8
    Ok "Foto de tu configuracion original guardada."
}

$MODOS_ENERGIA = @($MODO_EFICIENCIA, $MODO_EQUILIBRADO, $MODO_RENDIMIENTO)
$CLAVES_REGISTRO = @($REGISTRO | ForEach-Object { "$($_.Ruta)|$($_.Nombre)" })

# Lee la foto aceptando SOLO planes, ajustes, claves y servicios conocidos
# (el motor puede correr como administrador: nada raro de la foto se aplica)
function Leer-Foto {
    $foto = Get-Content $snapFile -Raw | ConvertFrom-Json
    $limpia = [ordered]@{ PlanActivo = $null; ModoEnergia = $null; Energia = @(); Registro = @(); Servicios = @() }
    if ($PLANES -contains $foto.PlanActivo) { $limpia.PlanActivo = $foto.PlanActivo }
    if ($MODOS_ENERGIA -contains $foto.ModoEnergia) { $limpia.ModoEnergia = $foto.ModoEnergia }
    foreach ($e in $foto.Energia.PSObject.Properties) {
        $plan, $nombre = $e.Name -split '\|'
        if ($PLANES -contains $plan -and $AJUSTES.Contains($nombre) -and "$($e.Value.AC)" -match '^\d+$' -and "$($e.Value.DC)" -match '^\d+$') {
            $limpia.Energia += , @($plan, $nombre, [uint32]$e.Value.AC, [uint32]$e.Value.DC)
        }
    }
    foreach ($r in $foto.Registro.PSObject.Properties) {
        if ($CLAVES_REGISTRO -contains $r.Name -and ($null -eq $r.Value -or "$($r.Value)" -match '^\d+$')) {
            $ruta, $nombre = $r.Name -split '\|'
            $limpia.Registro += , @($ruta, $nombre, $r.Value)
        }
    }
    $limpia.Servicios = @($foto.Servicios | Where-Object { $SERVICIOS -contains $_ })
    return $limpia
}

function Volver-A-Original {
    $foto = Leer-Foto
    Poner-AhorroWindows $false
    if ($foto.ModoEnergia) { Poner-ModoEnergia $foto.ModoEnergia }
    foreach ($e in $foto.Energia) { Poner $e[0] $e[1] $e[2] $e[3] }
    foreach ($r in $foto.Registro) {
        $ruta, $nombre, $valor = $r
        if ($ruta -like 'HKLM:*' -and -not $isAdmin) { continue }
        if ($null -eq $valor) { Remove-ItemProperty -Path $ruta -Name $nombre -ErrorAction SilentlyContinue }
        else { Poner-Reg $ruta $nombre ([int]$valor) }
    }
    if ($isAdmin) {
        foreach ($s in $foto.Servicios) {
            $svc = Get-Service $s -ErrorAction SilentlyContinue
            if ($svc -and $svc.Status -ne 'Running') { Start-Service $s -ErrorAction SilentlyContinue }
        }
    }
    return $foto
}

# ---------- piezas de los modos ----------
function Ajustes-De-Juego {
    # Modo juego de Windows: activado, salvo con limite de velocidad (al abrir un juego
    # Windows puede saltarse el limite del plan si el Modo juego esta activado)
    $modoJuego = if ($CPU_MHZ_LIMITE -gt 0) { 0 } else { 1 }
    Poner-Reg 'HKCU:\Software\Microsoft\GameBar' 'AutoGameModeEnabled' $modoJuego
    Poner-Reg 'HKCU:\System\GameConfigStore' 'GameDVR_Enabled' 0                         # Sin grabacion en segundo plano
    Poner-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR' 'AppCaptureEnabled' 0
    if ($isAdmin) {
        Poner-Reg 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile' 'SystemResponsiveness' 10  # Windows: 20
        Ok "Modo juego $(if ($modoJuego) {'activado'} else {'apagado (respeta el limite de CPU)'}), grabacion en segundo plano apagada, prioridad al juego."
    } else {
        Ok "Modo juego $(if ($modoJuego) {'activado'} else {'apagado (respeta el limite de CPU)'}), grabacion en segundo plano apagada."
        Aviso "Prioridad al juego NO aplicada: hace falta administrador."
    }
}
function Detener-Servicios {
    if (-not $isAdmin) { Aviso "Servicios NO detenidos: hace falta administrador."; return }
    Write-Host "Deteniendo servicios innecesarios..."
    foreach ($s in $SERVICIOS) {
        $svc = Get-Service $s -ErrorAction SilentlyContinue
        if ($svc -and $svc.Status -eq 'Running') { Stop-Service $s -Force -ErrorAction SilentlyContinue; Ok "detenido: $s" }
    }
}
function Cerrar-Programas {
    Write-Host "Cerrando programas en segundo plano..."
    foreach ($p in $CERRAR) { if (Get-Process $p -ErrorAction SilentlyContinue) { Stop-Process -Name $p -Force -ErrorAction SilentlyContinue; Ok "cerrado: $p" } }
}
function Optimizar-Internet {
    ipconfig /flushdns | Out-Null
    Ok "Cache DNS limpiada."
    if ($isAdmin) {
        # Windows deja de subir actualizaciones a otras PCs (P2P); las descargas siguen normales
        Poner-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization' 'DODownloadMode' 0
        Ok "Windows ya no usa tu internet para compartir actualizaciones con otras PCs."
    } else {
        Aviso "Optimizacion de distribucion NO cambiada: hace falta administrador."
    }
}
function Liberar-RAM {
    if (-not $isAdmin) { Aviso "Memoria standby NO liberada: hace falta administrador."; return }
    if (Test-Path $RAMMAP) { & $RAMMAP -Es; Start-Sleep 2; Ok "Memoria standby liberada." } else { Aviso "RAMMap no encontrado." }
}
function Guardar-Modo($m) { Set-Content $stateFile $m -Encoding ASCII }
function Modo-Actual { if (Test-Path $stateFile) { (Get-Content $stateFile -Raw).Trim() } else { 'original' } }

# ---------- modos ----------
function Modo-Gaming([int]$mhz = $CPU_MHZ_LIMITE, [string]$id = 'gaming') {
    Volver-A-Original | Out-Null
    Poner $EQUILIBRADO CPU_MAX $CPU_MAX_JUEGO   # 99 = sin Turbo (CPU mas fresca)
    if ($CPU_MAX_JUEGO -lt 100) { Poner $EQUILIBRADO CPU_BOOST 0 }   # Turbo apagado de verdad (Speed Shift ignora el 99%)
    Limitar-Velocidad $EQUILIBRADO $mhz
    Poner $EQUILIBRADO CPU_MIN 5            # CPU baja en reposo
    Poner $EQUILIBRADO SUSPENDER 0          # Nunca suspender (descargas sin cortes)
    Poner $EQUILIBRADO PANTALLA 300         # Pantalla se apaga a los 5 min
    Activar $EQUILIBRADO
    Poner-ModoEnergia $MODO_RENDIMIENTO     # Modo de energia: Mejor rendimiento (ahorro de energia apagado)
    Ok "Plan Equilibrado + modo Mejor rendimiento. La PC NO se suspende (pantalla se apaga a los 5 min)."
    if ($CPU_MAX_JUEGO -lt 100) { Ok "Turbo desactivado para que la CPU caliente menos." }
    if ($mhz -gt 0) { Ok ("CPU limitada a {0:N1} GHz." -f ($mhz / 1000)) }
    Ajustes-De-Juego
    Detener-Servicios
    Cerrar-Programas
    Optimizar-Internet
    Liberar-RAM
    Guardar-Modo $id
}

# ---------- cerrar lo que usa CPU ----------
# Nunca se cierran: Windows, juegos y launchers, drivers, audio, antivirus, Razer, Claude.
$PROTEGIDOS = @(
    # Windows
    'System', 'Idle', 'Registry', 'smss', 'csrss', 'wininit', 'winlogon', 'services', 'lsass', 'svchost', 'dwm',
    'explorer', 'sihost', 'fontdrvhost', 'ctfmon', 'taskhostw', 'RuntimeBroker', 'ShellExperienceHost',
    'StartMenuExperienceHost', 'SearchHost', 'TextInputHost', 'ApplicationFrameHost', 'SystemSettings',
    'conhost', 'cmd', 'powershell', 'pwsh', 'WindowsTerminal', 'OpenConsole', 'SecurityHealthSystray',
    'SecurityHealthService', 'MsMpEng', 'NisSrv', 'audiodg', 'dllhost', 'LockApp', 'Taskmgr', 'userinit',
    'backgroundTaskHost', 'smartscreen', 'WUDFHost', 'spoolsv', 'MemCompression', 'SearchIndexer',
    # Juegos, launchers y anticheats
    'steam', 'steamwebhelper', 'steamservice', 'RiotClientServices', 'RiotClientUx', 'RiotClientUxRender',
    'LeagueClient', 'LeagueClientUx', 'LeagueClientUxRender', 'League of Legends', 'vgtray', 'vgc',
    'XboxPcApp', 'XboxPcAppFT', 'GamingServices', 'GamingServicesNet', 'gameinputsvc', 'GameBar',
    'GameBarFTServer', 'EpicGamesLauncher', 'EasyAntiCheat', 'BEService',
    # Drivers, audio, perifericos y antivirus
    'nvcontainer', 'NVDisplay.Container', 'NVIDIA app', 'NVIDIA Overlay', 'nvsphelper64', 'NVIDIA Web Helper',
    'RtkAudUService64', 'RAVBg64', 'RazerAppEngine', 'Razer Synapse', 'RzEngineMon', 'HipsTray', 'HipsDaemon',
    'usysdiag', 'wsctrlsvc',
    # Claude y esta herramienta
    'Claude', 'claude', 'node', 'bash', 'sh', 'git'
)
$CARPETAS_JUEGOS = '\\steamapps\\|\\XboxGames\\|\\Riot Games\\|\\Epic Games\\|\\WindowsApps\\'

function Cerrar-Lo-Que-Usa-CPU {
    Write-Host "Midiendo uso de CPU durante 3 segundos..."
    $sesion = (Get-Process -Id $PID).SessionId
    $nucleos = [Environment]::ProcessorCount
    $antes = @{}
    foreach ($p in Get-Process) { try { $antes[$p.Id] = $p.TotalProcessorTime.TotalMilliseconds } catch {} }
    Start-Sleep 3
    $filas = foreach ($p in Get-Process) {
        if ($p.SessionId -ne $sesion -or $PROTEGIDOS -contains $p.ProcessName -or $p.Id -eq $PID) { continue }
        $ruta = try { $p.Path } catch { $null }
        if ($ruta -and $ruta -match $CARPETAS_JUEGOS) { continue }
        $cpu = 0
        try { if ($antes.ContainsKey($p.Id)) { $cpu = ($p.TotalProcessorTime.TotalMilliseconds - $antes[$p.Id]) / 30 / $nucleos } } catch {}
        [pscustomobject]@{ Nombre = $p.ProcessName; CPU = $cpu; RAM = $p.WorkingSet64 }
    }
    $lista = $filas | Group-Object Nombre | ForEach-Object {
        [pscustomobject]@{
            Programa = $_.Name
            'CPU %'  = [math]::Round(($_.Group | Measure-Object CPU -Sum).Sum, 1)
            'RAM MB' = [math]::Round(($_.Group | Measure-Object RAM -Sum).Sum / 1MB)
        }
    } | Where-Object { $_.'CPU %' -ge 0.5 -or $CERRAR -contains $_.Programa } | Sort-Object 'CPU %' -Descending

    if (-not $lista) { Ok "No hay nada en segundo plano usando CPU. Todo limpio."; return }
    Write-Host ""
    Write-Host "Programas que estan usando CPU:" -ForegroundColor Cyan
    $lista | Format-Table -AutoSize | Out-String | Write-Host
    Aviso "Se cerraran SIN guardar. Guarda tu trabajo antes si tienes algo abierto."
    $r = Read-Host "Cerrar todos? (S/N)"
    if ($r -notmatch '^[sS]') { Ok "No se cerro nada."; return }
    foreach ($x in $lista) {
        Stop-Process -Name $x.Programa -Force -ErrorAction SilentlyContinue
        if (Get-Process -Name $x.Programa -ErrorAction SilentlyContinue) { Aviso "no se pudo cerrar: $($x.Programa)" } else { Ok "cerrado: $($x.Programa)" }
    }
}

if ($Modo -ne 'cerrarcpu') { Asegurar-Planes }

# ---------- regulador termico (modo Gaming dinamico) ----------
$GOBERNADOR = Join-Path $PSScriptRoot 'gobernador.ps1'
$PARAR_GOB = Join-Path $dir 'detener_gobernador'
function Procesos-Gobernador {
    @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -like '*gobernador.ps1*' })
}
function Detener-Gobernador {
    # 1) Pedirle que se apague solo: asi devuelve el ventilador de salida a la placa (solo el sabe su valor original)
    $procs = @(Procesos-Gobernador)
    if ($procs.Count -gt 0) {
        New-Item -ItemType File -Force $PARAR_GOB | Out-Null
        $hasta = (Get-Date).AddSeconds(8)
        while ((Get-Date) -lt $hasta -and (Get-Process -Id $procs.ProcessId -ErrorAction SilentlyContinue)) { Start-Sleep -Milliseconds 300 }
    }
    # 2) Si no se apago, a la fuerza (y entonces el ventilador se pone en 50%, lo que usa la placa)
    $forzado = @(Procesos-Gobernador).Count -gt 0
    try { Stop-ScheduledTask -TaskPath '\ModoGaming\' -TaskName 'gobernador' -ErrorAction Stop } catch {}
    Procesos-Gobernador | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
    Remove-Item $PARAR_GOB -Force -ErrorAction SilentlyContinue
    if ($forzado) { Restaurar-Ventilador }
}
# Solo si el regulador se cerro a la fuerza: poner el ventilador de salida en 50%, como lo tiene la placa.
# (SetDefault aqui no sirve: la libreria toma como "original" el valor que hay al abrirla, o sea el 80%)
function Restaurar-Ventilador {
    $dll = Join-Path $PSScriptRoot 'lhm\LibreHardwareMonitorLib.dll'
    if (-not $isAdmin -or -not (Test-Path $dll)) { return }
    try {
        [void][Reflection.Assembly]::LoadFrom($dll)
        $pcV = New-Object LibreHardwareMonitor.Hardware.Computer
        $pcV.IsMotherboardEnabled = $true
        $pcV.Open()
        $mb = $pcV.Hardware | Where-Object { $_.HardwareType -eq 'Motherboard' -and $_.Name -eq 'Lenovo 3102' } | Select-Object -First 1
        if ($mb) {
            $sio = $mb.SubHardware | Where-Object { $_.HardwareType -eq 'SuperIO' } | Select-Object -First 1
            $c = if ($sio) { ($sio.Sensors | Where-Object { $_.SensorType -eq 'Control' -and $_.Name -eq 'Fan #3' } | Select-Object -First 1).Control }
            if ($c) { $c.SetSoftware(50) }
        }
        # Sin $pcV.Close(): Close() devolveria el ventilador al valor que vio al abrir (80%)
    } catch {}
}
# Techo de velocidad de cada modo para el regulador termico (MHz) y como va el ventilador de salida.
# El regulador sube hasta el techo y baja (minimo 2.9 GHz) para que el CPU no pase de 85 C.
# "Windows original" no tiene regulador: deja Windows exactamente como estaba.
$TECHO_MODO = @{
    normal = $CPU_MHZ_LIMITE; ahorro = $CPU_MHZ_LIMITE; ahorrosinsusp = $CPU_MHZ_LIMITE
    gaming = $CPU_MHZ_LIMITE; altorend = $CPU_MHZ_LIMITE
    gamingfresco = $CPU_MHZ_FRESCO; cpuloose = $CPU_MHZ_LOOSE
    dinamico = $CPU_TURBO_MHZ
}
$VENT_JUEGO_MODOS = 'gaming', 'gamingfresco', 'cpuloose', 'dinamico', 'altorend'
$CFG_GOB = Join-Path $dir 'gobernador.cfg'
function Iniciar-Gobernador([string]$m) {
    if (-not $TECHO_MODO.ContainsKey($m)) { return }
    $mhz = [int]$TECHO_MODO[$m]
    if ($mhz -le 0) { $mhz = 3600 }
    if (-not (Test-Path (Join-Path $PSScriptRoot 'lhm\LibreHardwareMonitorLib.dll'))) {
        Aviso ("No se encontro el lector de temperatura: el CPU se queda fijo en {0:N1} GHz. Reinstala Modo Gaming." -f ([math]::Min($mhz, 3200) / 1000))
        $p = Plan-Activo; Limitar-Velocidad $p ([math]::Min($mhz, 3200)); Activar $p; return
    }
    $vent = if ($m -in $VENT_JUEGO_MODOS) { 'juego' } else { 'auto' }
    $turbo = if ($m -in $TURBO_MODOS) { 1 } else { 0 }
    @("max=$mhz", "ventilador=$vent", "plan=$(Plan-Activo)", "turbo=$turbo") | Set-Content $CFG_GOB -Encoding ASCII
    try { Start-ScheduledTask -TaskPath '\ModoGaming\' -TaskName 'gobernador' -ErrorAction Stop }
    catch { Start-Process powershell.exe -WindowStyle Hidden -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$GOBERNADOR`"" }
    Ok ("Regulador termico activo: hasta {0:N1} GHz, baja de a poco en 84 C (freno en 85 C) y sube bajo 80 C (minimo 2.9 GHz)." -f ($mhz / 1000))
}
function Extras-CPU-Suelto {
    Poner $EQUILIBRADO CPU_EPP 0            # CPU responde al instante (Speed Shift)
    Poner $EQUILIBRADO CPU_NUCLEOS 100      # 4 nucleos siempre listos
    Poner $EQUILIBRADO DISCO 600            # Apagar discos a los 10 min sin uso
    Poner $EQUILIBRADO USB 0                # USB siempre despiertos (el mouse no se "duerme" y no da tirones)
    Activar $EQUILIBRADO
    Poner-ModoEnergia $MODO_RENDIMIENTO
}
# Cualquier cambio de modo apaga primero el regulador (para que no pise los ajustes nuevos)
if ($Modo -notin 'snapshot', 'cerrarcpu') { Detener-Gobernador }

switch ($Modo) {
    'snapshot' { Tomar-Foto }

    'cerrarcpu' {
        Cerrar-Lo-Que-Usa-CPU
    }

    'original' {
        if (-not (Test-Path $snapFile)) { Ok "Nunca se activo ningun modo: ya estas en tu configuracion original."; break }
        $foto = Volver-A-Original
        if ($foto.PlanActivo) { Activar $foto.PlanActivo }
        if ($foto.ModoEnergia) { Poner-ModoEnergia $foto.ModoEnergia }
        if (-not $isAdmin) { Aviso "Servicios y prioridad NO restaurados: hace falta administrador (o reinicia la PC)." }
        Guardar-Modo 'original'
        Write-Host ""; Write-Host "CONFIGURACION ORIGINAL DE WINDOWS RESTAURADA." -ForegroundColor Cyan
        Write-Host "Los programas cerrados vuelven al abrirlos o al reiniciar."
    }

    'normal' {
        # Igual que Windows original (servicios, suspension, programas, todo) pero sin calentar:
        # sin Turbo y con el limite de velocidad de los modos de juego
        Tomar-Foto
        $foto = Volver-A-Original
        $plan = if ($foto.PlanActivo) { $foto.PlanActivo } else { Plan-Activo }
        Poner $plan CPU_BOOST 0
        Limitar-Velocidad $plan
        Activar $plan
        if ($foto.ModoEnergia) { Poner-ModoEnergia $foto.ModoEnergia }
        # El Modo juego de Windows puede saltarse el limite al abrir un juego
        if ($CPU_MHZ_LIMITE -gt 0) { Poner-Reg 'HKCU:\Software\Microsoft\GameBar' 'AutoGameModeEnabled' 0 }
        Ok "Todo como Windows original (servicios, suspension, programas)."
        Ok ("Turbo apagado y CPU limitada a {0:N1} GHz para que no caliente." -f ($CPU_MHZ_LIMITE / 1000))
        Guardar-Modo 'normal'
        Write-Host ""; Write-Host "MODO NORMAL FRESCO ACTIVADO." -ForegroundColor Cyan
    }

    'gaming' {
        Tomar-Foto
        Modo-Gaming
        Write-Host ""; Write-Host "MODO GAMING EFICIENTE ACTIVADO." -ForegroundColor Cyan
    }

    'gamingfresco' {
        Tomar-Foto
        Modo-Gaming $CPU_MHZ_FRESCO 'gamingfresco'
        Write-Host ""; Write-Host ("MODO GAMING FRESCO ACTIVADO (CPU a {0:N1} GHz, mas fresca)." -f ($CPU_MHZ_FRESCO / 1000)) -ForegroundColor Cyan
    }

    'cpuloose' {
        Tomar-Foto
        Modo-Gaming $CPU_MHZ_LOOSE 'cpuloose'
        Extras-CPU-Suelto
        Ok "CPU suelto: respuesta maxima y nucleos siempre listos."
        Guardar-Modo 'cpuloose'
        Write-Host ""; Write-Host "MODO GAMING EFICIENTE (CPU SUELTO) ACTIVADO." -ForegroundColor Cyan
    }

    'dinamico' {
        # Todo lo de CPU suelto, pero la velocidad la decide el regulador segun la temperatura
        Tomar-Foto
        Modo-Gaming 3200 'dinamico'      # arranca seguro en 3.2; el regulador sube hasta 4.2 con Turbo
        Extras-CPU-Suelto
        Ok "CPU suelto: respuesta maxima y nucleos siempre listos."
        Guardar-Modo 'dinamico'          # el regulador (al final) sube hasta 4.2 (Turbo) segun la temperatura
        Write-Host ""; Write-Host "MODO GAMING DINAMICO ACTIVADO." -ForegroundColor Cyan
    }

    'revertircpu' {
        if ((Modo-Actual) -ne 'cpuloose') { Ok "CPU suelto no esta activo: no hay nada que revertir."; break }
        Modo-Gaming
        Write-Host ""; Write-Host "CPU SUELTO REVERTIDO. Sigues en MODO GAMING EFICIENTE." -ForegroundColor Cyan
        Write-Host "Para volver a todo como estaba, usa 'windows original'."
    }

    'altorend' {
        Tomar-Foto
        Volver-A-Original | Out-Null
        # Plan Alto rendimiento de Windows (seguro: tu i5 no admite overclock y se protege solo por temperatura)
        Poner $ALTO CPU_MIN 5                   # CPU baja la velocidad en reposo (no gasta de mas sin jugar)
        Poner $ALTO CPU_MAX $CPU_MAX_JUEGO      # 99 = sin Turbo (CPU mas fresca)
        if ($CPU_MAX_JUEGO -lt 100) { Poner $ALTO CPU_BOOST 0 }
        Limitar-Velocidad $ALTO
        Poner $ALTO SUSPENDER 0                 # Nunca suspender
        Poner $ALTO PANTALLA 600                # Pantalla se apaga a los 10 min
        Poner $ALTO USB 0                       # USB nunca se duermen (mouse/teclado sin retrasos)
        Activar $ALTO
        Poner-ModoEnergia $MODO_RENDIMIENTO     # Modo de energia: Mejor rendimiento (ahorro de energia apagado)
        Ok "Plan Alto rendimiento + modo Mejor rendimiento. La PC NO se suspende."
        if ($CPU_MAX_JUEGO -lt 100) { Ok "Turbo desactivado para que la CPU caliente menos." }
        Ajustes-De-Juego
        Detener-Servicios
        Cerrar-Programas
        Optimizar-Internet
        Liberar-RAM
        Guardar-Modo 'altorend'
        Write-Host ""; Write-Host "MODO ALTO RENDIMIENTO SEGURO ACTIVADO." -ForegroundColor Cyan
        Write-Host "Gasta mas luz y calienta mas: vuelve a otro modo cuando no juegues."
    }

    { $_ -in 'ahorro', 'ahorrosinsusp' } {
        Tomar-Foto
        Volver-A-Original | Out-Null
        Poner $ECONOMIZADOR CPU_MAX 99          # 99% = sin Turbo Boost (gasta y calienta menos)
        Poner $ECONOMIZADOR CPU_BOOST 0         # Turbo apagado de verdad
        Limitar-Velocidad $ECONOMIZADOR
        Poner $ECONOMIZADOR CPU_EPP 80          # CPU prioriza ahorrar
        Poner $ECONOMIZADOR CPU_NUCLEOS 10      # Windows apaga nucleos que no usa
        Poner $ECONOMIZADOR USB 1               # USB inactivos ahorran energia
        if ($Modo -eq 'ahorrosinsusp') {
            Poner $ECONOMIZADOR SUSPENDER 0     # Nunca suspender (descargas sin cortes)
            Poner $ECONOMIZADOR PANTALLA 180    # Pantalla se apaga a los 3 min
        }
        Activar $ECONOMIZADOR
        Poner-ModoEnergia $MODO_EFICIENCIA      # Modo de energia: Maxima eficiencia
        Poner-AhorroWindows $true               # Interruptor "Ahorro de energia" de Windows: Activo
        if ($isAdmin) { Ok "Ahorro de energia de Windows ACTIVADO (Configuracion > Energia lo muestra Activo)." }
        Guardar-Modo $Modo
        Write-Host ""
        if ($Modo -eq 'ahorrosinsusp') {
            Write-Host "MODO AHORRO DE ENERGIA SIN SUSPENSION ACTIVADO." -ForegroundColor Cyan
            Write-Host "La PC NO se suspende (pantalla se apaga a los 3 min): ideal para dejar descargando."
        } else {
            Write-Host "MODO AHORRO DE ENERGIA ACTIVADO (Economizador, sin Turbo)." -ForegroundColor Cyan
            Write-Host "Ideal para navegar, videos y musica. Para jugar, usa un modo gaming."
        }
    }
}

# Regulador termico en el modo que quedo activo (todos menos "Windows original"):
# va despues de Guardar-Modo porque el regulador se apaga si el modo cambia.
if ($Modo -notin 'snapshot', 'cerrarcpu') {
    $modoFinal = Modo-Actual
    if ($modoFinal -ne 'original') { Iniciar-Gobernador $modoFinal }
}

try { Stop-Transcript | Out-Null } catch {}
