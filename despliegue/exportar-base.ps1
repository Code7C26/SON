# Exporta la base de datos de ESTA PC (la que usa backend\.env) para llevarla al servidor.
#
#   .\exportar-base.ps1               -> despliegue\datos-base.sql (los datos: técnicos, órdenes, clientes, administradores)
#   .\exportar-base.ps1 -SoloEsquema  -> regenera backend\sql\esquema.sql (solo la estructura, sin datos)
#
# No modifica nada en tu base: solo la lee.
param([switch]$SoloEsquema)

$ErrorActionPreference = 'Stop'
$raiz = Split-Path -Parent $PSScriptRoot
$envArchivo = Join-Path $raiz 'backend\.env'
if (-not (Test-Path $envArchivo)) { throw "No encuentro $envArchivo" }

function Leer-Env($clave) {
    $linea = Get-Content $envArchivo | Where-Object { $_ -match "^$clave=" } | Select-Object -First 1
    if (-not $linea) { return $null }
    return ($linea -replace "^$clave=", '').Trim().Trim('"')
}

$pgDump = (Get-Command pg_dump -ErrorAction SilentlyContinue).Source
if (-not $pgDump) {
    $pgDump = Get-ChildItem 'C:\Program Files\PostgreSQL\*\bin\pg_dump.exe' -ErrorAction SilentlyContinue |
        Sort-Object FullName -Descending | Select-Object -First 1 -ExpandProperty FullName
}
if (-not $pgDump) { throw 'No encuentro pg_dump. Instalá PostgreSQL o agregá su carpeta bin al PATH.' }

$env:PGPASSWORD = Leer-Env 'DB_PASSWORD'
$comun = @('-h', (Leer-Env 'DB_HOST'), '-p', ($(if (Leer-Env 'DB_PORT') { Leer-Env 'DB_PORT' } else { '5432' })), '-U', (Leer-Env 'DB_USER'), '-d', (Leer-Env 'DB_NAME'), '--no-owner', '--no-privileges')

$temporal = Join-Path $env:TEMP 'son_dump.sql'
if ($SoloEsquema) {
    & $pgDump @comun --schema-only -f $temporal
    $destino = Join-Path $raiz 'backend\sql\esquema.sql'
    $cabecera = "-- Esquema de la base de SON (PostgreSQL). Se aplica solo cuando la base está vacía.`n-- Para regenerarlo: despliegue\exportar-base.ps1 -SoloEsquema`n"
} else {
    # Los agentes no se llevan: cada servidor tiene los suyos (se vinculan de nuevo con un código).
    & $pgDump @comun --data-only --column-inserts --disable-triggers --exclude-table-data=agentes -f $temporal
    $destino = Join-Path $PSScriptRoot 'datos-base.sql'
    $cabecera = ''
}
if ($LASTEXITCODE -ne 0) { throw 'pg_dump falló.' }

# Quita instrucciones que dependen de la versión de PostgreSQL y no hacen falta.
$limpio = Get-Content $temporal -Encoding UTF8 | Where-Object {
    $_ -notmatch '^\\' -and $_ -notmatch '^SET transaction_timeout' -and $_ -notmatch '^-- Dumped'
}
if ($SoloEsquema) { $limpio = $limpio | Where-Object { $_ -notmatch "set_config\('search_path'" } }
[IO.File]::WriteAllText($destino, $cabecera + ($limpio -join "`n") + "`n", (New-Object Text.UTF8Encoding $false))
Remove-Item $temporal -Force
Write-Host "Listo: $destino"
