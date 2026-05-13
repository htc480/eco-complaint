# PROMPT MAESTRO · Plataforma de Denuncia Ambiental Colombia
## Continuación de desarrollo en Claude Code · Enfoque Lean

---

## 0 · Identidad del proyecto

**Naturaleza:** Proyecto de **tesis doctoral**. No es producto comercial. El entregable principal es la tesis; el prototipo es la evidencia empírica.

**Dominio:** Plataforma ciudadana web para denunciar **delitos ambientales en Colombia** bajo el marco de la **Ley 2111 de 2021** (reforma del Código Penal que incorporó/modificó 18 delitos ambientales en los Arts. 328 a 337A).

**Diferenciador metodológico:**
- Árbol de decisión jurídico que mapea hechos → artículos del CP (cobertura formal de los 18 delitos)
- Modelo de riesgo cuantitativo con matriz **severidad × probabilidad** (5×5) basado en ISO 31000:2018
- Probabilidad calculada con metodología **CONESA Fdez-Vítora (2010)** ponderada en 5 dimensiones
- Direccionamiento automatizado a autoridades por banda de riesgo (acumulativo, no sustitutivo)
- Privacy by design en consulta pública

**Estado del archivo:** Un solo HTML (~6.700 líneas, HTML + CSS + JS vanilla). Funciona desde GitHub Pages (https) o abriendo el archivo. localStorage como persistencia. Sin backend. Versión actual: **v0.8.0** (Fase 0 prácticamente completa).

---

## 1 · Filosofía Lean del proyecto

El desarrollo sigue principios Lean Startup adaptados a contexto académico:

### 1.1 · Build–Measure–Learn por fases
Cada fase es un **MVP independiente que valida una hipótesis**. No se avanza a la siguiente fase sin haber validado la anterior. La fase termina cuando la hipótesis está confirmada o refutada con evidencia.

| Fase | Hipótesis a validar | Métrica de éxito |
|---|---|---|
| **0** · Prototipo funcional | "Es técnicamente viable construir un sistema cliente-único que cubra los 18 delitos con árbol jurídico, riesgo cuantitativo y direccionamiento automático" | Cobertura del 100% de la Ley 2111, flujo E2E funcional en navegador moderno + Safari iOS, PDF de comprobante descargable, dashboard admin operacional |
| **1** · Backend mínimo | "El sistema escala a múltiples usuarios concurrentes con persistencia real y auth verificada sin perder usabilidad" | Firebase Auth funcional, Firestore reactivo, ≥10 cuentas de prueba diferentes, denuncias persisten entre sesiones |
| **2** · Storage de evidencias | "Las evidencias multimedia se manejan correctamente con URLs firmadas sin saturar el cliente" | Firebase Storage operativo, evidencias accesibles vía link en email, security rules probadas |
| **3** · Envío real de notificaciones | "Las autoridades reciben efectivamente las denuncias por email automáticamente" | EmailJS configurado, outbox se procesa, autoridades reciben emails reales, tracking de entrega |
| **4** · Datos reales y dashboard productivo | "El dashboard admin con datos reales permite gestionar volumen del mundo real (>100 denuncias)" | Performance OK con 500 reports, filtros sub-segundo, exports funcionales |
| **5** · Hardening y compliance | "El sistema es seguro y cumple normas mínimas (habeas data, accesibilidad)" | Auditoría OWASP top 10, WCAG 2.1 AA, RGPD/Ley 1581 de 2012 |

### 1.2 · Principios de implementación

1. **YAGNI estricto.** No construir features sin hipótesis a validar. Cada feature debe responder a una pregunta de la tesis o a una necesidad de usuario observada en pruebas.

2. **MVP > completitud.** Mejor un flujo end-to-end funcional con limitaciones documentadas que un módulo perfecto sin integración.

3. **Pivot autorizado.** Si los datos de pruebas con usuarios indican que un módulo no aporta valor, está autorizado eliminarlo. La tesis documentará el aprendizaje.

4. **Documentación viva.** Cada decisión arquitectónica importante se registra como ADR (Architecture Decision Record) inline en comentario JS. Si después se revierte, queda el historial.

5. **Riesgos enumerados.** Todo riesgo identificado entra al registro `RSK-XX` (vamos en RSK-39). Estado: identificado/mitigado/aceptado/cerrado. Esto alimenta el capítulo de FMEA de la tesis.

6. **Validación empírica.** Cada fase incluye pruebas con usuarios reales (mínimo 5, máximo 20) cuyos resultados se documentan. La fase 0 ya tuvo prueba interna en iPhone real (problema WebView detectado y resuelto).

### 1.3 · Trade-offs aceptados por ser tesis

- **Sin tests automatizados** (hasta Fase 5). El costo de mantenerlos durante iteración rápida no se justifica cuando el desarrollador único es también QA.
- **Single-file en Fase 0-3.** Bundlers/build-step se introducen recién en Fase 4. Hasta entonces, el archivo único facilita demos rápidas y revisión del director de tesis.
- **Cuentas demo hardcodeadas** (`maria@demo.co`, `admin@demo.co`, password `demo`) hasta Fase 1.
- **localStorage para todo** en Fase 0. Limitaciones (~5MB, sin backup, sin sync) documentadas en RSK-16.
- **Sin i18n real.** Solo español. La infraestructura I18n está pero solo carga `es`.

---

## 2 · Marco normativo y técnico de fondo

### 2.1 · Ley 2111 de 2021 — los 18 delitos cubiertos

Mapeo de severidad calibrado (1-5):

| Severidad | Tipo | Artículos |
|---|---|---|
| **5** Catastrófico | Daños masivos, irreversibles | 333 (Daño en los recursos naturales), 330A (Financiación deforestación), 334A (Contaminación con minería), 336A (Financiación invasión áreas), 337A (Financiación apropiación baldíos) |
| **4** Grave | Daño significativo | 328 (Aprovechamiento ilícito de recursos biológicos), 330 (Deforestación), 332 (Contaminación ambiental), 334 (Contaminación de aguas), 336 (Invasión de áreas de especial importancia ecológica), 337 (Apropiación de baldíos) |
| **3** Moderado | Daño localizado | 328A (Tráfico de fauna), 328C (Pesca ilegal), 331 (Daños a recursos hídricos), 335 (Experimentación ilegal con especies) |
| **2** Menor | Infracción aislada | 329 (Aprovechamiento ilícito de recursos genéticos) |
| **1** Insignificante | Infracción mínima | 328B (Caza ilegal) |

**Regla multi-resultado:** severidad final = `max(severidades de los delitos detectados)`. Justificación: principio penal de "el delito más grave absorbe en gravedad a los menores cuando concurren".

### 2.2 · Modelo de riesgo

**Score = severidad × probabilidad** (rango 1-25).

**Bandas** (basadas en cuartiles ajustados):
- `1-4` BAJO 🟢
- `5-9` MEDIO 🟡
- `10-14` ALTO 🟠
- `15-19` CRÍTICO 🔴
- `20-25` EXTREMO ⛔

**Probabilidad CONESA Fdez-Vítora (2010)** — 5 dimensiones ponderadas:
- Extensión: peso 0.25
- Reversibilidad: peso 0.30
- Recurrencia: peso 0.20
- Vulnerabilidad: peso 0.15
- Persistencia: peso 0.10

Cada dimensión se evalúa 1-5. `Probabilidad = round(Σ respuesta_i × peso_i)`.

### 2.3 · Autoridades por banda (acumulativo)

| Banda | Autoridades notificadas |
|---|---|
| BAJO | UMATA municipal |
| MEDIO | + CAR regional |
| ALTO | + ANLA |
| CRÍTICO | + Fiscalía (Unidad 122) |
| EXTREMO | + MinAmbiente + Policía Ambiental |
| **Maestro (siempre)** | radicacion@plataforma (correo central de archivo) |

### 2.4 · Árbol de decisión

10 nodos: `q1`, `q2_bio`, `q2b_fauna`, `q3_deforest`, `q4_contam`, `q5_mineria`, `q6_areas`, `q6b_areas`, `q6c_baldios`, `q7_ogm`. 23 rutas terminales que cubren los 18 delitos.

---

## 3 · Roadmap completo del proyecto

### Fase 0 · Prototipo funcional (DONE ~95%)

Lo que se construyó turno por turno:

- **STEP-001** · Shell del app: persistencia, store, bus, auditoría, router, auth simulada, sistema visual Brote, vistas placeholder
- **STEP-002** · Motor del árbol de decisión + catálogo de 18 delitos + modo invitado + i18n + focus management + skeletons
- **STEP-003** · Probabilidad CONESA + Risk + Authorities + Score + Modal propio + matriz 5×5 visual + acumulación de autoridades
- **STEP-004** · Ubicación (GPS/Mapa Leaflet/Texto) + Evidencias (drag&drop, compresión) + Revisión + Vista enviado + módulos Geo, MapWidget, Evidence, Outbox, Report, Review, SentView
- **STEP-005** · Dashboard admin completo (KPIs, donut/bars/hbars SVG, heatmap Leaflet, tabla filtrable, drawer detalle, matrix interactiva, users, config, export, outbox)
- **STEP-006** · PDF formal con jsPDF + galería de imágenes embebidas + nota transparente sobre limitaciones de entrega de evidencias por email + hotfixes Safari iOS + panel diag visible + aviso WebView
- **STEP-007** · Páginas públicas /consulta y /contacto (PublicLookup, Contact) + privacy by design + quick actions en home
- **STEP-008** · Mejoras UX: Clipboard module, QRGen vanilla, QR en PDF, relativeTime, PublicStats en home, fix login redundante con updateLandingCTA

**Pendiente de Fase 0:**
- **STEP-009** · Memoria técnica de Fase 0 en Markdown (3.000-5.000 palabras) para anexo de tesis
- **STEP-010** · Mejoras menores: rate limit local, copy en otras vistas, URL real del QR, Open Graph tags, manifest PWA, "Add to Home Screen" iOS

### Fase 1 · Backend mínimo (Firebase Auth + Firestore)

- **STEP-101** · Setup proyecto Firebase + config keys + SDK Firebase v10 vía CDN modular
- **STEP-102** · Feature flag `eco.config.backend = 'localStorage' | 'firebase'` para coexistencia durante migración
- **STEP-103** · Reemplazo módulo `Auth` con Firebase Auth (email/password, verificación de correo, recuperación)
- **STEP-104** · Migración progresiva de `eco.users` → Firebase Auth users
- **STEP-105** · Schema Firestore: collections `reports`, `users`, `audit_log`, `config` (singleton)
- **STEP-106** · Reemplazo escrituras de reports → Firestore con `onSnapshot` reactivo
- **STEP-107** · Migración admin dashboard a fuente Firestore con paginación cursor-based
- **STEP-108** · Security Rules Firestore (admin vs ciudadano vs anónimo)
- **STEP-109** · Tool de migración de datos demo locales → Firestore
- **STEP-110** · Pruebas con usuarios (≥10 cuentas distintas, ≥30 denuncias reales)
- **STEP-111** · Documento técnico de Fase 1 para tesis

### Fase 2 · Storage de evidencias

- **STEP-201** · Setup Firebase Storage + reglas
- **STEP-202** · Reemplazo de evidencias inline (base64) por upload a Storage con progress indicator
- **STEP-203** · URLs firmadas con expiración (24h-7d) para acceso de autoridades
- **STEP-204** · Refactor de la sección de evidencias en email body para usar URLs en lugar de "solicitar al maestro"
- **STEP-205** · Panel admin: viewer de evidencias desde Storage con preview lazy-loaded
- **STEP-206** · Política de retención (autodelete a 365 días, configurable)
- **STEP-207** · Security Rules Storage (anónimos suben, solo admin lee)
- **STEP-208** · Pruebas E2E del flujo completo con evidencias reales
- **STEP-209** · Documento técnico de Fase 2

### Fase 3 · Envío real de notificaciones

- **STEP-301** · Setup EmailJS (template + service)
- **STEP-302** · Reemplazo `Outbox.enqueue` con llamada a EmailJS API
- **STEP-303** · Worker periódico para retry de outbox pendiente (Firebase Functions o setInterval)
- **STEP-304** · Tracking de entrega (status pending → sent → delivered → bounced)
- **STEP-305** · Template HTML del email con marca, banda destacada, link a evidencias y consulta pública
- **STEP-306** · Recepción real de prueba en bandeja de correo de autoridades demo
- **STEP-307** · Manejo de rebotes y errores de entrega
- **STEP-308** · Documento técnico de Fase 3

### Fase 4 · Datos reales y dashboard productivo

- **STEP-401** · Migración a build-step (Vite) con code-splitting
- **STEP-402** · Refactor de módulos JS a archivos separados manteniendo arquitectura modular
- **STEP-403** · Lazy loading de Admin dashboard, Leaflet, jsPDF, QRGen
- **STEP-404** · Optimización de performance (virtualización de tabla con react-window o equivalente vanilla)
- **STEP-405** · Caché agresivo de queries Firestore (SWR pattern)
- **STEP-406** · Métricas y monitoreo (Firebase Analytics + Sentry o Highlight.io)
- **STEP-407** · Carga inicial < 3s en 3G simulado
- **STEP-408** · Documento técnico de Fase 4

### Fase 5 · Hardening y compliance

- **STEP-501** · Auditoría OWASP Top 10 (XSS en inputs, CSRF en forms, IDOR en URLs de evidencias, etc.)
- **STEP-502** · Implementación de hCaptcha o reCAPTCHA en consulta pública y registro (anti-spam)
- **STEP-503** · Rate limit en Firestore (Firebase App Check)
- **STEP-504** · Compliance Ley 1581 de 2012 (Habeas Data Colombia): consentimiento explícito, política de tratamiento de datos, derecho al olvido
- **STEP-505** · Accesibilidad WCAG 2.1 AA (auditoría con axe-core, lectores de pantalla, alto contraste)
- **STEP-506** · Análisis de seguridad estática (Snyk, GitHub Dependabot)
- **STEP-507** · Penetration test informal (puede ser autoría dirigida)
- **STEP-508** · Política de seguridad pública (security.txt + responsible disclosure)
- **STEP-509** · Documento técnico de Fase 5 + capítulo de seguridad en tesis

---

## 4 · Estado técnico actual (v0.8.0)

### 4.1 · Capa de datos · localStorage prefix `eco.`

| Key | Tipo | Descripción |
|---|---|---|
| `eco.users` | Array | Cuentas demo (admin@demo.co, maria@demo.co) |
| `eco.session` | Object\|null | Sesión activa |
| `eco.tree` | Object | Estructura del árbol de decisión |
| `eco.delitos` | Object | Catálogo de 18 delitos con name, cat, sev, prision, multa |
| `eco.draft` | Object\|null | Denuncia en construcción |
| `eco.reports` | Array | Denuncias enviadas |
| `eco.outbox` | Array | Cola simulada de emails |
| `eco.audit_log` | Array | Bitácora (cap 1000 entries) |
| `eco.report_counter` | Number | Secuencial diario para radicado |
| `eco.config.authorities` | Object | Correos por banda + master_email |
| `eco.config.contact` | Object | Datos públicos: org, email, phones, address, hours |
| `eco.authorities_meta` | Object | Labels y urgencia por banda |
| `eco.last_sent_radicado` | String | Para vista de éxito |

### 4.2 · Módulos JS (33 totales)

Organizados como objetos con métodos. No usan `class` por compatibilidad ES5.

**Core (8):** `Persist`, `Store`, `Bus`, `Audit`, `I18n`, `Focus`, `Auth`, `Router`

**Flujo denuncia (11):** `Tree`, `Probability`, `Risk`, `Authorities`, `Modal`, `Score`, `Geo`, `MapWidget`, `LocationView`, `Evidence`, `EvidenceView`

**Envío y output (6):** `Outbox`, `Report`, `Review`, `SentView`, `Clipboard`, `QRGen`, `PdfGen`

**Públicas (3):** `PublicStats`, `PublicLookup`, `Contact`

**Admin (2):** `AdminViews` (proxy), `Admin` (con sub-módulos `Stats`, `Charts`, `dashboard`, `reports`, `matrix`, `users`, `config`, `export`, `outbox`)

**UI (3):** `UI`, `Toast`, `Skeleton`

### 4.3 · Rutas activas (18)

`/`, `/consulta`, `/contacto`, `/iniciar-sesion`, `/denunciar`, `/denunciar/resultado`, `/denunciar/probabilidad`, `/denunciar/score`, `/denunciar/ubicacion`, `/denunciar/evidencias`, `/denunciar/revision`, `/denunciar/enviado`, `/mis-denuncias`, `/admin`, `/admin/denuncias`, `/admin/matriz`, `/admin/usuarios`, `/admin/config`, `/admin/exportar`, `/admin/outbox`.

### 4.4 · Sistema visual Brote (light mode only)

**Fuentes** (Google Fonts):
- Display: Bricolage Grotesque (h1-h3, brand)
- Body: Plus Jakarta Sans (texto)
- Mono: JetBrains Mono (radicado, código)

**Variables CSS clave:**
- `--brand: #2EAA70`
- `--brand-deep: #1F6F4A`
- `--brand-tint: #DBF0E1`
- `--brand-soft: #B4DDC2`
- `--warm: #F5B344`
- `--coral: #F47D6F`
- `--alarm: #DC4545`
- `--bg: #F8FBF5`
- `--bg-card: #FFF`
- `--bg-subtle: #F0F4ED`
- `--line/--line-strong/--text/--text-soft/--text-muted`

**Espaciado:** `--s-1` (4px) → `--s-12` (96px)
**Tipografía:** `--t-11` → `--t-40`
**Radios:** `--r-sm` (4px) → `--r-xl` (24px) + `--r-pill`
**Sombras:** `--sh-1` (sutil) → `--sh-3` (modal)

### 4.5 · Restricciones críticas de compatibilidad

1. **ES5-safe.** NO usar `||=`, `??=`, `&&=` (rompen parser de Safari iOS < 14)
2. **Scripts externos al final del body** sin `integrity`/`crossorigin` (fallan en `file://` origin)
3. **Meta no-cache** en `<head>` para evitar caché agresiva en Safari iOS
4. **Persist con fallback en memoria** si localStorage está bloqueado (modo privado)
5. **bindHandlers blindado** con patrón `safe(name, fn)` y verificación `if (el)` antes de cada `getElementById`
6. **Aviso JS-required** al inicio del body, oculto por JS si está disponible (detecta WebView de WhatsApp/Files/Mail que NO ejecuta JS)
7. **Panel de diagnóstico visible** ES5 puro en esquina inferior derecha con badge de versión

---

## 5 · Decisiones arquitectónicas registradas (ADRs)

### ADR-01 · Single-file HTML para Fase 0-3
**Decisión:** Todo en un archivo `.html` hasta Fase 3.
**Justificación:** Distribución trivial (un link), no requiere build step, facilita demos al director de tesis, GitHub Pages sin configuración. El costo (~6.700 líneas en un archivo) es manejable porque la complejidad está bien modularizada en objetos.
**Trade-off:** Performance subóptima en first paint (~250KB sin gzip). Aceptable hasta validar producto.
**Revisitar en:** Fase 4 (build step con Vite).

### ADR-02 · Marco Ley 2111/2021 (no CP original)
**Decisión:** Implementar exclusivamente con la versión post-Ley 2111. No retrocompatibilidad con CP de 2000.
**Justificación:** La Ley 2111 es la reforma más reciente y completa. Mantener dos versiones del CP duplicaría el catálogo y la lógica del árbol sin valor agregado para la tesis.
**Trade-off:** Si en el futuro hay una contra-reforma, hay que migrar todo.

### ADR-03 · Severidad ancla por max()
**Decisión:** Cuando un hecho concurre múltiples delitos, la severidad es la máxima individual, no la suma ni el promedio.
**Justificación:** Principio penal de absorción: el más grave domina. Además, sumar severidades produciría scores fuera de rango.

### ADR-04 · CONESA para probabilidad
**Decisión:** Usar metodología CONESA Fdez-Vítora (2010) con 5 dimensiones ponderadas en lugar de probabilidad subjetiva o frecuencias históricas.
**Justificación:** CONESA es el estándar académico colombiano para evaluación de impacto ambiental. Da defensibilidad ante el director de tesis y el jurado. Los pesos están calibrados según literatura.

### ADR-05 · Acumulación de autoridades (no sustitución)
**Decisión:** Banda CRÍTICO incluye autoridades de ALTO + MEDIO + BAJO, no solo CRÍTICO.
**Justificación:** Coordinación interinstitucional. Una denuncia de banda EXTREMO debe llegar también a CAR regional y UMATA municipal porque ellos tienen jurisdicción territorial directa.

### ADR-06 · Privacy by design en consulta pública
**Decisión:** La vista pública de consulta muestra solo: estado, banda, fecha, categoría, artículos, timeline. NO muestra ubicación, evidencias, descripción del denunciante, autoridades específicas, ni si fue anónima.
**Justificación:** El radicado podría caer en manos de actores hostiles (sicariato ambiental es un problema real en Colombia). Minimizar la superficie de información reduce riesgo al denunciante.

### ADR-07 · Sistema visual Brote light-only
**Decisión:** No implementar dark mode.
**Justificación:** Es una decisión explícita del autor para reducir scope. Dark mode duplicaría el trabajo de QA visual y no aporta a la validación de hipótesis.

### ADR-08 · QRGen vanilla embebido vs CDN
**Decisión:** Embeber la librería qrcode-generator de Kazuhiko Arase (MIT) condensada (~120 líneas) en lugar de cargar otro CDN.
**Justificación:** Reducir dependencias externas. Ya tenemos Leaflet y jsPDF como CDN; agregar un tercero aumenta puntos de falla (como ya pasó con Safari iOS y los `integrity` attributes).

### ADR-09 · Sin tests automatizados en Fase 0-4
**Decisión:** No invertir en Jest/Vitest hasta Fase 5.
**Justificación:** El costo de mantener tests durante iteración rápida con un solo desarrollador es alto. La validación es manual + paneles de diagnóstico visibles. Se documentan los riesgos no cubiertos (RSK-XX).

### ADR-10 · WebView de WhatsApp/Files/Mail no es target
**Decisión:** Aceptar que el HTML no funciona en WebViews internos de iOS. Mostrar mensaje explícito explicando opciones.
**Justificación:** Esos WebViews están diseñados como preview, no como navegador. iOS los limita por seguridad. Combatir esta limitación tomaría semanas y solo afecta el flujo "abrir archivo local en iPhone", que ya no es relevante con GitHub Pages.

---

## 6 · Protocolo de trabajo

### 6.1 · Estructura de un STEP

Cada STEP es una unidad de trabajo coherente. Para implementar un STEP completo:

1. **Leer el archivo HTML** (Read tool) o las secciones relevantes
2. **Listar las edits planeadas** como mini-spec antes de hacerlas (excepto STEPs triviales)
3. **Implementar** con Edit/Write tools, una edit por vez
4. **Validar estructura** con el comando bash de balance (ver sección 7)
5. **Cierre del STEP** con los 4 elementos:
   - **CHANGELOG inline** en comentario JS al final del archivo (en formato existente)
   - **Riesgos identificados** numerados desde RSK-40 hacia adelante
   - **Oportunidades de mejora** observadas durante la implementación
   - **Propuesta concreta** del siguiente STEP con alternativas si las hay

6. **Esperar confirmación** del usuario ("OK / procede / continúa") antes del siguiente STEP, a menos que el usuario haya pedido varios STEPs encadenados desde el principio.

### 6.2 · Cuando hay ambigüedad

Si una decisión técnica tiene >1 opción razonable, **NO la tomes silenciosamente**. Lista las opciones con pros/contras y deja que el usuario elija. Especialmente:
- Cambios en el schema de datos
- Cambios en colores/tipografía
- Introducción de dependencias nuevas
- Cambios al modelo de riesgo o al árbol jurídico
- Cualquier cosa que afecte vistas públicas (privacy implications)

### 6.3 · Si detectas un anti-pattern

Si al leer el código detectas un anti-pattern (estado mutado sin persistir, handler sin defensas, lógica duplicada), **propón la corrección** explícitamente. La tesis se beneficia de tener el código más limpio para defensa.

### 6.4 · Honestidad técnica

- Si una solución no funciona como se prometió, decirlo claramente.
- Si una librería externa puede fallar, documentar el degradación.
- Si un riesgo conocido se mantiene, registrarlo como RSK-XX con estado "aceptado".
- No marketing-speak. Prosa técnica clara.

### 6.5 · Estilo de comunicación

- Español neutro (no español de España ni mexicanismos)
- Prosa técnica explicativa, no listas para todo
- El **por qué** detrás de cada decisión importante
- Trade-offs explícitos
- Comentarios JS en español (ya es la convención en el archivo)
- Mensajes de commit (cuando aplique) en español

---

## 7 · Validación obligatoria post-edits

Después de cada edición sustancial, ejecutar:

```bash
python3 -c "
content = open('ARCHIVO.html').read()
import re
print('=== Estructura ===')
print('section:', content.count('<section'), '/', content.count('</section>'))
print('div:', content.count('<div'), '/', content.count('</div>'))
print('script:', content.count('<script'), '/', content.count('</script>'))
print('style:', content.count('<style'), '/', content.count('</style>'))
print('button:', content.count('<button'), '/', content.count('</button>'))
print('label:', content.count('<label'), '/', content.count('</label>'))
print()
print('=== Compat ES5 ===')
# Buscar logical assignment ops fuera de comentarios
real_ops = 0
for line in content.split(chr(10)):
    stripped = line.strip()
    if stripped.startswith(('*','-','/*','//','+','>')):
        continue
    if '||=' in line or '??=' in line or '&&=' in line:
        real_ops += 1
        print('  ⚠', line.strip()[:80])
print('Logical assignments en código real:', real_ops, '(debe ser 0)')
print()
print('=== Sintaxis JS frágil ===')
print('Optional chaining ?.:', len(re.findall(r'\\?\\.[a-zA-Z_]', content)), '(Safari 13.4+)')
print('Nullish coalescing ??:', len(re.findall(r'\\?\\?[^=]', content)), '(Safari 13.4+)')
"
```

Si **algún par no balancea** o aparecen `||=` reales: NO entregar el archivo. Revisar qué edit lo desbalanceó.

---

## 8 · Cuando inicies en Claude Code

1. **Pregunta inicial al usuario:**
   > "Veo el roadmap completo. ¿Qué fase/STEP arrancamos? Te recomiendo continuar con STEP-009 (memoria técnica de Fase 0) para cerrar formalmente la fase antes de pasar a Fase 1, pero si prefieres saltar a Firebase puedo empezar con STEP-101."

2. **Antes de la primera edit:**
   - Lee el archivo HTML completo con Read tool (varias llamadas si es necesario por tamaño)
   - Identifica el **nombre actual de la app** (el usuario lo cambió manualmente y posiblemente otras cosas)
   - Identifica la **versión actual** y el último STEP completado leyendo el CHANGELOG al final del archivo
   - Identifica las **URLs reales** (GitHub Pages) si están actualizadas
   - Identifica los **datos de contacto demo** actuales en `Persist.bootstrap`

3. **Si encuentras inconsistencias** entre lo que dice este prompt y lo que está en el archivo, **prioriza el archivo**. El usuario hizo cambios manuales que tienen autoridad.

4. **Empieza con el STEP solicitado** siguiendo el protocolo de la sección 6.

---

## 9 · Información operativa

- **Usuario:** Colombia, fechas en es-CO, idioma español
- **Navegador primario de pruebas:** Safari iOS (iPhone) → Chrome Android → desktop
- **Hosting actual:** GitHub Pages (URL temporal del repo del usuario, está activa)
- **Cuentas Firebase:** No creadas aún. Se necesitarán cuando empiece Fase 1.
- **EmailJS:** Cuenta no creada. Se necesitará en Fase 3.
- **Dominio propio:** No comprado. Posible en Fase 5 si la tesis pasa a producto real.

---

## 10 · Anti-objetivos explícitos

Cosas que NO se van a hacer en este proyecto:

- ❌ Mobile app nativa (iOS/Android). Web app responsive es suficiente.
- ❌ Dark mode (ADR-07).
- ❌ Tests E2E automatizados antes de Fase 5 (ADR-09).
- ❌ Internacionalización a más idiomas. Solo español.
- ❌ Integración con blockchain (modas tecnológicas que no resuelven el problema real).
- ❌ Sistema de votación/reputación entre ciudadanos. El alcance es denuncia, no red social.
- ❌ Soporte de navegadores anteriores a Safari 12 / Chrome 70 / Firefox 65. iOS 13+ es el piso.

---
