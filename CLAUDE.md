# CLAUDE.md — Guías de Diseño UX/UI y Arquitectura Visual (SON)

## 1. Contexto y Objetivo Visual
- **Producto:** SON, plataforma B2B para gestión operativa, higiene, seguridad y medio ambiente.
- **Identidad de marca:** El nombre oficial es exclusivamente **SON** (acompañado de su isologo de reloj de arena). Si encontrás textos antiguos en la web o en la app que digan "Sima Operation", reemplazalos por **SON**.
- **Ecosistema:** App Móvil en Flutter (uso en campo con una mano) + Panel Web / Landing en Flutter Web (uso administrativo y comercial).
- **Dirección Estética (Estilo Referencia):** Neo-minimalismo editorial B2B. Interfaces limpias y aireadas sobre fondo gris piedra claro (`#F4F4F4`), elementos de navegación flotantes con forma de píldora, alto contraste con bloques oscuros (`#2E2E2E`), acentos en coral vibrante (`#FF6147`), métricas grandes y micro-animaciones fluidas.
- **Regla de oro:** Mejorar primero la claridad y facilidad de uso (UX) sin romper la lógica de negocio ni las conexiones con el backend.

---

## 2. Regla Obligatoria sobre Tipografías
- **Tipografías base del proyecto:**
  - **Títulos y encabezados (Display):** `Plus Jakarta Sans`
  - **Textos de interfaz, botones y tablas (Body/UI):** `Inter`
- **REGLA ESTRICTA:** Si en algún momento proponés, agregás o cambiás una familia tipográfica en cualquier archivo del proyecto, **tenés que escribir explícitamente en tu respuesta cuál es el nombre exacto de la fuente nueva** antes de aplicarla.
- **Estilo de títulos (Contraste de peso):** Combinar texto en peso `Regular (400)` con palabras clave en `Bold (700)` dentro de un mismo titular (ej: *"Toda su operación* **sincronizada en un único ecosistema***"), con tracking ligeramente cerrado (`-0.5px`).

---

## 3. Paleta de Colores y Tokens (No hardcodear)
Centralizar todos los colores, fuentes y espaciados en los archivos de tema (`AppColors`, `AppTypography`, `AppSpacing`).

- **Fondo principal (Canvas):** `#F4F4F4` (gris neutro claro en toda la web y app).
- **Superficies y tarjetas flotantes:** `#FFFFFF` (blanco puro) con sombras muy suaves (`blur: 20px`, opacidad `4%`) o bordes sutiles de `1px` en `#D5D5D5`.
- **Bloques de alto contraste / Contenedor de logo / Botones secundarios:** `#2E2E2E` (tinta / negro carbón neutro, sin tono azul) con texto `#FFFFFF`.
- **Acento primario (CTA principal):** `#FF6147` (coral vibrante) con texto e íconos en tinta `#2E2E2E` (4.56:1). No usar texto blanco sobre coral: da 2.98:1 y no cumple contraste.
- **Etiquetas suaves (Eyebrow pills):** Fondo coral al 12% (`#FF6147` con opacidad) con texto `#FF6147` en mayúsculas y tracking amplio (`+1.2px`).
- **Acento secundario (Progreso, destacados, badges):** `#D99C13` (dorado/ámbar) con texto oscuro `#2E2E2E`.
- **Textos:**
  - Principal: `#2E2E2E`
  - Secundario / Descripciones: `#6E6E6E`
  - Muted / Etiquetas: `#9A9A9A`
- **Estados semánticos:** Éxito / Completado `#FF6147` | Alerta / Pendiente `#D99C13` | En progreso `#C46A3A` | Error `#C62828`.
- **Superficies secundarias:** relleno `#E7E7E7`.
- **Modo oscuro:** fondo `#2E2E2E`, panel `#262626`, tarjetas `#353535`, relleno `#3F3F3F`, bordes `#4C4C4C`, texto `#F4F4F4`, texto secundario `#B3B3B3`, error `#FF8A80`.
- **REGLA ESTRICTA:** usar solo estos colores. No agregar azules, grises azulados, verdes ni otros tonos nuevos; los tonos suaves se arman con opacidad del coral o del dorado.

---

## 4. Componentes Clave y Estilo Visual (Web y App)
1. **Barra de navegación flotante (Web):**
   - Contenedor redondeado tipo píldora (`border-radius: 999px`), flotando con margen superior, fondo `#FFFFFF` o `#EAEAEA`, isologo de reloj de arena de **SON** a la izquierda, enlaces limpios en el centro y botón CTA en píldora a la derecha.
2. **Bloques de Métricas / KPIs:**
   - Números grandes y protagonistas (`28px`–`36px` en `Bold`, color `#2E2E2E`, ej: `100%`, `10x`, `+50`) acompañados justo debajo por una etiqueta corta y fina (`13px`, color `#6E6E6E`).
3. **Contenedores Visuales y Tarjetas:**
   - Usar radios de borde generosos: `16px` a `24px` para tarjetas, `999px` para píldoras/botones y contenedores destacados con curvas orgánicas o recortes tipo cápsula.
   - En la app móvil, mostrar tarjetas limpias con máximo 3 o 4 datos clave, íconos circulares oscuros (`#2E2E2E`) y etiquetas de estado redondeadas.
4. **Movimiento y Micro-interacciones (Estilo Motion):**
   - Agregar transiciones suaves (`250ms`–`350ms`, `Curves.easeOutCubic`) al aparecer tarjetas, cambiar de pestaña o pasar el mouse (`hover` con leve elevación y cambio de tono).
   - Usar indicadores de flujo/conexión suaves entre pasos o módulos cuando corresponda.

---

## 5. Reglas de UX (Funcionalidad Obligatoria)
- **Interfaz autoexplicativa (CERO textos descriptivos redundantes):** Eliminá todos los mensajes, subtítulos o párrafos que explican qué hace cada botón o función tanto en la web como en la app. Los botones y tarjetas de acción deben entenderse por sí solos con un ícono claro y una etiqueta corta (1 a 3 palabras, ej: *"Nueva carga"*, *"Ver historial"*, *"Exportar"*), sin textos aclaratorios debajo ni al costado.
- **Un único botón principal por vista:** El usuario debe entender en menos de 3 segundos cuál es la acción principal.
- **Ergonomía por plataforma:**
  - *Móvil:* Navegación inferior alcanzable con el pulgar, áreas táctiles de mínimo `48x48dp` y formularios divididos en pasos cortos.
  - *Web:* Barra lateral o píldora superior limpia, grillas ordenadas en múltiplos de `8px` (`8, 16, 24, 32, 48`) y tablas con buscador y filtros rápidos.
- **Estados completos:** Todas las pantallas deben tener diseño para estado *Cargando* (skeleton), *Vacío* (ícono + mensaje + botón de acción) y *Error* (mensaje claro + reintentar).