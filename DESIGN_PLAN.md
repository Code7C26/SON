# DESIGN_PLAN.md — Rediseño visual y UX de SON


> **Actualización de paleta (pedido de la usuaria, ya aplicada también en CLAUDE.md):** se usan **solo los colores originales de la página**: coral `#FF6147`, dorado `#D99C13`, tinta `#2E2E2E`, gris claro `#F4F4F4` y sus grises neutros (`#6E6E6E`, `#9A9A9A`, `#D5D5D5`, `#E7E7E7`; en oscuro `#262626`, `#353535`, `#3F3F3F`, `#4C4C4C`, `#B3B3B3`). Donde este plan menciona `#111827` u otros colores (`#4B5563`, `#9CA3AF`, `#E5E7EB`, `#FFE8E3`, `#D9482E`, `#16A34A`, `#DC2626`), aplica el equivalente de esta lista.

## Contexto
SON tiene tres frentes visuales que hoy no comparten un sistema común:
- **Landing:** `backend/presentacion/index.html`, servida en `/`.
- **Panel admin:** `son_admin`, Flutter Web, servido en `/panel/`.
- **App de técnicos:** `son_tecnico`, Flutter, como APK y en `/tecnico/`.

Los tres usan la fuente **Bw Gradual DEMO**, que es una versión de prueba con riesgo de licencia. Arrancan en modo oscuro, usan tinta `#2E2E2E` o `#1C1C1E` en lugar de `#111827`, no tienen tokens de tipografía ni de espaciado, y tienen estados de carga, vacío y error desparejos.

El objetivo es llevar los tres a la estética de las referencias, sin tocar la lógica de negocio ni el backend:
- neo-minimalismo editorial
- navegación flotante en píldora
- titulares que combinan peso regular y negrita
- KPIs grandes
- micro-animaciones

Decisiones ya tomadas con la usuaria:
- **Modo claro por defecto** (`#F4F4F4`). El modo oscuro queda como opción, rediseñado sobre `#111827`.
- **Los PDF y mails con membrete "SIMA Ambiente" no se tocan**, porque son de un cliente.

## Tipografías (cambio de familia, aviso explícito)
| Uso | Familia exacta | Pesos |
|---|---|---|
| Títulos / Display | **Plus Jakarta Sans** | 400, 700 (y 600 para subtítulos de tarjeta) |
| Texto de interfaz, botones, tablas | **Inter** | 400, 500, 600 |

Ambas reemplazan a **Bw Gradual DEMO** (familia `TuFuente`) en los tres frentes.
- **Flutter:** los `.ttf` se empaquetan localmente en `assets/fonts/` (son licencia OFL). No se usa el paquete `google_fonts` porque la app tiene que funcionar sin conexión en campo.
- **Landing:** se cargan desde Google Fonts y se quitan los `@font-face` de Bw Gradual.
- **Titulares:** tracking `-0.5px`, combinando 400 con palabras clave en 700.
- **Etiquetas eyebrow:** Inter 600 en mayúsculas con tracking `+1.2px`.

## Lenguaje visual tomado de las referencias
- **Barra de navegación:** píldora flotante (`#FFFFFF`/`#EAEAEA`, radio 999). Logo de reloj de arena en un círculo `#111827` a la izquierda, enlaces al centro y CTA en píldora a la derecha.
- **Eyebrow pill:** fondo `#FFE8E3` con texto `#D9482E`, sobre cada titular de sección.
- **KPIs:** número de 28–36px en negrita `#111827` con una etiqueta de 13px `#4B5563` debajo, en filas o en columna.
- **Tarjetas:** blancas, radio 16–24, sombra con blur 20 y opacidad 4%, o borde 1px `#E5E7EB`. En la landing se mezclan con tarjetas de foto a sangre.
- **Bloques de contraste:** `#111827`, usados para el formulario de contacto, el banner de sincronización y el contenedor del logo.
- **Diagrama de flujo:** Campo → Sincronización → Panel → Informe, con líneas finas y un nodo coral. Va en la landing; en el panel, una versión mínima en el detalle de orden.
- **Movimiento:** 250–350ms con `Curves.easeOutCubic`, para la aparición escalonada de tarjetas, el hover con elevación de 2px y el cambio de pestaña con fade y slide de 8px. Se respeta reduced-motion.

---

## Auditoría UX

### Landing (`backend/presentacion/index.html`)
| Problema | Simplificación |
|---|---|
| La barra de navegación ocupa todo el ancho y está pegada arriba, no es una píldora | Píldora flotante con margen superior de 16px |
| Hay dos CTA en la barra ("Acceso Clientes" y "Solicitar Demostración") | Un único CTA coral "Pedir demo"; "Ingresar" pasa a ser un enlace de texto |
| Párrafos explicativos en el hero (l.455) y en la franja coral (l.526) | Titular con contraste de pesos, una línea de bajada y fila de KPIs |
| Fotos de Unsplash marcadas con TODO | Capturas reales de `medios/` (`panel.png`, `tecnico.png`, `clientes.png`) |
| Video comentado con un cartel de "próximamente" | Activar `medios/demostracion.mp4`, que ya existe, o quitar la sección |
| Unas 150 líneas de CSS muerto (l.162-273 y l.340-361) | Eliminarlas |
| Falta una sección de preguntas frecuentes | Acordeón de FAQ con las categorías en una columna lateral, como en la referencia 5 |
| Formulario de contacto sobre fondo claro genérico | Bloque oscuro `#111827`: foto a la izquierda, formulario a la derecha y botón coral. Se mantiene la misma lógica de formsubmit y mailto |

### Panel web (`son_admin`)
| Problema | Simplificación |
|---|---|
| Arranca en oscuro; tinta `#2E2E2E`; getters con nombres engañosos (`sonDarkGreen` devuelve la tinta y `sonLightGreen` el coral) | Tokens `AppColors`, `AppTypography` y `AppSpacing`. Los getters viejos quedan como alias `@Deprecated` para no romper nada |
| Dos selectores de tema en el login (`main.dart:238`, `:248`) | Uno solo, discreto, en el pie |
| Menú lateral denso de 262px | Barra lateral flotante con radio 24 y ítems en píldora; el ítem activo va en `#111827` con texto blanco |
| Subtítulos explicativos solo en Vencimientos, Gastos, Dashboard y Análisis | Eliminarlos; queda solo el título con contraste de pesos |
| Títulos de pantalla con criterios distintos ("Gestión de Técnicos", "Análisis y Estadísticas") | Títulos cortos: "Órdenes", "Técnicos", "Análisis", etc. |
| Botón principal con tres estilos distintos (`main.dart:1465`, `1821`, `2084`) | Un componente `BotonPrincipal`, coral y en píldora, uno solo por vista |
| Mayúsculas mezcladas ("Crear Nueva Orden" frente a "Nuevo cliente") | Solo la primera letra en mayúscula y de 1 a 3 palabras: "Nueva orden", "Nuevo técnico" |
| Órdenes se traga el error con `print` y muestra "No hay órdenes" (`main.dart:756`) | Estado de error con botón "Reintentar" |
| Faltan los botones de reintentar en Dashboard, CRM e Informes | Componente común `EstadoError` |
| Los estados vacíos son solo texto gris | Componente `EstadoVacio`: ícono, mensaje y botón de acción |
| Solo hay spinners | Componente `Skeleton` con brillo animado para listas, tarjetas y KPIs |
| Órdenes no tiene buscador | Buscador y filtros rápidos en píldora (se reutiliza `PildoraFiltro` de `pantallas/piezas.dart`) |
| Presupuestos mezcla 6 pestañas con el CRM, y "Clientes y contactos" duplica a Clientes | Se agrupan en Embudo (tablero y lista), Notas, Pendientes y Cerrados. "Clientes y contactos" se integra como acceso a Clientes. **Solo se mueve navegación; los endpoints no cambian** |
| El diálogo de orden tiene unos 18 campos en 500px | Panel lateral ancho en 3 pasos: Datos → Checklist y formularios → Recurrencia |
| "Conectar agente" es un flujo técnico dentro de un diálogo | Un stepper de 3 pasos con un botón "Copiar" por paso |
| "Borrar formulario" está repetido (`formularios.dart:332`, `:420`) | Queda uno solo, dentro del menú "⋯" |
| Las tarjetas de KPI del dashboard son tiles chicos | Fila de KPIs grandes y protagonistas, cada uno clickeable hacia su lista filtrada |
| Padding de página hardcodeado (40, o 40/32/40/24) | `AppSpacing.page`, en múltiplos de 8 |

### App móvil (`son_tecnico`)
| Problema | Simplificación |
|---|---|
| Arranca en oscuro; el ícono del AppBar se fuerza a blanco y la flecha de volver desaparece en modo claro (`main.dart:1070`, `:1501`) | Usar los colores del tema; quitar el blanco forzado |
| "Trabajo en progreso" es un único scroll larguísimo con "Finalizar" al fondo (`main.dart:1152-1699`) | Flujo en 4 pasos (Checklist → Evidencia → Notas y gastos → Firmas), con indicador de progreso arriba y botón fijo "Siguiente" / "Finalizar" abajo. **El borrador autoguardado no cambia** |
| Las firmas de 150px están dentro del scroll, así que al firmar se mueve la página | Firma a pantalla completa en horizontal |
| Las acciones de cada sección ("Agregar", "Anotar", "Cargar") están arriba a la derecha | Botones de ancho completo al pie de cada paso, de 48dp o más |
| Áreas táctiles chicas: "Ir", chips de 32px, botones ±, "Limpiar firma", celdas | Mínimo 48x48dp en todos |
| Las fotos no se pueden ampliar ni borrar | Visor con borrado |
| El check-in no da señal mientras espera el GPS (hasta 25s) y se puede tocar dos veces | El botón muestra un spinner, se deshabilita y dice "Ubicando…" |
| Los errores muestran "Exception:" en crudo (`main.dart:1059`) | Mensaje claro y "Reintentar" |
| Las 4 tarjetas de contadores son todas coral y sus etiquetas tienen 10.5pt | KPIs grandes con etiqueta de 13px, ícono circular `#111827` y color semántico según el estado; se pueden tocar para filtrar |
| "Nota enviada" aparece aunque la nota quedó en cola (`main.dart:1365`) | El mensaje refleja el estado real: "Guardada en el celular" o "Enviada" |
| Banner de sincronización naranja `#D97B00`, fuera de la paleta | Píldora flotante `#111827` con punto de color semántico |
| "Pedir visita" es un diálogo centrado | Hoja inferior al alcance del pulgar |
| Dos botones "Listo" en Formularios | Uno solo, fijo abajo |
| Las órdenes completadas no se pueden tocar y no dan ninguna respuesta | Se abren en modo de solo lectura |
| Textos explicativos en `main.dart:1293`, `:1597`, `:1626`, `planilla_excel.dart:295` y `operacion.dart:581` | Eliminarlos |
| La barra inferior es estándar | Barra en píldora flotante con 3 destinos (Inicio, Órdenes, Más), con el ítem activo en `#111827` |

---

## Fases (cada una se puede publicar por separado y no rompe nada)

### Fase 0 — Preparación (sin cambios visibles)
1. Crear `DESIGN_PLAN.md` en la raíz del repo con este contenido.
2. Agregar las fuentes **Plus Jakarta Sans** e **Inter** (`.ttf`, OFL) en `son_admin/assets/fonts/` y `son_tecnico/assets/fonts/`, y declararlas en cada `pubspec.yaml`. Bw Gradual se mantiene hasta la Fase 1.
3. Tomar capturas de referencia de cada pantalla actual, para comparar antes y después.

### Fase 1 — Tokens y tema (las dos apps de Flutter)
- Crear `lib/theme/app_colors.dart`, `app_typography.dart`, `app_spacing.dart` y `app_motion.dart` en cada app, con los valores de `CLAUDE.md` §3.
- Reescribir `temaCon()` en `lib/theme/tema.dart` (las dos apps) para que consuma los tokens. Claro por defecto (`tema.dart:74`); oscuro sobre `#111827`. Radios 16/24/999. `PaletaSon` y los getters `sonX` quedan como alias `@Deprecated` que apuntan a los tokens nuevos, así ninguna pantalla se rompe.
- Cambiar `fontFamily` a Inter y `displayLarge`…`titleSmall` a Plus Jakarta Sans. Quitar Bw Gradual de `pubspec.yaml` y de assets.
- Verificación: `flutter analyze` sin errores nuevos y recorrido visual de todas las pantallas en claro y en oscuro.

### Fase 2 — Biblioteca de componentes compartidos
Cada app tiene su propio `lib/ui/` con la misma API, porque no hay un paquete compartido. Se parte de lo que ya hay en `son_admin/lib/pantallas/piezas.dart` (`PildoraFiltro`, `EtiquetaEstado`, `DatoConIcono`).
- `TituloContraste` (regular + negrita), `Eyebrow`, `BotonPrincipal` y `BotonSecundario` en píldora.
- `TarjetaSon` con hover y elevación, `KpiBloque`, `IconoCircular`.
- `EstadoCargando` (skeleton), `EstadoVacio` y `EstadoError`.
- `AparecerEscalonado`, con fade y slide de 250–350ms y `easeOutCubic`.

### Fase 3 — Landing (`backend/presentacion/index.html`)
- Cambiar las fuentes, con aviso: **Plus Jakarta Sans** e **Inter**.
- Variables CSS con la paleta de `CLAUDE.md`, con tinta `#111827`.
- Navegación en píldora flotante y un solo CTA.
- Hero con eyebrow, titular con contraste de pesos, una línea de bajada y KPIs.
- Diagrama de flujo, tarjetas de módulos mezclando foto y tarjeta blanca, demo con el video real, FAQ en acordeón y contacto en bloque oscuro.
- Eliminar el CSS muerto y los textos explicativos. Mantener `revelar` y `prefers-reduced-motion`.
- Las rutas `/panel/` y `/tecnico/` y la lógica del formulario no cambian.

### Fase 4 — Panel web: estructura y navegación
- Barra lateral flotante en píldora, con colapso a íconos por debajo de 900px (se conserva el umbral de `main.dart:466`). El filtrado por rol (`main.dart:281-293`) no cambia.
- Login rediseñado con un solo selector de tema.
- Encabezado de pantalla común: título con contraste de pesos y botón principal a la derecha. Se quitan los subtítulos explicativos.

### Fase 5 — Panel web: pantallas
Orden de trabajo:
1. **Dashboard:** fila de KPIs clickeable, tarjetas y reintentar.
2. **Órdenes:** buscador, filtros en píldora, estados completos y el error visible en lugar del `print`.
3. **Diálogo de orden** pasa a panel lateral en 3 pasos.
4. **Presupuestos:** reagrupar las pestañas.
5. **Clientes, Técnicos, Usuarios, Precios.**
6. **Vencimientos, Gastos, Análisis, Informes y el stepper de agente.**
7. **Formularios y Planilla.**

Cada pantalla es un commit aparte. La lógica (`http`, endpoints y modelos) no se toca.

### Fase 6 — App móvil: estructura
- Barra inferior en píldora flotante.
- Banner de sincronización rediseñado.
- Login.
- Corregir el color del AppBar.

### Fase 7 — App móvil: flujos de campo
1. **Dashboard:** KPIs semánticos que se pueden tocar.
2. **Órdenes:** tarjetas con un CTA de 48dp y "Pedir visita" como hoja inferior.
3. **Detalle:** check-in con estado de "Ubicando…".
4. **Trabajo en progreso** pasa a 4 pasos, con firma a pantalla completa y visor de fotos.
5. **Formularios y Planilla:** targets de 48dp y un solo "Listo".
6. **Vencimientos, Mis presupuestos y las hojas inferiores.**
7. **Mensajes honestos** de cola o enviado.

### Fase 8 — Pulido y marca
- Ajustar los tiempos de micro-animación y revisar la accesibilidad: contraste AA, tamaños de texto y `MediaQuery.disableAnimations`.
- Limpiar los alias `@Deprecated` cuando ya no los use nadie.
- Borrar los logos que no se usan (`COLOR4.png`, `3.png`).
- Cambiar la `description` del `pubspec.yaml` de la app de técnicos.
- Marca: el UI ya no muestra "Sima". Quedan solo comentarios (`son_tecnico/lib/config/api_config.dart:3`, `son_admin/lib/pantallas/crm.dart:11`), que pasan a "SON". **No se tocan** las referencias a "SIMA Ambiente" como empresa cliente: PDF, mails, tarifario y portal.

## Reglas de seguridad durante la ejecución
- No se modifica nada de `backend/src/*.js` salvo `index.html` de la presentación. Las firmas de los servicios Flutter (`lib/services/`) no cambian.
- El autoguardado del borrador y la cola offline (`son_tecnico/lib/services/sincronizacion.dart`) se mantienen intactos.
- Una fase o pantalla por commit, para poder revertir aislado.

## Verificación
- **Flutter (las dos apps):** `flutter analyze` y `flutter build web --release --base-href /panel/` (o `/tecnico/`), y `flutter build apk --release` para técnicos.
- **Navegador:** recorrer cada pantalla con `flutter run -d chrome`, en claro, en oscuro, a 375px y en escritorio. Forzar los estados de carga, vacío y error cortando el backend.
- **Backend sin cambios de lógica:** `node --test test/` en `backend/`, y los e2e (`node test/formularios.e2e.js`, `node test/reunion.e2e.js`, etc.) con el backend levantado.
- **Landing:** abrir `/`, revisar la consola sin errores, el formulario de contacto, los enlaces a `/panel/` y `/tecnico/`, `prefers-reduced-motion` y el ancho de 375px.
- **Flujo de campo de punta a punta:** login → orden → check-in → 4 pasos → finalizar, primero en línea y después sin conexión, verificando que se sincroniza al volver la red.

---

## Anexo — Fotos de la landing (generadas con IA)
Van en `backend/presentacion/medios/ia/` con estos nombres exactos (JPG, horizontales salvo que se indique). Mientras no estén, la página muestra un fondo de marca.

| Archivo | Dónde se ve | Formato |
|---|---|---|
| `tecnico-campo.jpg` | Portada (recorte en cápsula) | 1600×1280 |
| `oficina-coordinacion.jpg` | Tarjeta "Agenda en vivo" | 900×1200 (vertical) |
| `cliente-informado.jpg` | Tarjeta "Clientes informados" | 900×1200 (vertical) |
| `inspeccion-equipo.jpg` | Bloque de contacto | 1200×1400 (vertical) |

Estilo común para todos los prompts: *fotografía editorial realista, luz natural cálida, tonos neutros grises y blancos con un detalle en coral (#FF6147), profundidad de campo corta, sin texto ni logos, sin marcas de agua, personas latinoamericanas, Argentina.*
