# Crea despliegue\.env con claves al azar (nunca repetidas, nunca "123456").
#   .\generar-env.ps1 -Dominio son.tudominio.com -EmailAdmin tu@correo.com -NombreAdmin "Francina De Napoli"
param(
    [Parameter(Mandatory = $true)][string]$Dominio,
    [Parameter(Mandatory = $true)][string]$EmailAdmin,
    [string]$NombreAdmin = 'Administrador'
)
$ErrorActionPreference = 'Stop'
$destino = Join-Path $PSScriptRoot '.env'
if (Test-Path $destino) { throw "Ya existe $destino. Si querés generar uno nuevo, borralo primero (ojo: cambiar las claves en un servidor que ya anda rompe el acceso a la base)." }

function Clave-Azar($largo) {
    $bytes = New-Object byte[] $largo
    [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
    return ([Convert]::ToBase64String($bytes) -replace '[^a-zA-Z0-9]', '').Substring(0, $largo)
}

$passAdmin = Clave-Azar 14
$contenido = @"
DOMINIO=$Dominio
DB_PASSWORD=$(Clave-Azar 32)
JWT_SECRET=$(Clave-Azar 64)
ADMIN_EMAIL=$EmailAdmin
ADMIN_PASSWORD=$passAdmin
ADMIN_NOMBRE=$NombreAdmin
DEMO_DOMINIO=demo.$Dominio
DEMO_JWT_SECRET=$(Clave-Azar 64)
DEMO_ADMIN_EMAIL=demo@sonoperation.com
DEMO_ADMIN_PASSWORD=conocer-son
DEMO_ADMIN_NOMBRE=Demostración
"@
[IO.File]::WriteAllText($destino, $contenido + "`n", (New-Object Text.UTF8Encoding $false))
Write-Host "Listo: $destino"
Write-Host ""
Write-Host "Tu primer ingreso al panel:"
Write-Host "  usuario:    $EmailAdmin"
Write-Host "  contraseña: $passAdmin"
Write-Host "(guardala en un lugar seguro y cambiala apenas entres, desde 'Perfil')"
