# Sube SON al servidor y lo deja funcionando. Se puede correr las veces que haga falta:
# cada vez actualiza el programa SIN tocar la base de datos ni los informes guardados.
#
#   .\publicar.ps1 -Servidor root@123.45.67.89
#   .\publicar.ps1 -Servidor root@123.45.67.89 -ConBase    (la primera vez, para llevar los datos de esta PC)
#
# Antes: tener despliegue\.env (generar-env.ps1) y el servidor creado con cloud-init.yaml.
param(
    [Parameter(Mandatory = $true)][string]$Servidor,
    [switch]$ConBase,
    [switch]$SinPanel
)
$ErrorActionPreference = 'Stop'
$raiz = Split-Path -Parent $PSScriptRoot
$paquete = Join-Path $PSScriptRoot 'paquete'

function Ejecutar($texto, [scriptblock]$bloque) {
    Write-Host ">> $texto" -ForegroundColor Cyan
    & $bloque
    if ($LASTEXITCODE -ne 0) { throw "Falló: $texto" }
}

if (-not (Test-Path (Join-Path $PSScriptRoot '.env'))) {
    throw 'Falta despliegue\.env. Generalo con: .\generar-env.ps1 -Dominio son.tudominio.com -EmailAdmin tu@correo.com'
}

# 1) Panel web. Vive en /panel/ para que la raíz del dominio sea la página pública.
$panel = Join-Path $raiz 'son_admin\build\web'
$basePanel = Join-Path $panel 'index.html'
$panelListo = (Test-Path $basePanel) -and ((Get-Content $basePanel -Raw) -match 'base href="/panel/"')
if (-not $SinPanel -or -not $panelListo) {
    Ejecutar 'Compilando el panel web' { Push-Location (Join-Path $raiz 'son_admin'); try { flutter build web --release --base-href /panel/ --no-wasm-dry-run } finally { Pop-Location } }
}

# 1b) App del técnico, para abrirla en el celular en https://el-dominio/tecnico/
$tecnico = Join-Path $raiz 'son_tecnico\build\web'
$baseTecnico = Join-Path $tecnico 'index.html'
$baseLista = (Test-Path $baseTecnico) -and ((Get-Content $baseTecnico -Raw) -match 'base href="/tecnico/"')
if (-not $baseLista) {
    Ejecutar 'Compilando la app del técnico' { Push-Location (Join-Path $raiz 'son_tecnico'); try { flutter build web --release --base-href /tecnico/ --no-wasm-dry-run } finally { Pop-Location } }
}

# 2) Programa del agente (SON-Agente.exe)
$exe = Join-Path $raiz 'backend\descargas\SON-Agente.exe'
if (-not (Test-Path $exe)) {
    Ejecutar 'Armando SON-Agente.exe' { Push-Location (Join-Path $raiz 'agente'); try { node construir.js } finally { Pop-Location } }
}

# 3) Armar el paquete
Write-Host '>> Armando el paquete' -ForegroundColor Cyan
if (Test-Path $paquete) { Remove-Item $paquete -Recurse -Force }
$app = Join-Path $paquete 'app'
New-Item -ItemType Directory -Force $app | Out-Null
foreach ($archivo in 'index.js', 'package.json', 'package-lock.json') { Copy-Item (Join-Path $raiz "backend\$archivo") $app }
foreach ($carpeta in 'src', 'sql', 'assets', 'presentacion') { Copy-Item (Join-Path $raiz "backend\$carpeta") (Join-Path $app $carpeta) -Recurse }
Copy-Item $panel (Join-Path $app 'panel') -Recurse
Copy-Item $tecnico (Join-Path $app 'tecnico') -Recurse
New-Item -ItemType Directory -Force (Join-Path $app 'descargas') | Out-Null
Copy-Item $exe (Join-Path $app 'descargas')
Copy-Item (Join-Path $PSScriptRoot 'Dockerfile') $app
foreach ($archivo in 'docker-compose.yml', 'Caddyfile', '.env') { Copy-Item (Join-Path $PSScriptRoot $archivo) $paquete }
# Los scripts del servidor tienen que terminar las líneas con \n (formato Linux).
foreach ($archivo in 'backup.sh', 'importar-base.sh') {
    $texto = (Get-Content (Join-Path $PSScriptRoot $archivo) -Raw -Encoding UTF8) -replace "`r`n", "`n"
    [IO.File]::WriteAllText((Join-Path $paquete $archivo), $texto, (New-Object Text.UTF8Encoding $false))
}
if ($ConBase) {
    Ejecutar 'Exportando la base de datos de esta PC' { & (Join-Path $PSScriptRoot 'exportar-base.ps1'); $global:LASTEXITCODE = 0 }
    Copy-Item (Join-Path $PSScriptRoot 'datos-base.sql') $paquete
}

$tgz = Join-Path $PSScriptRoot 'son.tgz'
Ejecutar 'Comprimiendo' { tar -czf $tgz -C $paquete . }

# 4) Subir y desplegar
$ssh = @('-o', 'StrictHostKeyChecking=accept-new')
Ejecutar 'Subiendo al servidor' { scp @ssh $tgz "${Servidor}:/tmp/son.tgz" }
Ejecutar 'Descomprimiendo en el servidor' {
    # (sin comillas ni tildes dentro del comando: Windows las rompe al pasarlas por ssh)
    ssh @ssh $Servidor 'test -f /var/lib/son-listo || { echo ERROR el servidor no esta preparado: falta correr preparar-servidor.sh; exit 1; }; mkdir -p /opt/son/datos && cd /opt/son && rm -rf app && tar xzf /tmp/son.tgz && rm /tmp/son.tgz && chmod +x *.sh && chmod 600 .env'
}
if ($ConBase) {
    Ejecutar 'Importando la base de datos' { ssh @ssh $Servidor 'bash /opt/son/importar-base.sh && rm -f /opt/son/datos-base.sql' }
}
Ejecutar 'Arrancando SON' { ssh @ssh $Servidor 'cd /opt/son && docker compose up -d --build && docker compose ps' }

Remove-Item $tgz -Force
Remove-Item $paquete -Recurse -Force
$dominio = ((Get-Content (Join-Path $PSScriptRoot '.env')) | Where-Object { $_ -match '^DOMINIO=' }) -replace '^DOMINIO=', ''
Write-Host ""
Write-Host "Listo. Abrí https://$dominio (el candadito puede tardar un minuto en aparecer la primera vez)." -ForegroundColor Green
