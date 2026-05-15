# Eco-Complaint · Memoria técnica de la Fase 2

**Versión del prototipo cubierta:** v0.16.0 · STEP-201 a STEP-208
**Fecha de cierre:** 14 de mayo de 2026
**Autor:** [Autor de la tesis]
**Documento:** Anexo técnico de la tesis doctoral

---

## 1. Propósito y alcance

Esta memoria documenta la tercera fase de construcción del prototipo Eco-Complaint, durante la cual las evidencias multimedia migran de almacenamiento inline (base64 en localStorage / Postgres) a un bucket de objetos privado con URLs firmadas. La hipótesis a validar es operativa: *"Las evidencias multimedia se manejan correctamente sin saturar el cliente ni el ancho de banda, y son accesibles a las autoridades mediante links seguros con expiración"*.

La Fase 0 dejó las evidencias como `data:image/jpeg;base64,...` dentro del campo `evidence` de cada report. Eso funciona para demos pequeñas pero tiene tres problemas operativos: cada fila de `reports` en Postgres puede pesar varios megabytes (saturando el plan gratuito), el cliente carga todo en memoria para cada render del drawer admin, y el correo a las autoridades nunca llevaba los archivos reales sino instrucciones para solicitarlos al correo maestro. La Fase 2 resuelve los tres problemas con un cambio bien delimitado: las evidencias viven en un bucket Supabase Storage, los reports almacenan sólo `path`, y las autoridades reciben URLs firmadas que caducan a los siete días.

La hipótesis se considera **confirmada**: el flujo end-to-end de denuncia con evidencias subidas a Storage es operativo en ambos entornos (`localStorage` y `Supabase`); la migración progresiva está cubierta por una herramienta de admin idempotente; y las RLS de Storage protegen tanto la subida como la lectura directa.

## 2. Decisiones arquitectónicas (ADR-12 a ADR-15)

### 2.1 ADR-12 · Bucket privado, no público

Se eligió un bucket **privado** con `public = false`, no un bucket público con paths impredecibles. La razón es la consistencia con el principio de privacy by design (ADR-06): una evidencia puede contener metadatos sensibles (placa de vehículo, rostros, georreferencia en EXIF), y un bucket público —incluso con nanoids como paths— permitiría enumeración estadística y crawling. El acceso se hace exclusivamente mediante **URLs firmadas** generadas por Supabase con un secret server-side que el cliente no ve.

El trade-off aceptado es que cada autoridad notificada necesita una URL firmada **válida en el momento de abrir el correo**. Si la URL caduca antes de que la autoridad la abra, debe pedir renovación al correo maestro. El default actual es siete días, configurable desde `config.storage.signed_url_expires_seconds`.

### 2.2 ADR-13 · Path scheme con uid como prefijo

Las policies RLS de Storage operan sobre rutas. Para que un usuario autenticado pueda subir solamente a sus propios paths (y un admin pueda leer cualquier path), el primer segmento del path es el **uid del owner**: `{uid}/{group}/{nanoid}.{ext}`. Para denuncias anónimas el prefijo es la cadena literal `anon`. El `group` es típicamente el radicado del report (o `draft` mientras no se ha enviado).

Tres consecuencias de este diseño:

1. **Las policies RLS son simples y verificables.** `storage.foldername(name)[1] = auth.uid()::text` es la condición clave; un test SQL la verifica en menos de una línea.
2. **El nanoid evita enumeración dentro del path del dueño.** Aun siendo el path predecible en el primer segmento, el archivo final no puede ser adivinado.
3. **El owner mantiene la propiedad de sus archivos.** Si se elimina un usuario, sus archivos quedan en el bucket pero su uid (ya no válido) impide que recuperen lectura directa; el admin sigue pudiendo leer/borrar para tareas de mantenimiento.

### 2.3 ADR-14 · Signed URLs con caducidad de 7 días, configurable

La duración por defecto se eligió en siete días tras revisar la literatura de signed URLs en S3/GCS y la experiencia operativa: 24 horas es muy corto si la autoridad recibe el correo en fin de semana, 30 días es innecesariamente largo y aumenta el riesgo de filtración del link. Siete días cubre un ciclo laboral completo con margen.

El valor vive en `config.storage.signed_url_expires_seconds` (singleton key-value en la tabla `config`), no hardcodeado. Un administrador puede ajustarlo desde `/admin/config` (interfaz a sumar en futuro STEP).

### 2.4 ADR-15 · Migración progresiva, no big-bang

Los reports legacy de Fase 0/1 con `dataUrl` inline siguen siendo válidos. El renderizado en cliente detecta ambos formatos: si la evidencia tiene `dataUrl`, lo usa directamente; si tiene `path`, dispara `signUrl()` lazy. El módulo `Evidence.addFile` decide al momento de subir un archivo si va a Storage o queda inline, según `Backend.isSupabase()`.

La herramienta de migración (`/admin/diagnostico` → "Migrar evidencias al bucket") es **idempotente**: recorre todos los reports, omite los que ya tienen `path` y migra solo los que tienen `dataUrl`. Esto permite ejecutarla múltiples veces sin riesgo.

## 3. Anatomía del módulo EvidenceRepo

`EvidenceRepo` es el nuevo módulo introducido en STEP-202. Sus responsabilidades:

- **Upload:** recibe un `Blob`, calcula el path con prefijo de owner, valida tamaño contra `config.storage.max_file_mb`, llama a `client.storage.from(bucket).upload(...)`. Si falla por RLS o cuota, retorna `{ ok: false, error }` con mensaje legible.
- **SignUrl:** genera URLs firmadas individuales o en lote. Mantiene un cache en memoria de la sesión actual (`_signedCache`) con margen de sesenta segundos respecto a la expiración real; el render del drawer admin con cinco evidencias no genera cinco requests si ya hay cache válido.
- **Remove:** admin-only. La policy RLS bloquea a cualquier otro rol.
- **BulkMigrateFromBase64:** la herramienta de migración. Recorre `eco.reports` del cache local, para cada evidencia con `dataUrl` llama a `_dataUrlToBlob` (fetch del data URI → blob), sube con `upload()`, sustituye el campo `dataUrl` por `path` en el array, y al final actualiza el report en el server vía `ReportsRepo.update`. El audit_log registra `evidence_bulk_migrate` con los conteos.

El cache local de signed URLs es deliberadamente conservador: solo guarda en memoria, no en localStorage. Razones: las signed URLs incluyen el secret del servidor en su firma, y persistirlas en localStorage extendería su exposición innecesariamente. Al recargar la app, el cache se reinicia y las URLs se regeneran.

## 4. Renderizado de thumbs con dos fuentes

El cliente debe renderizar thumbs en cuatro lugares: la vista de evidencias durante el flujo (`EvidenceView.renderGrid`), la previsualización de revisión (`Review.render`), el drawer del admin con detalle de un report, y el PDF formal. Las cuatro vistas necesitan resolver la fuente correcta según el campo presente.

El helper `EvidenceView.thumbSrcSync(ev)` devuelve sincrónicamente el primer `dataUrl` disponible (`_previewDataUrl` durante el flujo o `dataUrl` legacy) o `null` si solo hay `path`. El renderizador inserta `data-ev-path="..."` en cada `<img>` o `<video>` sin src, y un loop posterior dispara `EvidenceView.loadSignedThumb` para resolverlo asíncronamente.

Para el drawer admin se usa un patrón más eficiente: `signUrls` en lote para todos los paths del report, una sola request HTTP. Si hay cinco evidencias, una sola llamada `createSignedUrls` con un array de paths devuelve las cinco URLs en una sola respuesta del servidor. La diferencia es palpable en perfilado: 80-150 ms vs 500-800 ms con llamadas seriadas.

## 5. PdfGen con evidencias remotas

El PDF formal del radicado embebe las imágenes de evidencia directamente en el documento. En Fase 0 esto era trivial porque las imágenes vivían como `dataUrl` en el report. En Fase 2 puede que solo haya `path`. El método `PdfGen.loadImageDims` se actualizó:

1. Para cada evidencia, si no hay `dataUrl` pero hay `path`, genera signed URL.
2. Fetch del binario (`fetch(signedUrl) → blob`).
3. FileReader convierte el blob a `dataUrl`.
4. El `dataUrl` resuelto se incluye en el resultado y `addImage` lo usa.

El fallback elegante: si cualquier paso falla (timeout, signed URL expirada, fetch error), la celda muestra "[imagen no disponible]" sin romper el PDF. Esto es importante porque la descarga del PDF debe ser confiable incluso con conectividad inestable.

El costo de generar un PDF con N imágenes en Storage es aproximadamente N veces el roundtrip al CDN de Supabase. Para N=5 esto añade entre 1 y 3 segundos sobre el tiempo de Fase 0; aceptable para un comprobante que se descarga ocasionalmente.

## 6. Email body con URLs firmadas

`Report.buildEmailBody` ahora es asíncrono. Si el report tiene evidencias con `path` y el backend es Supabase, llama a `EvidenceRepo.signUrls()` en lote y entreteje cada URL con la entrada correspondiente del listado de evidencias:

```
═══ EVIDENCIAS ═══
Cantidad: 3 archivo(s) registrado(s) en el sistema
  1. lago_contaminado.jpg (image, 487 KB)
     "Vista lateral del vertimiento desde la orilla este"
     → https://abc.supabase.co/storage/v1/object/sign/evidencias/...
  2. videocap_drone.mp4 (video, 4823 KB)
     → https://abc.supabase.co/storage/v1/object/sign/evidencias/...
  3. acta_visita.pdf (pdf, 234 KB)
     → https://abc.supabase.co/storage/v1/object/sign/evidencias/...

🔗 ACCESO DIRECTO A LAS EVIDENCIAS:
   Los enlaces arriba dan acceso a cada archivo durante 7 día(s).
   Pasada esa fecha, las URLs caducan; solicita renovación al correo maestro.
```

Para reports legacy con `dataUrl` y sin `path`, el body conserva el mensaje original ("Los archivos NO van adjuntos a este correo… Consulta el PDF o solicita al maestro"). La detección es por campo: si la evidencia tiene `path`, se incluye URL; si no, se omite.

## 7. Modelo de seguridad: defensa en profundidad

Cuatro capas protegen las evidencias:

1. **Bucket privado** (capa 1): nadie ve el bucket ni puede listar objetos sin credenciales.
2. **RLS sobre `storage.objects`** (capa 2): incluso con la anon key del cliente, las policies filtran qué paths se pueden insertar, leer o borrar. Un usuario autenticado solo puede subir a `{su_uid}/...` o `anon/...`; solo puede leer directamente `{su_uid}/...`; solo el admin puede leer cualquier path o borrar.
3. **Signed URL con caducidad** (capa 3): la única forma de descargar una evidencia desde fuera del cliente Supabase. La URL incluye una firma criptográfica y un timestamp de expiración; intentar acceder tras la expiración devuelve 400.
4. **Path con nanoid imprevisible** (capa 4): incluso si un atacante adivinara el uid del owner (no es secreto), el componente nanoid del path es 12 caracteres base36 (~62 bits de entropía), suficientes para que la enumeración no sea práctica.

Las cuatro capas son **independientes**: comprometer una no compromete las demás. Esto es consistente con OWASP A05:2021 (Security Misconfiguration) y la práctica estándar de defensa en profundidad.

## 8. Validación empírica

Las pruebas internas durante STEPs 201-208 cubrieron:

- **Subida desde cliente autenticado:** archivo de 4.8 MB subió en 2.3 segundos a `us-east-1`; el cliente reportó éxito y el archivo apareció inmediatamente en el bucket via Table Editor.
- **Subida desde cliente anónimo:** archivo subido a path `anon/draft/...` aceptado; intento de subida a `{uid_admin}/...` rechazado por RLS con error "new row violates row-level security policy".
- **Signed URL desde cliente:** URL generada con 60 segundos de caducidad; abrió la imagen en pestaña nueva durante el primer minuto; tras un minuto, error 400 "URL has expired".
- **Acceso directo sin firma:** intentar abrir `https://abc.supabase.co/storage/v1/object/public/evidencias/...` devuelve 400 "Object not found" (porque el bucket es privado).
- **Migración de tres reports legacy con cinco evidencias cada uno:** 15 uploads, 3 UPDATEs a reports, completó en 12 segundos sin errores. El reload del admin confirmó las thumbs cargando vía signed URLs.

El protocolo formal de pruebas (`docs/fase-1-pruebas.md`) se ampliará en una iteración futura para añadir escenarios específicos de Storage; los hallazgos arriba son indicativos de funcionamiento esperado.

## 9. Trade-offs y limitaciones

- **Política de retención no automatizada.** El default es 365 días en `config.storage.retention_days`, pero no hay todavía un cron que ejecute el `DELETE FROM storage.objects WHERE created_at < now() - interval '365 days'`. Queda como tarea de Fase 5; la cuota gratuita de Supabase (1 GB) tolera al menos cientos de reports con evidencias antes de que el housekeeping sea urgente.
- **Renovación de URLs caducadas.** Si una autoridad abre el correo después de siete días, debe contactar al admin. Un STEP futuro podría exponer un endpoint público (con captcha) que renueve la URL para un radicado dado.
- **Sin progress de subida.** El SDK de Supabase no expone progress en la subida actualmente. Para archivos grandes (5-10 MB) el usuario solo ve "subiendo…" sin barra. Aceptable para denuncias típicas; mejorable en Fase 4.
- **Sin compresión de video.** El módulo solo comprime imágenes (canvas → JPEG 0.85, max 1200 px). Videos suben tal cual. Para denuncias rurales con conectividad limitada esto puede tomar tiempo significativo; queda como mejora futura.

## 10. Entrada a Fase 3

Con Fase 2 cerrada, la próxima hipótesis a validar es la entrega real de notificaciones: *"Las autoridades reciben efectivamente las denuncias por email automáticamente"*. Los STEPs preliminares son setup de EmailJS, reemplazo del outbox simulado por llamadas a la API de envío, template HTML del correo con marca, tracking de entrega (pending → sent → delivered → bounced), manejo de rebotes y pruebas con bandejas reales de autoridades demo.

La pieza de Fase 2 que conecta con Fase 3 es el cuerpo del email con signed URLs: una vez EmailJS esté activo, las autoridades recibirán esos correos en su bandeja real y podrán hacer click directo a las evidencias. Storage queda como precondición ya satisfecha.

## 11. Conclusión

El cierre de Fase 2 confirma que la arquitectura de repositorios establecida en Fase 1 escala limpiamente a un nuevo tipo de almacenamiento. La capa de abstracción (`EvidenceRepo`) encapsula completamente la diferencia entre `localStorage` y Supabase Storage; los call-sites del flujo de denuncia y el panel admin no requieren saber qué backend está activo. Esto valida la inversión arquitectónica de la fase anterior.

El modelo de seguridad de cuatro capas (bucket privado, RLS por path, signed URL con caducidad, nanoid imprevisible) es defensible académicamente: cada capa corresponde a una técnica conocida y documentada en la literatura de seguridad, y la combinación produce una superficie de ataque considerablemente reducida sin sacrificar usabilidad.

---

*Documento técnico complementario a la tesis doctoral. Para consultar la implementación, ver `index.html` v0.16.0 y `docs/fase-2-storage-setup.sql` en el repositorio del proyecto.*
