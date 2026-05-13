# Eco-Complaint · Memoria técnica de la Fase 0

**Versión del prototipo cubierta:** v0.9.0 · STEP-001 a STEP-010
**Fecha de cierre:** 11 de mayo de 2026
**Autor:** [Autor de la tesis]
**Documento:** Anexo técnico de la tesis doctoral

---

## 1. Naturaleza y propósito del documento

Esta memoria documenta la primera fase de construcción del prototipo Eco-Complaint, una plataforma ciudadana web para la denuncia de delitos ambientales en Colombia bajo el marco normativo de la Ley 2111 de 2021. El prototipo es la evidencia empírica que acompaña a la tesis: no es el entregable principal, pero permite validar las hipótesis metodológicas planteadas en el cuerpo del trabajo y discutir, a partir de un artefacto funcional, la viabilidad técnica del modelo propuesto.

La Fase 0 corresponde a un MVP de prototipo funcional con persistencia local (cliente único, sin backend) cuya hipótesis a validar fue: *es técnicamente viable construir un sistema cliente-único que cubra los 18 delitos de la Ley 2111, incorpore árbol jurídico de decisión, modelo de riesgo cuantitativo basado en CONESA (Fdez-Vítora, 2010) e ISO 31000:2018, y direccione automáticamente a las autoridades competentes, todo dentro de un único archivo HTML que funcione en navegadores modernos incluyendo Safari iOS*. La hipótesis se considera confirmada con el cierre de esta fase: el flujo end-to-end funciona desde GitHub Pages, se cubren formalmente los 18 delitos y el direccionamiento a autoridades opera de manera acumulativa con base en la banda de riesgo.

El documento sigue las convenciones del proyecto: prosa técnica, decisiones arquitectónicas justificadas, trade-offs explícitos y registro de riesgos numerados (RSK-XX). Los identificadores ADR-NN refieren a decisiones arquitectónicas registradas en el código fuente como comentarios JS inline.

## 2. Contexto, problema y diferenciador metodológico

### 2.1 El problema

Colombia es un país megadiverso con presión sostenida sobre sus ecosistemas: deforestación, minería ilegal, tráfico de fauna, contaminación de aguas, ocupación de áreas protegidas y otros delitos previstos en los artículos 328 a 337A del Código Penal. La Ley 2111 de 2021 reformó ese capítulo para incorporar 18 tipos penales ambientales con penas significativas. Sin embargo, persiste un cuello de botella entre el hecho denunciable y la radicación efectiva ante la autoridad competente: la ciudadanía, en general, desconoce qué autoridad corresponde a cada hecho, qué información mínima debe acompañar la denuncia, cómo evaluar la gravedad o cómo dar trazabilidad al caso. El resultado típico es que la denuncia se desvía, se diluye en correos generales o no llega a ninguna autoridad con jurisdicción real sobre el caso.

### 2.2 Diferenciador metodológico de la propuesta

Eco-Complaint articula cuatro elementos que en la literatura aparecen por separado pero rara vez integrados en un mismo flujo:

1. **Árbol de decisión jurídico:** mapea los hechos relatados por el denunciante a uno o más artículos del Código Penal mediante un grafo de 10 nodos con 23 rutas terminales que cubren los 18 delitos. La cobertura es formal (no estadística): cada delito tiene al menos una ruta del árbol que lo identifica.

2. **Modelo de riesgo cuantitativo (matriz 5×5):** combina severidad y probabilidad bajo el esquema de ISO 31000:2018. La severidad la fija el catálogo de delitos (ancla por el delito más grave concurrente). La probabilidad se calcula con la metodología CONESA Fdez-Vítora (2010) ponderada en cinco dimensiones: extensión (0.25), reversibilidad (0.30), recurrencia (0.20), vulnerabilidad (0.15), persistencia (0.10).

3. **Direccionamiento automático y acumulativo a autoridades:** la banda de riesgo (BAJO, MEDIO, ALTO, CRÍTICO, EXTREMO) determina qué autoridades reciben la denuncia. La regla es acumulativa: una denuncia EXTREMO incluye a las autoridades de las cuatro bandas inferiores (UMATA municipal, CAR regional, ANLA, Fiscalía Unidad 122) más las propias (MinAmbiente, Policía Ambiental). Esto refleja el principio de coordinación interinstitucional y reduce el riesgo de que una denuncia grave no llegue a la autoridad territorial que tiene jurisdicción directa.

4. **Privacy by design en la consulta pública:** un actor hostil podría obtener un número de radicado e intentar identificar al denunciante o el lugar exacto del hecho. La vista pública del radicado muestra únicamente estado, banda, fecha, categoría, artículos y timeline; nunca ubicación, evidencias, descripción del denunciante, autoridades específicas ni el indicador de anonimato. Esto reduce la superficie de información disponible a un radicado filtrado.

La integración de los cuatro elementos en un mismo flujo es lo que la tesis sostiene como aporte. El prototipo demuestra que esa integración es técnicamente realizable con tecnología disponible y, lo que es más relevante, con un solo desarrollador, sin backend y con dependencias mínimas.

## 3. Arquitectura del prototipo

### 3.1 Visión general

La Fase 0 implementa toda la aplicación en un único archivo `index.html` (≈6.930 líneas) que contiene HTML, CSS y JavaScript vanilla. No hay build step, no hay backend, no hay framework. La persistencia se hace contra `localStorage`. Las dependencias externas son tres: Google Fonts (Bricolage Grotesque, Plus Jakarta Sans, JetBrains Mono), Leaflet 1.9.4 (mapa y heatmap) y jsPDF 2.5.1 (generación del PDF formal). Todo lo demás —incluido un generador de códigos QR vanilla derivado de la librería MIT *qrcode-generator* de Kazuhiko Arase, condensado a aproximadamente 120 líneas— está embebido en el archivo.

Esta decisión se documenta como **ADR-01 (single-file HTML para Fase 0-3)**. La justificación es operativa: distribución trivial (un enlace, un archivo), demos rápidas al director de tesis, GitHub Pages sin configuración, y revisión del código completo en una sola lectura. El trade-off aceptado es una *first paint* subóptima (≈250 KB sin gzip) y la falta de code-splitting; se revisará en la Fase 4 cuando se introduzca Vite.

### 3.2 Capa de datos

Toda la información se persiste en `localStorage` bajo el prefijo `eco.`. Las claves principales son:

| Clave | Tipo | Función |
|---|---|---|
| `eco.users` | array | cuentas demo (admin@demo.co, maria@demo.co) |
| `eco.session` | object\|null | sesión activa |
| `eco.tree` | object | estructura del árbol de decisión |
| `eco.delitos` | object | catálogo de los 18 delitos |
| `eco.draft` | object\|null | denuncia en construcción |
| `eco.reports` | array | denuncias enviadas |
| `eco.outbox` | array | cola simulada de emails |
| `eco.audit_log` | array | bitácora (cap 1000 entradas) |
| `eco.report_counter` | number | secuencial diario para radicado |
| `eco.config.authorities` | object | correos por banda + master_email |
| `eco.config.contact` | object | datos públicos (org, email, teléfonos, dirección) |
| `eco.rate_limit` | array | timestamps de envíos para anti-spam local |

El módulo `Persist` envuelve toda la lectura/escritura con un patrón de fallback en memoria si `localStorage` no está disponible (modo privado de Safari, cuota llena). Es importante: sin ese fallback la app crashearía en navegación privada. El módulo `Audit` registra todas las acciones relevantes con la firma `(action, entity, entity_id, metadata)` y mantiene una cola circular de 1000 entradas para evitar saturar el almacenamiento.

### 3.3 Capa de presentación

La interfaz usa el sistema visual **Brote**, light mode únicamente (ver ADR-07). Tokens CSS expuestos como variables `--brand` (#2EAA70), `--brand-deep`, `--brand-tint`, `--warm`, `--coral`, `--alarm`, escalas tipográficas `--t-12` a `--t-72`, espaciado `--s-1` a `--s-16`, radios `--r-sm` a `--r-xl` y sombras `--sh-1` a `--sh-3`. Las fuentes Bricolage Grotesque (display), Plus Jakarta Sans (body) y JetBrains Mono (radicados/código) se cargan vía Google Fonts.

La aplicación organiza el código JavaScript en 33 módulos como objetos planos (sin `class` por compatibilidad ES5; ver ADR estricto sobre compatibilidad Safari iOS). Los módulos se agrupan en cinco bloques funcionales:

- **Core (8):** Persist, Store, Bus, Audit, I18n, Focus, Auth, Router
- **Flujo de denuncia (11):** Tree, Probability, Risk, Authorities, Modal, Score, Geo, MapWidget, LocationView, Evidence, EvidenceView
- **Envío y output (7):** Outbox, Report, Review, SentView, Clipboard, QRGen, PdfGen
- **Públicas (3):** PublicStats, PublicLookup, Contact
- **Admin (2):** AdminViews (proxy), Admin (con sub-módulos Stats, Charts, dashboard, reports, matrix, users, config, export, outbox)
- **UI (3):** UI, Toast, Skeleton

El router es de tipo hash-based, con 20 rutas activas que cubren las vistas pública (`/`, `/consulta`, `/contacto`), de autenticación (`/iniciar-sesion`), el flujo de denuncia paso a paso (`/denunciar`, `/denunciar/resultado`, `/denunciar/probabilidad`, `/denunciar/score`, `/denunciar/ubicacion`, `/denunciar/evidencias`, `/denunciar/revision`, `/denunciar/enviado`), las del ciudadano autenticado (`/mis-denuncias`) y las del admin (`/admin`, `/admin/denuncias`, `/admin/matriz`, `/admin/usuarios`, `/admin/config`, `/admin/exportar`, `/admin/outbox`).

### 3.4 Sistema de eventos

`Bus` es un mini event bus interno (`emit`/`on`/`off`) que desacopla productores y consumidores. Lo usan los handlers de UI y la auditoría para reaccionar a eventos como `report:sent`, `auth:login`, `auth:logout`, etc. No reemplaza al estado persistente, sino que sirve como sistema de notificación inmediata.

## 4. El árbol de decisión jurídico

El árbol tiene 10 nodos (`q1`, `q2_bio`, `q2b_fauna`, `q3_deforest`, `q4_contam`, `q5_mineria`, `q6_areas`, `q6b_areas`, `q6c_baldios`, `q7_ogm`) con 23 rutas terminales. Cada ruta terminal emite uno o más artículos del Código Penal. Por ejemplo:

- `q1 → "Daño grave y generalizado al ambiente" → ECOCIDIO (Art. 333)`
- `q1 → "Tala de árboles" → q3_deforest → "Existe un financiador" → Arts. 330 + 330A`
- `q1 → "Minería" → q5_mineria → "Con contaminación" → Arts. 332 + 334A`
- `q1 → "Fauna/flora" → q2_bio → "Animales" → q2b_fauna → "Tráfico" → Art. 328A`

El motor del árbol (`Tree`) opera sobre una estructura declarativa cargada en `eco.tree` al inicio. La navegación entre nodos es bidireccional: el usuario puede retroceder. El estado intermedio del árbol vive en `Tree.state` y solo se promueve al `draft` cuando el usuario llega a una ruta terminal y confirma.

Cuando concurren múltiples delitos (caso frecuente: tala con financiador, minería con contaminación, área protegida con financiador), la severidad efectiva del caso es `max(severidad_i)` de los delitos concurrentes (ver **ADR-03**). La justificación es jurídica: el principio penal de absorción establece que el delito más grave domina cuando hay concurrencia. Sumar o promediar habría producido scores fuera del rango definido y, lo que es peor, habría restado peso al delito más grave en favor de los menores.

## 5. El modelo de riesgo

### 5.1 Severidad

La severidad la asigna el catálogo de delitos como un valor entero de 1 a 5. La calibración se hizo a partir de la literatura sobre evaluación de impacto ambiental y la jurisprudencia disponible, con las siguientes anclas:

- **Severidad 5 (Catastrófico):** daño masivo, irreversible o sistémico. Incluye Art. 333 (Daño en los recursos naturales), 330A (Financiación de deforestación), 334A (Contaminación con minería), 336A (Financiación de invasión de áreas), 337A (Financiación de apropiación de baldíos). Es el escalón reservado a los delitos con perpetradores estructurales (financiadores, empresas) y a los ecocidios.
- **Severidad 4 (Grave):** daño significativo y territorialmente acotado pero no inmediatamente reversible. Incluye los delitos base de las cinco categorías (deforestación, contaminación general, contaminación de aguas, invasión de áreas, apropiación de baldíos, aprovechamiento ilícito de recursos biológicos).
- **Severidad 3 (Moderado):** daño localizado, generalmente reversible con intervención. Tráfico de fauna, pesca ilegal, daños a recursos hídricos, experimentación ilegal con especies.
- **Severidad 2 (Menor):** infracción aislada de bajo impacto. Aprovechamiento ilícito de recursos genéticos.
- **Severidad 1 (Insignificante):** infracción mínima. Caza ilegal individual (Art. 328B).

### 5.2 Probabilidad (CONESA Fdez-Vítora 2010)

La probabilidad se calcula con cinco preguntas al denunciante, una por dimensión, con respuestas en escala 1-5. La fórmula es:

```
P = round( Σᵢ respuestaᵢ × pesoᵢ )
```

Pesos calibrados según la propuesta original de CONESA:

| Dimensión | Peso | Pregunta de cara al ciudadano |
|---|---|---|
| Extensión | 0.25 | ¿Qué tan extensa fue/es la afectación? |
| Reversibilidad | 0.30 | ¿Es el daño reversible naturalmente? |
| Recurrencia | 0.20 | ¿Se repite el hecho en el tiempo? |
| Vulnerabilidad | 0.15 | ¿El entorno es vulnerable (especies en riesgo, comunidad indígena, fuente hídrica)? |
| Persistencia | 0.10 | ¿Cuánto persiste el efecto? |

La elección de CONESA en lugar de probabilidades subjetivas o frecuencias históricas se documenta en **ADR-04**: es el estándar académico colombiano para evaluación de impacto ambiental, lo que da defensibilidad ante el jurado, y los pesos están calibrados según literatura previa, no inventados para el prototipo.

### 5.3 Score y bandas

El score final es `severidad × probabilidad`, en rango 1-25. Las bandas se asignan en cuartiles ajustados:

- **1-4 BAJO** (verde) — UMATA municipal
- **5-9 MEDIO** (amarillo) — + CAR regional
- **10-14 ALTO** (naranja) — + ANLA
- **15-19 CRÍTICO** (rojo) — + Fiscalía (Unidad 122 de delitos ambientales)
- **20-25 EXTREMO** (carmín oscuro) — + MinAmbiente + Policía Ambiental

A todas las bandas se suma el correo maestro (`radicacion@plataforma`), que sirve como archivo central. La acumulación (ver **ADR-05**) es deliberada: la jurisdicción territorial directa siempre debe ser notificada aun cuando intervengan autoridades de nivel nacional.

## 6. El flujo end-to-end de denuncia

El ciudadano puede denunciar como invitado (anónimo) o autenticado. La diferencia operativa es que la denuncia anónima no queda asociada a un `user_id`, lo que tiene implicaciones para la consulta posterior: la denuncia anónima solo se puede consultar con el número de radicado. La denuncia asociada también se ve en `/mis-denuncias`.

Los pasos del flujo, en orden, son:

1. **Árbol jurídico** (`/denunciar`, `/denunciar/resultado`): el ciudadano responde el árbol y obtiene la lista de delitos identificados con la severidad ancla calculada.
2. **Probabilidad CONESA** (`/denunciar/probabilidad`): cinco preguntas en escala 1-5 con descripciones explicativas en lenguaje ciudadano.
3. **Score y matriz** (`/denunciar/score`): visualización de la matriz 5×5 con la celda actual destacada, la banda asignada y las autoridades que serán notificadas.
4. **Ubicación** (`/denunciar/ubicacion`): tres modos disponibles —GPS del navegador, selección manual en mapa Leaflet, o texto libre—. La ubicación es opcional (no bloqueante) pero recomendada.
5. **Evidencias** (`/denunciar/evidencias`): drag & drop de archivos con compresión local. En Fase 0 las evidencias viajan inline (base64) en el report, lo cual no escala más allá de ~5 archivos por denuncia y se sustituirá por Firebase Storage en Fase 2.
6. **Revisión** (`/denunciar/revision`): resumen completo con mini-mapa estático.
7. **Envío** (`/denunciar/enviado`): radicado con formato `ECO-YYYYMMDD-{artAncla}-{seq4}` (p. ej. `ECO-20260511-330A-0042`), confirmación de autoridades notificadas, botón para descargar PDF formal y botón de copia del radicado.

El radicado se genera de manera secuencial con persistencia en `eco.report_counter`. Las autoridades reciben un email simulado (en Fase 0 se acumula en el `outbox` local; Fase 3 lo conecta a EmailJS) con el cuerpo construido en `Report.buildEmailBody`, que incluye delitos, ubicación, listado de evidencias (sin los archivos —explicado más abajo—), descripción adicional y mención al PDF formal.

## 7. El PDF formal del radicado

`PdfGen.downloadReport(report)` genera un PDF A4 multi-página con jsPDF 2.5.1. La estructura es:

- **Página 1:** cabecera con marca, recuadro destacado con número de radicado y código QR (que apunta a la URL pública de consulta), metadatos en dos columnas, banda visual, lista de delitos identificados con artículos y categoría, evaluación de probabilidad con barras visuales de las cinco dimensiones CONESA.
- **Página 2 en adelante:** ubicación con fuente (GPS/mapa/texto), galería de evidencias embebidas como imágenes (con metadatos), descripción del denunciante si existe, autoridades notificadas con el maestro destacado en verde, footer legal y paginación.

El código QR se genera con el módulo `QRGen` (qrcode-generator condensado) sin recurrir a CDN externo (**ADR-08**). La URL del QR es dinámica desde `location.origin + location.pathname` (cambio del STEP-010): apunta al endpoint público `#/consulta?radicado=X` de la misma página. En entornos `file://` el QR se omite porque la URL resultante no sería escaneable desde otro dispositivo.

El PDF incluye una nota transparente sobre las limitaciones actuales de entrega de evidencias por email: en Fase 0 las evidencias viajan inline en el body del email simulado o se solicitan al maestro; la Fase 2 introduce URLs firmadas con expiración contra Firebase Storage.

## 8. Las vistas públicas

La separación entre las vistas para denunciantes/admin y las **vistas públicas** (`/`, `/consulta`, `/contacto`) es deliberada. La consulta pública (`PublicLookup`) muestra el estado de un radicado sin requerir login. Como se anticipó, la información mostrada está auditada por privacy by design (**ADR-06**):

- **Sí se muestra:** estado actual, banda, fecha de radicación, categoría del hecho, artículos infringidos, timeline de cambios de estado con tiempo relativo (“hace 3 días”).
- **No se muestra:** ubicación, evidencias, descripción del denunciante, autoridades específicas notificadas, indicador de anonimato.

La home page incluye `PublicStats`, una sección de transparencia con cuatro tarjetas: total de denuncias y recientes 30 días, casos en investigación, tasa de resolución porcentual destacada, y categoría más denunciada. Estas estadísticas se computan en tiempo real desde `eco.reports` y se actualizan con cada nueva denuncia o cambio de estado.

La página `/contacto` lee sus datos de `eco.config.contact` (configurable por el admin desde `/admin/config`) y muestra los canales oficiales: organización, email público, teléfono general, teléfono de emergencia 24/7, dirección física, horarios y handle de Twitter.

## 9. El panel administrativo

`/admin` y subrutas implementan un dashboard completo con siete sub-secciones:

- **Dashboard general:** 6 KPIs (total, hoy, semana, mes, % anónimas, banda top), distribución por banda en gráfico de dona SVG vanilla, tendencia de 30 días en barras, top 5 delitos en barras horizontales, heatmap con Leaflet usando `circleMarker` coloreado por banda y radio proporcional a severidad, y tabla de últimas 5 denuncias con click a detalle.
- **Denuncias:** tabla filtrable con búsqueda con debounce de 200 ms, chips multi-banda, filtro por modo (anónimo/cuenta), paginación implícita por filtros. El click sobre un row abre un drawer derecho con detalle completo: árbol path, probabilidad con respuestas, ubicación con mini-mapa, evidencias en galería, descripción, autoridades con maestro destacado, metadatos y botones de cambio de estado con auditoría.
- **Matriz 5×5:** matriz interactiva con conteos reales por celda; click en celda abre drawer con las denuncias de esa combinación severidad × probabilidad.
- **Usuarios:** KPIs y tabla con conteo de denuncias por usuario.
- **Configuración:** editor del correo maestro y de los correos por banda con `textarea`, guardado con auditoría, opción de restaurar valores demo con confirmación modal.
- **Exportación:** tres formatos disponibles —CSV con headers estándar, JSON completo sin evidencias base64, y bitácora de auditoría en CSV—.
- **Outbox:** cola de correos simulados con preview del body, opción de marcar individual o todos como enviados (simulación Fase 0 que se sustituirá por la integración real con EmailJS en Fase 3).

`Admin.seedDemo()` permite poblar el panel con 20 denuncias aleatorias con coordenadas reales colombianas (Bogotá, Medellín, Cali, Barranquilla, Bucaramanga, Florencia, San José del Guaviare, Ibagué) y trayectorias coherentes con el árbol de decisión, lo que facilita demostraciones y pruebas con el director de tesis sin contaminar los datos reales.

## 10. Decisiones arquitectónicas (síntesis)

Las 10 ADRs registradas inline en el código se sintetizan así:

- **ADR-01 — Single-file HTML para Fase 0-3.** Distribución trivial, GitHub Pages sin configuración, sin build step. Trade-off: first paint subóptima.
- **ADR-02 — Marco Ley 2111/2021 exclusivo.** No retrocompatibilidad con el CP original. Reduce duplicación de catálogo y lógica.
- **ADR-03 — Severidad ancla por max().** Principio penal de absorción.
- **ADR-04 — CONESA para probabilidad.** Estándar académico colombiano de evaluación de impacto ambiental.
- **ADR-05 — Acumulación de autoridades.** Coordinación interinstitucional; la jurisdicción territorial directa siempre se notifica.
- **ADR-06 — Privacy by design en consulta pública.** Minimiza superficie de información ante radicados filtrados.
- **ADR-07 — Sistema visual Brote light-only.** Reduce scope; dark mode no aporta a la validación de hipótesis.
- **ADR-08 — QRGen vanilla embebido.** Reduce dependencias externas.
- **ADR-09 — Sin tests automatizados en Fase 0-4.** Costo de mantenimiento durante iteración rápida no se justifica con un desarrollador.
- **ADR-10 — WebView de WhatsApp/Files/Mail no es target.** Esos WebViews están diseñados como preview, no como navegador; iOS los limita por seguridad.

## 11. Compatibilidad con Safari iOS

Una parte material del esfuerzo de la Fase 0 fue resolver la compatibilidad con Safari iOS, donde se realizó la primera prueba con usuario real. Los hallazgos:

- **Operadores de asignación lógica (`||=`, `??=`, `&&=`)** rompen el parser de Safari iOS anterior a 14. Se eliminaron del código y se reemplazaron por `if (x === undefined) x = …;` o equivalentes.
- **Scripts externos con `integrity` y `crossorigin`** fallan cuando el archivo se abre desde `file://` (porque el origen es null). Se movieron los scripts externos al final del body y se eliminaron esos atributos. La app arranca incluso si Leaflet o jsPDF no cargan; los features dependientes muestran un Toast de error en lugar de fallar silenciosamente.
- **Caché agresiva de Safari iOS:** se añadieron metas `Cache-Control`, `Pragma` y `Expires` para evitar que la app quede pegada en una versión vieja.
- **`localStorage` puede estar bloqueado** (modo privado, cuota llena): el módulo `Persist` detecta esto al arranque y degrada a memoria, con un Toast permanente que avisa al usuario que los datos no persistirán.
- **`bindHandlers`** se blindó con un patrón `safe(name, fn)` que envuelve cada bloque en try/catch granular para que un fallo en un handler no rompa el resto del binding.
- **Panel de diagnóstico visible:** una caja flotante en la esquina inferior derecha muestra el progreso de inicialización paso a paso. Se oculta automáticamente si la inicialización termina bien, pero queda visible si algo falla, lo que permite diagnosticar in-situ sobre el dispositivo del usuario.
- **Aviso JS-required:** un mensaje visible al inicio del body se oculta vía JS si el navegador es funcional. Si la página se abre en el WebView de WhatsApp, Files o Mail (que no ejecutan JS), el aviso queda visible explicando que hay que abrir el archivo en un navegador real.

## 12. Validación empírica

La Fase 0 incluyó una prueba con un único usuario real (autor del prototipo, en iPhone real, fuera del entorno de desarrollo). El hallazgo principal fue el problema del WebView de iOS que motivó la documentación de ADR-10 y la mejora del aviso JS-required. La validación completa con 5-20 usuarios reales se realiza en cada cierre de fase posterior según el roadmap. Para la Fase 0, dado que la hipótesis era exclusivamente técnica (viabilidad del modelo en cliente único), la validación interna se considera suficiente.

## 13. Limitaciones conocidas y entrada a Fase 1

La Fase 0 tiene limitaciones intencionales:

- **Sin backend.** No hay persistencia compartida ni sincronización entre dispositivos. Lo resuelve Fase 1 (Firebase Auth + Firestore).
- **Sin envío real de emails.** El outbox local simula la cola pero los correos no salen. Lo resuelve Fase 3 (EmailJS).
- **Sin storage de evidencias.** Evidencias inline en base64, máximo ~5 archivos por denuncia por límite de `localStorage` (~5 MB). Lo resuelve Fase 2 (Firebase Storage con URLs firmadas).
- **Cuentas demo hardcoded** (`maria@demo.co`, `admin@demo.co`, contraseña `demo`). Se reemplazan en Fase 1.
- **Sin internacionalización real.** Infraestructura I18n presente pero solo carga español. No es prioridad.
- **Sin tests automatizados.** Validación manual con paneles de diagnóstico visibles. Tests entran en Fase 5.
- **Rate limit local circumvenible.** Defensa de UX, no de seguridad. Lo resuelve Fase 5 con Firebase App Check + reCAPTCHA.
- **Open Graph URLs como placeholder.** Quedan como `[USUARIO].github.io/Eco-Complaint/`; deben actualizarse manualmente al desplegar.

El registro de riesgos `RSK-01` a `RSK-44` documenta cada limitación con estado (identificado, mitigado, aceptado, cerrado) y alimenta el capítulo de FMEA de la tesis.

## 14. Conclusión

El cierre de la Fase 0 confirma la hipótesis técnica: el modelo metodológico que combina árbol jurídico, riesgo cuantitativo CONESA, direccionamiento acumulativo a autoridades y privacy by design es realizable como prototipo funcional con stack mínimo y desarrollador único. La Fase 1 traslada el prototipo de cliente único a backend Firebase, validando que la arquitectura escala a múltiples usuarios concurrentes con persistencia real y autenticación verificada, sin perder la usabilidad observada en la Fase 0.

---

*Documento técnico complementario a la tesis doctoral. Para consultar la implementación, ver `index.html` v0.9.0 en el repositorio del proyecto.*
