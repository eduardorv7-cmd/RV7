#Requires -Version 5.1
<#
.SYNOPSIS
    Auditoría de seguridad y estado del equipo para Windows 10/11. Solo lectura.

.DESCRIPTION
    Revisa la configuración de seguridad de Windows (actualizaciones, antivirus,
    cifrado, arranque seguro, firewall, cuentas, programas de inicio...) y el
    estado del hardware (BIOS, batería, disco, memoria). Está pensado para un
    Lenovo ThinkPad P14s Gen 1 (AMD), pero funciona en cualquier PC con
    Windows 10 u 11.

    El script NO cambia ninguna configuración: solo lee. Al terminar guarda dos
    informes en el Escritorio (HTML y texto) con lo que está bien, lo que
    conviene mejorar y cómo hacerlo.

    Necesita permisos de administrador para leer BitLocker, Secure Boot, TPM,
    etc. Si no los tiene, se vuelve a abrir pidiéndolos (ventana de UAC).

.PARAMETER Salida
    Carpeta donde guardar los informes. Por defecto, el Escritorio.

.PARAMETER SinWinget
    No consultar con winget qué aplicaciones tienen actualizaciones pendientes
    (esa consulta puede tardar uno o dos minutos).

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File .\Auditoria-Seguridad.ps1

.NOTES
    Los informes incluyen nombres de usuario y de programas instalados. No los
    publiques (por ejemplo, en un repositorio público de GitHub).
#>
[CmdletBinding()]
param(
    [string]$Salida,
    [switch]$SinWinget,
    # Uso interno: indica que el script se volvió a abrir con permisos de administrador.
    [switch]$Relanzado
)

$VersionScript = '1.0 (septiembre de 2026)'
$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Permisos y carpeta de salida
# ---------------------------------------------------------------------------

function Test-EsAdministrador {
    try {
        $identidad = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object Security.Principal.WindowsPrincipal($identidad)
        return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch {
        return $false
    }
}

if (-not $Salida) {
    $Salida = [Environment]::GetFolderPath('Desktop')
    if (-not $Salida -or -not (Test-Path -LiteralPath $Salida)) { $Salida = $env:USERPROFILE }
    if (-not $Salida) { $Salida = (Get-Location).Path }
}
# Una barra final dentro de comillas rompería los argumentos al relanzar ("C:\").
$Salida = $Salida.TrimEnd('\')
if ($Salida -match '^[A-Za-z]:$') { $Salida += '\.' }

$script:EsAdmin = Test-EsAdministrador
if (-not $script:EsAdmin -and -not $Relanzado) {
    Write-Host 'Este análisis necesita permisos de administrador (BitLocker, Secure Boot, TPM...).' -ForegroundColor Yellow
    if ($PSCommandPath) {
        Write-Host 'Se abrirá una ventana de Windows pidiendo permiso (UAC)...' -ForegroundColor Yellow
        $argumentos = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"{0}"' -f $PSCommandPath),
            '-Salida', ('"{0}"' -f $Salida), '-Relanzado')
        if ($SinWinget) { $argumentos += '-SinWinget' }
        try {
            Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList $argumentos
            Write-Host 'El análisis continúa en la ventana nueva.' -ForegroundColor Green
            return
        } catch {
            Write-Warning 'No se concedieron permisos de administrador. Continúo sin ellos: varias comprobaciones saldrán como "No comprobado".'
        }
    } else {
        Write-Warning 'Abre PowerShell como administrador y ejecuta el script desde ahí para un análisis completo.'
    }
}

# ---------------------------------------------------------------------------
# Utilidades
# ---------------------------------------------------------------------------

$script:Hallazgos = New-Object 'System.Collections.Generic.List[object]'
$script:Inventario = New-Object 'System.Collections.Generic.List[object]'

function Add-Hallazgo {
    param(
        [Parameter(Mandatory = $true)][string]$Categoria,
        [Parameter(Mandatory = $true)][string]$Control,
        [Parameter(Mandatory = $true)][ValidateSet('OK', 'Aviso', 'Critico', 'Info', 'Error')][string]$Estado,
        [string]$Detalle = '',
        [string]$Recomendacion = ''
    )
    $script:Hallazgos.Add([pscustomobject]@{
            Categoria     = $Categoria
            Control       = $Control
            Estado        = $Estado
            Detalle       = $Detalle
            Recomendacion = $Recomendacion
        })
}

function Add-Dato {
    param(
        [Parameter(Mandatory = $true, Position = 0)][string]$Seccion,
        [Parameter(Mandatory = $true, Position = 1)][string]$Nombre,
        [Parameter(Position = 2)][AllowEmptyString()][string]$Valor = ''
    )
    $script:Inventario.Add([pscustomobject]@{ Seccion = $Seccion; Nombre = $Nombre; Valor = $Valor })
}

function Invoke-Comprobacion {
    param(
        [Parameter(Mandatory = $true, Position = 0)][string]$Categoria,
        [Parameter(Mandatory = $true, Position = 1)][string]$Control,
        [Parameter(Mandatory = $true, Position = 2)][scriptblock]$Bloque
    )
    Write-Host ('  - {0}' -f $Control) -ForegroundColor DarkGray
    try {
        & $Bloque
    } catch {
        $motivo = $_.Exception.Message
        if (-not $script:EsAdmin) { $motivo += ' (probablemente por no tener permisos de administrador)' }
        Add-Hallazgo -Categoria $Categoria -Control $Control -Estado 'Error' -Detalle ('No se pudo comprobar: {0}' -f $motivo)
    }
}

function Get-ValorRegistro {
    param(
        [Parameter(Mandatory = $true, Position = 0)][string]$Ruta,
        [Parameter(Mandatory = $true, Position = 1)][string]$Nombre
    )
    try {
        $item = Get-ItemProperty -LiteralPath $Ruta -Name $Nombre -ErrorAction Stop
        return $item.$Nombre
    } catch {
        return $null
    }
}

function Format-Tamano {
    param([double]$Bytes)
    if ($Bytes -ge 1TB) { return ('{0:N1} TB' -f ($Bytes / 1TB)) }
    if ($Bytes -ge 1GB) { return ('{0:N0} GB' -f ($Bytes / 1GB)) }
    return ('{0:N0} MB' -f ($Bytes / 1MB))
}

function Format-Fecha {
    param($Fecha)
    if ($null -eq $Fecha) { return 'desconocida' }
    try { return ([datetime]$Fecha).ToString('dd/MM/yyyy') } catch { return [string]$Fecha }
}

function ConvertTo-HtmlSeguro {
    param([AllowNull()][object]$Texto)
    if ($null -eq $Texto) { return '' }
    return [System.Net.WebUtility]::HtmlEncode([string]$Texto)
}

# Extrae la ruta del ejecutable de una línea de comandos ("C:\a b\x.exe" -arg, C:\x.exe /y...).
function Get-RutaEjecutable {
    param([string]$Comando)
    if (-not $Comando) { return $null }
    $c = [Environment]::ExpandEnvironmentVariables($Comando.Trim())
    if ($c.StartsWith('"')) {
        $fin = $c.IndexOf('"', 1)
        if ($fin -gt 1) { return $c.Substring(1, $fin - 1) }
        return $c.Trim('"')
    }
    $m = [regex]::Match($c, '^(.+?\.(exe|com|bat|cmd|ps1|vbs|js|dll|scr))(\s|,|$)', 'IgnoreCase')
    if ($m.Success) { $ruta = $m.Groups[1].Value } else { $ruta = ($c -split '\s+')[0] }
    try {
        if ($ruta -and -not [System.IO.Path]::IsPathRooted($ruta)) {
            $enSystem32 = Join-Path (Join-Path $env:SystemRoot 'System32') $ruta
            if (Test-Path -LiteralPath $enSystem32) { $ruta = $enSystem32 }
        }
    } catch { }   # Caracteres no válidos en la ruta: se devuelve tal cual.
    return $ruta
}

function Get-Firma {
    param([string]$Ruta)
    $existe = $false
    try { $existe = [bool]$Ruta -and (Test-Path -LiteralPath $Ruta -PathType Leaf) } catch { }
    if (-not $existe) {
        return [pscustomobject]@{ Valida = $false; Estado = 'No encontrado'; Firmante = '' }
    }
    try {
        $s = Get-AuthenticodeSignature -LiteralPath $Ruta
        $firmante = ''
        if ($s.SignerCertificate) {
            $firmante = $s.SignerCertificate.GetNameInfo([System.Security.Cryptography.X509Certificates.X509NameType]::SimpleName, $false)
        }
        return [pscustomobject]@{ Valida = ([string]$s.Status -eq 'Valid'); Estado = [string]$s.Status; Firmante = $firmante }
    } catch {
        return [pscustomobject]@{ Valida = $false; Estado = 'Error'; Firmante = '' }
    }
}

# Carpetas donde un programa de arranque automático es sospechoso casi siempre.
$PatronRutaSospechosa = '(?i)\\(AppData\\Local\\Temp|Windows\\Temp|Temp|Downloads|Descargas|Users\\Public|\$Recycle\.Bin)\\'
# Comandos típicos de malware "sin archivo" o descargadores.
$PatronComandoSospechoso = '(?i)(-enc(odedcommand)?\s|frombase64string|downloadstring|downloadfile|invoke-webrequest|\biwr\s|bitsadmin|certutil.*-urlcache|mshta|wscript|cscript|regsvr32.*/i:|rundll32.*(javascript|https?:)|https?://)'

# ---------------------------------------------------------------------------
# Datos básicos del equipo
# ---------------------------------------------------------------------------

Write-Host ''
Write-Host "Auditoría de seguridad de Windows - versión $VersionScript" -ForegroundColor Cyan
Write-Host 'Solo lectura: este script no cambia nada en tu equipo.' -ForegroundColor Cyan
Write-Host ''

$os = $null; $cs = $null; $csp = $null; $bios = $null; $cpu = $null; $cv = $null
try { $os = Get-CimInstance -ClassName Win32_OperatingSystem } catch { }
try { $cs = Get-CimInstance -ClassName Win32_ComputerSystem } catch { }
try { $csp = Get-CimInstance -ClassName Win32_ComputerSystemProduct } catch { }
try { $bios = Get-CimInstance -ClassName Win32_BIOS } catch { }
try { $cpu = Get-CimInstance -ClassName Win32_Processor | Select-Object -First 1 } catch { }
try { $cv = Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' } catch { }

$build = 0
if ($cv -and $cv.CurrentBuild) { $build = [int]$cv.CurrentBuild }
$ubr = $null
if ($cv) { $ubr = $cv.UBR }
$edicion = ''
if ($cv) { $edicion = [string]$cv.EditionID }
$esHome = $edicion -like 'Core*'
$esEmpresa = $edicion -match 'Enterprise|Education'
$fabricante = ''
$modelo = ''
if ($csp) { $fabricante = [string]$csp.Vendor; $modelo = [string]$csp.Version }
$esLenovo = $fabricante -match 'LENOVO'
$cpuNombre = ''
if ($cpu) { $cpuNombre = ([string]$cpu.Name).Trim() }
$esP14sGen1Amd = $esLenovo -and ($modelo -match 'P14s Gen 1|T14 Gen 1') -and ($cpuNombre -match 'Ryzen')
$ahora = Get-Date

# ---------------------------------------------------------------------------
# 1. Sistema y actualizaciones
# ---------------------------------------------------------------------------
Write-Host 'Sistema y actualizaciones' -ForegroundColor White
$cat = 'Sistema y actualizaciones'

Invoke-Comprobacion $cat 'Versión de Windows y fin de soporte' {
    if (-not $build) { throw 'No se pudo leer la versión de Windows.' }
    $nombreSO = 'Windows'
    if ($os) { $nombreSO = $os.Caption }
    $version = $cv.DisplayVersion
    if (-not $version) { $version = $cv.ReleaseId }
    $texto = '{0} {1}, compilación {2}.{3}' -f $nombreSO, $version, $build, $ubr

    # Fin de soporte: Home/Pro (24 meses) y Enterprise/Education (36 meses).
    $soporte = @{
        19045 = @{ Nombre = 'Windows 10 22H2'; Home = [datetime]'2025-10-14'; Empresa = [datetime]'2025-10-14' }
        22000 = @{ Nombre = 'Windows 11 21H2'; Home = [datetime]'2023-10-10'; Empresa = [datetime]'2024-10-08' }
        22621 = @{ Nombre = 'Windows 11 22H2'; Home = [datetime]'2024-10-08'; Empresa = [datetime]'2025-10-14' }
        22631 = @{ Nombre = 'Windows 11 23H2'; Home = [datetime]'2025-11-11'; Empresa = [datetime]'2026-11-10' }
        26100 = @{ Nombre = 'Windows 11 24H2'; Home = [datetime]'2026-10-13'; Empresa = [datetime]'2027-10-12' }
        26200 = @{ Nombre = 'Windows 11 25H2'; Home = [datetime]'2027-10-12'; Empresa = [datetime]'2028-10-10' }
    }
    $irA11 = 'Tu P14s Gen 1 AMD es compatible con Windows 11: actualiza gratis desde Configuración > Windows Update.'
    if (-not $esP14sGen1Amd) { $irA11 = 'Comprueba si tu PC es compatible con Windows 11 (app "Comprobación de estado del PC") y actualiza.' }

    if ($build -lt 19045) {
        Add-Hallazgo $cat 'Versión de Windows' 'Critico' "$texto. Esta versión ya no recibe parches de seguridad." "Actualiza a Windows 11. $irA11"
        return
    }
    if (-not $soporte.ContainsKey($build)) {
        Add-Hallazgo $cat 'Versión de Windows' 'Info' "$texto. Es más nueva que las versiones que conoce este script." 'Mantén Windows Update activado.'
        return
    }
    $datos = $soporte[$build]
    $fin = $datos.Home
    if ($esEmpresa) { $fin = $datos.Empresa }
    $dias = [int][math]::Floor(($fin - $ahora).TotalDays)

    if ($build -eq 19045) {
        $esu = [datetime]'2026-10-13'
        $diasEsu = [int][math]::Floor(($esu - $ahora).TotalDays)
        $detalle = "$texto. Windows 10 dejó de tener soporte el 14/10/2025. Solo recibe parches si te inscribiste en ESU, y eso termina el 13/10/2026"
        if ($diasEsu -ge 0) { $detalle += " (quedan $diasEsu días)." } else { $detalle += ' (ya terminó).' }
        Add-Hallazgo $cat 'Versión de Windows' 'Critico' $detalle $irA11
        return
    }
    if ($dias -lt 0) {
        Add-Hallazgo $cat 'Versión de Windows' 'Critico' ("{0}. {1} dejó de recibir parches el {2}." -f $texto, $datos.Nombre, (Format-Fecha $fin)) 'Actualiza a la versión más reciente: Configuración > Windows Update > Buscar actualizaciones.'
    } elseif ($dias -le 60) {
        Add-Hallazgo $cat 'Versión de Windows' 'Aviso' ("{0}. {1} deja de recibir parches el {2} (quedan {3} días)." -f $texto, $datos.Nombre, (Format-Fecha $fin), $dias) 'Actualiza ya a la versión más reciente (25H2 o posterior): Configuración > Windows Update. Activa "Obtener las actualizaciones más recientes en cuanto estén disponibles".'
    } else {
        Add-Hallazgo $cat 'Versión de Windows' 'OK' ("{0}. Con soporte hasta el {1}." -f $texto, (Format-Fecha $fin))
    }
}

Invoke-Comprobacion $cat 'Último parche de Windows instalado' {
    $parches = @(Get-CimInstance -ClassName Win32_QuickFixEngineering)
    $fechas = foreach ($p in $parches) {
        $s = [string]$p.InstalledOn
        if (-not $s) { continue }
        $f = $null
        $formatos = [string[]]@('M/d/yyyy', 'MM/dd/yyyy')
        try { $f = [datetime]::ParseExact($s, $formatos, [Globalization.CultureInfo]::InvariantCulture, 'None') } catch { }
        if (-not $f) { try { $f = [datetime]::Parse($s) } catch { } }
        if (-not $f -and $s -match '^[0-9a-fA-F]{15,16}$') { try { $f = [datetime]::FromFileTime([Convert]::ToInt64($s, 16)) } catch { } }
        if ($f -and $f -le $ahora.AddDays(1)) { [pscustomobject]@{ Fecha = $f; KB = $p.HotFixID } }
    }
    $ultimo = $fechas | Sort-Object Fecha -Descending | Select-Object -First 1
    if (-not $ultimo) { throw 'No se encontraron parches con fecha de instalación.' }
    $dias = [int][math]::Floor(($ahora - $ultimo.Fecha).TotalDays)
    $detalle = 'Último parche: {0}, instalado el {1} (hace {2} días).' -f $ultimo.KB, (Format-Fecha $ultimo.Fecha), $dias
    if ($dias -gt 90) {
        Add-Hallazgo $cat 'Parches de Windows' 'Critico' $detalle 'Hace más de 3 meses que no se instalan parches. Abre Configuración > Windows Update y soluciona lo que impida actualizar.'
    } elseif ($dias -gt 45) {
        Add-Hallazgo $cat 'Parches de Windows' 'Aviso' $detalle 'Microsoft publica parches cada mes (segundo martes). Abre Configuración > Windows Update > Buscar actualizaciones.'
    } else {
        Add-Hallazgo $cat 'Parches de Windows' 'OK' $detalle
    }
}

Invoke-Comprobacion $cat 'Servicio y directivas de Windows Update' {
    $problemas = @()
    $svc = Get-CimInstance -ClassName Win32_Service -Filter "Name='wuauserv'"
    if ($svc -and $svc.StartMode -eq 'Disabled') { $problemas += 'el servicio Windows Update está deshabilitado' }
    $noAuto = Get-ValorRegistro 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU' 'NoAutoUpdate'
    if ($noAuto -eq 1) { $problemas += 'una directiva desactiva las actualizaciones automáticas (NoAutoUpdate=1)' }
    $pausa = Get-ValorRegistro 'HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings' 'PauseUpdatesExpiryTime'
    $pausadoHasta = $null
    if ($pausa) { try { $pausadoHasta = [datetime]::Parse($pausa, [Globalization.CultureInfo]::InvariantCulture) } catch { } }
    if ($problemas.Count -gt 0) {
        Add-Hallazgo $cat 'Windows Update' 'Critico' ('Windows no se puede actualizar solo: {0}. Suele pasar tras usar programas de "optimización" o "debloat".' -f ($problemas -join '; ')) 'Vuelve a activar el servicio "Windows Update" (services.msc, tipo de inicio Manual) y elimina esas directivas.'
    } elseif ($pausadoHasta -and $pausadoHasta -gt $ahora) {
        Add-Hallazgo $cat 'Windows Update' 'Aviso' ('Las actualizaciones están en pausa hasta el {0}.' -f (Format-Fecha $pausadoHasta)) 'Pulsa "Reanudar actualizaciones" en Configuración > Windows Update.'
    } else {
        Add-Hallazgo $cat 'Windows Update' 'OK' 'El servicio está activo y no hay directivas que bloqueen las actualizaciones.'
    }
}

Invoke-Comprobacion $cat 'Reinicio pendiente' {
    $pendiente = (Test-Path -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired') -or
    (Test-Path -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending')
    $detalleUptime = ''
    if ($os -and $os.LastBootUpTime) {
        $diasEncendido = [int][math]::Floor(($ahora - $os.LastBootUpTime).TotalDays)
        $detalleUptime = " El equipo lleva $diasEncendido días sin reiniciarse (apagar con el inicio rápido activado no cuenta como reinicio)."
    }
    if ($pendiente) {
        Add-Hallazgo $cat 'Reinicio pendiente' 'Aviso' ('Hay actualizaciones esperando un reinicio para terminar de instalarse.' + $detalleUptime) 'Reinicia el equipo (Inicio > Encendido > Reiniciar).'
    } else {
        Add-Hallazgo $cat 'Reinicio pendiente' 'OK' ('No hay reinicios pendientes.' + $detalleUptime)
    }
}

if (-not $SinWinget) {
    Invoke-Comprobacion $cat 'Aplicaciones con actualizaciones (winget)' {
        Write-Host '    (consultando winget, puede tardar un poco...)' -ForegroundColor DarkGray
        $trabajo = Start-Job -ScriptBlock {
            try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }
            $exe = Get-Command -Name 'winget.exe' -ErrorAction SilentlyContinue
            if (-not $exe) { return '__SIN_WINGET__' }
            & $exe.Source upgrade --include-unknown --accept-source-agreements --disable-interactivity 2>&1 | Out-String -Width 400
        }
        $salidaWinget = $null
        if (Wait-Job -Job $trabajo -Timeout 180) { $salidaWinget = Receive-Job -Job $trabajo | Out-String } else { Stop-Job -Job $trabajo }
        Remove-Job -Job $trabajo -Force
        if (-not $salidaWinget) {
            Add-Hallazgo $cat 'Actualizaciones de aplicaciones' 'Info' 'winget no respondió a tiempo.' 'Ejecuta "winget upgrade" en PowerShell para ver qué aplicaciones tienen actualizaciones.'
            return
        }
        if ($salidaWinget -match '__SIN_WINGET__') {
            Add-Hallazgo $cat 'Actualizaciones de aplicaciones' 'Info' 'winget no está instalado para este usuario.' 'Instala "Instalador de aplicación" desde Microsoft Store para poder actualizar programas con winget.'
            return
        }
        $lineas = $salidaWinget -split "`r?`n" | ForEach-Object { $_.TrimEnd() } |
        Where-Object { $_ -and $_ -notmatch '^\s*[-\\|/]\s*$' -and $_ -notmatch '[\u2580-\u259F]' }
        $inicio = -1
        for ($i = 0; $i -lt $lineas.Count; $i++) { if ($lineas[$i] -match '^-{10,}') { $inicio = $i; break } }
        $filas = @()
        if ($inicio -ge 0) {
            for ($i = $inicio + 1; $i -lt $lineas.Count; $i++) {
                if ($lineas[$i] -match '^\d+\s' -or $lineas[$i] -match '^-{10,}') { break }
                $filas += $lineas[$i].Trim()
            }
        }
        $n = $filas.Count
        $m = [regex]::Match($salidaWinget, '(?m)^\s*(\d+)\s+(actualizaci|upgrades? available)')
        if ($m.Success) { $n = [int]$m.Groups[1].Value }
        if ($n -gt 0) {
            $lista = ($filas | Select-Object -First 40) -join "`n"
            Add-Hallazgo $cat 'Actualizaciones de aplicaciones' 'Aviso' ("$n aplicaciones tienen versiones nuevas (los programas desactualizados son una vía de ataque muy común):`n$lista") 'Actualízalas: en PowerShell, "winget upgrade --all", o desde cada programa.'
        } else {
            Add-Hallazgo $cat 'Actualizaciones de aplicaciones' 'OK' 'winget no encontró aplicaciones con actualizaciones pendientes.'
        }
    }
}

# ---------------------------------------------------------------------------
# 2. Antivirus y protección
# ---------------------------------------------------------------------------
Write-Host 'Antivirus y protección' -ForegroundColor White
$cat = 'Antivirus y protección'

$script:MpEstado = $null
$script:MpPreferencias = $null
$script:DefenderActivo = $false
try { $script:MpEstado = Get-MpComputerStatus } catch { }
try { $script:MpPreferencias = Get-MpPreference } catch { }
if ($script:MpEstado -and $script:MpEstado.AntivirusEnabled -and $script:MpEstado.RealTimeProtectionEnabled) { $script:DefenderActivo = $true }

Invoke-Comprobacion $cat 'Antivirus activo' {
    $otros = @()
    try {
        $productos = @(Get-CimInstance -Namespace 'root/SecurityCenter2' -ClassName AntiVirusProduct)
        foreach ($p in $productos) {
            $hex = [Convert]::ToString([int64]$p.productState, 16).PadLeft(6, '0')
            $activo = $hex.Substring(2, 2) -in @('10', '11')
            $alDia = $hex.Substring(4, 2) -eq '00'
            if ($p.displayName -notmatch 'Windows Defender|Microsoft Defender') {
                $otros += [pscustomobject]@{ Nombre = $p.displayName; Activo = $activo; AlDia = $alDia }
            }
        }
    } catch { }
    $otrosActivos = @($otros | Where-Object { $_.Activo })
    if ($script:DefenderActivo) {
        Add-Hallazgo $cat 'Antivirus' 'OK' 'Microsoft Defender está activo con protección en tiempo real.'
    } elseif ($otrosActivos.Count -gt 0) {
        $nombres = ($otrosActivos | ForEach-Object { $_.Nombre }) -join ', '
        Add-Hallazgo $cat 'Antivirus' 'OK' "La protección la da otro antivirus: $nombres."
        foreach ($o in $otrosActivos) {
            if (-not $o.AlDia) { Add-Hallazgo $cat 'Firmas del antivirus' 'Aviso' ("{0} indica que sus firmas no están al día." -f $o.Nombre) 'Abre el antivirus y actualízalo.' }
        }
    } elseif ($script:MpEstado) {
        Add-Hallazgo $cat 'Antivirus' 'Critico' 'Microsoft Defender no tiene la protección en tiempo real activada y no hay otro antivirus activo.' 'Abre Seguridad de Windows > Protección antivirus y contra amenazas y activa la protección en tiempo real.'
    } else {
        throw 'No se pudo leer el estado de Microsoft Defender ni del Centro de seguridad.'
    }
}

if ($script:DefenderActivo) {
    Invoke-Comprobacion $cat 'Firmas y análisis de Defender' {
        $edad = [int]$script:MpEstado.AntivirusSignatureAge
        $detalle = 'Firmas de hace {0} días (versión {1}).' -f $edad, $script:MpEstado.AntivirusSignatureVersion
        if ($edad -gt 7) {
            Add-Hallazgo $cat 'Firmas de Defender' 'Critico' $detalle 'Actualiza: Seguridad de Windows > Protección antivirus > Buscar actualizaciones.'
        } elseif ($edad -gt 2) {
            Add-Hallazgo $cat 'Firmas de Defender' 'Aviso' $detalle 'Actualiza: Seguridad de Windows > Protección antivirus > Buscar actualizaciones.'
        } else {
            Add-Hallazgo $cat 'Firmas de Defender' 'OK' $detalle
        }
    }

    Invoke-Comprobacion $cat 'Protección contra alteraciones' {
        if ($script:MpEstado.IsTamperProtected) {
            Add-Hallazgo $cat 'Protección contra alteraciones' 'OK' 'Activada: el malware no puede apagar Defender cambiando su configuración.'
        } else {
            Add-Hallazgo $cat 'Protección contra alteraciones' 'Aviso' 'Desactivada: un programa malicioso podría apagar Defender.' 'Seguridad de Windows > Protección antivirus > Administrar la configuración > Protección contra alteraciones: Activada.'
        }
    }

    Invoke-Comprobacion $cat 'Protección en la nube y aplicaciones no deseadas' {
        $p = $script:MpPreferencias
        if (-not $p) { throw 'No se pudieron leer las preferencias de Defender.' }
        if ([int]$p.MAPSReporting -eq 0) {
            Add-Hallazgo $cat 'Protección basada en la nube' 'Aviso' 'Desactivada: Defender tarda más en reconocer amenazas nuevas.' 'Seguridad de Windows > Protección antivirus > Administrar la configuración > Protección basada en la nube: Activada.'
        } else {
            Add-Hallazgo $cat 'Protección basada en la nube' 'OK' 'Activada.'
        }
        if ([int]$p.PUAProtection -eq 1) {
            Add-Hallazgo $cat 'Bloqueo de aplicaciones no deseadas' 'OK' 'Activado: bloquea adware, mineros y programas "de regalo" en instaladores.'
        } else {
            Add-Hallazgo $cat 'Bloqueo de aplicaciones no deseadas' 'Aviso' 'Desactivado: Defender deja pasar adware y programas potencialmente no deseados.' 'Seguridad de Windows > Control de aplicaciones y navegador > Protección basada en reputación > Bloqueo de aplicaciones potencialmente no deseadas: Activado (marca "Bloquear aplicaciones" y "Bloquear descargas").'
        }
        if ([int]$p.EnableControlledFolderAccess -eq 1) {
            Add-Hallazgo $cat 'Acceso controlado a carpetas' 'OK' 'Activado: protege Documentos, Imágenes, etc. frente a ransomware.'
        } else {
            Add-Hallazgo $cat 'Acceso controlado a carpetas' 'Info' 'Desactivado (es lo normal por defecto).' 'Opcional: actívalo en Seguridad de Windows > Protección antivirus > Protección contra ransomware. Si bloquea un programa legítimo, puedes permitirlo desde ahí. Y, sobre todo, ten copia de seguridad de tus archivos.'
        }
    }

    Invoke-Comprobacion $cat 'Exclusiones de Defender' {
        $p = $script:MpPreferencias
        if (-not $p) { throw 'No se pudieron leer las preferencias de Defender.' }
        $exclusiones = @()
        foreach ($nombre in 'ExclusionPath', 'ExclusionProcess', 'ExclusionExtension') {
            foreach ($valor in @($p.$nombre)) {
                if ($valor -and $valor -notmatch '^N/A') { $exclusiones += ('{0}: {1}' -f $nombre, $valor) }
            }
        }
        if ($exclusiones.Count -gt 0) {
            Add-Hallazgo $cat 'Exclusiones de Defender' 'Aviso' ("Defender no analiza lo siguiente:`n" + ($exclusiones -join "`n")) 'Si no añadiste tú estas exclusiones, elimínalas (Seguridad de Windows > Protección antivirus > Administrar la configuración > Exclusiones). El malware suele añadirse a sí mismo aquí.'
        } else {
            Add-Hallazgo $cat 'Exclusiones de Defender' 'OK' 'No hay carpetas, procesos ni extensiones excluidos del análisis.'
        }
    }

    Invoke-Comprobacion $cat 'Amenazas detectadas (últimos 30 días)' {
        $detecciones = @(Get-MpThreatDetection | Where-Object { $_.InitialDetectionTime -gt $ahora.AddDays(-30) })
        if ($detecciones.Count -eq 0) {
            Add-Hallazgo $cat 'Amenazas recientes' 'OK' 'Defender no ha detectado amenazas en los últimos 30 días.'
            return
        }
        $nombres = @{}
        try { Get-MpThreat | ForEach-Object { $nombres[[string]$_.ThreatID] = $_.ThreatName } } catch { }
        $resueltos = @(2, 3, 4, 6)   # limpiada, en cuarentena, eliminada, bloqueada
        $textosEstado = @{
            1 = 'detectada, sin resolver'; 2 = 'limpiada'; 3 = 'en cuarentena'; 4 = 'eliminada'; 5 = 'PERMITIDA'
            6 = 'bloqueada'; 102 = 'falló la cuarentena'; 103 = 'falló la eliminación'; 104 = 'falló al permitirla'
            105 = 'abandonada'; 107 = 'falló el bloqueo'
        }
        $lineas = @()
        $pendientes = 0
        foreach ($d in $detecciones) {
            $estadoId = [int]$d.ThreatStatusID
            if ($estadoId -notin $resueltos) { $pendientes++ }
            $nombre = $nombres[[string]$d.ThreatID]
            if (-not $nombre) { $nombre = 'Amenaza ' + $d.ThreatID }
            $textoEstado = $textosEstado[$estadoId]
            if (-not $textoEstado) { $textoEstado = "estado $estadoId" }
            $recursos = (@($d.Resources) | ForEach-Object { $_ -replace '^\w+:_', '' }) -join ' '
            $lineas += ('{0} - {1} ({2}) {3}' -f (Format-Fecha $d.InitialDetectionTime), $nombre, $textoEstado, $recursos)
        }
        if ($pendientes -gt 0) {
            Add-Hallazgo $cat 'Amenazas recientes' 'Critico' ("Hay detecciones sin resolver o permitidas:`n" + ($lineas -join "`n")) 'Abre Seguridad de Windows > Protección antivirus > Historial de protección y elimina las amenazas. Después haz un "Análisis sin conexión de Microsoft Defender".'
        } else {
            Add-Hallazgo $cat 'Amenazas recientes' 'Aviso' ("Defender bloqueó o eliminó amenazas recientemente:`n" + ($lineas -join "`n")) 'Revisa de dónde venían (descargas, USB, correo) para no repetir.'
        }
    }
}

Invoke-Comprobacion $cat 'SmartScreen y Control inteligente de aplicaciones' {
    $ss = Get-ValorRegistro 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer' 'SmartScreenEnabled'
    $ssPolitica = Get-ValorRegistro 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System' 'EnableSmartScreen'
    if ($ss -eq 'Off' -or $ssPolitica -eq 0) {
        Add-Hallazgo $cat 'SmartScreen' 'Aviso' 'SmartScreen para aplicaciones y archivos está desactivado: Windows no te avisará al abrir programas descargados sospechosos.' 'Seguridad de Windows > Control de aplicaciones y navegador > Protección basada en reputación: activa "Comprobar aplicaciones y archivos".'
    } else {
        Add-Hallazgo $cat 'SmartScreen' 'OK' 'SmartScreen está activo (avisa antes de abrir programas desconocidos).'
    }
    $sac = Get-ValorRegistro 'HKLM:\SYSTEM\CurrentControlSet\Control\CI\Policy' 'VerifiedAndReputablePolicyState'
    if ($null -ne $sac) {
        $textoSac = switch ([int]$sac) { 0 { 'desactivado' } 1 { 'activado' } 2 { 'en evaluación' } default { "estado $sac" } }
        Add-Hallazgo $cat 'Control inteligente de aplicaciones' 'Info' "Smart App Control: $textoSac." 'Solo se puede activar en instalaciones limpias de Windows 11; si está desactivado, no pasa nada mientras Defender y SmartScreen estén activos.'
    }
}

# ---------------------------------------------------------------------------
# 3. Cifrado y arranque
# ---------------------------------------------------------------------------
Write-Host 'Cifrado y arranque' -ForegroundColor White
$cat = 'Cifrado y arranque'

$script:TpmFabricante = ''
Invoke-Comprobacion $cat 'Chip de seguridad (TPM)' {
    $tpm = Get-Tpm
    if (-not $tpm.TpmPresent) {
        Add-Hallazgo $cat 'TPM' 'Critico' 'No se detecta TPM. Windows 11, BitLocker y Windows Hello lo necesitan.' 'Actívalo en la BIOS: Security > Security Chip (Lenovo).'
        return
    }
    $version = ''
    try {
        $w = Get-CimInstance -Namespace 'root/cimv2/Security/MicrosoftTpm' -ClassName Win32_Tpm
        $version = ([string]$w.SpecVersion -split ',')[0].Trim()
    } catch { }
    $fab = [string]$tpm.ManufacturerIdTxt
    $script:TpmFabricante = $fab
    $tipo = switch -Regex ($fab) {
        '^AMD' { 'fTPM de AMD (integrado en el procesador)' }
        '^INTC' { 'Intel PTT (integrado en el procesador)' }
        '^MSFT' { 'Microsoft Pluton' }
        '^NTC' { 'chip discreto Nuvoton' }
        '^STM' { 'chip discreto STMicroelectronics' }
        '^IFX' { 'chip discreto Infineon' }
        default { "fabricante $fab" }
    }
    $detalle = 'TPM {0}, {1}. Listo para usarse: {2}.' -f $version, $tipo, $(if ($tpm.TpmReady) { 'sí' } else { 'no' })
    if ($tpm.TpmReady) {
        Add-Hallazgo $cat 'TPM' 'OK' $detalle
    } else {
        Add-Hallazgo $cat 'TPM' 'Aviso' $detalle 'Abre tpm.msc para ver qué falta, o actívalo en la BIOS.'
    }
}

Invoke-Comprobacion $cat 'Cifrado del disco (BitLocker)' {
    $unidad = $env:SystemDrive
    $vol = Get-CimInstance -Namespace 'root/cimv2/Security/MicrosoftVolumeEncryption' -ClassName Win32_EncryptableVolume -Filter ("DriveLetter='{0}'" -f $unidad)
    if (-not $vol) { throw 'Esta edición de Windows no expone BitLocker/Cifrado del dispositivo.' }
    $proteccion = [int](Invoke-CimMethod -InputObject $vol -MethodName GetProtectionStatus).ProtectionStatus
    $conversion = [int](Invoke-CimMethod -InputObject $vol -MethodName GetConversionStatus).ConversionStatus
    $metodo = [int](Invoke-CimMethod -InputObject $vol -MethodName GetEncryptionMethod).EncryptionMethod
    $tipos = @()
    $ids = @((Invoke-CimMethod -InputObject $vol -MethodName GetKeyProtectors -Arguments @{ KeyProtectorType = [uint32]0 }).VolumeKeyProtectorID)
    foreach ($id in $ids) {
        if ($id) { $tipos += [int](Invoke-CimMethod -InputObject $vol -MethodName GetKeyProtectorType -Arguments @{ VolumeKeyProtectorID = $id }).KeyProtectorType }
    }
    $nombreMetodo = switch ($metodo) { 6 { 'XTS-AES 128' } 7 { 'XTS-AES 256' } 3 { 'AES-CBC 128' } 4 { 'AES-CBC 256' } 5 { 'cifrado por hardware del SSD' } default { "método $metodo" } }
    $nombreBitLocker = 'BitLocker'
    if ($esHome) { $nombreBitLocker = 'Cifrado del dispositivo' }

    if ($conversion -eq 0) {
        $como = 'Panel de control > Cifrado de unidad BitLocker > Activar BitLocker. Guarda la clave de recuperación fuera del PC (en tu cuenta Microsoft o impresa).'
        if ($esHome) { $como = 'Configuración > Privacidad y seguridad > Cifrado del dispositivo > Activado (necesita iniciar sesión con una cuenta Microsoft, que guardará la clave de recuperación). Si no aparece esa opción, tu edición Home no lo admite: plantéate Windows Pro.' }
        Add-Hallazgo $cat $nombreBitLocker 'Critico' "El disco $unidad NO está cifrado: si te roban o pierdes el portátil, pueden leer todos tus archivos y contraseñas guardadas." $como
        return
    }
    if ($conversion -in @(2, 4)) {
        Add-Hallazgo $cat $nombreBitLocker 'Aviso' "El cifrado de $unidad está en curso o en pausa." 'Deja el portátil enchufado y encendido hasta que termine.'
        return
    }
    if ($proteccion -ne 1) {
        Add-Hallazgo $cat $nombreBitLocker 'Aviso' "El disco $unidad está cifrado, pero la protección está suspendida (la clave está accesible sin protección). Es normal justo antes de actualizar la BIOS; no debería quedarse así." 'Reinicia; si sigue suspendido, ejecuta como administrador: manage-bde -protectors -enable C:'
        return
    }

    $soloTpm = ($tipos -contains 1) -and -not (($tipos -contains 4) -or ($tipos -contains 5) -or ($tipos -contains 6))
    $tieneRecuperacion = $tipos -contains 3
    $detalle = "El disco $unidad está cifrado con $nombreMetodo."
    if ($tieneRecuperacion) { $detalle += ' Tiene clave de recuperación: asegúrate de tenerla guardada fuera del PC (account.microsoft.com/devices/recoverykey si la subiste a tu cuenta Microsoft).' }
    Add-Hallazgo $cat $nombreBitLocker 'OK' $detalle

    if ($soloTpm) {
        $porque = 'El portátil arranca y descifra el disco sin pedir nada; quien lo robe puede intentar extraer la clave del TPM con acceso físico'
        if ($script:TpmFabricante -match '^AMD') {
            $porque += ' (en procesadores AMD Zen 2 como el tuyo existe el ataque "faulTPM", que extrae los secretos del fTPM en unas horas con el equipo abierto).'
        } else {
            $porque += ' (con un TPM discreto, espiando el bus entre el chip y el procesador).'
        }
        if ($esHome) {
            Add-Hallazgo $cat 'Desbloqueo del cifrado' 'Info' ($porque + ' Windows Home no permite añadir un PIN de arranque.') 'Usa una contraseña o PIN de Windows robusto y Windows Hello. Si pasas a Windows Pro, activa BitLocker con TPM + PIN.'
        } else {
            Add-Hallazgo $cat 'Desbloqueo del cifrado' 'Aviso' ($porque + ' Un PIN de arranque lo evita.') 'Activa TPM + PIN: gpedit.msc > Configuración del equipo > Plantillas administrativas > Componentes de Windows > Cifrado de unidad BitLocker > Unidades del sistema operativo > "Requerir autenticación adicional al iniciar" (Habilitada) y "Permitir PIN mejorados para el inicio" (Habilitada). Después, como administrador: manage-bde -protectors -add C: -TPMAndPIN. Usa un PIN mejorado largo, tipo frase (15-20 caracteres con letras y números): si extraen el TPM, el PIN se puede atacar sin límite de intentos y uno corto no basta.'
        }
    }
}

Invoke-Comprobacion $cat 'Arranque seguro (Secure Boot)' {
    $activo = $false
    try {
        $activo = Confirm-SecureBootUEFI
    } catch {
        if ($_.Exception -is [System.PlatformNotSupportedException] -or $_.Exception.Message -match 'not supported|no se admite|no compatible') {
            Add-Hallazgo $cat 'Arranque seguro' 'Critico' 'El equipo arranca en modo heredado (Legacy/CSM), sin arranque seguro.' 'En la BIOS: Startup > UEFI/Legacy Boot = UEFI Only y Security > Secure Boot = On. Si Windows se instaló en modo Legacy, antes hay que convertir el disco a GPT (mbr2gpt).'
            return
        }
        throw
    }
    if ($activo) {
        Add-Hallazgo $cat 'Arranque seguro' 'OK' 'Activado: solo arrancan cargadores firmados (protege contra bootkits).'
    } else {
        Add-Hallazgo $cat 'Arranque seguro' 'Critico' 'Desactivado: un bootkit podría cargarse antes que Windows y el antivirus.' 'Actívalo en la BIOS (F1 al encender): Security > Secure Boot > Secure Boot: On.'
        return
    }

    # Certificados de 2023: los de 2011 caducan entre junio y octubre de 2026.
    $db = [System.Text.Encoding]::ASCII.GetString((Get-SecureBootUEFI -Name db).Bytes)
    $kek = [System.Text.Encoding]::ASCII.GetString((Get-SecureBootUEFI -Name KEK).Bytes)
    $dbNuevo = $db -match 'Windows UEFI CA 2023'
    $kekNuevo = $kek -match 'Microsoft Corporation KEK 2K CA 2023'
    $estadoServicio = Get-ValorRegistro 'HKLM:\SYSTEM\CurrentControlSet\Control\SecureBoot\Servicing' 'UEFICA2023Status'
    $detalle = 'Certificado "Windows UEFI CA 2023" en la base de datos (db): {0}. Clave "KEK 2K CA 2023": {1}.' -f $(if ($dbNuevo) { 'sí' } else { 'no' }), $(if ($kekNuevo) { 'sí' } else { 'no' })
    if ($estadoServicio) { $detalle += " Estado de la actualización en Windows: $estadoServicio." }
    if ($dbNuevo -and $kekNuevo) {
        Add-Hallazgo $cat 'Certificados de arranque seguro 2023' 'OK' $detalle
    } else {
        Add-Hallazgo $cat 'Certificados de arranque seguro 2023' 'Aviso' ($detalle + ' Los certificados de Microsoft de 2011 caducan entre junio y octubre de 2026. El PC seguirá arrancando, pero sin los nuevos no recibirá futuras correcciones de seguridad del arranque.') 'Instala todas las actualizaciones de Windows (Microsoft las despliega automáticamente desde enero de 2026) y la BIOS más reciente de Lenovo. Vuelve a ejecutar este análisis tras un par de reinicios.'
    }
}

Invoke-Comprobacion $cat 'Aislamiento del núcleo e integridad de memoria' {
    $dg = Get-CimInstance -Namespace 'root/Microsoft/Windows/DeviceGuard' -ClassName Win32_DeviceGuard
    $servicios = @($dg.SecurityServicesRunning)
    if ([int]$dg.VirtualizationBasedSecurityStatus -eq 2) {
        Add-Hallazgo $cat 'Seguridad basada en virtualización (VBS)' 'OK' 'VBS está en funcionamiento.'
    } else {
        Add-Hallazgo $cat 'Seguridad basada en virtualización (VBS)' 'Info' 'VBS no está en funcionamiento. Se activa sola al encender la integridad de memoria.' 'Comprueba en la BIOS que la virtualización (AMD-V/SVM) esté activada.'
    }
    if ($servicios -contains 2) {
        Add-Hallazgo $cat 'Integridad de memoria (HVCI)' 'OK' 'Activada: impide cargar drivers maliciosos o vulnerables en el núcleo.'
    } else {
        Add-Hallazgo $cat 'Integridad de memoria (HVCI)' 'Aviso' 'Desactivada. En un Ryzen 4000 (Zen 2) funciona bien y apenas afecta al rendimiento.' 'Seguridad de Windows > Seguridad del dispositivo > Detalles de aislamiento del núcleo > Integridad de memoria: Activada. Si un driver antiguo lo impide, Windows te dirá cuál; actualízalo o desinstálalo.'
    }
    if ($esEmpresa) {
        if ($servicios -contains 1) {
            Add-Hallazgo $cat 'Credential Guard' 'OK' 'Activado.'
        } else {
            Add-Hallazgo $cat 'Credential Guard' 'Info' 'No está en funcionamiento.' 'En ediciones Enterprise/Education puedes activarlo por directiva de grupo.'
        }
    }
}

Invoke-Comprobacion $cat 'Protección de LSA y lista de drivers vulnerables' {
    $ppl = Get-ValorRegistro 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa' 'RunAsPPL'
    if ($ppl -in @(1, 2)) {
        Add-Hallazgo $cat 'Protección de la autoridad de seguridad local (LSA)' 'OK' 'Activada: dificulta que un malware robe contraseñas de la memoria.'
    } else {
        Add-Hallazgo $cat 'Protección de la autoridad de seguridad local (LSA)' 'Aviso' 'Desactivada: herramientas como Mimikatz pueden leer credenciales de la memoria.' 'Seguridad de Windows > Seguridad del dispositivo > Detalles de aislamiento del núcleo > Protección de la autoridad de seguridad local: Activada (y reinicia).'
    }
    $vdb = Get-ValorRegistro 'HKLM:\SYSTEM\CurrentControlSet\Control\CI\Config' 'VulnerableDriverBlocklistEnable'
    if ($vdb -eq 0) {
        Add-Hallazgo $cat 'Lista de bloqueados de drivers vulnerables' 'Aviso' 'Desactivada: se permiten drivers con vulnerabilidades conocidas.' 'Seguridad de Windows > Seguridad del dispositivo > Detalles de aislamiento del núcleo > Lista de bloqueados de controladores vulnerables de Microsoft: Activada.'
    } elseif ($vdb -eq 1 -or $build -ge 22621) {
        Add-Hallazgo $cat 'Lista de bloqueados de drivers vulnerables' 'OK' 'Activada.'
    } else {
        Add-Hallazgo $cat 'Lista de bloqueados de drivers vulnerables' 'Info' 'Valor por defecto de Windows 10.' 'Actívala en Seguridad de Windows > Seguridad del dispositivo > Detalles de aislamiento del núcleo.'
    }
}

# ---------------------------------------------------------------------------
# 4. Red y firewall
# ---------------------------------------------------------------------------
Write-Host 'Red y firewall' -ForegroundColor White
$cat = 'Red y firewall'

Invoke-Comprobacion $cat 'Firewall de Windows' {
    $perfiles = @(Get-NetFirewallProfile -PolicyStore ActiveStore)
    $nombresPerfil = @{ Domain = 'dominio'; Private = 'privada'; Public = 'pública' }
    $apagados = @($perfiles | Where-Object { [string]$_.Enabled -ne 'True' } | ForEach-Object { $nombresPerfil[[string]$_.Name] })
    $permiten = @($perfiles | Where-Object { [string]$_.DefaultInboundAction -eq 'Allow' } | ForEach-Object { $nombresPerfil[[string]$_.Name] })
    $otroFirewall = ''
    try {
        $fw = @(Get-CimInstance -Namespace 'root/SecurityCenter2' -ClassName FirewallProduct)
        $otroFirewall = ($fw | ForEach-Object { $_.displayName }) -join ', '
    } catch { }
    if ($apagados.Count -eq 0 -and $permiten.Count -eq 0) {
        Add-Hallazgo $cat 'Firewall' 'OK' 'Activo en los perfiles de dominio, privado y público, bloqueando conexiones entrantes no permitidas.'
        return
    }
    if ($otroFirewall) {
        Add-Hallazgo $cat 'Firewall' 'Info' ("El firewall de Windows está desactivado en la red {0}, pero hay otro firewall registrado: {1}." -f ($apagados -join ', '), $otroFirewall) 'Asegúrate de que ese firewall está activo y actualizado.'
        return
    }
    $estado = 'Aviso'
    if ($apagados -contains 'pública' -or $permiten -contains 'pública') { $estado = 'Critico' }
    $detalle = @()
    if ($apagados.Count) { $detalle += ('desactivado en el perfil de red ' + ($apagados -join ', ')) }
    if ($permiten.Count) { $detalle += ('permite todo lo entrante en el perfil ' + ($permiten -join ', ')) }
    Add-Hallazgo $cat 'Firewall' $estado ('El firewall de Windows está ' + ($detalle -join '; ') + '. En una Wi-Fi pública cualquiera podría conectarse a servicios de tu PC.') 'Seguridad de Windows > Firewall y protección de red: activa los tres perfiles.'
}

Invoke-Comprobacion $cat 'Perfil de las redes conectadas' {
    $redes = @(Get-NetConnectionProfile)
    if ($redes.Count -eq 0) {
        Add-Hallazgo $cat 'Redes conectadas' 'Info' 'No hay ninguna red conectada ahora mismo.'
        return
    }
    $lineas = $redes | ForEach-Object {
        $tipoRed = switch ([string]$_.NetworkCategory) { 'Public' { 'pública' } 'Private' { 'privada' } 'DomainAuthenticated' { 'de dominio' } default { [string]$_.NetworkCategory } }
        '{0} ({1}): red {2}' -f $_.Name, $_.InterfaceAlias, $tipoRed
    }
    Add-Hallazgo $cat 'Redes conectadas' 'Info' ($lineas -join "`n") 'Marca como "privada" solo la red de tu casa. Cafeterías, hoteles, aeropuertos y universidades: siempre "pública" (Configuración > Red e Internet > Wi-Fi > Propiedades).'
}

Invoke-Comprobacion $cat 'Compartir archivos en redes públicas' {
    $grupos = @{
        '@FirewallAPI.dll,-28502' = 'Compartir archivos e impresoras'
        '@FirewallAPI.dll,-32752' = 'Detección de redes'
    }
    $abiertos = @()
    foreach ($g in $grupos.Keys) {
        $reglas = @(Get-NetFirewallRule -Group $g -ErrorAction SilentlyContinue |
            Where-Object { [string]$_.Direction -eq 'Inbound' -and [string]$_.Enabled -eq 'True' -and ([string]$_.Profile -match 'Public|Any') })
        if ($reglas.Count -gt 0) { $abiertos += $grupos[$g] }
    }
    if ($abiertos.Count -gt 0) {
        Add-Hallazgo $cat 'Uso compartido en redes públicas' 'Aviso' ('Activado en redes públicas: ' + ($abiertos -join ', ') + '. Otros dispositivos de una Wi-Fi pública podrían ver tu PC y sus carpetas compartidas.') 'Configuración > Red e Internet > Configuración de red avanzada > Configuración de uso compartido avanzado > Redes públicas: desactiva "Detección de redes" y "Uso compartido de archivos e impresoras".'
    } else {
        Add-Hallazgo $cat 'Uso compartido en redes públicas' 'OK' 'La detección de redes y el uso compartido de archivos están cerrados en redes públicas.'
    }
}

Invoke-Comprobacion $cat 'SMBv1 (protocolo obsoleto)' {
    $f = Get-WindowsOptionalFeature -Online -FeatureName SMB1Protocol
    if ($f -and [string]$f.State -eq 'Enabled') {
        Add-Hallazgo $cat 'SMBv1' 'Critico' 'SMBv1 está instalado. Es el protocolo que usaron WannaCry y NotPetya.' 'Panel de control > Programas > Activar o desactivar las características de Windows > desmarca "Compatibilidad con el protocolo para compartir archivos SMB 1.0/CIFS" y reinicia.'
    } else {
        Add-Hallazgo $cat 'SMBv1' 'OK' 'No está instalado.'
    }
}

Invoke-Comprobacion $cat 'Escritorio remoto' {
    $deny = Get-ValorRegistro 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server' 'fDenyTSConnections'
    $denyPol = Get-ValorRegistro 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services' 'fDenyTSConnections'
    if ($null -ne $denyPol) { $deny = $denyPol }
    if ($deny -eq 0) {
        $nla = Get-ValorRegistro 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' 'UserAuthentication'
        if ($nla -eq 0) {
            Add-Hallazgo $cat 'Escritorio remoto' 'Critico' 'El Escritorio remoto está activado SIN autenticación a nivel de red (NLA).' 'Si no lo usas, desactívalo (Configuración > Sistema > Escritorio remoto). Si lo usas, activa "Requerir que los dispositivos usen la autenticación a nivel de red" y no lo expongas a Internet.'
        } else {
            Add-Hallazgo $cat 'Escritorio remoto' 'Aviso' 'El Escritorio remoto está activado (con NLA).' 'Si no lo usas, desactívalo: Configuración > Sistema > Escritorio remoto.'
        }
    } else {
        Add-Hallazgo $cat 'Escritorio remoto' 'OK' 'Desactivado.'
    }
}

Invoke-Comprobacion $cat 'Programas que aceptan conexiones de la red' {
    $conexiones = @(Get-NetTCPConnection -State Listen | Where-Object { $_.LocalAddress -notmatch '^(127\.|::1$)' })
    $procesos = @{}
    Get-Process | ForEach-Object { $procesos[[int]$_.Id] = $_.ProcessName }
    $sistema = @('System', 'svchost', 'lsass', 'wininit', 'services', 'spoolsv', 'Idle')
    $lineas = @()
    foreach ($grupo in ($conexiones | Group-Object -Property OwningProcess)) {
        $nombre = $procesos[[int]$grupo.Name]
        if (-not $nombre) { $nombre = 'PID ' + $grupo.Name }
        if ($nombre -in $sistema) { continue }
        $puertos = ($grupo.Group | ForEach-Object { [int]$_.LocalPort } | Sort-Object -Unique) -join ', '
        $lineas += ('{0}: puertos {1}' -f $nombre, $puertos)
    }
    if ($lineas.Count -eq 0) {
        Add-Hallazgo $cat 'Puertos abiertos' 'OK' 'Solo los servicios propios de Windows escuchan conexiones de la red.'
    } else {
        Add-Hallazgo $cat 'Puertos abiertos' 'Info' ("Programas (no del sistema) escuchando conexiones de la red:`n" + ($lineas -join "`n")) 'El firewall bloquea lo que no tenga una regla de permiso. Si no reconoces alguno de estos programas, investígalo o desinstálalo.'
    }
}

Invoke-Comprobacion $cat 'Archivo hosts, proxy y DNS' {
    $hostsRuta = Join-Path $env:SystemRoot 'System32\drivers\etc\hosts'
    $entradas = @(Get-Content -LiteralPath $hostsRuta | ForEach-Object { $_.Trim() } | Where-Object { $_ -and -not $_.StartsWith('#') })
    $entradas = @($entradas | Where-Object { $_ -notmatch '^(127\.0\.0\.1|::1)\s+localhost\s*$' })
    if ($entradas.Count -eq 0) {
        Add-Hallazgo $cat 'Archivo hosts' 'OK' 'Sin redirecciones.'
    } elseif (($entradas -join "`n") -match '(?i)(microsoft|windowsupdate|google|bing|apple|brave|mozilla|avast|kaspersky|eset|malwarebytes|bitdefender|norton|mcafee|paypal|banco|bank)') {
        Add-Hallazgo $cat 'Archivo hosts' 'Aviso' ("El archivo hosts redirige dominios importantes:`n" + (($entradas | Select-Object -First 20) -join "`n")) 'Si no lo cambiaste tú, puede ser malware bloqueando actualizaciones o suplantando webs. Revisa C:\Windows\System32\drivers\etc\hosts.'
    } else {
        Add-Hallazgo $cat 'Archivo hosts' 'Info' ("Entradas personalizadas:`n" + (($entradas | Select-Object -First 20) -join "`n")) 'Si no las añadiste tú (o un programa que conoces), revísalas.'
    }

    $claveInternet = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings'
    $proxyOn = Get-ValorRegistro $claveInternet 'ProxyEnable'
    $proxy = Get-ValorRegistro $claveInternet 'ProxyServer'
    $pac = Get-ValorRegistro $claveInternet 'AutoConfigURL'
    if ($proxyOn -eq 1 -or $pac) {
        $texto = @()
        if ($proxyOn -eq 1) { $texto += "proxy $proxy" }
        if ($pac) { $texto += "script de configuración $pac" }
        Add-Hallazgo $cat 'Proxy' 'Aviso' ('Hay un proxy configurado: ' + ($texto -join '; ') + '. Todo tu tráfico web pasa por él.') 'Si no lo configuraste tú (ni tu empresa o centro de estudios), quítalo: Configuración > Red e Internet > Proxy.'
    } else {
        Add-Hallazgo $cat 'Proxy' 'OK' 'Sin proxy configurado.'
    }

    $conocidos = @{
        '1.1.1.1' = 'Cloudflare'; '1.0.0.1' = 'Cloudflare'; '1.1.1.2' = 'Cloudflare (bloquea malware)'; '1.0.0.2' = 'Cloudflare (bloquea malware)'
        '8.8.8.8' = 'Google'; '8.8.4.4' = 'Google'; '9.9.9.9' = 'Quad9 (bloquea malware)'; '149.112.112.112' = 'Quad9 (bloquea malware)'
        '208.67.222.222' = 'OpenDNS'; '208.67.220.220' = 'OpenDNS'; '94.140.14.14' = 'AdGuard'; '94.140.15.15' = 'AdGuard'
    }
    $servidores = @(Get-DnsClientServerAddress -AddressFamily IPv4 | ForEach-Object { $_.ServerAddresses } | Where-Object { $_ } | Sort-Object -Unique)
    if ($servidores.Count -gt 0) {
        $lineas = foreach ($s in $servidores) {
            if ($conocidos.ContainsKey($s)) { "$s ($($conocidos[$s]))" }
            elseif ($s -match '^(10\.|192\.168\.|172\.(1[6-9]|2\d|3[01])\.|169\.254\.)') { "$s (tu router o red local)" }
            else { "$s (desconocido: puede ser el de tu operador)" }
        }
        Add-Hallazgo $cat 'Servidores DNS' 'Info' ($lineas -join "`n") 'Si ves un DNS público que no reconoces y no lo pusiste tú, puede ser un secuestro de DNS. Opcional: Quad9 (9.9.9.9) o Cloudflare (1.1.1.2) bloquean dominios de malware.'
    }
}

# ---------------------------------------------------------------------------
# 5. Cuentas y acceso
# ---------------------------------------------------------------------------
Write-Host 'Cuentas y acceso' -ForegroundColor White
$cat = 'Cuentas y acceso'

Invoke-Comprobacion $cat 'Control de cuentas de usuario (UAC)' {
    $clave = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'
    $lua = Get-ValorRegistro $clave 'EnableLUA'
    $consentimiento = Get-ValorRegistro $clave 'ConsentPromptBehaviorAdmin'
    $escritorioSeguro = Get-ValorRegistro $clave 'PromptOnSecureDesktop'
    if ($lua -eq 0) {
        Add-Hallazgo $cat 'UAC' 'Critico' 'UAC está desactivado: cualquier programa se ejecuta con permisos de administrador sin preguntar.' 'Actívalo: busca "Cambiar configuración de Control de cuentas de usuario" y sube el control al nivel por defecto (o al máximo). Reinicia.'
    } elseif ($consentimiento -eq 0) {
        Add-Hallazgo $cat 'UAC' 'Critico' 'UAC eleva permisos sin preguntar (nivel más bajo).' 'Sube el nivel de "Configuración de Control de cuentas de usuario" al valor por defecto o al máximo.'
    } elseif ($escritorioSeguro -eq 0) {
        Add-Hallazgo $cat 'UAC' 'Aviso' 'UAC pregunta, pero sin atenuar el escritorio (un programa podría simular el clic).' 'Pon el nivel por defecto: "Notificarme solo cuando una aplicación intente realizar cambios (atenuar el escritorio)".'
    } else {
        Add-Hallazgo $cat 'UAC' 'OK' 'Activado y pidiendo confirmación en el escritorio seguro.'
    }
}

Invoke-Comprobacion $cat 'Cuentas locales' {
    $identidadActual = ''
    try { $identidadActual = [Security.Principal.WindowsIdentity]::GetCurrent().Name } catch { }
    $usuarioSesion = ''
    if ($cs) { $usuarioSesion = [string]$cs.UserName }
    if ($script:EsAdmin -and $usuarioSesion -and $identidadActual -and ($usuarioSesion -eq $identidadActual)) {
        Add-Hallazgo $cat 'Cuenta del día a día' 'Info' "Usas una cuenta de administrador ($usuarioSesion) para el día a día." 'Más seguro: crea una cuenta estándar para el uso diario y usa la de administrador solo para instalar o cambiar configuración. Reduce mucho el daño de un malware.'
    } elseif ($script:EsAdmin -and $usuarioSesion -and $identidadActual) {
        Add-Hallazgo $cat 'Cuenta del día a día' 'OK' "La sesión abierta ($usuarioSesion) no es la cuenta que dio los permisos de administrador ($identidadActual): usas una cuenta estándar a diario."
    }

    $usuarios = @(Get-LocalUser)
    $adminIntegrado = $usuarios | Where-Object { $_.SID.Value -like '*-500' }
    $invitado = $usuarios | Where-Object { $_.SID.Value -like '*-501' }
    if ($adminIntegrado -and $adminIntegrado.Enabled) {
        Add-Hallazgo $cat 'Administrador integrado' 'Aviso' ('La cuenta integrada "{0}" está habilitada. Es un objetivo típico de ataques de contraseña.' -f $adminIntegrado.Name) ('Deshabilítala (como administrador): net user "{0}" /active:no' -f $adminIntegrado.Name)
    } else {
        Add-Hallazgo $cat 'Administrador integrado' 'OK' 'La cuenta integrada de Administrador está deshabilitada.'
    }
    if ($invitado -and $invitado.Enabled) {
        Add-Hallazgo $cat 'Cuenta de invitado' 'Aviso' 'La cuenta de Invitado está habilitada.' ('Deshabilítala: net user "{0}" /active:no' -f $invitado.Name)
    }
    $sinClave = @($usuarios | Where-Object { $_.Enabled -and -not $_.PasswordRequired })
    if ($sinClave.Count -gt 0) {
        Add-Hallazgo $cat 'Cuentas sin contraseña obligatoria' 'Aviso' ('Estas cuentas podrían no tener contraseña: ' + (($sinClave | ForEach-Object { $_.Name }) -join ', ') + '.') 'Pon contraseña (o usa una cuenta Microsoft con Windows Hello) a todas las cuentas habilitadas, o deshabilita las que no uses.'
    }

    try {
        $nombreGrupo = (New-Object System.Security.Principal.SecurityIdentifier('S-1-5-32-544')).Translate([System.Security.Principal.NTAccount]).Value.Split('\')[-1]
        $miembros = @()
        try {
            $miembros = @(Get-LocalGroupMember -SID 'S-1-5-32-544' | ForEach-Object { $_.Name })
        } catch {
            # Get-LocalGroupMember falla si el grupo contiene cuentas huérfanas o de Entra ID.
            $grupoAdsi = [ADSI]("WinNT://./{0},group" -f $nombreGrupo)
            $miembros = @($grupoAdsi.psbase.Invoke('Members') | ForEach-Object { $_.GetType().InvokeMember('Name', 'GetProperty', $null, $_, $null) })
        }
        Add-Hallazgo $cat "Miembros del grupo $nombreGrupo" 'Info' ($miembros -join ', ') 'Solo deberían estar las cuentas que conoces. Si ves alguna extraña, investígala.'
    } catch {
        Add-Hallazgo $cat 'Miembros del grupo Administradores' 'Error' ('No se pudo listar: {0}' -f $_.Exception.Message)
    }
}

Invoke-Comprobacion $cat 'Bloqueo por intentos fallidos' {
    $tmp = Join-Path $env:TEMP ('secpol-{0}.inf' -f [guid]::NewGuid())
    try {
        & (Join-Path $env:SystemRoot 'System32\secedit.exe') /export /cfg $tmp /areas SECURITYPOLICY /quiet | Out-Null
        if (-not (Test-Path -LiteralPath $tmp)) { throw 'secedit no pudo exportar la directiva de seguridad.' }
        $politica = @{}
        Get-Content -LiteralPath $tmp | ForEach-Object {
            if ($_ -match '^\s*(\w+)\s*=\s*(.+?)\s*$') { $politica[$Matches[1]] = $Matches[2] }
        }
    } finally {
        Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
    }
    $intentos = 0
    if ($politica.ContainsKey('LockoutBadCount')) { $intentos = [int]$politica['LockoutBadCount'] }
    if ($intentos -eq 0) {
        Add-Hallazgo $cat 'Bloqueo de cuenta' 'Aviso' 'No hay bloqueo tras intentos fallidos de contraseña: se pueden probar contraseñas sin límite.' 'Como administrador: net accounts /lockoutthreshold:10 /lockoutduration:10 /lockoutwindow:10'
    } else {
        Add-Hallazgo $cat 'Bloqueo de cuenta' 'OK' "La cuenta se bloquea tras $intentos intentos fallidos."
    }
}

Invoke-Comprobacion $cat 'Credenciales guardadas de forma insegura' {
    $winlogon = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'
    $auto = [string](Get-ValorRegistro $winlogon 'AutoAdminLogon')
    $clave = Get-ValorRegistro $winlogon 'DefaultPassword'
    if ($clave) {
        Add-Hallazgo $cat 'Inicio de sesión automático' 'Critico' 'Hay una contraseña guardada en texto plano en el registro (DefaultPassword) para el inicio de sesión automático.' 'Desactiva el inicio automático (netplwiz > marca "Los usuarios deben escribir su nombre y contraseña") y borra el valor DefaultPassword de HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon.'
    } elseif ($auto -eq '1') {
        Add-Hallazgo $cat 'Inicio de sesión automático' 'Aviso' 'Windows inicia sesión solo, sin pedir contraseña: quien encienda el portátil entra en tu cuenta.' 'netplwiz > marca "Los usuarios deben escribir su nombre y contraseña para usar el equipo".'
    } else {
        Add-Hallazgo $cat 'Inicio de sesión automático' 'OK' 'Desactivado.'
    }
    $wdigest = Get-ValorRegistro 'HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\WDigest' 'UseLogonCredential'
    if ($wdigest -eq 1) {
        Add-Hallazgo $cat 'WDigest' 'Critico' 'WDigest guarda tu contraseña en claro en la memoria (UseLogonCredential=1). Suele ser obra de malware.' 'Pon UseLogonCredential a 0 en HKLM\SYSTEM\CurrentControlSet\Control\SecurityProviders\WDigest, reinicia y haz un análisis completo con Defender.'
    }
}

# ---------------------------------------------------------------------------
# 6. Programas y persistencia
# ---------------------------------------------------------------------------
Write-Host 'Programas y persistencia' -ForegroundColor White
$cat = 'Programas y persistencia'

Invoke-Comprobacion $cat 'Programas que se inician con Windows' {
    $entradas = @()
    $claves = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run',
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\RunOnce',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce'
    )
    foreach ($clave in $claves) {
        if (-not (Test-Path -LiteralPath $clave)) { continue }
        $item = Get-Item -LiteralPath $clave
        foreach ($nombre in $item.GetValueNames()) {
            if (-not $nombre) { continue }
            $entradas += [pscustomobject]@{ Nombre = $nombre; Comando = [string]$item.GetValue($nombre) }
        }
    }
    $shell = $null
    try { $shell = New-Object -ComObject WScript.Shell } catch { }
    foreach ($carpeta in @([Environment]::GetFolderPath('Startup'), [Environment]::GetFolderPath('CommonStartup'))) {
        if (-not $carpeta -or -not (Test-Path -LiteralPath $carpeta)) { continue }
        foreach ($archivo in Get-ChildItem -LiteralPath $carpeta -File) {
            if ($archivo.Name -eq 'desktop.ini') { continue }
            $comando = $archivo.FullName
            if ($archivo.Extension -eq '.lnk' -and $shell) {
                $acceso = $shell.CreateShortcut($archivo.FullName)
                $comando = ('"{0}" {1}' -f $acceso.TargetPath, $acceso.Arguments).Trim()
            }
            $entradas += [pscustomobject]@{ Nombre = $archivo.Name; Comando = $comando }
        }
    }
    if ($entradas.Count -eq 0) {
        Add-Hallazgo $cat 'Inicio automático' 'OK' 'No hay programas de terceros configurados para iniciarse con Windows.'
        return
    }
    $normales = @()
    $sospechosos = @()
    foreach ($e in $entradas) {
        $ruta = Get-RutaEjecutable $e.Comando
        $firma = Get-Firma $ruta
        $texto = '{0}: {1} [{2}]' -f $e.Nombre, $e.Comando, $(if ($firma.Valida) { 'firmado por ' + $firma.Firmante } else { 'SIN FIRMA VÁLIDA (' + $firma.Estado + ')' })
        $esSospechoso = ($e.Comando -match $PatronComandoSospechoso) -or ($ruta -match $PatronRutaSospechosa) -or
        ((-not $firma.Valida) -and ($ruta -match '(?i)\\(AppData|ProgramData)\\'))
        if ($esSospechoso) { $sospechosos += $texto } else { $normales += $texto }
    }
    if ($sospechosos.Count -gt 0) {
        Add-Hallazgo $cat 'Inicio automático sospechoso' 'Aviso' ($sospechosos -join "`n") 'Estos elementos se inician con Windows desde carpetas temporales, sin firma o con comandos típicos de malware. Si no los reconoces, desactívalos (Administrador de tareas > Aplicaciones de arranque) y analiza el PC con Defender.'
    }
    if ($normales.Count -gt 0) {
        Add-Hallazgo $cat 'Inicio automático' 'Info' ($normales -join "`n") 'Desactiva los que no necesites (Administrador de tareas > Aplicaciones de arranque): el portátil arrancará más rápido.'
    }
}

Invoke-Comprobacion $cat 'Tareas programadas de terceros' {
    $tareas = @(Get-ScheduledTask | Where-Object { $_.TaskPath -notlike '\Microsoft\*' -and [string]$_.State -ne 'Disabled' })
    $sospechosas = @()
    $total = 0
    foreach ($t in $tareas) {
        foreach ($a in @($t.Actions)) {
            if (-not $a.Execute) { continue }
            $total++
            $comando = ('{0} {1}' -f $a.Execute, $a.Arguments).Trim()
            $ruta = Get-RutaEjecutable $a.Execute
            if (($comando -match $PatronComandoSospechoso) -or ($ruta -match $PatronRutaSospechosa)) {
                $firma = Get-Firma $ruta
                $sospechosas += ('{0}{1}: {2} [{3}]' -f $t.TaskPath, $t.TaskName, $comando, $(if ($firma.Valida) { 'firmado por ' + $firma.Firmante } else { 'sin firma válida' }))
            }
        }
    }
    if ($sospechosas.Count -gt 0) {
        Add-Hallazgo $cat 'Tareas programadas sospechosas' 'Aviso' ($sospechosas -join "`n") 'Revisa estas tareas en el Programador de tareas (taskschd.msc). Si no sabes qué son, deshabilítalas y analiza el PC con Defender.'
    } else {
        Add-Hallazgo $cat 'Tareas programadas' 'OK' ("Acciones de tareas de terceros revisadas: $total. Ninguna usa comandos o carpetas típicos de malware.")
    }
}

Invoke-Comprobacion $cat 'Servicios de terceros' {
    $servicios = @(Get-CimInstance -ClassName Win32_Service | Where-Object { $_.PathName })
    $sinFirma = @()
    $sinComillas = @()
    foreach ($s in $servicios) {
        $ruta = Get-RutaEjecutable $s.PathName
        if (-not $ruta -or $ruta -match '(?i)^[a-z]:\\windows\\') { continue }
        if ($s.PathName -notmatch '^\s*"' -and $ruta -match ' ') {
            $sinComillas += ('{0}: {1}' -f $s.Name, $s.PathName)
        }
        if ($s.StartMode -ne 'Disabled') {
            $firma = Get-Firma $ruta
            if (-not $firma.Valida) { $sinFirma += ('{0} ({1}): {2} [{3}]' -f $s.DisplayName, $s.StartMode, $ruta, $firma.Estado) }
        }
    }
    if ($sinFirma.Count -gt 0) {
        Add-Hallazgo $cat 'Servicios sin firma' 'Aviso' ($sinFirma -join "`n") 'Un servicio sin firma no es necesariamente malo (algunos drivers y programas antiguos no la tienen), pero si no reconoces alguno, investígalo.'
    }
    if ($sinComillas.Count -gt 0) {
        Add-Hallazgo $cat 'Rutas de servicio sin comillas' 'Aviso' ($sinComillas -join "`n") 'Error de instalación que permite a un programa sin permisos ejecutarse como SYSTEM. Actualiza o reinstala ese programa; si persiste, avisa a su fabricante.'
    }
    if ($sinFirma.Count -eq 0 -and $sinComillas.Count -eq 0) {
        Add-Hallazgo $cat 'Servicios' 'OK' 'Todos los servicios de terceros están firmados y con rutas correctas.'
    }
}

Invoke-Comprobacion $cat 'Programas de acceso remoto' {
    $patron = '(?i)(AnyDesk|TeamViewer|RustDesk|UltraViewer|ScreenConnect|ConnectWise Control|Splashtop|Chrome Remote Desktop|RealVNC|TightVNC|UltraVNC|Remote Utilities|Atera|NinjaOne|LogMeIn|GoTo Resolve|Zoho Assist|RemotePC|AweSun|Sunlogin|ToDesk|Supremo|DWService|MeshAgent|SimpleHelp|NetSupport)'
    $encontrados = @()
    $rutasDesinstalar = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    $programas = @(Get-ItemProperty -Path $rutasDesinstalar -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName })
    $encontrados += @($programas | Where-Object { $_.DisplayName -match $patron } | ForEach-Object { 'instalado: ' + $_.DisplayName })
    $encontrados += @(Get-Process | Where-Object { $_.ProcessName -match '(?i)^(AnyDesk|TeamViewer|rustdesk|UltraViewer|ScreenConnect|Splashtop|remoting_host|winvnc|tvnserver|vncserver|client32|ToDesk|SunloginClient|AweSun|Supremo|dwagent|meshagent)' } |
        ForEach-Object { 'en ejecución: ' + $_.ProcessName } | Sort-Object -Unique)
    if ($encontrados.Count -gt 0) {
        Add-Hallazgo $cat 'Acceso remoto' 'Aviso' ($encontrados -join "`n") 'Estos programas permiten controlar tu PC a distancia. Si no los instalaste tú o ya no los usas, desinstálalos: los estafadores de "soporte técnico" los usan para entrar y robar.'
    } else {
        Add-Hallazgo $cat 'Acceso remoto' 'OK' 'No se encontraron programas conocidos de control remoto.'
    }
}

Invoke-Comprobacion $cat 'PowerShell 2.0' {
    $f = $null
    try { $f = Get-WindowsOptionalFeature -Online -FeatureName MicrosoftWindowsPowerShellV2Root } catch { }
    if ($f -and [string]$f.State -eq 'Enabled') {
        Add-Hallazgo $cat 'PowerShell 2.0' 'Aviso' 'El motor antiguo de PowerShell 2.0 está instalado; permite saltarse el registro y las protecciones de PowerShell moderno.' 'Características de Windows > desmarca "Windows PowerShell 2.0".'
    } else {
        Add-Hallazgo $cat 'PowerShell 2.0' 'OK' 'No está instalado.'
    }
}

Invoke-Comprobacion $cat 'Distribuciones de WSL (Linux en Windows)' {
    $lxss = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Lxss'
    if (-not (Test-Path -LiteralPath $lxss)) { return }
    $distros = @(Get-ChildItem -LiteralPath $lxss | ForEach-Object { (Get-ItemProperty -LiteralPath $_.PSPath).DistributionName } | Where-Object { $_ })
    if ($distros.Count -eq 0) { return }
    Add-Hallazgo $cat 'WSL' 'Info' ('Distribuciones instaladas: ' + ($distros -join ', ') + '.') 'Mantenlas actualizadas (sudo apt update && sudo apt upgrade) y borra las que no uses (wsl --unregister NOMBRE).'
    if ($distros -contains 'linbox-Brave') {
        $espejo = ''
        $wslconfig = Join-Path $env:USERPROFILE '.wslconfig'
        if ((Test-Path -LiteralPath $wslconfig) -and ((Get-Content -LiteralPath $wslconfig -Raw) -match '(?im)^\s*networkingMode\s*=\s*mirrored')) {
            $espejo = ' Además, WSL está en modo de red "mirrored": no abras el firewall de Hyper-V o los puertos 9611/9612 quedarían expuestos a tu red.'
        }
        Add-Hallazgo $cat 'Brave Origin for Windows (WSL)' 'Aviso' ('Está instalado "brave-origin-for-windows" (distribución linbox-Brave): ejecuta Brave Origin Nightly como root y SIN el sandbox de Chromium, dentro de una distribución que puede leer y modificar tus archivos de Windows.' + $espejo) 'Úsalo solo para pruebas, sin iniciar sesión en cuentas importantes. Alternativa segura: Brave normal + las políticas de windows\Brave-Minimalista.ps1, o Brave Origin oficial. Para quitarlo: wsl --unregister linbox-Brave y borra la carpeta de la app.'
    }
}

# ---------------------------------------------------------------------------
# 7. Hardware y firmware (e inventario)
# ---------------------------------------------------------------------------
Write-Host 'Hardware y firmware' -ForegroundColor White
$cat = 'Hardware y firmware'

Invoke-Comprobacion $cat 'Datos del equipo' {
    $nombreModelo = ('{0} {1}' -f $fabricante, $modelo).Trim()
    if ($csp -and $csp.Name) { $nombreModelo += (' (tipo {0})' -f $csp.Name) }
    Add-Dato 'Equipo' 'Modelo' $nombreModelo
    if ($cpu) {
        Add-Dato 'Equipo' 'Procesador' ('{0}: {1} núcleos / {2} hilos, hasta {3} MHz' -f $cpuNombre, $cpu.NumberOfCores, $cpu.NumberOfLogicalProcessors, $cpu.MaxClockSpeed)
        $virt = 'desactivada en la BIOS'
        if ($cs -and $cs.HypervisorPresent) { $virt = 'activa (hipervisor en uso: VBS, WSL2 o Hyper-V)' }
        elseif ($cpu.VirtualizationFirmwareEnabled) { $virt = 'activada en la BIOS' }
        Add-Dato 'Equipo' 'Virtualización' $virt
    }
    if ($os) {
        Add-Dato 'Equipo' 'Windows' ('{0} {1} (compilación {2}.{3}), instalado el {4}' -f $os.Caption, $cv.DisplayVersion, $build, $ubr, (Format-Fecha $os.InstallDate))
    }
    if ($bios) { Add-Dato 'Equipo' 'BIOS' ('{0}, del {1}' -f ([string]$bios.SMBIOSBIOSVersion).Trim(), (Format-Fecha $bios.ReleaseDate)) }
    if ($esP14sGen1Amd) { Add-Dato 'Equipo' 'Modelo reconocido' 'ThinkPad P14s / T14 Gen 1 AMD (BIOS R1BET): se aplican comprobaciones específicas' }
    try {
        foreach ($g in Get-CimInstance -ClassName Win32_VideoController) {
            Add-Dato 'Gráficos y red' 'Gráfica' ('{0}, driver {1} del {2}' -f $g.Name, $g.DriverVersion, (Format-Fecha $g.DriverDate))
        }
    } catch { }
    try {
        foreach ($a in Get-NetAdapter -Physical) {
            Add-Dato 'Gráficos y red' 'Adaptador de red' ('{0} ({1}), driver {2} del {3}' -f $a.InterfaceDescription, $a.Name, $a.DriverVersionString, $a.DriverDate)
        }
    } catch { }
    try {
        $huella = @(Get-PnpDevice -Class Biometric -PresentOnly -ErrorAction Stop)
        if ($huella.Count -gt 0) { Add-Dato 'Equipo' 'Lector de huellas' ('sí: ' + (($huella | ForEach-Object { $_.FriendlyName }) -join ', ') + ' (úsalo con Windows Hello)') }
        else { Add-Dato 'Equipo' 'Lector de huellas' 'no detectado' }
    } catch { }
    try {
        $ir = @(Get-PnpDevice -Class Camera -PresentOnly -ErrorAction Stop | Where-Object { $_.FriendlyName -match '(?i)\bIR\b|infrared|infrarroj' })
        if ($ir.Count -gt 0) { Add-Dato 'Equipo' 'Cámara IR (reconocimiento facial)' 'sí' }
    } catch { }
}

Invoke-Comprobacion $cat 'BIOS' {
    if (-not $bios) { throw 'No se pudo leer la BIOS.' }
    $verBios = ([string]$bios.SMBIOSBIOSVersion).Trim()
    if ($esP14sGen1Amd -and $verBios -match 'R1BET(\d+)W') {
        $n = [int]$Matches[1]
        if ($n -lt 84) {
            Add-Hallazgo $cat 'BIOS' 'Aviso' ("Tienes la BIOS $verBios. La más reciente publicada que conocemos para el P14s/T14 Gen 1 AMD es la 1.53 (R1BET84W) o posterior; las BIOS nuevas traen los parches de AMD (Zenbleed, SinkClose, EntrySign), LogoFAIL y certificados de arranque.") 'Actualízala con Lenovo Commercial Vantage / Lenovo System Update, o desde support.lenovo.com (busca tu tipo de máquina). Enchufa el cargador y no apagues durante la actualización. Si usas BitLocker, ten a mano la clave de recuperación.'
        } else {
            Add-Hallazgo $cat 'BIOS' 'OK' ("BIOS $verBios (1.53 o posterior). Revisa de vez en cuando si Lenovo publica otra.")
        }
        return
    }
    $dias = 0
    if ($bios.ReleaseDate) { $dias = [int][math]::Floor(($ahora - $bios.ReleaseDate).TotalDays) }
    if ($dias -gt 730) {
        Add-Hallazgo $cat 'BIOS' 'Aviso' ('BIOS {0} del {1} (más de 2 años).' -f $verBios, (Format-Fecha $bios.ReleaseDate)) 'Busca una versión más nueva en la web de soporte del fabricante: las actualizaciones de BIOS corrigen fallos de seguridad del procesador y del arranque.'
    } else {
        Add-Hallazgo $cat 'BIOS' 'Info' ('BIOS {0} del {1}.' -f $verBios, (Format-Fecha $bios.ReleaseDate)) 'Comprueba de vez en cuando si el fabricante publica una más nueva.'
    }
}

if ($esLenovo) {
    Invoke-Comprobacion $cat 'Contraseñas y ajustes de la BIOS Lenovo' {
        $pw = Get-CimInstance -Namespace 'root/wmi' -ClassName Lenovo_BiosPasswordSettings | Select-Object -First 1
        $estadoPw = [int]$pw.PasswordState
        $activas = @()
        if ($estadoPw -band 1) { $activas += 'encendido (power-on)' }
        if ($estadoPw -band 2) { $activas += 'supervisor' }
        if ($estadoPw -band 4) { $activas += 'disco duro' }
        if ($estadoPw -band 2) {
            Add-Hallazgo $cat 'Contraseña de la BIOS' 'OK' ('Contraseñas de BIOS configuradas: ' + ($activas -join ', ') + '.')
        } else {
            $texto = 'Sin contraseña de supervisor: quien tenga el portátil en la mano puede entrar en la BIOS, desactivar el arranque seguro o arrancar desde un USB.'
            if ($activas.Count) { $texto += ' Configuradas: ' + ($activas -join ', ') + '.' }
            Add-Hallazgo $cat 'Contraseña de la BIOS' 'Info' $texto 'Opcional: pon una contraseña de supervisor (F1 al encender > Security > Password). ¡CUIDADO!: si la olvidas, en un ThinkPad no se puede recuperar y hay que cambiar la placa base. Guárdala en tu gestor de contraseñas.'
        }

        $ajustes = @(Get-CimInstance -Namespace 'root/wmi' -ClassName Lenovo_BiosSetting | Where-Object { $_.CurrentSetting } | ForEach-Object {
                $partes = (([string]$_.CurrentSetting) -split ';')[0] -split ',', 2
                [pscustomobject]@{ Nombre = $partes[0]; Valor = $(if ($partes.Count -gt 1) { $partes[1] } else { '' }) }
            })
        foreach ($a in ($ajustes | Where-Object { $_.Nombre -match '(?i)secur|tpm|memory|guard|tsme|virtual|amdvt|iommu|dma|password|absolute|computrace|boot|tamper|biometric|fingerprint|rollback|firmwareupdate|usb|wireless|wake' } | Sort-Object Nombre)) {
            Add-Dato 'BIOS Lenovo (ajustes de seguridad)' $a.Nombre $a.Valor
        }
        $guardia = $ajustes | Where-Object { $_.Nombre -match '(?i)MemoryGuard|TSME' } | Select-Object -First 1
        if ($guardia) {
            if ($guardia.Valor -match '(?i)^enable') {
                Add-Hallazgo $cat 'AMD Memory Guard' 'OK' 'Activado: la memoria RAM va cifrada (protege frente a ataques de "arranque en frío").'
            } else {
                Add-Hallazgo $cat 'AMD Memory Guard' 'Aviso' ("AMD Memory Guard está en '{0}'. Tu Ryzen PRO puede cifrar toda la RAM casi sin coste de rendimiento." -f $guardia.Valor) 'Actívalo en la BIOS (F1 al encender > Security). Si usas BitLocker, suspéndelo antes de cambiar ajustes de la BIOS o ten la clave de recuperación a mano.'
            }
        }
        $rollback = $ajustes | Where-Object { $_.Nombre -match '(?i)SecureRollBackPrevention' } | Select-Object -First 1
        if ($rollback -and $rollback.Valor -notmatch '(?i)^enable') {
            Add-Hallazgo $cat 'Protección contra rollback de BIOS' 'Aviso' 'Se permite instalar versiones antiguas (vulnerables) de la BIOS.' 'Actívala en la BIOS: Security > Secure RollBack Prevention: On.'
        }
    }

    Invoke-Comprobacion $cat 'Herramienta de actualizaciones de Lenovo' {
        $lenovoApps = @()
        $nombresAppx = @{ 'E046963F.LenovoSettingsforEnterprise' = 'Lenovo Commercial Vantage'; 'E046963F.LenovoCompanion' = 'Lenovo Vantage' }
        try {
            $lenovoApps += @(Get-AppxPackage -AllUsers -Name 'E046963F.*' | ForEach-Object {
                    if ($nombresAppx.ContainsKey($_.Name)) { $nombresAppx[$_.Name] } else { $_.Name }
                })
        } catch { }
        $rutas = @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*')
        $lenovoApps += @(Get-ItemProperty -Path $rutas -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -match '(?i)Lenovo (System Update|Commercial Vantage|Vantage)' } | ForEach-Object { $_.DisplayName })
        if ($lenovoApps.Count -gt 0) {
            Add-Hallazgo $cat 'Actualizaciones de Lenovo' 'OK' ('Instalado: ' + (($lenovoApps | Sort-Object -Unique) -join ', ') + '.') 'Ábrelo una vez al mes para instalar BIOS y drivers.'
        } else {
            Add-Hallazgo $cat 'Actualizaciones de Lenovo' 'Info' 'No se encontró Lenovo Vantage / Commercial Vantage / System Update.' 'Instala "Lenovo Commercial Vantage" desde Microsoft Store: es la forma fácil de mantener BIOS y drivers al día.'
        }
    }
}

Invoke-Comprobacion $cat 'Memoria RAM' {
    $modulos = @(Get-CimInstance -ClassName Win32_PhysicalMemory)
    $total = ($modulos | Measure-Object -Property Capacity -Sum).Sum
    Add-Dato 'Memoria' 'Total' (Format-Tamano $total)
    $velocidades = @()
    foreach ($m in $modulos) {
        $tipo = switch ([int]$m.SMBIOSMemoryType) { 26 { 'DDR4' } 34 { 'DDR5' } 30 { 'LPDDR4' } 35 { 'LPDDR5' } default { '' } }
        $vel = $m.ConfiguredClockSpeed
        if (-not $vel) { $vel = $m.Speed }
        if ($vel) { $velocidades += [int]$vel }
        Add-Dato 'Memoria' ('Módulo {0}' -f $m.DeviceLocator) ('{0} {1} a {2} MT/s - {3} {4}' -f (Format-Tamano $m.Capacity), $tipo, $vel, ([string]$m.Manufacturer).Trim(), ([string]$m.PartNumber).Trim())
    }
    $capacidades = @($modulos | ForEach-Object { [int64]$_.Capacity } | Sort-Object -Unique)
    if ($modulos.Count -eq 2 -and $capacidades.Count -eq 2) {
        $comun = [int64]$capacidades[0] * 2
        Add-Hallazgo $cat 'Configuración de la memoria' 'Info' ('Memoria asimétrica ({0} + {1}): {2} trabajan en doble canal y el resto en canal simple. Es lo normal con 8 GB soldados + un módulo de 32 GB; se nota poco, salvo algo en la gráfica integrada, y a cambio tienes {3}.' -f (Format-Tamano $capacidades[0]), (Format-Tamano $capacidades[1]), (Format-Tamano $comun), (Format-Tamano $total))
    }
    if ($esP14sGen1Amd -and $velocidades.Count -gt 0) {
        $minima = ($velocidades | Measure-Object -Minimum).Minimum
        if ($minima -lt 3200) {
            Add-Hallazgo $cat 'Velocidad de la memoria' 'Aviso' "La memoria funciona a $minima MT/s; este modelo admite DDR4-3200. Un módulo más lento baja la velocidad de toda la RAM." 'Si cambias el módulo, compra uno DDR4-3200 SO-DIMM (hasta 32 GB). Mejora sobre todo la gráfica integrada.'
        } else {
            Add-Hallazgo $cat 'Velocidad de la memoria' 'OK' "La memoria funciona a $minima MT/s (máximo del modelo)."
        }
    }
}

Invoke-Comprobacion $cat 'Salud del disco' {
    $discos = @(Get-PhysicalDisk)
    foreach ($d in $discos) {
        $contador = $null
        try { $contador = $d | Get-StorageReliabilityCounter } catch { }
        $partes = @('{0}, {1} {2}' -f (Format-Tamano $d.Size), $d.BusType, $d.MediaType)
        $desgaste = $null
        if ($contador) {
            if ($null -ne $contador.Wear) { $desgaste = [int]$contador.Wear; $partes += "desgaste $desgaste %" }
            if ($contador.Temperature) { $partes += ('{0} °C' -f $contador.Temperature) }
            if ($contador.PowerOnHours) { $partes += ('{0:N0} horas encendido' -f $contador.PowerOnHours) }
        }
        $nombreDisco = [string]$d.FriendlyName
        if (-not $nombreDisco) { $nombreDisco = 'Disco ' + $d.DeviceId }
        Add-Dato 'Almacenamiento' $nombreDisco ($partes -join ', ')
        $salud = [string]$d.HealthStatus
        if ($salud -and $salud -ne 'Healthy') {
            Add-Hallazgo $cat ('Disco ' + $d.FriendlyName) 'Critico' "Windows marca el disco como '$salud'." 'Haz copia de seguridad YA y cambia el disco.'
        } elseif ($null -ne $desgaste -and $desgaste -ge 90) {
            Add-Hallazgo $cat ('Disco ' + $d.FriendlyName) 'Critico' "El SSD ha consumido el $desgaste % de su vida útil." 'Haz copia de seguridad y cámbialo pronto (el P14s Gen 1 admite un SSD M.2 2280 NVMe).'
        } elseif ($null -ne $desgaste -and $desgaste -ge 70) {
            Add-Hallazgo $cat ('Disco ' + $d.FriendlyName) 'Aviso' "El SSD ha consumido el $desgaste % de su vida útil." 'Ten copia de seguridad al día y plantéate cambiarlo.'
        } else {
            Add-Hallazgo $cat ('Disco ' + $d.FriendlyName) 'OK' ('Estado correcto' + $(if ($null -ne $desgaste) { " (desgaste $desgaste %)." } else { '.' }))
        }
    }
    $unidad = Get-CimInstance -ClassName Win32_LogicalDisk -Filter ("DeviceID='{0}'" -f $env:SystemDrive)
    if ($unidad -and $unidad.Size) {
        $pct = [math]::Round(100 * $unidad.FreeSpace / $unidad.Size)
        $texto = 'Espacio libre en {0} {1} de {2} ({3} %).' -f $env:SystemDrive, (Format-Tamano $unidad.FreeSpace), (Format-Tamano $unidad.Size), $pct
        if ($unidad.FreeSpace -lt 15GB -or $pct -lt 10) {
            Add-Hallazgo $cat 'Espacio libre' 'Aviso' $texto 'Con poco espacio, Windows Update falla. Libera espacio: Configuración > Sistema > Almacenamiento > Recomendaciones de limpieza.'
        } else {
            Add-Hallazgo $cat 'Espacio libre' 'OK' $texto
        }
    }
}

Invoke-Comprobacion $cat 'Batería' {
    $estaticos = @(Get-CimInstance -Namespace 'root/wmi' -ClassName BatteryStaticData -ErrorAction SilentlyContinue)
    if ($estaticos.Count -eq 0) {
        Add-Hallazgo $cat 'Batería' 'Info' 'No se detecta batería (o Windows no expone sus datos).'
        return
    }
    $cargas = @(Get-CimInstance -Namespace 'root/wmi' -ClassName BatteryFullChargedCapacity -ErrorAction SilentlyContinue)
    $ciclos = @(Get-CimInstance -Namespace 'root/wmi' -ClassName BatteryCycleCount -ErrorAction SilentlyContinue)
    foreach ($e in $estaticos) {
        $carga = $cargas | Where-Object { $_.InstanceName -eq $e.InstanceName } | Select-Object -First 1
        $ciclo = $ciclos | Where-Object { $_.InstanceName -eq $e.InstanceName } | Select-Object -First 1
        $diseno = [double]$e.DesignedCapacity
        if (-not $carga -or $diseno -le 0) { continue }
        $actual = [double]$carga.FullChargedCapacity
        $salud = [math]::Round(100 * $actual / $diseno)
        $texto = 'Capacidad actual {0:N0} mWh de {1:N0} mWh de fábrica: {2} % de salud' -f $actual, $diseno, $salud
        if ($ciclo -and $ciclo.CycleCount) { $texto += (', {0} ciclos' -f $ciclo.CycleCount) }
        $texto += '.'
        $nombreBateria = ([string]$e.DeviceName).Trim()
        if (-not $nombreBateria) { $nombreBateria = 'Batería' }
        Add-Dato 'Batería' $nombreBateria $texto
        if ($salud -lt 60) {
            Add-Hallazgo $cat 'Batería' 'Aviso' ($texto + ' Está muy desgastada.') 'Plantéate cambiarla (batería original Lenovo o de marca fiable). Si notas el touchpad levantado o la carcasa abombada, deja de usarla: puede estar hinchada. Mientras tanto, limita la carga al 80 % en Lenovo Vantage > Energía.'
        } elseif ($salud -lt 80) {
            Add-Hallazgo $cat 'Batería' 'Aviso' $texto 'Normal en una batería de varios años. Para alargar su vida, limita la carga al 75-80 % en Lenovo Vantage > Energía si sueles usarlo enchufado.'
        } else {
            Add-Hallazgo $cat 'Batería' 'OK' $texto
        }
    }
}

# ---------------------------------------------------------------------------
# Informes
# ---------------------------------------------------------------------------

$etiquetas = @{ Critico = 'Crítico'; Aviso = 'Aviso'; OK = 'Correcto'; Info = 'Info'; Error = 'No comprobado' }
$ordenCategorias = @('Sistema y actualizaciones', 'Antivirus y protección', 'Cifrado y arranque', 'Red y firewall', 'Cuentas y acceso', 'Programas y persistencia', 'Hardware y firmware')
$ordenSecciones = @('Equipo', 'Memoria', 'Almacenamiento', 'Batería', 'Gráficos y red', 'BIOS Lenovo (ajustes de seguridad)')
$gruposInventario = foreach ($s in $ordenSecciones) {
    $filas = @($script:Inventario | Where-Object { $_.Seccion -eq $s })
    if ($filas.Count -gt 0) { [pscustomobject]@{ Name = $s; Group = $filas } }
}
$cuenta = @{}
foreach ($e in 'Critico', 'Aviso', 'OK', 'Info', 'Error') { $cuenta[$e] = @($script:Hallazgos | Where-Object { $_.Estado -eq $e }).Count }
$prioridades = @($script:Hallazgos | Where-Object { $_.Estado -eq 'Critico' }) + @($script:Hallazgos | Where-Object { $_.Estado -eq 'Aviso' })

$nombreEquipo = $env:COMPUTERNAME
$marcaTiempo = $ahora.ToString('yyyyMMdd-HHmm')
$rutaHtml = Join-Path $Salida ("Informe-Seguridad-{0}-{1}.html" -f $nombreEquipo, $marcaTiempo)
$rutaTxt = Join-Path $Salida ("Informe-Seguridad-{0}-{1}.txt" -f $nombreEquipo, $marcaTiempo)
$resumenEquipo = ('{0} {1} · {2} · {3} RAM · {4}' -f $fabricante, $modelo, $cpuNombre, $(if ($cs) { Format-Tamano $cs.TotalPhysicalMemory } else { '?' }), $(if ($os) { $os.Caption } else { 'Windows' })).Trim()

# --- Texto ---
$txt = New-Object 'System.Collections.Generic.List[string]'
$txt.Add('INFORME DE SEGURIDAD DE WINDOWS')
$txt.Add(('Fecha: {0} · Script: {1}' -f $ahora.ToString('dd/MM/yyyy HH:mm'), $VersionScript))
$txt.Add("Equipo: $resumenEquipo")
if (-not $script:EsAdmin) { $txt.Add('Aviso: se ejecutó sin permisos de administrador; resultados incompletos.') }
$txt.Add(('Resumen: {0} críticos, {1} avisos, {2} correctos, {3} informativos, {4} sin comprobar.' -f $cuenta.Critico, $cuenta.Aviso, $cuenta.OK, $cuenta.Info, $cuenta.Error))
$txt.Add('')
if ($prioridades.Count -gt 0) {
    $txt.Add('=== QUÉ HACER PRIMERO ===')
    $i = 1
    foreach ($h in $prioridades) {
        $txt.Add(('{0}. [{1}] {2}: {3}' -f $i, $etiquetas[$h.Estado].ToUpper(), $h.Control, $h.Detalle))
        if ($h.Recomendacion) { $txt.Add('   -> ' + $h.Recomendacion) }
        $i++
    }
    $txt.Add('')
}
foreach ($c in $ordenCategorias) {
    $items = @($script:Hallazgos | Where-Object { $_.Categoria -eq $c })
    if ($items.Count -eq 0) { continue }
    $txt.Add("=== $($c.ToUpper()) ===")
    foreach ($h in $items) {
        $txt.Add(('[{0}] {1}: {2}' -f $etiquetas[$h.Estado], $h.Control, $h.Detalle))
        if ($h.Recomendacion -and $h.Estado -ne 'OK') { $txt.Add('   -> ' + $h.Recomendacion) }
    }
    $txt.Add('')
}
$txt.Add('=== INVENTARIO ===')
foreach ($grupo in $gruposInventario) {
    $txt.Add("-- $($grupo.Name)")
    foreach ($d in $grupo.Group) { $txt.Add(('   {0}: {1}' -f $d.Nombre, $d.Valor)) }
}

# --- HTML ---
$css = @'
:root { --fondo:#f6f7f9; --tarjeta:#ffffff; --texto:#1c1f24; --suave:#5b6470; --borde:#dfe3e8;
  --critico:#c62828; --aviso:#b26a00; --ok:#2e7d32; --info:#1565c0; --error:#6b7280; }
@media (prefers-color-scheme: dark) { :root { --fondo:#121417; --tarjeta:#1c1f24; --texto:#e8eaed; --suave:#a0a8b3; --borde:#2d323a;
  --critico:#ef5350; --aviso:#ffb74d; --ok:#66bb6a; --info:#64b5f6; --error:#9ca3af; } }
* { box-sizing:border-box; }
body { margin:0; background:var(--fondo); color:var(--texto); font:15px/1.5 "Segoe UI", system-ui, sans-serif; }
main { max-width:1000px; margin:0 auto; padding:24px 16px 48px; }
h1 { font-size:1.6rem; margin:0 0 4px; } h2 { font-size:1.2rem; margin:32px 0 12px; }
.sub { color:var(--suave); margin:0 0 16px; }
.resumen { display:flex; flex-wrap:wrap; gap:10px; margin:16px 0; }
.caja { background:var(--tarjeta); border:1px solid var(--borde); border-radius:10px; padding:10px 16px; min-width:120px; }
.caja b { display:block; font-size:1.5rem; }
.tarjeta { background:var(--tarjeta); border:1px solid var(--borde); border-radius:10px; padding:12px 16px; margin:8px 0; }
.fila { display:flex; gap:12px; align-items:flex-start; }
.etiqueta { flex:0 0 auto; font-size:.8rem; font-weight:600; padding:2px 8px; border-radius:999px; border:1px solid currentColor; white-space:nowrap; }
.Critico { color:var(--critico); } .Aviso { color:var(--aviso); } .OK { color:var(--ok); } .Info { color:var(--info); } .Error { color:var(--error); }
.control { font-weight:600; }
.detalle { white-space:pre-wrap; margin:4px 0 0; overflow-wrap:anywhere; }
.reco { margin:6px 0 0; padding-left:10px; border-left:3px solid var(--borde); color:var(--suave); overflow-wrap:anywhere; }
table { width:100%; border-collapse:collapse; background:var(--tarjeta); border:1px solid var(--borde); border-radius:10px; overflow:hidden; }
td { padding:6px 10px; border-top:1px solid var(--borde); vertical-align:top; overflow-wrap:anywhere; }
td:first-child { width:32%; color:var(--suave); }
.aviso-admin { border:1px solid var(--aviso); color:var(--aviso); border-radius:10px; padding:10px 14px; }
footer { color:var(--suave); font-size:.85rem; margin-top:32px; }
'@

$html = New-Object 'System.Collections.Generic.List[string]'
$html.Add('<!DOCTYPE html><html lang="es"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">')
$html.Add('<title>Informe de seguridad</title><style>' + $css + '</style></head><body><main>')
$html.Add('<h1>Informe de seguridad de Windows</h1>')
$html.Add(('<p class="sub">{0}<br>{1} · script {2}</p>' -f (ConvertTo-HtmlSeguro $resumenEquipo), $ahora.ToString('dd/MM/yyyy HH:mm'), (ConvertTo-HtmlSeguro $VersionScript)))
if (-not $script:EsAdmin) { $html.Add('<p class="aviso-admin">Ejecutado sin permisos de administrador: varias comprobaciones no se pudieron hacer. Vuelve a ejecutarlo aceptando la ventana de permisos.</p>') }
$html.Add('<div class="resumen">')
foreach ($e in 'Critico', 'Aviso', 'OK', 'Info', 'Error') {
    $html.Add(('<div class="caja {0}"><b>{1}</b>{2}</div>' -f $e, $cuenta[$e], $etiquetas[$e]))
}
$html.Add('</div>')

function Add-TarjetaHtml {
    param($Hallazgo, [switch]$ConRecomendacion)
    $html.Add('<div class="tarjeta"><div class="fila">')
    $html.Add(('<span class="etiqueta {0}">{1}</span><div>' -f $Hallazgo.Estado, $etiquetas[$Hallazgo.Estado]))
    $html.Add(('<div class="control">{0}</div>' -f (ConvertTo-HtmlSeguro $Hallazgo.Control)))
    if ($Hallazgo.Detalle) { $html.Add(('<p class="detalle">{0}</p>' -f (ConvertTo-HtmlSeguro $Hallazgo.Detalle))) }
    if ($ConRecomendacion -and $Hallazgo.Recomendacion) { $html.Add(('<p class="reco">{0}</p>' -f (ConvertTo-HtmlSeguro $Hallazgo.Recomendacion))) }
    $html.Add('</div></div></div>')
}

if ($prioridades.Count -gt 0) {
    $html.Add('<h2>Qué hacer primero</h2>')
    foreach ($h in $prioridades) { Add-TarjetaHtml -Hallazgo $h -ConRecomendacion }
}
foreach ($c in $ordenCategorias) {
    $items = @($script:Hallazgos | Where-Object { $_.Categoria -eq $c })
    if ($items.Count -eq 0) { continue }
    $html.Add(('<h2>{0}</h2>' -f (ConvertTo-HtmlSeguro $c)))
    foreach ($h in $items) { Add-TarjetaHtml -Hallazgo $h -ConRecomendacion:($h.Estado -ne 'OK') }
}
$html.Add('<h2>Inventario del equipo</h2>')
foreach ($grupo in $gruposInventario) {
    $html.Add(('<h3>{0}</h3><table>' -f (ConvertTo-HtmlSeguro $grupo.Name)))
    foreach ($d in $grupo.Group) { $html.Add(('<tr><td>{0}</td><td>{1}</td></tr>' -f (ConvertTo-HtmlSeguro $d.Nombre), (ConvertTo-HtmlSeguro $d.Valor))) }
    $html.Add('</table>')
}
$html.Add('<footer>Generado por Auditoria-Seguridad.ps1 (solo lectura: no cambió nada del sistema). Contiene nombres de usuario y programas: no lo publiques.</footer>')
$html.Add('</main></body></html>')

try {
    $html -join "`n" | Out-File -LiteralPath $rutaHtml -Encoding utf8
    $txt -join "`r`n" | Out-File -LiteralPath $rutaTxt -Encoding utf8
} catch {
    $rutaHtml = Join-Path $env:TEMP (Split-Path -Leaf $rutaHtml)
    $rutaTxt = Join-Path $env:TEMP (Split-Path -Leaf $rutaTxt)
    $html -join "`n" | Out-File -LiteralPath $rutaHtml -Encoding utf8
    $txt -join "`r`n" | Out-File -LiteralPath $rutaTxt -Encoding utf8
}

# --- Consola ---
Write-Host ''
Write-Host '================ RESUMEN ================' -ForegroundColor Cyan
Write-Host ('Críticos: {0}   Avisos: {1}   Correctos: {2}   Info: {3}   Sin comprobar: {4}' -f $cuenta.Critico, $cuenta.Aviso, $cuenta.OK, $cuenta.Info, $cuenta.Error)
foreach ($h in $prioridades) {
    $color = 'Yellow'
    if ($h.Estado -eq 'Critico') { $color = 'Red' }
    Write-Host ('[{0}] {1}' -f $etiquetas[$h.Estado], $h.Control) -ForegroundColor $color
}
Write-Host ''
Write-Host "Informe HTML:  $rutaHtml" -ForegroundColor Green
Write-Host "Informe texto: $rutaTxt" -ForegroundColor Green

# Abrir el informe a través de explorer.exe: así el navegador no se ejecuta como administrador.
try { Start-Process -FilePath (Join-Path $env:SystemRoot 'explorer.exe') -ArgumentList ('"{0}"' -f $rutaHtml) } catch { }

if ($Relanzado) {
    Write-Host ''
    Read-Host 'Pulsa Enter para cerrar esta ventana'
}
