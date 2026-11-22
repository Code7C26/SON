# Abre una instalación vacía de SON en el puerto 3010.
# La base de SIMA (puerto 3000) no se modifica.
$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot

node crear-base-vacia.js
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$env:BASE_VACIA = '1'
$env:DB_NAME = 'son_vacia'
$env:PORT = '3010'
$env:INFORMES_DIR = Join-Path $PSScriptRoot 'storage\base-vacia\clientes'
$env:STORAGE_DIR = Join-Path $PSScriptRoot 'storage\base-vacia\interno'
New-Item -ItemType Directory -Force -Path $env:INFORMES_DIR, $env:STORAGE_DIR | Out-Null

node index.js
