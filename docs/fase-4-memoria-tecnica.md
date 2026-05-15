# Eco-Complaint · Memoria técnica de la Fase 4 (incremental)

**Versión del prototipo cubierta:** v0.19.0
**Fecha de cierre:** 15 de mayo de 2026
**Autor:** [Autor de la tesis]
**Documento:** Anexo técnico de la tesis doctoral

---

## 1. Propósito y alcance

Esta memoria documenta una versión **incremental** de la Fase 4 del roadmap original. La hipótesis original era operativa: *"El dashboard admin con datos reales permite gestionar volumen del mundo real (>100 denuncias)"*, con métricas asociadas como carga inicial <3s en 3G simulado y filtros sub-segundo.

El roadmap original proponía migrar a Vite con code-splitting y lazy loading de módulos pesados (Admin, Leaflet, jsPDF). Tras evaluación arquitectónica, esta memoria documenta la **decisión de diferir Vite a Fase 5** (ADR-17 abajo) y describe las optimizaciones aplicables manteniendo el archivo único:

- **Captura de métricas observables** desde la app (timings, eventos, page renders) con visualización en `/admin/metricas`.
- **Audit cross-browser** para que el timeline público se vea desde cualquier navegador (RSK-72 fix).

El alcance es deliberadamente acotado: la fase no introduce optimizaciones especulativas. Mide primero; optimiza solo lo que las mediciones reales muestren como cuello de botella.

## 2. ADR-17 · Vite diferido a Fase 5

### Decisión

No migrar a Vite (ni a otro bundler) en Fase 4. Mantener single-file (ADR-01) y la entrega directa desde GitHub Pages. Reevaluar en Fase 5 si las métricas reales lo justifican.

### Contexto

El roadmap original asumía que Fase 4 requería build step para code-splitting. Esta asunción se hizo en planificación abstracta antes de tener mediciones empíricas. Al llegar al momento de implementar, las preguntas relevantes son:

1. ¿Cuál es el tamaño actual del HTML servido?
2. ¿Cuánto toma el primer paint en condiciones reales?
3. ¿Hay un cuello de botella medible que un bundler resolvería?

El archivo `index.html` pesa aproximadamente **400 KB sin gzip** en v0.19.0 (≈110 KB gzipped sobre HTTP/2 de GitHub Pages). Los SDKs externos (Supabase ESM, Leaflet, jsPDF, EmailJS) cargan diferidos y solo cuando se necesitan. Las pruebas en el dispositivo del autor reportan first paint <1s en conexión doméstica.

### Justificación

**Defensa de tesis.** El single-file es defendible: el jurado puede leer el código completo en una sola pasada, sin necesidad de entender un proceso de build. Cualquier afirmación de la tesis puede verificarse abriendo el archivo. Un bundle minificado y code-split rompe esa propiedad.

**Operación.** El flujo "abrir el archivo en cualquier navegador → funciona" es el caso de uso real para el director de tesis durante revisiones. Un build step introduce un paso entre el código y el resultado, lo cual rompe ese flujo.

**Costo vs beneficio.** Vite no es gratis: añade `package.json`, `node_modules`, configuración, posibles incompatibilidades con el código actual (módulos como objetos planos sin `import`), y un pipeline de despliegue. El beneficio (code-splitting) solo aplica si efectivamente hay cuello de botella. No lo hay con los datos actuales.

**Reversibilidad.** Si en Fase 5 las pruebas con usuarios reales muestran first paint >3s o tiempos de interacción altos, la migración a Vite es localizada: el código está organizado en módulos como objetos que se pueden separar a archivos sin reescribir lógica. La inversión arquitectónica está hecha; el packaging se cambia cuando se necesite.

### Consecuencias aceptadas

- El HTML cargará en su totalidad en cada visita, incluyendo código admin que un ciudadano nunca usa. Es ~30% del peso total. Con HTTP caching agresivo de GitHub Pages (Cache-Control con ETag), la segunda carga es desde memoria del navegador.
- Las optimizaciones de Fase 4 no incluyen virtualización de tabla admin ni lazy loading dinámico. Si el dashboard admin se vuelve lento con >500 denuncias, se aborda con paginación cliente (~30 líneas de JS) antes de considerar bundler.

## 3. Captura de métricas observables

### Módulo `Metrics`

Nuevo módulo `Metrics` con tres tipos de entrada:

- **`timing(name, durationMs, context)`** — operación con duración medida (wakeup del backend, refresh de reports, envío de email, render de página).
- **`event(name, context)`** — evento discreto sin duración (denuncia enviada, login, navegación a una ruta clave).
- **`page` entries** — capturadas automáticamente por `Router.recordPageStart`/`recordPageRender` que envuelven cada navegación.

Los datos viven en `localStorage` bajo `eco.metrics` como ring buffer de 500 entradas. No salen del navegador (no se envían a Sentry, Highlight ni analytics externos). La intención es académica: para el capítulo de validación empírica de la tesis, el autor puede exportar el JSON y graficar tiempos reales observados en uso normal.

### Helper `measureAsync`

```js
async measureAsync(name, fn, context) {
  const t0 = this.measureStart();
  try {
    const r = await fn();
    this.measureEnd(t0, name, Object.assign({ ok: true }, context || {}));
    return r;
  } catch (e) {
    this.measureEnd(t0, name, Object.assign({ ok: false, error: e.message }, context || {}));
    throw e;
  }
}
```

Permite envolver cualquier promesa para medir su duración sin contaminar el call-site con código de timing. No se usa todavía masivamente; queda disponible para futuros refactores.

### Puntos conectados

Las métricas capturan cuatro flujos críticos:

1. **`app_init`** — tiempo desde `performance.timing.navigationStart` hasta el final de `init()`. Indica boot total.
2. **`backend_wakeup`** — duración del ping a Supabase. Si supera 5000 ms, indica cold-start del plan gratuito.
3. **Page renders** (`type='page'`) — duración entre `Router.resolve` y el final del binding de vista. Si una ruta tarda >500 ms consistentemente, vale optimizar esa vista específica.
4. **`emailjs_send`** — duración del round-trip al SDK de EmailJS. Útil para saber si los correos a autoridades son rápidos o si están saturando el plan free de 200/mes.
5. **`report_sent`** (evento) — cada denuncia exitosa, con banda + emails + evidence count en contexto. Permite agregados como "cuántas denuncias por banda" para la tesis.

### Vista `/admin/metricas`

Tres bloques:

- **Timings agregados**: tabla con tipo, nombre, count, avg, min, max en milisegundos. Si avg de `backend_wakeup` es >1000 ms, el admin sabe que el proyecto Supabase está fríamente despierto.
- **Contadores de eventos**: tabla con nombre del evento y conteo total. Permite ver "100 denuncias enviadas en la sesión actual" como métrica de uso.
- **Últimas 50 entradas crudas**: timestamp, tipo, nombre con duración, contexto JSON. Útil para inspección detallada o reproducir un caso específico.

Botones de **exportar JSON** (descarga el ring buffer completo) y **limpiar** (reset entre demos). El export es lo que el autor usará para la tesis: una sesión de pruebas con usuarios produce un JSON con 100-500 entradas timestamped que se analizan offline.

## 4. Audit cross-browser (RSK-72 fix)

### Problema

`PublicLookup.search` mostraba el timeline de cambios de estado leyendo `eco.audit_log` de localStorage. Funcionaba **solo en el browser que ejecutó el cambio**: en modo Supabase, cualquier otro navegador (incluyendo el del denunciante anónimo que consulta) veía un timeline incompleto.

### Solución

Tres piezas en conjunto:

1. **View SQL `public.status_changes_public`** con `SECURITY INVOKER` que proyecta solo cuatro campos del audit_log: `radicado`, `changed_at`, `new_status`, `previous_status`. Excluye `user_id`, IP, user_agent, y cualquier otro detalle. La projección selectiva expresa privacy by design (ADR-06) al nivel del motor.

2. **Policy `audit_log_public_status_changes`** que permite a anónimos y autenticados hacer SELECT sobre `audit_log` filtrando por `entity='report' AND action='status_change' AND details ? 'to'`. La policy original `audit_log_admin_read` permanece intacta para lectura completa desde admin.

3. **`AuditRepo.statusChangesFor(radicado)`** consulta la view en modo Supabase y el cache local en modo localStorage. En ambos casos retorna la lista ordenada ascendente por timestamp.

`PublicLookup.search` ahora hace `Promise.all([publicLookup, statusChangesFor])` y pasa la lista mergeada a `renderResult`. El renderResult mantiene un fallback al cache local si la lista del server llega vacía (defensivo).

### Privacidad expuesta

La view expone:
- `changed_at` (timestamp del cambio)
- `new_status` (uno de los cuatro estados válidos)
- `previous_status` (idem o null)

**No** expone: quién hizo el cambio, desde dónde, qué razón. Aceptable porque el estado actual del reporte ya es público vía `reports_public` y los timestamps de cambio solo revelan la cadencia de gestión de la entidad operadora, no la identidad del operador.

## 5. Trade-offs y limitaciones

- **Las métricas son locales por diseño.** No se sincronizan a Supabase ni a un agregador externo. La tesis se valida con la exportación JSON manual del autor. Para producción real se migraría a un APM (Sentry, Highlight) en Fase 5.
- **Ring buffer de 500 entradas** puede no ser suficiente para una sesión muy larga de defensa. Si excede, se descartan las más antiguas. Tamaño configurable vía `Metrics.CAP`.
- **No hay correlación entre métricas locales y el audit_log de Postgres.** El audit registra acciones; las métricas registran tiempos. Son dimensiones distintas que conviene mantener separadas: el audit es legal, las métricas son operativas.
- **La view pública de status_changes solo expone status_change.** Otras acciones del audit (login, navigate, config_set) siguen siendo admin-only. Defensible: las acciones internas del admin no deben filtrarse.

## 6. Entrada a Fase 5

Con Fase 4 cerrada en su versión incremental, la próxima hipótesis a validar es de seguridad y cumplimiento: *"El sistema es seguro y cumple normas mínimas (habeas data, accesibilidad)"*. Los STEPs preliminares son:

- Auditoría OWASP Top 10 (XSS, IDOR en signed URLs, CSRF en formularios, etc.)
- hCaptcha o reCAPTCHA en consulta pública y registro
- Rate limit server-side con Supabase App Check
- Compliance Ley 1581 de 2012 (Habeas Data Colombia): consentimiento explícito, política de tratamiento, derecho al olvido
- WCAG 2.1 AA con axe-core, lectores de pantalla
- Snyk / Dependabot
- Penetration test informal
- Política de seguridad pública (`security.txt`, responsible disclosure)

**Vite reentra a la discusión en Fase 5 si las pruebas WCAG/performance requieren critical CSS extraction, tree-shaking u otras optimizaciones difíciles de hacer en single-file.** Hasta entonces, la arquitectura actual se considera adecuada.

## 7. Conclusión

Esta fase introduce dos cosas pequeñas pero significativas:

- **Observabilidad mínima**: el sistema ahora reporta su propio comportamiento. Antes, "rápido" o "lento" eran impresiones subjetivas; ahora hay números que la tesis puede citar con autoridad.
- **Privacidad del timeline cross-browser**: la consulta pública refleja el estado real del reporte desde cualquier dispositivo, no solo desde el del admin que hizo el cambio.

La decisión más interesante de esta fase es **no hacer Vite**. La fase original lo asumía como dado; la implementación real demostró que es una optimización especulativa sin evidencia que la respalde. Diferir la decisión a Fase 5 con datos en mano es buen ingeniería y mejor defensa de tesis: lo que se hace, se justifica con números.

---

*Documento técnico complementario a la tesis doctoral. Para consultar la implementación, ver `index.html` v0.19.0 + `docs/fase-3-audit-public-view.sql` en el repositorio del proyecto.*
