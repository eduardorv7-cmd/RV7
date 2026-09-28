#Requires -Version 5.1
<#
.SYNOPSIS
    Deja el Brave normal "minimalista", como Brave Origin, con las políticas oficiales de Brave.

.DESCRIPTION
    Brave Origin (de pago en Windows y Mac) desactiva Rewards, Wallet, VPN, Leo,
    News, Talk, Tor, la telemetría, etc. En su modo "actualización" lo hace
    fijando 16 políticas de Brave. Se puede comprobar en el código fuente de
    Brave: brave-core, browser/brave_origin/brave_origin_service_factory.cc.

    Este script fija esas mismas 16 políticas en el Brave normal de Windows:
      - Como administrador: HKLM\SOFTWARE\Policies\BraveSoftware\Brave (todos los usuarios).
      - Sin permisos:       HKCU\SOFTWARE\Policies\BraveSoftware\Brave (solo tu usuario).

    No descarga nada ni toca otros programas ni otras políticas. Con -Revertir
    borra lo que puso.

    Diferencia con Brave Origin: aquí esas funciones siguen dentro del programa
    (desactivadas y ocultas); en la app independiente de Brave Origin se eliminan
    al compilar.

.PARAMETER Mantener
    Funciones que quieres conservar: Rewards, Wallet, VPN, Leo, IALocal, News,
    Talk, Tor, Speedreader, Playlist, Wayback, WebDiscovery, P3A, PingUso,
    AliasCorreo, PSST.

.PARAMETER Revertir
    Elimina las políticas que pone este script (en HKCU y, si eres administrador, en HKLM).

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File .\Brave-Minimalista.ps1

.EXAMPLE
    # Todo desactivado menos el VPN y las ventanas privadas con Tor
    powershell -NoProfile -ExecutionPolicy Bypass -File .\Brave-Minimalista.ps1 -Mantener VPN,Tor

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File .\Brave-Minimalista.ps1 -Revertir
#>
[CmdletBinding()]
param(
    [ValidateSet('Rewards', 'Wallet', 'VPN', 'Leo', 'IALocal', 'News', 'Talk', 'Tor', 'Speedreader', 'Playlist',
        'Wayback', 'WebDiscovery', 'P3A', 'PingUso', 'AliasCorreo', 'PSST')]
    [string[]]$Mantener = @(),
    [switch]$Revertir
)

$ErrorActionPreference = 'Stop'

# Las 16 políticas que Brave Origin fija por defecto. Valor = el que desactiva la función.
$politicas = @(
    [pscustomobject]@{ Clave = 'Rewards'; Nombre = 'BraveRewardsDisabled'; Valor = 1; Funcion = 'Brave Rewards y anuncios de Brave' }
    [pscustomobject]@{ Clave = 'Wallet'; Nombre = 'BraveWalletDisabled'; Valor = 1; Funcion = 'Brave Wallet (criptomonedas y dominios Web3)' }
    [pscustomobject]@{ Clave = 'VPN'; Nombre = 'BraveVPNDisabled'; Valor = 1; Funcion = 'Brave VPN' }
    [pscustomobject]@{ Clave = 'Leo'; Nombre = 'BraveAIChatEnabled'; Valor = 0; Funcion = 'Leo (asistente de IA)' }
    [pscustomobject]@{ Clave = 'IALocal'; Nombre = 'BraveLocalAIEnabled'; Valor = 0; Funcion = 'IA local (búsqueda semántica en el historial)' }
    [pscustomobject]@{ Clave = 'News'; Nombre = 'BraveNewsDisabled'; Valor = 1; Funcion = 'Brave News' }
    [pscustomobject]@{ Clave = 'Talk'; Nombre = 'BraveTalkDisabled'; Valor = 1; Funcion = 'Brave Talk (videollamadas)' }
    [pscustomobject]@{ Clave = 'Tor'; Nombre = 'TorDisabled'; Valor = 1; Funcion = 'Ventanas privadas con Tor' }
    [pscustomobject]@{ Clave = 'Speedreader'; Nombre = 'BraveSpeedreaderEnabled'; Valor = 0; Funcion = 'Speedreader (modo lectura)' }
    [pscustomobject]@{ Clave = 'Playlist'; Nombre = 'BravePlaylistEnabled'; Valor = 0; Funcion = 'Playlist' }
    [pscustomobject]@{ Clave = 'Wayback'; Nombre = 'BraveWaybackMachineEnabled'; Valor = 0; Funcion = 'Aviso de Wayback Machine en páginas caídas' }
    [pscustomobject]@{ Clave = 'WebDiscovery'; Nombre = 'BraveWebDiscoveryEnabled'; Valor = 0; Funcion = 'Web Discovery Project' }
    [pscustomobject]@{ Clave = 'P3A'; Nombre = 'BraveP3AEnabled'; Valor = 0; Funcion = 'Analítica de uso privada (P3A)' }
    [pscustomobject]@{ Clave = 'PingUso'; Nombre = 'BraveStatsPingEnabled'; Valor = 0; Funcion = 'Ping diario de uso' }
    [pscustomobject]@{ Clave = 'AliasCorreo'; Nombre = 'EmailAliasesEnabled'; Valor = 0; Funcion = 'Alias de correo' }
    [pscustomobject]@{ Clave = 'PSST'; Nombre = 'PsstEnabled'; Valor = 0; Funcion = 'Ajuste automático de privacidad por web (PSST)' }
)

$rutaMaquina = 'HKLM:\SOFTWARE\Policies\BraveSoftware\Brave'
$rutaUsuario = 'HKCU:\SOFTWARE\Policies\BraveSoftware\Brave'

function Test-EsAdministrador {
    try {
        $principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
        return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch {
        return $false
    }
}

function Remove-PoliticasDe {
    param([string]$Ruta)
    if (-not (Test-Path -LiteralPath $Ruta)) { return 0 }
    $borradas = 0
    $clave = Get-Item -LiteralPath $Ruta
    foreach ($p in $politicas) {
        if ($clave.GetValueNames() -contains $p.Nombre) {
            Remove-ItemProperty -LiteralPath $Ruta -Name $p.Nombre
            $borradas++
        }
    }
    # Si la clave queda vacía (no había otras políticas tuyas), se elimina.
    $clave = Get-Item -LiteralPath $Ruta
    if ($clave.ValueCount -eq 0 -and $clave.SubKeyCount -eq 0) { Remove-Item -LiteralPath $Ruta }
    return $borradas
}

$esAdmin = Test-EsAdministrador

if ($Revertir) {
    $total = Remove-PoliticasDe -Ruta $rutaUsuario
    if ($esAdmin) {
        $total += Remove-PoliticasDe -Ruta $rutaMaquina
    } elseif (Test-Path -LiteralPath $rutaMaquina) {
        Write-Warning 'Hay políticas de Brave para todos los usuarios (HKLM). Para quitarlas, ejecuta este script como administrador con -Revertir.'
    }
    Write-Host "Políticas eliminadas: $total. Cierra Brave del todo y vuelve a abrirlo." -ForegroundColor Green
    return
}

if ($esAdmin) {
    $ruta = $rutaMaquina
    $ambito = 'todos los usuarios de este PC'
} else {
    $ruta = $rutaUsuario
    $ambito = 'solo tu usuario (ejecuta como administrador para aplicarlo a todos)'
}

# Ojo: New-Item -Force sobre una clave existente la vaciaría; solo se crea si no existe.
if (-not (Test-Path -LiteralPath $ruta)) { New-Item -Path $ruta -Force | Out-Null }

Write-Host "Aplicando políticas de Brave en $ruta ($ambito)" -ForegroundColor Cyan
foreach ($p in $politicas) {
    if ($Mantener -contains $p.Clave) {
        # Se quita de las dos ramas por si quedó de una ejecución anterior (con o sin administrador).
        foreach ($r in @($rutaMaquina, $rutaUsuario)) {
            if (Test-Path -LiteralPath $r) { Remove-ItemProperty -LiteralPath $r -Name $p.Nombre -ErrorAction SilentlyContinue }
        }
        Write-Host ('  Se mantiene:  {0}' -f $p.Funcion) -ForegroundColor Yellow
        continue
    }
    New-ItemProperty -LiteralPath $ruta -Name $p.Nombre -PropertyType DWord -Value $p.Valor -Force | Out-Null
    Write-Host ('  Desactivado:  {0}  ({1} = {2})' -f $p.Funcion, $p.Nombre, $p.Valor)
}

$ejecutables = @(
    (Join-Path $env:ProgramFiles 'BraveSoftware\Brave-Browser\Application\brave.exe'),
    (Join-Path $env:LOCALAPPDATA 'BraveSoftware\Brave-Browser\Application\brave.exe')
)
$instalado = @($ejecutables | Where-Object { $_ -and (Test-Path -LiteralPath $_) }).Count -gt 0

Write-Host ''
if (-not $instalado) {
    Write-Host 'No encontré Brave instalado. Las políticas se aplicarán cuando lo instales:' -ForegroundColor Yellow
    Write-Host '  winget install --id Brave.Brave -e   (o desde https://brave.com/download/)' -ForegroundColor Yellow
}
Write-Host 'Listo. Ahora:' -ForegroundColor Green
Write-Host '  1. Cierra Brave del todo (también el icono junto al reloj, si lo hay) y vuelve a abrirlo.'
Write-Host '  2. Escribe brave://policy en la barra de direcciones: deberías ver estas políticas con estado "OK".'
Write-Host '  3. Brave mostrará "Tu organización administra el navegador": es normal, lo indica por las políticas.'
Write-Host '  Para deshacerlo: .\Brave-Minimalista.ps1 -Revertir'
