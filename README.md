<div align="center">
  <img src="DESINGS/1.png" alt="SON Operation Platform" width="220"/>
  <h1>SON — Sistema de Gestión Operativa</h1>
  <p><strong>Plataforma integral SaaS para la digitalización, auditoría y control de operaciones técnicas en terreno.</strong></p>
  <p>
    <img src="https://img.shields.io/badge/Versi%C3%B3n-2.0.0-ff6147?style=flat-square" alt="Version"/>
    <img src="https://img.shields.io/badge/Entorno-Flutter%20%7C%20Node.js%20%7C%20PostgreSQL-1c1c1e?style=flat-square" alt="Tech Stack"/>
    <img src="https://img.shields.io/badge/Estado-Producci%C3%B3n-d99c13?style=flat-square" alt="Estado"/>
  </p>
</div>

---

## 📌 Visión General

**SON (Operation Platform)** es una solución empresarial Full-Stack concebida para centralizar, auditar y optimizar los flujos de trabajo de organizaciones con despliegue de personal técnico y operarios en campo.

Diseñada bajo estándares de escalabilidad B2B, la plataforma sincroniza en tiempo real la planificación estratégica desde la administración central, la ejecución guiada en campo mediante aplicación móvil y la comunicación automatizada de calidad hacia los clientes finales.

---

## 🏗️ Arquitectura y Ecosistema Tecnológico

La solución articula tres pilares desacoplados que garantizan alta disponibilidad, integridad de datos y portabilidad:

* **Aplicación Móvil (Equipos en Terreno):** Desarrollada en **Flutter**, orientada a entornos offline/online de alto rendimiento, geolocalización continua y captura de evidencias biométricas/digitales.
* **Panel de Control Central (Administración):** Implementado en **Flutter Web**, optimizado para supervisión global, despacho de servicios y visualización geoespacial.
* **Backend y Servicios Core:** API REST desarrollada en **Node.js con Express**, con persistencia relacional en **PostgreSQL**, transaccionalidad segura y servicios dedicados de generación de documentos formales mediante **PDFKit**.

El servidor expone la API, sirve el panel y la aplicación web del técnico, y entrega los comprobantes al repositorio documental de la organización. En producción, el perímetro HTTPS queda a cargo de **Caddy**, orquestado junto con la base de datos mediante **Docker Compose**.

---

## 🚀 Capacidades y Módulos Operativos

### 1. Panel de Administración Central (Web)

* **Monitoreo Geoespacial en Vivo:** Trazabilidad de recursos técnicos en mapa interactivo en tiempo real.
* **Planificación y Motor de Recurrencia:** Despacho dinámico de órdenes con asignación por técnico, cliente y frecuencias programadas.
* **Gestión de Protocolos (Checklists):** Parametrización de listas de verificación e inspección específicas por rubro o servicio.
* **Gobierno de Accesos:** Gestión integral de usuarios, asignación de roles y control de credenciales.
* **Repositorio Estructurado:** Auditoría y resguardo documental categorizado por cuentas corporativas y clientes.

### 2. Aplicación Móvil para Equipos en Terreno

* **Validación de Presencia por GPS:** Registro inmutable de coordenadas geográficas en el check-in de cada servicio.
* **Navegación e Interfaz de Gestión:** Visualización de asignaciones diarias, mapa integrado y cronómetro de permanencia en sitio.
* **Protocolos de Ejecución:** Cumplimentación obligatoria de checklists operativos e ingreso de observaciones técnicas.
* **Registro de Evidencias:** Captura fotográfica con almacenamiento de metadatos desde la cámara del dispositivo.
* **Cierre y Conformidad Digital:** Lienzo táctil para la rúbrica y certificación de firmas digitales del técnico y responsable en el sitio.

### 3. Servicios Automatizados de Calidad y Cierre

* **Compilación de Reportes Formales:** Generación automática de actas e informes técnicos en formato PDF con inclusión de datos operativos, fotografías y firmas.
* **Notificaciones Automatizadas:** Alertas directas al cliente ante el inicio de recorrido y arribo del técnico asignado.
* **Medición de Experiencia del Cliente:** Envío instantáneo de constancias e integración de encuestas de satisfacción del servicio.

---

## 🎨 Identidad Visual y Diseño

El diseño de interfaces responde a un sistema visual de alto contraste y legibilidad operativa:

* **Paleta de Colores Corporativa:**
  * Base principal: `#f4f4f4`
  * Acento primario / Acción: `#ff6147` (Naranja coral)
  * Acento secundario / Indicadores de estado: `#d99c13` (Dorado/Ocre)
  * Paneles de contraste: `#1c1c1e` (Gris oscuro corporativo)
* **Tipografía Oficial:** `BwGradualDEMO` implementada de manera unificada en interfaces web y móviles.

Los originales de marca se encuentran en `DESINGS/`.

---

## ⚙️ Requisitos de Despliegue y Configuración

### Prerrequisitos

* Flutter SDK (`^3.x`)
* Node.js (`^18.x` o superior)
* PostgreSQL (`^14.x`; la imagen de producción es PostgreSQL 17)
* Servidor de almacenamiento en red / Disco de red para resguardo de comprobantes

### Organización del repositorio

| Ruta | Responsabilidad |
| --- | --- |
| `backend/` | API REST, autenticación, recurrencia, correo y motor PDF |
| `son_admin/` | Panel de control (Flutter Web) |
| `son_tecnico/` | Aplicación de campo (Flutter) |
| `agente/` | Agente de oficina que entrega los informes al disco de red |
| `despliegue/` | Contenedores, proxy HTTPS y procedimiento de publicación |
| `DESINGS/` | Sistema de identidad visual |

### Configuración del Entorno Backend

1. Clonar el repositorio y navegar a la carpeta de servicios:

   ```bash
   cd backend
   npm install
   ```

2. Crear el archivo de entorno a partir de la plantilla y completar las credenciales. No versionar el archivo resultante.

   ```bash
   copy .env.example .env
   ```

   Variables operativas:

   | Variable | Función |
   | --- | --- |
   | `PORT` | Puerto de la API (referencia: `3000`) |
   | `DB_USER`, `DB_HOST`, `DB_PORT`, `DB_NAME`, `DB_PASSWORD` | Conexión a PostgreSQL |
   | `JWT_SECRET` | Firma de sesiones |
   | `ADMIN_EMAIL`, `ADMIN_PASSWORD`, `ADMIN_NOMBRE` | Cuenta inicial de administración, creada solo si la base no posee una |
   | `INFORMES_DIR` | Carpeta de red donde se archivan los comprobantes por cliente |
   | `PUBLIC_URL` | Dirección pública que abre el cliente al responder la encuesta |
   | `SMTP_HOST`, `SMTP_PORT`, `SMTP_SECURE`, `SMTP_USER`, `SMTP_PASS`, `SMTP_FROM` | Canal de notificaciones. En Gmail se requiere una clave de aplicación |

3. Crear la base indicada en `DB_NAME` (el entorno de referencia utiliza `sima_db`). Al primer arranque, el servicio aplica `backend/sql/esquema.sql` si el esquema aún no existe.

4. Iniciar la API:

   ```bash
   node index.js
   ```

   El proceso escucha en `0.0.0.0`. Con el panel y la aplicación compilados, quedan publicados en `http://localhost:3000/panel/` y `http://localhost:3000/tecnico/`.

### Panel de Control Central

```bash
cd son_admin
flutter pub get
flutter run -d chrome
```

Compilación para el servidor:

```bash
flutter build web --dart-define=API_URL=https://su-dominio
```

Si no se define `API_URL`, el panel publicado utiliza el mismo origen desde el que se abre.

### Aplicación Móvil

```bash
cd son_tecnico
flutter pub get
flutter run
```

Paquete de distribución Android, apuntando a la API de producción:

```bash
flutter build apk --release --dart-define=API_URL=https://su-dominio
```

El artefacto queda en `son_tecnico/build/app/outputs/flutter-apk/app-release.apk`. Sin `API_URL`, la compilación de campo resuelve `https://sonoperation.com`.

### Despliegue productivo

El directorio `despliegue/` describe la topología de producción: PostgreSQL, la aplicación Node.js y Caddy, con los secretos fuera del control de versiones. El procedimiento operativo —dominio, servidor, agente de oficina y publicación— está documentado en `despliegue/GUIA-PUBLICACION.md`.

La entrega al disco de red puede resolverse de dos maneras: escritura directa sobre `INFORMES_DIR`, o mediante el agente de oficina, que se vincula desde el panel (**Informes → Conectar agente**) y sincroniza los comprobantes pendientes cuando el puesto de la organización está disponible.
