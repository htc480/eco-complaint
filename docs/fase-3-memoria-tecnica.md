# Eco-Complaint · Memoria técnica de la Fase 3

**Versión del prototipo cubierta:** v0.18.0 · STEP-301 a STEP-308
**Fecha de cierre:** 15 de mayo de 2026
**Autor:** [Autor de la tesis]
**Documento:** Anexo técnico de la tesis doctoral

---

## 1. Propósito y alcance

Esta memoria documenta la cuarta fase de construcción del prototipo Eco-Complaint, durante la cual los correos a las autoridades pasan de ser una simulación local (cola `outbox` en localStorage o Postgres sin envío real) a entregas efectivas vía EmailJS. La hipótesis a validar es operativa: *"Las autoridades reciben efectivamente las denuncias por email automáticamente"*.

Hasta Fase 2 el sistema construía cuerpos de correo completos con todos los datos del caso, generaba URLs firmadas para las evidencias y los encolaba en el `outbox`, pero ningún correo salía realmente del navegador. El cuello de botella era el último centímetro: convertir un buffer de mensajes en entregas concretas a bandejas de las autoridades. Fase 3 cierra ese hueco.

La hipótesis se considera **confirmada** con el cierre de esta fase: tras configurar las credenciales de EmailJS desde el panel de administración, una denuncia enviada por un ciudadano (autenticado o anónimo) dispara entregas reales a todos los destinatarios calculados por el direccionamiento acumulativo de Fase 0, con tracking visible en `/admin/outbox` y reintento individual disponible para casos fallidos.

## 2. Decisión arquitectónica clave (ADR-16)

### ADR-16 · Credenciales de EmailJS configurables, no hardcodeadas

La decisión fundamental de Fase 3 fue **no commitear las credenciales de EmailJS en el HTML**, ni siquiera como placeholders. Las tres claves (`service_id`, `template_id`, `public_key`) viven exclusivamente en la tabla `config` de Supabase bajo la key `emailjs`, y se editan desde `/admin/config`. Las razones que justifican esta decisión son operativas y académicas:

1. **Permite cambiar credenciales sin redesplegar el HTML.** Si el usuario rota las claves o cambia de servicio SMTP en el dashboard de EmailJS, solo actualiza los valores en `/admin/config` y la app empieza a usar las nuevas en el próximo envío. Sin recompile, sin git push, sin GitHub Pages re-build.

2. **Permite múltiples entornos compartiendo el mismo HTML.** Un mismo `index.html` puede correr en desarrollo (con credenciales de un proyecto EmailJS de pruebas), en staging (otro proyecto) y en producción (un tercer proyecto), simplemente cambiando el contenido de la tabla `config` del Supabase correspondiente. La separación de concerns entre código y configuración es estándar en sistemas serios.

3. **Si el repositorio es público, el HTML no expone los identificadores.** Aunque ninguna de las tres claves es secreta —`public_key` es pública por diseño igual que la anon key de Supabase, y los IDs son identificadores administrativos— mantenerlos fuera del código fuente reduce la superficie atacable. Si un actor hostil encuentra las claves en un repo abierto, puede aún así enviar correos abusivamente a través de la cuenta del usuario, agotando la cuota gratuita o asociando la cuenta a actividades de spam. Tenerlas en una tabla con RLS admin-write y public-read minimiza ese riesgo (un atacante necesitaría primero comprometer la sesión del admin).

4. **El admin controla cuándo activar el envío real.** Un flag `enabled` en `config.emailjs` permite "modo dry run": los correos se encolan pero no se envían, útil durante pruebas o si el admin necesita pausar temporalmente las notificaciones para investigar incidentes.

La consecuencia operacional es que `EmailService.isConfigured()` se evalúa en cada envío: verifica que el SDK cargó, que los tres valores existen y que `enabled` no es `false`. Si cualquiera falla, el correo queda con status `pending` en el outbox y el admin lo procesa manualmente cuando configure.

## 3. Arquitectura del envío

### 3.1 EmailService

El módulo nuevo `EmailService` es un wrapper delgado sobre el SDK `@emailjs/browser@4` cargado desde `cdn.jsdelivr.net`. Expone una superficie mínima:

- `isConfigured()`: predicado sincrónico que combina presencia del SDK + datos en `ConfigRepo.getSync('emailjs')`.
- `_initIfNeeded()`: llama `emailjs.init({ publicKey })` la primera vez que se necesita. Es idempotente con un flag `_ready`.
- `_params(item)`: mapeo del objeto del outbox a las variables que el template HTML del usuario en EmailJS debería usar. Documentado en `/admin/config` como referencia para que el usuario diseñe su template.
- `sendOne(item)`: invoca `emailjs.send(service_id, template_id, params)` y normaliza la respuesta a `{ ok, status, text }` o `{ ok: false, error }`.
- `testSend(toEmail)`: construye un item sintético y llama `sendOne`. No toca el outbox.

La elección de EmailJS frente a alternativas (SendGrid, Mailgun, Resend, Postmark) responde a tres criterios prácticos. Primero, EmailJS opera puramente desde el cliente: no requiere backend ni Edge Functions, lo cual es consistente con la arquitectura single-file de la app y elimina una pieza de infraestructura. Segundo, su plan gratuito (200 correos/mes en mayo de 2026) cubre con holgura una tesis que se demuestra varias veces. Tercero, su SDK web es maduro, expone una API simple y maneja CORS, OAuth con Gmail, y autenticación con SMTP genérico desde su dashboard sin que el cliente tenga que conocer credenciales SMTP. El trade-off aceptado es la cuota limitada y la dependencia de un proveedor cliente-side; en producción real con miles de correos diarios se migraría a SendGrid + Edge Function (Fase 5).

### 3.2 Outbox refactored

El módulo `Outbox` existente se amplió para soportar el ciclo de vida real del envío. El estado de cada item ahora atraviesa: `pending → sending → sent` o `pending → sending → failed`. Los campos nuevos por item son `created_at`, `sent_at`, `attempts`, `last_error`, además de los originales `to`, `subject`, `body`, `report_radicado`, `meta`, `id`.

`Outbox.processQueue()` itera todos los pending y los manda con `EmailService.sendOne`. Si EmailJS no está configurado, todos quedan `skipped` (siguen `pending` para reintento manual). El resumen `{ sent, failed, skipped }` se publica al `Bus` y se loguea en `audit_log`.

`Outbox.retry(id)` permite reintento individual desde la UI. Incrementa el contador `attempts` antes de cada intento y persiste `last_error` cuando falla. No tiene exponential backoff automático en Fase 3; eso queda para Fase 4 cuando el volumen lo justifique.

### 3.3 Integración con Report.send

`Report.send()` ya existía con el flujo correcto desde Fase 0: calcula radicado, resuelve autoridades, construye el cuerpo del email (asíncrono desde Fase 2 por las signed URLs), encola en el outbox una entrada por destinatario, persiste el report y navega a la vista de éxito. Fase 3 agrega dos detalles:

Primero, cada `Outbox.enqueue` recibe un objeto `meta` con campos útiles para el template (`band_label`, `from_name`, `reply_to`, `to_name`). Esto separa los datos estructurados (que el template puede renderizar como `{{band_label}}` con colores condicionales) de la prosa libre del `body`.

Segundo, tras encolar los N correos, si `EmailService.isConfigured()` es verdadero, se dispara `Outbox.processQueue()` de forma asíncrona (no se aguarda). El ciudadano ve inmediatamente el radicado en `/denunciar/enviado` y los toasts informan en segundo plano cuántos correos se enviaron y cuántos fallaron. La razón de no aguardar es UX: con cinco destinatarios y un round-trip de 800 ms por correo, esperar bloquearía la pantalla cuatro segundos. Mejor mostrar el radicado primero y reportar el progreso de fondo.

## 4. Modelo de seguridad

Las tres claves de EmailJS no son secretas individualmente:

- **public_key**: es la clave que EmailJS usa para identificar tu cuenta desde el cliente. Diseñada para ser pública, equivalente a la anon key de Supabase. La protección real está en el dominio: en el dashboard de EmailJS se puede restringir el uso de la public_key a dominios específicos (`localhost`, `htc480.github.io`, etc.).
- **service_id**: identificador del servicio SMTP conectado (Gmail, Outlook, SendGrid, etc.). No expone credenciales del servicio subyacente, solo apunta a una configuración en el dashboard.
- **template_id**: identificador del template HTML que se enviará. Cambiar el template requiere acceso al dashboard de EmailJS.

El secreto real de la cuenta EmailJS (el password de Gmail conectado, la API key de SendGrid, etc.) nunca toca el navegador del cliente: vive solo en el dashboard de EmailJS. Si las tres claves del cliente se filtran, un atacante puede como mucho agotar la cuota gratuita enviando correos vacíos al template configurado; no puede acceder a la bandeja del usuario ni cambiar la configuración.

Pese a esto, la decisión arquitectónica (ADR-16) es **no** ponerlas en el HTML por las cuatro razones discutidas en la sección 2. La protección adicional es defensa en profundidad: aunque cada capa individual sea pública, la combinación de capas aumenta el costo del ataque.

## 5. Schema y RLS

El archivo `docs/fase-3-emailjs-setup.sql` modifica la policy `config_public_read` para incluir las keys `emailjs`, `authorities` y `storage` además de las dos originales (`contact`, `authorities_meta`). La decisión de incluir `authorities` resuelve el RSK-61 documentado en Fase 1: las direcciones de UMATA, CAR, ANLA, Fiscalía 122, MinAmbiente y Policía Ambiental son correos institucionales públicos (publicados en sus respectivas páginas de contacto), no secretos. El secreto del sistema está en QUÉ se denuncia, no en A QUIÉN se notifica.

`storage` se incluye porque sus defaults (duración de signed URLs, máximo de archivos, retención) son parámetros de UX que cualquier cliente puede consultar sin riesgo. La key `emailjs` se incluye por el mismo motivo: el SDK necesita leer `public_key` para inicializarse aunque el usuario sea anónimo.

Las policies de escritura (`config_admin_write`) permanecen inalteradas: solo admin puede modificar cualquier key de config. La lectura amplia + escritura restringida es el patrón correcto de configuración pública en sistemas con auth role-based.

## 6. UI del panel admin

`/admin/config` recibe una sección nueva entre el card de Backend y el de Datos públicos. Tiene:

- **Tarjeta de estado** con tres celdas: SDK (cargado/no), Estado (configurado/no), Cuota free (200/mes).
- **Tres inputs editables** para service_id, template_id, public_key, con `autocomplete="off"` para evitar que el navegador los cachee como credenciales.
- **Checkbox enabled** que permite activar/desactivar el envío sin borrar los valores.
- **Botón "Guardar EmailJS"** que llama `ConfigRepo.set('emailjs', ...)` (escribe a Postgres) y luego reinicializa el SDK con la nueva public_key.
- **Botón "Probar configuración"** que abre un prompt para el email destinatario, llama `EmailService.testSend()` y muestra el resultado inline (verde si OK, rojo con detalle del error si falla).
- **Bloque `<details>`** expandible que documenta las nueve variables que debe usar el template HTML del usuario (`{{to_email}}`, `{{to_name}}`, `{{from_name}}`, `{{subject}}`, `{{radicado}}`, `{{band_label}}`, `{{body}}`, `{{consulta_url}}`, `{{reply_to}}`).

La sección replica el patrón visual de la tarjeta de Backend de Fase 1, lo que mantiene consistencia en la experiencia del admin: estado en grid + acciones inline + ayuda contextual.

## 7. UI del outbox

`/admin/outbox` se rediseñó para reflejar los estados reales del ciclo de vida del envío. Cambios:

- **Cuatro contadores** en el header (pendiente, enviando, enviado, fallido) en lugar de dos.
- **Banner amarillo de aviso** si EmailJS no está configurado, con link directo a `/admin/config`.
- **Tabla** con columnas adicionales: número de intentos, fecha de creación o envío según el status.
- **Botones por fila**: "Ver" (drawer con cuerpo del email y último error si falló), "↻ Reintentar" (failed) o "▶ Enviar" (pending).
- **Botón "Procesar cola ahora"** en el header que dispara `Outbox.processQueue()` con feedback en vivo.
- **Drawer enriquecido**: si el item tiene `last_error`, lo destaca en un bloque rojo encima del body del correo.

La razón de tener tanto un botón "procesar todo" como reintento individual es operativa: el admin a veces quiere validar un solo correo (uno que fue rechazado por una dirección inválida y quiere reintentarlo tras corregir el listado de autoridades), y otras veces quiere procesar todo lo pendiente acumulado (después de configurar EmailJS por primera vez con denuncias previas en cola).

## 8. Validación empírica

Las pruebas internas durante STEP-301 a STEP-308 cubrieron:

- **Configuración inicial**: en `/admin/config` ingresé los tres valores reales, guardé, y el indicador pasó de "No configurado" (amarillo) a "Activo" (verde) tras la siguiente recarga (necesaria para que `EmailService._initIfNeeded()` corra con la public_key fresca).
- **Test send**: el botón "Probar configuración" envió correctamente a un correo de prueba. Respuesta `{ status: 200, text: 'OK' }` en aproximadamente 600 ms.
- **Denuncia anónima end-to-end**: desde una pestaña incógnita sin sesión, completé el flujo de denuncia. Tras click en "Enviar", el redirect a `/denunciar/enviado` ocurrió inmediatamente, y dentro de 2-3 segundos apareció un toast verde "✓ 5 notificaciones enviadas a autoridades". Las cinco bandejas demo recibieron el correo con el template HTML renderizado correctamente.
- **Denuncia con autoridad inválida**: cambié manualmente uno de los emails de `config.authorities` a una dirección sintácticamente inválida y envié. El outbox quedó con 4 items en `sent` y 1 en `failed`. El drawer del fallido mostró el error específico de EmailJS, y el botón "Reintentar" estaba disponible.
- **Modo no configurado**: desactivé el flag `enabled` desde `/admin/config`. Una nueva denuncia generó 5 items todos en `pending`, sin disparo de processQueue. Reactivé y procesé la cola con el botón del admin: los 5 pasaron a `sent`.
- **RLS test**: desde una sesión de ciudadano (no admin), `supabase.from('config').select('value').eq('key', 'emailjs')` devolvió correctamente los valores (lectura pública). Un intento de UPDATE fue rechazado por la policy `config_admin_write` con error de RLS, como se esperaba.

Las pruebas con bandejas reales pendientes (recibir el correo en una cuenta corporativa real de UMATA o CAR) quedan deferidas a la fase de defensa de tesis: requieren coordinación previa con la entidad para confirmar que es una prueba.

## 9. Trade-offs y limitaciones

- **No hay tracking de delivery real.** EmailJS responde con `{ status: 200 }` cuando el correo fue aceptado por el servidor SMTP conectado, pero no informa si el correo llegó a la bandeja, si fue marcado como spam o si rebotó. Para distinguir entre `sent` (aceptado por SMTP) y `delivered` (en bandeja) o `bounced` (rebotado), se necesita un proveedor con webhooks y un endpoint server-side que los reciba; esto entra en el alcance de Fase 5.
- **Cuota gratuita finita.** 200 correos/mes alcanza para demos académicas, no para uso productivo. Una denuncia con banda Extremo genera hasta 7 correos (UMATA + CAR + ANLA + Fiscalía + MinAmbiente + Policía Ambiental + maestro), lo cual significa que la cuota se agota en ~28 denuncias mensuales de máxima severidad. Para producción real se migraría a SendGrid (3000/mes free) con Edge Function intermediaria.
- **Sin retry automático en background.** Si el cliente cierra la app antes de que `processQueue` termine, los items quedan en `pending` hasta que un admin abra `/admin/outbox` y reintente. Una mejora futura sería un service worker que despierte periódicamente y procese la cola; queda fuera del alcance académico de la tesis.
- **El template HTML lo gestiona el usuario.** El sistema no envía un template propio; usa el `template_id` que el usuario configuró en su dashboard de EmailJS. Si el template está mal diseñado o no usa las variables esperadas, los correos llegan con campos vacíos. La sección expandible en `/admin/config` documenta las variables que el template debe aceptar; la responsabilidad de diseñar el HTML queda en el admin.
- **No hay rate limit por usuario.** Un atacante con acceso a una cuenta o sesión anónima podría saturar la cuota generando muchas denuncias. El rate limit local (3/5 min, 10/hora) de Fase 0 ayuda pero es bypaseable. Fase 5 con App Check / reCAPTCHA cerrará esto.

## 10. Entrada a Fase 4

Con Fase 3 cerrada, la próxima hipótesis a validar es de escala: *"El dashboard admin con datos reales permite gestionar volumen del mundo real (>100 denuncias)"*. Los STEPs preliminares son: migración a build step con Vite, code-splitting (Admin dashboard, Leaflet, jsPDF lazy), virtualización de la tabla de denuncias, cache agresivo de queries Supabase, métricas con Sentry/Highlight, y optimización de first paint a <3s en 3G simulado.

La pieza de Fase 3 que conecta con Fase 4 es el outbox como buffer de notificaciones: cuando el volumen crezca, el processQueue se beneficiará de batching (enviar 10 correos en paralelo en lugar de seriado), throttling (no exceder la cuota minuto a minuto) y persistencia en Postgres (no en localStorage) para que múltiples admins puedan colaborar en el reintento. Esos cambios entran en el roadmap de Fase 4-5.

## 11. Conclusión

El cierre de Fase 3 valida que el modelo metodológico de Eco-Complaint (árbol jurídico + riesgo CONESA + direccionamiento acumulativo + privacy by design) se completa con entrega real cuando se materializa con un proveedor de email cliente-side. La integración fue contenida: 350 líneas de JS nuevo, 60 líneas de SQL, una nueva sección en `/admin/config`, una tabla rediseñada en `/admin/outbox`. Ningún cambio en el flujo del ciudadano fuera de un par de toasts informativos.

La decisión de no hardcodear las credenciales (ADR-16) es la pieza arquitectónica clave de esta fase y demuestra que un prototipo académico puede mantener buenas prácticas operacionales (separación de código y configuración, edición sin redeploy, controlabilidad por admin) sin agregar complejidad significativa. La capa `ConfigRepo` introducida en Fase 1 se reveló particularmente valiosa: las credenciales de EmailJS se leen, escriben y validan con exactamente la misma API que cualquier otra configuración del sistema. La inversión arquitectónica de Fase 1 continúa pagando.

---

*Documento técnico complementario a la tesis doctoral. Para consultar la implementación, ver `index.html` v0.18.0 y `docs/fase-3-emailjs-setup.sql` en el repositorio del proyecto.*
