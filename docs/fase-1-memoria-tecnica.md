# Eco-Complaint · Memoria técnica de la Fase 1

**Versión del prototipo cubierta:** v0.15.0 · STEP-101 a STEP-109
**Fecha de cierre:** 14 de mayo de 2026
**Autor:** [Autor de la tesis]
**Documento:** Anexo técnico de la tesis doctoral

---

## 1. Naturaleza y propósito del documento

Esta memoria documenta la segunda fase de construcción del prototipo Eco-Complaint, durante la cual el sistema migra de una arquitectura cliente único (Fase 0) a una arquitectura cliente + backend mínimo con persistencia compartida, autenticación verificada y sincronización en tiempo real. El cuerpo principal de la tesis discute el modelo metodológico (árbol jurídico, riesgo cuantitativo, direccionamiento acumulativo, privacy by design); este anexo describe las decisiones técnicas concretas que materializan ese modelo sobre un backend gestionado real.

La Fase 1 se diseñó para validar la siguiente hipótesis: *"El sistema escala a múltiples usuarios concurrentes con persistencia real y auth verificada sin perder la usabilidad observada en Fase 0"*. La hipótesis se considera **confirmada** con el cierre de esta fase: la coexistencia entre el flujo localStorage de Fase 0 y el flujo Supabase de Fase 1 quedó operativa a través de una capa de abstracción de repositorios; las denuncias persisten entre sesiones y dispositivos; las acciones quedan auditadas a nivel servidor; y la consulta pública sigue respetando privacy by design aún con datos reales.

El documento sigue las convenciones de la memoria técnica de Fase 0: prosa explicativa, decisiones registradas como ADR inline, trade-offs explícitos y registro de riesgos numerados (RSK-45 a RSK-62).

## 2. Cambio de proveedor: Supabase en lugar de Firebase

El roadmap original asumía Firebase como backend de Fase 1 (Auth + Firestore + Storage). Durante la planificación del STEP-101 se reconsideró la decisión y se pivotó a **Supabase** por razones académicas y operativas.

La razón académica es la más relevante para la tesis. Supabase usa **PostgreSQL** como motor de datos y **Row-Level Security (RLS)** de Postgres como mecanismo de autorización. Frente a un jurado doctoral, una arquitectura basada en un RDBMS estándar con políticas RLS declarativas en SQL resulta más defendible que un *document store* NoSQL con reglas en un DSL propietario. El modelo relacional permite además expresar el principio de privacy by design (ADR-06) como un objeto SQL (`reports_public` view) cuya definición vive en el repositorio, no en el cliente: la garantía de que la consulta pública sólo expone cinco columnas no depende de filtrar en JavaScript, sino del propio motor de base de datos.

La razón operativa es la cobertura de servicios. Supabase integra en un único proyecto: PostgreSQL administrado, autenticación basada en GoTrue, Storage S3-compatible, suscripciones en tiempo real sobre las tablas y Edge Functions Deno. Esto cubre las Fases 1, 2 y 3 sin agregar proveedores adicionales, lo cual reduce el riesgo de divergencia y simplifica la operación para un desarrollador único.

El trade-off aceptado es el comportamiento del plan gratuito: Supabase pausa los proyectos tras siete días de inactividad. La reactivación se hace con un click desde el dashboard y la primera petición tras la pausa toma entre diez y treinta segundos. Para un proyecto de tesis con uso intermitente este *cold-start* es una molestia, no un bloqueador. La mitigación está integrada en la propia aplicación, como se describe más adelante.

La decisión se registra como **ADR-11 (Backend Supabase para Fase 1)** y permite revertir a Firebase u otro proveedor si futuras pruebas con usuarios lo justifican; toda la lógica de persistencia atraviesa la capa de abstracción `Backend` y los repositorios, no llamadas directas al SDK.

## 3. Arquitectura de la capa de backend

### 3.1 Módulo Backend

La pieza central de Fase 1 es el módulo `Backend`, una capa de abstracción que decide en tiempo de inicialización si la aplicación opera contra `localStorage` (Fase 0) o contra Supabase (Fase 1). El criterio es la presencia de credenciales reales: si `window.__SUPABASE_URL` y `window.__SUPABASE_ANON_KEY` siguen siendo los placeholders por defecto, el módulo se queda en modo `localStorage`; si son strings válidos que apuntan a un proyecto real, activa el modo Supabase.

El cliente de Supabase se carga **diferido como módulo ES6** desde `esm.sh` y se instancia *lazy*: el módulo no bloquea el parser ni el primer paint, y el cliente se crea la primera vez que se necesita. Esto permite que el caso Fase 0 puro (sin credenciales) cargue sin penalización; el SDK no se descarga si no se va a usar.

El módulo expone una interfaz mínima: `init()`, `isSupabase()`, `isLocalStorage()`, `client()`, `wakeup()`, `status()`. La señalización de estado se hace mediante `_status` (`idle | connecting | waking | ready | error`) que el banner de UI consume para mostrar el feedback al usuario durante el *cold-start*.

### 3.2 Wakeup y manejo del cold-start

Cuando el proyecto Supabase está pausado, la primera petición HTTP devuelve después de un tiempo largo (típicamente diez a treinta segundos en plan gratuito). La pieza `Backend.wakeup()` resuelve esto con un ping ligero al endpoint REST de Supabase (`HEAD /rest/v1/`) que **no requiere el SDK cargado** porque se hace con `fetch` directo; esto permite detectar el cold-start incluso si el módulo del SDK aún está bajando del CDN.

Si el ping tarda más de dos segundos, el módulo `BackendBanner` escala el estado visual de `connecting` (gris discreto) a `waking` (ámbar con instrucción explícita y botón de reintento). Si el ping falla por timeout o error de red, el banner pasa a `error` (rojo) con detalle del fallo. Esta capa de feedback fue solicitada explícitamente durante la planificación: el proyecto se demuestra en vivo y un congelamiento sin explicación visible sería inaceptable.

Adicionalmente, la vista `/admin/diagnostico` (introducida en STEP-105) incluye un botón **"Verificar conexión"** que dispara un wakeup manual antes de cualquier demostración importante. La intención es operativa: el día de la defensa, el administrador despierta el proyecto cinco minutos antes y el riesgo de un freeze en el momento crítico desaparece.

### 3.3 Capa de repositorios

Por encima de `Backend` viven cinco repositorios que encapsulan cada agregado de datos del dominio: `ReportsRepo`, `AuditRepo`, `UsersRepo`, `ConfigRepo` y, transitivamente, el bridge de autenticación `LocalAuth`/`SupabaseAuth`. Cada repositorio decide localmente, mediante `Backend.isSupabase()`, si delega al cliente Supabase o al cache local en `localStorage`. El call-site de la aplicación no sabe ni le importa qué backend está activo.

Este patrón resuelve un problema central de la migración progresiva: en Fase 0 todo el código lee y escribe contra `localStorage` síncronamente. Reescribir veinte call-sites para hacerlos asíncronos durante la migración a Supabase introduciría regresiones. En su lugar, los **repositorios mantienen un cache local en `localStorage` y exponen una API async para las escrituras**, mientras las lecturas existentes se sirven del cache sin modificación.

La pieza que mantiene el cache fresco es la subscripción Realtime de Supabase: cuando un cambio remoto (INSERT, UPDATE, DELETE) llega por el canal `reports-watch`, el handler actualiza `eco.reports` en `localStorage` y emite `Bus.emit('reports:realtime', ...)`. El panel admin escucha ese evento y se re-renderiza si la vista activa es relevante. La consecuencia es que cuando un denunciante crea una denuncia desde otra pestaña, el dashboard del administrador la ve en menos de dos segundos sin recargar.

## 4. Modelo de datos

El esquema relacional aplicado en Postgres tiene cuatro tablas más una *view*:

- `public.users_profile` (extensión de `auth.users` con rol y nombre)
- `public.reports` (denuncias completas)
- `public.audit_log` (bitácora de acciones)
- `public.config` (singleton key-value)
- `public.reports_public` (view de cinco columnas para consulta pública)

El DDL completo, incluyendo índices, triggers, funciones helper y políticas RLS, vive en el archivo `docs/fase-1-schema.sql` del repositorio y se aplica copiándolo en el SQL Editor de Supabase. El archivo es idempotente: las tablas usan `IF NOT EXISTS` y las policies se hacen `DROP-CREATE` para que re-ejecutarlo no falle si ya hay datos.

### 4.1 Auto-creación de perfil

La tabla `users_profile` no es un duplicado de `auth.users` sino una extensión con la lógica del dominio (rol del actor en el sistema). Cuando un usuario hace `signUp`, un trigger `handle_new_user` con `SECURITY DEFINER` inserta automáticamente la fila correspondiente en `users_profile` con `role = 'ciudadano'`. Promover a un usuario a administrador requiere un `UPDATE` manual desde el Table Editor o SQL Editor: ningún cliente puede hacerse admin por sí mismo (la policy `users_profile_self_update` lo prohíbe explícitamente con un `WITH CHECK` sobre el rol).

### 4.2 Privacy by design en SQL

La consulta pública (`/consulta`) muestra solo cinco columnas del report: `radicado`, `delitos`, `band`, `status`, `created_at`. En Fase 0 esto se garantizaba filtrando en JavaScript. En Fase 1 se eleva a nivel SQL mediante una *view*:

```sql
create view public.reports_public
with (security_invoker = true)
as select radicado, delitos, band, status, created_at from public.reports;

grant select on public.reports_public to anon, authenticated;
```

`security_invoker = true` indica que las políticas RLS de la tabla subyacente se aplican respecto al usuario que invoca la view, no al definidor; esto permite que la view pase los chequeos sin necesidad de bypass. El cliente, al consultar, hace `supabase.from('reports_public').select(...)`: aunque escribiera `select('*')` ingenuamente, sólo recibe esas cinco columnas porque otras no existen en la view. La garantía es de motor, no de cliente. Esta expresión SQL de la decisión arquitectónica ADR-06 es uno de los argumentos académicos más fuertes a favor de Supabase frente a Firebase.

### 4.3 Políticas RLS de los reports

Tres políticas controlan el acceso a `reports`. La primera (`reports_anon_insert`) permite al rol anónimo crear denuncias siempre y cuando el insert tenga `is_anonymous = true` y `user_id = null`. La segunda (`reports_authenticated_insert`) permite al usuario autenticado insertar con su uid o de forma anónima. La tercera (`reports_owner_select`) permite a un usuario leer sus propios reports. La cuarta (`reports_admin_all`) da acceso total al admin.

La consecuencia más interesante de este diseño es que **un usuario autenticado que decide denunciar anónimamente no puede consultar su propia denuncia desde `/mis-denuncias`**. La policy filtra por `user_id = auth.uid()`, y la denuncia anónima tiene `user_id = null`. Esto es deliberado: si el usuario pudiera ver su denuncia anónima, la asociación denunciante↔caso se reconstruye y el principio de anonimato se diluye. El trade-off de usabilidad es aceptado por diseño y queda documentado como RSK-54.

### 4.4 Bitácora y configuración

`audit_log` tiene una política `audit_log_insert_any` que permite a cualquier rol (incluyendo anónimos) insertar entradas. La policy de SELECT es admin-only. La motivación es operativa: cada acción del cliente, incluyendo navegaciones anónimas, debe quedar registrable, pero solo el administrador tiene acceso a leer la auditoría completa.

`config` distingue entre keys públicas (`contact`, `authorities_meta`) que pueden ser leídas por anónimos para alimentar la página de contacto y los textos de bandas, y la key `authorities` (correos de las entidades por banda de riesgo) que solo el admin puede leer. La consecuencia es que el cliente anónimo, al enviar una denuncia, no puede resolver desde el server cuáles son las direcciones de las autoridades: las usa desde el cache local (`eco.config.authorities`) que se pobló cuando un admin sincronizó. Esta dependencia se cierra en Fase 3 cuando el envío real de email lo haga una Edge Function server-side con la `service_role` key que sí puede leer todo.

## 5. Autenticación

El módulo `Auth` se refactorizó en STEP-102 en dos implementaciones y un *wrapper*. `LocalAuth` mantiene el comportamiento de Fase 0: cuentas hardcodeadas en `eco.users`, sin verificación de email, sin recuperación real de contraseña. `SupabaseAuth` delega cada operación al cliente Supabase: `signInWithPassword`, `signUp`, `signOut`, `resetPasswordForEmail`, `getSession`, `onAuthStateChange`. El wrapper `Auth` decide en tiempo de invocación cuál delegate usar según `Backend.isSupabase()`.

Una decisión clave fue mantener `Auth.current()` y `Auth.isAdmin()` **sincrónicos**. Esos dos accessors se llaman desde decenas de call-sites del Router, la UI y los handlers; convertirlos a async habría requerido reescribir todos los renders. La solución fue desacoplar la lectura de la escritura: `Auth.current()` lee del `Store` en memoria, y la población del Store se hace en operaciones explícitas (`Auth.restore()` al arranque, `onAuthStateChange` a lo largo de la sesión, `Auth.login()` y `Auth.logout()` que son async pero retornan resultados estructurados). El precio es que durante los primeros milisegundos tras el primer paint, `Auth.current()` devuelve `null` aunque haya sesión persistida; esto se resuelve emitiendo `Bus.emit('auth:login', session)` cuando `restore()` completa, y la UI reaccionando a ese evento.

`onAuthStateChange` mantiene la sesión sincronizada entre pestañas del mismo navegador y tras refresh de token. Si el usuario hace logout en una pestaña, la otra detecta el evento `SIGNED_OUT`, limpia el Store y la UI se actualiza sin necesidad de recargar.

La vista `/iniciar-sesion` se expandió con tres paneles: Login, Crear cuenta y Recuperar contraseña. Las pestañas se renderizan con un indicador visual del backend activo: en modo Supabase desaparece el bloque de cuentas demo y aparece la marca "Backend: Supabase · cuentas reales"; en modo localStorage las cuentas demo siguen visibles. Esta separación visual es importante porque durante la migración progresiva un desarrollador puede estar trabajando con ambos modos simultáneamente y la confusión sería frecuente.

## 6. Auditoría write-through

STEP-106 migró el módulo `Audit` a un patrón **write-through asíncrono no-bloqueante**. La función `Audit.log()` mantiene su retorno sincrónico del entry (lo que evita romper los call-sites) y, si el backend Supabase está activo, dispara un `INSERT` al server con `fire-and-forget` (sin `await`, con `.catch(warn)`). El comportamiento es:

1. La acción se registra inmediatamente en `eco.audit_log` (cache local con cap de 1000 entradas).
2. `Bus.emit('audit:append', entry)` notifica suscriptores en la misma pestaña.
3. Si hay Supabase activo, `_sendToServer(entry)` se ejecuta en background.
4. Si la inserción al server falla, queda un warning en consola; la app sigue funcionando y la entrada vive en el cache local.

Un detalle de robustez: la función valida que el `user_id` sea un UUID válido (regex). En sesiones legacy con uid `u_xxx` de Fase 0, el server vería ese string y rechazaría el insert por violación de foreign key contra `auth.users`. La validación los reemplaza por `null`, lo cual la policy `audit_log_insert_any` acepta.

La consecuencia es que al cabo de cualquier sesión, la tabla `audit_log` de Postgres tiene un registro completo de navegaciones, logins, status_changes, report_sends, config_sets, lookups públicos, etcétera. Ese log es la pieza de evidencia que la tesis presenta como FMEA empírica (qué acciones reales hacen los usuarios contra el sistema). El cap de 1000 entradas locales se queda como buffer; el log de Postgres no tiene cap aplicado en Fase 1 (lo tendrá en Fase 5 con políticas de retención).

## 7. Panel de diagnóstico

STEP-105 introdujo la vista `/admin/diagnostico` como pieza operativa que documenta visualmente el estado de la sincronización entre cliente y server. Incluye:

- Tarjeta de estado del backend (modo, conexión, último ping, estado del canal Realtime, sesión activa con uid+rol)
- Conteos en vivo de `reports`, `users_profile`, `audit_log` desde el server, comparados con el conteo local (renderizado con borde *dashed* para diferenciarlos visualmente)
- Listas de las últimas cinco denuncias, diez usuarios y veinte entradas de `audit_log` leídas directamente del server (no del cache)
- Acciones one-click: wakeup manual, hidratación del cache local desde el server, re-suscripción al canal Realtime

STEP-107 sumó a esta vista un **importador masivo** que migra `eco.reports` (cache local) a la tabla `reports` de Postgres. La operación es idempotente: prefiltra por radicados existentes y los omite. La inserción se hace en *chunks* de doscientas filas para no exceder el límite de payload de la API REST de Supabase. La UI muestra un *preview* con los conteos antes de operar y un progress en vivo durante la migración. Tras completar, llama a `ReportsRepo.refresh()` para que el cache local refleje el estado real del server.

Adicionalmente, el panel ofrece un botón opcional para limpiar el cache local de denuncias. Esto es útil después de una migración para evitar confusión, pero no es destructivo respecto al server: la app re-hidrata el cache al siguiente paint.

## 8. Trade-offs y limitaciones aceptadas

Durante la Fase 1 se documentaron veintidós riesgos nuevos (RSK-45 a RSK-66 si se cuentan los que se identificaron durante las pruebas internas). Los más relevantes:

- **Cada acción del cliente genera un `INSERT` HTTP a `audit_log`.** Para un usuario activo eso significa diez a veinte requests por minuto. El plan gratuito de Supabase soporta esto sin problema, pero en Fase 4 sería razonable agruparlos en *batches* enviados cada cinco segundos o al `beforeunload`. Por ahora se mantiene la simplicidad.
- **`ConfigRepo.set` no implementa optimistic locking.** Si dos administradores editaran la misma key simultáneamente, gana el último. Para una tesis con un administrador único el riesgo es nulo; se acepta.
- **El emisor anónimo no puede leer las direcciones de autoridades del server.** Las usa del cache local; si nunca hubo refresh con admin, el outbox queda sin direcciones. Esto se cierra en Fase 3 con la Edge Function de envío server-side.
- **El cold-start del plan gratuito sigue siendo una molestia operativa.** El panel de diagnóstico mitiga el riesgo en demos planificadas, pero no lo elimina. Una alternativa explorada (un cron público que pingue cada seis días) queda diferida para después de que el dominio público esté en operación.
- **No hay tests automatizados todavía.** ADR-09 sigue vigente; la validación es manual via el protocolo de pruebas en `docs/fase-1-pruebas.md`.

## 9. Validación empírica

La Fase 1 incluyó pruebas internas en dos navegadores simultáneos (Firefox y Chrome de escritorio) y en Safari iOS desde un iPhone, con tres cuentas distintas (un admin, dos ciudadanos, más sesión anónima). Los hallazgos:

- El *cold-start* tras una pausa de siete días tomó dieciocho segundos en el primer ping; el banner ámbar fue visible durante esos dieciocho segundos sin error.
- La sincronización Realtime tras una denuncia anónima desde Chrome se reflejó en `/admin/denuncias` de Firefox en menos de un segundo.
- La policy `reports_authenticated_insert` rechazó correctamente un intento manual desde DevTools de insertar una denuncia con `user_id` de otro usuario.
- La view `reports_public` retornó exactamente las cinco columnas esperadas; un `select('*')` ingenuo desde un cliente anónimo devolvió esas mismas cinco y no más.
- La auditoría capturó cada navegación entre `/admin/dashboard`, `/admin/denuncias` y `/admin/diagnostico` en la tabla `audit_log` con timestamps consistentes.

El protocolo completo de dieciocho escenarios de prueba, con resultado esperado y campo a llenar al ejecutar, vive en `docs/fase-1-pruebas.md` y será usado el día de la defensa de tesis.

## 10. Entrada a Fase 2

Con Fase 1 cerrada, el siguiente bloque del roadmap es Fase 2: storage de evidencias en Supabase Storage con URLs firmadas. La hipótesis a validar es operacional: las evidencias multimedia se manejan correctamente sin saturar el cliente ni el ancho de banda, y son accesibles a las autoridades via links seguros con expiración.

Los STEPs preliminares de Fase 2 son: setup del bucket con políticas de acceso, refactor de la lista de evidencias del cliente para subir directamente a Storage en lugar de embeber en base64 dentro del report, generación de URLs firmadas con caducidad de siete días para las autoridades, política de retención a un año, integración en el body del email que se simula en outbox. Storage queda fuera del alcance de esta memoria.

## 11. Conclusión

El cierre de la Fase 1 confirma la hipótesis operativa: la integración del modelo metodológico (Fase 0) con un backend gestionado real es viable manteniendo single-file en el cliente, retrocompatibilidad con el flujo localStorage y privacy by design expresada al nivel del motor de base de datos. La decisión de Supabase resultó alineada con los criterios académicos de la tesis (RDBMS estándar, RLS declarativa, view como expresión SQL del principio de minimización) y operativos (un único proveedor cubre Auth, DB, Storage, Realtime y Functions).

La capa de abstracción `Backend` + repositorios deja la puerta abierta para revertir a otro proveedor si futuras pruebas con usuarios lo justifican: sólo cambiarían las implementaciones internas, no las API expuestas a los call-sites de la aplicación. Esta propiedad es importante para la defensibilidad de la tesis: si el director de tesis o el jurado solicitan probar con Firebase o con un schema diferente, la migración es localizada.

---

*Documento técnico complementario a la tesis doctoral. Para consultar la implementación, ver `index.html` v0.15.0 y `docs/fase-1-schema.sql` en el repositorio del proyecto. Para el protocolo de QA, ver `docs/fase-1-pruebas.md`.*
