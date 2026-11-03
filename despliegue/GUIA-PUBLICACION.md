# Publicar SON en internet (dominio + servidor + agente)

Al terminar vas a tener:

```
Celulares de los técnicos ─┐
Panel web (vos y la oficina) ─┼──►  https://son.tudominio.com  (servidor en Hetzner, prendido 24 h)
                              │            │
                              │            ▼  cada 30 s
                              │     Agente (PC de la oficina) ──► disco K, carpeta de cada cliente
```

> Los scripts de esta carpeta se probaron por partes en la PC de desarrollo (agente, vinculación, esquema de
> base vacía). El tramo Docker/Hetzner solo se puede probar con el servidor real: si algo falla, copiá el
> mensaje de error y se arregla.

Costo aproximado: dominio `.com` ≈ USD 10 por año + servidor ≈ € 5 por mes (+20 % si activás las copias de Hetzner).

---

## Paso 1 – Comprar el dominio en Cloudflare (10 minutos)

1. Entrá a <https://dash.cloudflare.com/sign-up> y creá una cuenta (correo + contraseña, confirmá el mail).
2. En el menú de la izquierda: **Domain Registration → Register Domains**.
3. Buscá el nombre que quieras (el de este proyecto es `sonoperation.com`), elegilo y pagá con tarjeta. Conviene que el titular sea **la empresa**.
4. Listo: el dominio queda dentro de Cloudflare, que también administra sus direcciones (DNS).

No toques nada de `simaambiente.com`.

## Paso 2 – Crear el servidor en Hetzner (15 minutos)

1. Creá la cuenta en <https://accounts.hetzner.com/signUp>. Te pueden pedir verificar identidad: es normal y a veces tarda un día.
2. Entrá a la consola (<https://console.hetzner.cloud>) y creá un **Proyecto** (nombre: `son`).
3. **Llave SSH** (es la "contraseña" para entrar al servidor). En PowerShell, en tu PC:
   ```powershell
   ssh-keygen -t ed25519
   Get-Content $HOME\.ssh\id_ed25519.pub
   ```
   (apretá Enter a todo). Copiá el texto que muestra el segundo comando.
4. En Hetzner: **Security → SSH Keys → Add SSH key** y pegá ese texto.
5. **Servers → Add Server**:
   - Ubicación: la que ofrezca (Ashburn, EE. UU. queda más cerca de Argentina que Alemania).
   - Imagen: **Ubuntu 24.04**.
   - Tipo: el más barato con **2 vCPU y 4 GB** (alcanza de sobra).
   - Networking: dejá **IPv4 pública** tildada.
   - SSH keys: la que cargaste.
   - **Backups**: tildalo (copia de todo el servidor, +20 %).
   - **Cloud config**: pegá **todo** el contenido del archivo `despliegue\cloud-init.yaml`.
   - Nombre: `son`.
6. Apretá **Create & Buy now**. Anotá la **dirección IP** del servidor (ej. `123.45.67.89`).

El servidor tarda unos 3 minutos en prepararse solo (instala Docker, cierra el firewall, programa la copia de seguridad diaria).

### Si no podés usar Hetzner: otro proveedor

SON funciona en cualquier servidor con **Ubuntu 24.04** (2 vCPU / 4 GB de RAM, o 2 GB como mínimo). Alternativas:
**Vultr**, **DigitalOcean**, **Linode (Akamai)**, **Contabo**, **OVHcloud**, o **DonWeb** (argentino, se paga en pesos).
Los pasos son los mismos: cargar la llave SSH, elegir Ubuntu 24.04 y anotar la IP.

- Si el proveedor tiene el recuadro **"User data"** o **"Cloud-init"**, pegá ahí `cloud-init.yaml` (igual que en Hetzner).
- Si **no** lo tiene, esperá a que el servidor esté creado y después, desde tu PC:
  ```powershell
  cd C:\Users\franc\SIMAOPERATION\despliegue
  scp .\preparar-servidor.sh root@LA.IP:/root/
  ssh root@LA.IP "bash /root/preparar-servidor.sh"
  ```
  (la primera vez pregunta si confiás en el servidor: escribí `yes`). Tarda unos 3 minutos.
- Los scripts entran al servidor como `root` (así lo permiten los proveedores de arriba al cargar la llave SSH).

## Paso 3 – Apuntar el dominio al servidor (2 minutos)

En Cloudflare: tu dominio → **DNS → Records → Add record**:

| Campo | Valor |
|---|---|
| Type | `A` |
| Name | `son` |
| IPv4 address | la IP del servidor |
| Proxy status | **DNS only** (nube gris, **no** naranja) |

Tu dirección va a ser `son.tudominio.com`.

## Paso 4 – Preparar la configuración (en tu PC)

```powershell
cd C:\Users\franc\SIMAOPERATION\despliegue
.\generar-env.ps1 -Dominio son.tudominio.com -EmailAdmin tucorreo@ejemplo.com -NombreAdmin "Francina De Napoli"
```

Te muestra tu **usuario y contraseña inicial del panel**. Guardalos. El archivo `.env` que se crea tiene las claves del
servidor: **no lo compartas ni lo subas a git**, y guardá una copia en un lugar seguro (gestor de contraseñas).

## Paso 5 – Subir SON al servidor

```powershell
.\publicar.ps1 -Servidor root@LA.IP.DEL.SERVIDOR
```

La primera vez pregunta si confiás en el servidor: escribí `yes`. Tarda unos minutos (compila el panel y arma el
programa del agente). Cuando termina dice "Listo".

Entrá a `https://son.tudominio.com`. El candadito puede tardar uno o dos minutos la primera vez.

- Cada vez que cambies algo del programa, repetí **el mismo comando**: actualiza todo sin tocar la base de datos ni los informes.
- **Datos de prueba:** empezás con una base limpia (solo tu administrador). Es lo recomendable: no arrastra el técnico
  "Juan Pérez" ni las órdenes de prueba. Si de verdad querés llevar lo que hay en tu PC, la primera vez corré con
  `-ConBase` (`.\publicar.ps1 -Servidor root@IP -ConBase`).

## Paso 6 – Primeros pasos en el panel

1. Ingresá con el usuario y contraseña del Paso 4 y **cambiá la contraseña** desde tu perfil.
2. Si llevaste la base con `-ConBase`, borrá el administrador de prueba `admin@son.com` (sección Administradores).
3. Creá los técnicos con sus correos reales.

## Paso 7 – Conectar el agente en la PC de la oficina

1. En el panel: **Informes → Conectar agente → Descargar agente**.
2. Copiá `SON-Agente.exe` a la PC de la oficina que ve el disco K y hacé doble clic.
   - Windows puede avisar "Windows protegió tu PC" porque el programa no está firmado digitalmente:
     tocá **Más información → Ejecutar de todas formas**.
3. En el panel tocá **Generar código** y copiá el que aparece (`ABCD-EFGH@son.tudominio.com`). Pegalo en el programa.
4. Elegí la carpeta de clientes (`00. CLIENTES`).
5. Listo. Queda minimizado y arranca solo cuando se prende la PC. Si la PC está apagada, los informes esperan en el
   servidor y se entregan al prenderla.

Para cambiar la carpeta o volver a vincular: ejecutá `SON-Agente.exe --reconfigurar`.
El registro de lo que hace queda en `%APPDATA%\SON-Agente\agente.log`.

## Paso 8 – App de los técnicos

Android (APK):

```powershell
cd C:\Users\franc\SIMAOPERATION\son_tecnico
flutter build apk --release --dart-define=API_URL=https://son.tudominio.com
```

El archivo queda en `build\app\outputs\flutter-apk\app-release.apk`. Se instala en los celulares (hay que permitir
"instalar apps de origen desconocido").

iPhone: sin Mac hay que usar un servicio de compilación en la nube (Codemagic) y una cuenta Apple Developer
(USD 99 por año, a nombre de la empresa). Pendiente de decidir.

## Copias de seguridad

- Todos los días a las 3 AM el servidor guarda la base y los informes en `/opt/son/backups` (14 días).
- Eso no protege si se pierde el servidor entero: por eso activaste los **Backups de Hetzner**, y además
  conviene bajarte una copia cada tanto:
  ```powershell
  scp -r root@LA.IP:/opt/son/backups C:\Users\franc\Desktop\backups-son
  ```
- Los informes, además, terminan en el disco K de la empresa.

## Si algo no anda

| Síntoma | Qué mirar |
|---|---|
| `publicar.ps1` dice que el servidor se está preparando | Esperá 3 minutos y repetí. |
| No aparece el candadito / error de certificado | ¿La nube de Cloudflare está **gris**? ¿Pasaron unos minutos del Paso 3? Ver registros: `ssh root@IP "cd /opt/son && docker compose logs caddy"` |
| El panel no abre pero el dominio responde | `ssh root@IP "cd /opt/son && docker compose logs app"` |
| El agente dice "no reconoce a este agente" | Lo desvincularon: `SON-Agente.exe --reconfigurar` |
| El agente dice que la carpeta no está disponible | La PC no ve el disco K en ese momento; reintenta solo. |

## Seguridad: lo mínimo

- Solo están abiertos los puertos 80 y 443 (web) y 22 (SSH, solo con tu llave). La base de datos no se ve desde internet.
- Las contraseñas de técnicos y administradores se guardan cifradas; el login se bloquea tras varios intentos fallidos.
- Guardá el archivo `despliegue\.env` y la llave `~\.ssh\id_ed25519` en un lugar seguro: sin ellos no podés entrar al servidor.
