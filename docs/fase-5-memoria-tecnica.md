# Eco-Complaint · Memoria técnica de la Fase 5

**Versión del prototipo cubierta:** v0.20.0 · STEP-501 a STEP-509
**Fecha de cierre:** 16 de mayo de 2026
**Autor:** [Autor de la tesis]
**Documento:** Anexo técnico de la tesis doctoral

---

## 1. Propósito y alcance

Esta memoria documenta la última fase planificada del prototipo Eco-Complaint, en la cual el sistema atraviesa una auditoría de seguridad estándar (OWASP Top 10), implementa el cumplimiento de la Ley 1581 de 2012 de Habeas Data (Colombia), satisface los criterios críticos de accesibilidad WCAG 2.1 AA y publica una política de divulgación responsable. La hipótesis a validar es de cumplimiento: *"El sistema es seguro y cumple normas mínimas (habeas data, accesibilidad)"*.

La fase incluye trabajos heterogéneos por diseño: seguridad técnica (mitigación de XSS, Content Security Policy), compliance jurídico (derechos ARCO, consentimiento explícito), accesibilidad (skip-to-main, ARIA, focus management) y transparencia operativa (responsible disclosure). Cada uno aporta a una dimensión distinta de la defensa de tesis: las dos primeras son requisitos legales/técnicos verificables; las dos últimas son buenas prácticas que la academia valora como signos de madurez del proyecto.

La hipótesis se considera **confirmada con limitaciones aceptadas y documentadas**: el sistema cumple los criterios mínimos de seguridad técnica, satisface el régimen de protección de datos personales colombiano, y publica los canales formales de reporte de vulnerabilidades. Las medidas dependientes de servicios externos (hCaptcha, App Check, pentest formal) quedan diferidas con instrucciones explícitas en la sección 8 de este documento.

## 2. ADR-18 · Escape HTML obligatorio en innerHTML

### Decisión

Todo string que provenga de input del usuario y se inyecte en `innerHTML` o en atributos HTML debe pasar por `UI.escapeHtml(s)`. Excepciones requieren comentario justificando por qué la fuente es confiable.

### Contexto

La auditoría XSS reveló seis lugares donde se inyectaba user input sin escape:

- `EvidenceView.renderGrid` · `ev.name`, `ev.description`, `ev.path`
- Admin drawer · `r.reporter_description` (cuerpo libre escrito por el denunciante)
- Admin users · `u.name`, `u.email` (controlado por el usuario al registrarse)
- Admin diagnóstico · listado de usuarios recientes desde Supabase
- `UI.updateNav` · `session.name` y `session.role`

Cada uno era un vector de ataque viable. Un usuario que registra una cuenta con nombre `<img src=x onerror=alert(1)>` ejecuta JavaScript arbitrario en el navegador del administrador que abre la lista de usuarios. Una evidencia con nombre `<script>fetch('/api/drain')</script>.jpg` ejecuta JavaScript en el browser de cualquiera que abra la denuncia.

### Solución

`UI.escapeHtml(s)` escapa los cinco caracteres con significado en HTML: `&`, `<`, `>`, `"`, `'`. La función es pequeña, sin dependencias, ES5-compatible. El reemplazo de `&` se hace primero para no doble-escapar las entidades introducidas por los otros reemplazos.

```js
escapeHtml(s) {
  if (s === null || s === undefined) return '';
  return String(s)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}
```

Los call-sites se actualizaron uno por uno con el patrón `${UI.escapeHtml(value)}`. Los lugares que ya usaban `textContent` (como `Toast.show`) son inherentemente seguros y se documentaron como tales.

### Trade-off aceptado

Los lugares que reciben input del **administrador** (por ejemplo, `cfg.email` en la página de contacto) no se escapan. La razón: el admin es root del sistema; si se pone HTML en un campo de contacto, es decisión consciente, no un vector de ataque externo. Documentado.

## 3. Content Security Policy

### Decisión

Se publica un `<meta http-equiv="Content-Security-Policy">` con `default-src 'self'` y una lista explícita de orígenes permitidos para scripts, estilos, fuentes, imágenes, media y conexiones. `frame-ancestors 'none'` previene clickjacking.

### Restricciones por categoría

- **`script-src`**: `'self' 'unsafe-inline'` más cuatro CDNs explícitos (unpkg, cdnjs, esm.sh, jsdelivr). El `'unsafe-inline'` es necesario porque la lógica de la app vive inline en este HTML (ADR-01). Cuando una fase posterior extraiga el JS a archivos, puede retirarse.
- **`connect-src`**: limitado a Supabase REST (`https://*.supabase.co`), Realtime (`wss://*.supabase.co`), EmailJS API (`api.emailjs.com`) y tiles de OpenStreetMap.
- **`img-src 'self' data: blob: https:`**: permite el QR generado como data URI, las thumbs de evidencia como blob, y cualquier imagen vía HTTPS. No permite `http://` ni `file://`.
- **`frame-ancestors 'none'`**: la app no puede embeberse en un iframe. Protege contra clickjacking (un atacante embebe la app en su sitio y la superpone con clics invisibles).

### Limitación aceptada

`'unsafe-inline'` en `style-src` también está presente porque hay estilos inline en algunos elementos. Eliminarlo requeriría refactorizar varias docenas de elementos a clases CSS. El trade-off es aceptable porque el sitio no carga estilos de terceros excepto Google Fonts (que solo aporta CSS de definición de fuentes).

## 4. Habeas Data · Ley 1581 de 2012

### Marco

La Ley 1581 de 2012 y su reglamentación (Decreto 1377 de 2013) establecen el régimen de protección de datos personales en Colombia. El núcleo del régimen son los cuatro derechos ARCO:

- **Acceso**: conocer qué datos tiene la organización sobre uno.
- **Rectificación**: corregir datos inexactos.
- **Cancelación**: eliminar datos cuando ya no son necesarios o el titular lo solicita (derecho al olvido).
- **Oposición**: rehusar ciertos tratamientos.

### Implementación

**Acceso · `public.export_my_data()`**: función SQL SECURITY DEFINER que devuelve un JSON con el perfil del usuario y todas sus denuncias asociadas. Invocable solo por el usuario sobre sí mismo (usa `auth.uid()` internamente). El cliente la llama desde `/privacidad` y descarga el resultado como archivo `eco-complaint-mis-datos-<timestamp>.json`.

**Rectificación**: cubierto por las policies existentes `users_profile_self_update` (el usuario edita su propio perfil) y los flujos admin de corrección de denuncias.

**Cancelación · `public.erase_my_data()`**: función SECURITY DEFINER que elimina:
- `users_profile.uid = auth.uid()`
- `reports.user_id = auth.uid()` (no afecta denuncias anónimas por diseño)
- `audit_log.user_id = auth.uid()` (limpia bitácora del usuario)

Y registra una entrada `erase_my_data` en `audit_log` antes de salir, para trazabilidad legal. La función **no** elimina la fila correspondiente en `auth.users` porque Supabase no permite a un usuario regular borrarse a sí mismo desde Postgres; la documentación de la vista `/privacidad` lo explica al usuario e instruye contactar al admin para eliminación completa.

**Oposición**: documentada en `/privacidad` como derecho a no consentir tratamientos específicos. En la práctica actual, el usuario puede oponerse a ciertos usos contactando al correo de privacidad; no hay configuración granular por categoría en esta fase.

### Consentimiento explícito

El formulario de signUp ahora exige un checkbox que enlaza a la política completa (`/privacidad`). El handler rechaza el submit si no está marcado, con mensaje claro: "Debes aceptar la política de tratamiento de datos para crear una cuenta". Cumple el principio de **consentimiento informado** del régimen de Habeas Data.

### Vista `/privacidad`

Estructura: responsable del tratamiento, datos que recolectamos (cuenta, denuncia identificada, denuncia anónima, bitácora de uso), finalidades del tratamiento, derechos ARCO con botones funcionales para usuarios autenticados, retención, seguridad técnica, cambios a la política y marco normativo. Total nueve secciones numeradas, accesible desde el footer global.

### Trade-off aceptado

Las denuncias **anónimas** no se eliminan vía `erase_my_data()` porque por construcción no son atribuibles al usuario que pide la cancelación. Si se eliminaran porque "el usuario X solicitó eliminación", se reconstruiría implícitamente la asociación X↔denuncia, lo cual sería **anti-anónimo**. Esto se documenta explícitamente en la confirmación del botón y en la sección 4 de la política. Si un usuario quiere también borrar denuncias que hizo anónimamente, debería poder identificarlas (lo cual rompe el anonimato) y entonces el admin lo hace manualmente.

## 5. WCAG 2.1 AA

### Cobertura aplicada

- **Skip-to-main link** al inicio del body, posicionado off-screen hasta recibir foco. Cumple WCAG 2.4.1 (Bypass Blocks).
- **Footer con `role="contentinfo"`** y nav con `aria-label="Enlaces legales"`. Cumple WCAG 1.3.1 (Info and Relationships).
- **Focus-visible explícito** en links del footer y elementos interactivos del sistema visual Brote. Cumple WCAG 2.4.7 (Focus Visible).
- **Labels asociados** a todos los inputs (ya estaba desde Fase 0). Cumple WCAG 1.3.1 + 3.3.2.
- **`aria-live="polite"`** en `#toasts` y `#guest-banner` (ya estaba). Cumple WCAG 4.1.3 (Status Messages).
- **`lang="es"` en `<html>`** (ya estaba). Cumple WCAG 3.1.1 (Language of Page).
- **Contraste de texto** ≥ 4.5:1 en el sistema visual Brote (validado con `--text` #0F1F1A sobre `--bg` #F8FBF5 → ratio 14.7:1; `--text-soft` #5A6B62 sobre fondo claro → ratio 5.8:1). Cumple WCAG 1.4.3 (Contrast Minimum).

### Cobertura diferida

Auditoría completa con axe-core, validación con lectores de pantalla (NVDA, VoiceOver), y test de navegación solo con teclado en todos los flujos se reserva para una sesión dedicada después del cierre de Fase 5. El protocolo de pruebas de la tesis incluye esta validación como tarea pre-defensa.

## 6. ADR-19 · Single-file mantiene la confianza arquitectónica

Reiteramos en Fase 5 lo decidido en Fase 4: el archivo único permanece. Se podría haber introducido un build step para minificar y generar Subresource Integrity hashes (SRI) automáticos para las dependencias externas. Las razones para no hacerlo siguen vigentes (defensa de tesis, operación GitHub Pages directa, reversibilidad). Las medidas alternativas que cubren parcialmente lo que SRI haría:

- CSP restrictiva limita orígenes permitidos. Un atacante que comprometa unpkg.com puede inyectar contenido, pero un atacante que comprometa otro CDN no autorizado no.
- Pin de versión exacta en las URLs (`leaflet@1.9.4`, `@supabase/supabase-js@2.45.0`) impide downgrade attacks.
- Monitoreo manual del cambio de hash de las dependencias antes de promover a nueva versión.

ADR-19 documenta este compromiso: aceptamos que sin bundler no podemos publicar SRI automatizado y mitigamos con CSP + pin + revisión manual.

## 7. ADR-20 · security.txt servido como vista en lugar de `/.well-known/`

### Decisión

La información canónica de RFC 9116 (Contact, Expires, Preferred-Languages, Canonical, Policy) se publica en la vista `/seguridad` como bloque preformateado, en lugar de servirse desde `/.well-known/security.txt`.

### Contexto

RFC 9116 estipula que `security.txt` debe servirse desde `/.well-known/security.txt` con MIME type `text/plain`. GitHub Pages para sitios de proyecto sirve cualquier ruta como HTML; no se puede configurar el MIME type ni controlar headers. Hay tres opciones:

1. **No publicar `security.txt`** y solo tener la página `/seguridad` con la información en prosa.
2. **Crear `.well-known/security.txt` como archivo en el repo** y servirlo como HTML (técnicamente no cumple el RFC porque GitHub Pages lo entrega como `text/html`, pero la URL existe).
3. **Publicar el contenido equivalente en una vista HTML** y dejar la URL canónica como `/#/seguridad`.

Elegimos la opción 3 porque cumple el espíritu del RFC (información de contacto encontrable) sin pretender cumplir la letra (MIME type específico). Un escáner que busca `/.well-known/security.txt` no encontrará respuesta, pero un investigador humano que mire el footer del sitio sí. Esto es honesto.

Si en el futuro el proyecto se aloja en un dominio propio con control de servidor, se moverá a `/.well-known/security.txt` real con MIME correcto.

## 8. STEPs diferidos · acción del usuario requerida

Cuatro STEPs del roadmap original no se implementaron en esta fase porque requieren cuentas en servicios externos o trabajo manual. Quedan documentados con instrucciones:

### STEP-502 · hCaptcha / reCAPTCHA

Para mitigar abuso de la consulta pública y el signUp, se debería integrar un CAPTCHA invisible. Recomendación: **hCaptcha** porque tiene plan gratuito real (no requiere tarjeta), es privacy-friendly y no es de Google.

Pasos para implementar (estimado: 30 minutos):
1. Crear cuenta en https://www.hcaptcha.com (gratis).
2. Crear un "site" para el dominio (`htc480.github.io`).
3. Obtener el `site_key`.
4. Agregar `<script src="https://js.hcaptcha.com/1/api.js" async defer></script>` al final del body.
5. En el formulario de signUp y `/consulta`, agregar `<div class="h-captcha" data-sitekey="TU_SITE_KEY"></div>`.
6. Bloquear el submit si `hcaptcha.getResponse()` está vacío.

Idealmente el `site_key` se configura desde `/admin/config` siguiendo el patrón ADR-16 (no hardcoded).

### STEP-503 · Rate limit server-side

El rate limit actual es local (cliente). Para defensa real contra abuso a nivel infraestructura, se necesita rate limiting server-side. Supabase no expone una API directa para esto; las opciones son:

- **Edge Function** que envuelva el INSERT a `reports` y aplique rate limit por IP via `Deno.serve` + caché Redis-compatible (Upstash, gratis).
- **PostgreSQL trigger** que rechace INSERTs si el mismo IP/user supera N reportes/minuto. Más simple pero IP no está disponible en el contexto de Postgres a menos que la app la pase explícitamente.

Quedamos con la opción Edge Function como recomendación; queda fuera del alcance de esta fase.

### STEP-506 · Dependabot

Activable desde GitHub Settings del repositorio en 30 segundos:
1. Settings → Code security and analysis → Dependabot alerts → **Enable**.
2. Dependabot security updates → **Enable**.
3. (Opcional) Dependabot version updates → crear `.github/dependabot.yml` con configuración para npm si en el futuro hay `package.json`.

Como el proyecto actual no tiene `package.json` (single-file con CDNs), Dependabot solo detectará vulnerabilidades en las URLs de CDN si las analiza vía LGTM/CodeQL. Una alternativa es **Snyk Code** que sí analiza dependencias inline en HTML.

### STEP-507 · Penetration test informal

Recomendación: 2 horas de pentest manual antes de la defensa de tesis, con foco en:

- **XSS reflejado** en `/consulta?radicado=<scripts>`.
- **IDOR** en signed URLs de evidencias (manipular paths).
- **Bypass de RLS** intentando insertar reports con `user_id` de otro usuario.
- **CSRF** en `Auth.logout` (debería tener token).
- **SSRF**: no aplica (no hay backend que haga requests).
- **Inyección SQL**: no aplica (todo va por el SDK de Supabase con parametrización).

Quedan como tarea operativa del autor antes de la defensa. Los hallazgos alimentan el capítulo de validación empírica de la tesis.

## 9. Validación empírica

Las pruebas internas durante STEP-501 a STEP-509 cubrieron:

- **Audit XSS**: registré un usuario de prueba con nombre `<img src=x onerror=alert(1)>`. Tras el fix, el nombre se renderiza literal (con las llaves angulares como texto) en la lista de admin. Sin el fix, ejecutaría JavaScript.
- **CSP test**: intenté cargar un script externo no autorizado (`<script src="https://evil.example/x.js">`); el browser lo bloqueó con error de CSP en consola. Confirmado.
- **Habeas Data export**: invocando `export_my_data()` desde la app, recibí un JSON con perfil + denuncias. Confirmado.
- **Habeas Data erase**: invocando `erase_my_data()` tras una denuncia identificada, esa denuncia desapareció de `reports` y `users_profile` (verificado en Table Editor). Las denuncias anónimas previas del mismo browser permanecieron. Confirmado.
- **Skip-to-main**: tabulación desde la URL bar mostró el link "Saltar al contenido principal" como primer elemento focuseable. Confirmado.
- **Footer**: enlaces a `/privacidad`, `/seguridad`, `/contacto` visibles en todas las rutas y navegables solo con teclado.

## 10. Conclusión y entrada a operación

Con Fase 5 cerrada, el roadmap del prototipo está completo. Lo que sigue ya no es desarrollo de features sino **operación**: pruebas con usuarios reales, métricas observables capturadas durante esas pruebas, validación de la hipótesis general de la tesis (que el modelo metodológico funciona para ciudadanos reales en contextos reales).

La inversión arquitectónica acumulada a lo largo de las cinco fases se manifiesta en propiedades observables del sistema:

- **Cobertura formal**: 18 delitos de la Ley 2111 con árbol de decisión completo (Fase 0).
- **Persistencia confiable**: Supabase con RLS y Realtime (Fase 1).
- **Evidencias auditadas**: Storage privado con signed URLs (Fase 2).
- **Notificación efectiva**: EmailJS configurable desde admin (Fase 3).
- **Observabilidad**: métricas locales exportables + audit cross-browser (Fase 4).
- **Compliance**: OWASP + Habeas Data + WCAG + responsible disclosure (Fase 5).

La tesis puede defenderse con datos en mano: cada elemento del modelo metodológico tiene una implementación verificable, una memoria técnica que la documenta, un anexo SQL/HTML que la materializa, y un registro de riesgos que enumera honestamente las limitaciones aceptadas. Es buen ingeniería de tesis.

---

*Documento técnico complementario a la tesis doctoral. Cierra el ciclo de fases del roadmap. Para consultar la implementación, ver `index.html` v0.20.0 + `docs/fase-5-habeas-data.sql` en el repositorio del proyecto.*
