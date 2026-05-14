# Eco-Complaint · Fase 1 · Protocolo de pruebas

**Versión cubierta:** v0.15.0 · STEPs 101-109
**Fecha del documento:** 14 de mayo de 2026
**Audiencia:** Autor del proyecto (autoría dirigida) + lectores de la tesis

---

## 0 · Propósito

Este documento define los **18 escenarios de prueba** que validan empíricamente la hipótesis de Fase 1: *"El sistema escala a múltiples usuarios concurrentes con persistencia real y auth verificada sin perder usabilidad"*. La validación es **manual y dirigida** (el autor es también QA — ver ADR-09); no hay tests automatizados hasta Fase 5.

Cada escenario tiene:
- **Precondición** (estado del sistema antes de empezar)
- **Pasos** explícitos a ejecutar
- **Resultado esperado** verificable
- **Resultado observado** (campo a llenar al ejecutar)

El protocolo culmina con un **checklist pre-defensa** de 7 ítems para validar el día de la defensa de tesis.

---

## 1 · Setup inicial (4 escenarios)

### TEST-1.1 · Clean install funcional

**Precondición:** archivo `index.html` recién clonado, sin credenciales Supabase configuradas (placeholder `TU_SUPABASE_URL` intactos), `eco.*` ausente en localStorage.

**Pasos:**
1. Abrir `index.html` desde GitHub Pages o file://
2. Esperar el primer paint
3. Abrir DevTools → Console
4. Verificar el log de bienvenida

**Resultado esperado:**
- Console muestra `Eco-Complaint · v0.15.0 · ... · backend localStorage` en verde
- `[Backend] Modo localStorage · credenciales Supabase placeholder` aparece en gris
- Banner de cuentas demo visible en `/iniciar-sesion`
- Panel de diagnóstico en esquina inferior derecha muestra `✓ Backend.init · localStorage`
- Ningún error en consola

---

### TEST-1.2 · Schema SQL aplicado correctamente

**Precondición:** proyecto Supabase recién creado, `docs/fase-1-schema.sql` pegado en SQL Editor y ejecutado.

**Pasos:**
1. En Supabase Table Editor, verificar que existen las 4 tablas: `users_profile`, `reports`, `audit_log`, `config`
2. En SQL Editor ejecutar: `select count(*) from public.config;`
3. Ejecutar: `select * from public.reports_public;`
4. Ejecutar: `select * from pg_policies where schemaname = 'public';`

**Resultado esperado:**
- 4 tablas visibles
- `config` count = 3 (authorities, authorities_meta, contact)
- `reports_public` devuelve `0 rows` sin error (la view existe)
- pg_policies devuelve ≥10 policies activas

---

### TEST-1.3 · Credenciales reales activan modo Supabase

**Precondición:** TEST-1.2 OK. Credenciales del proyecto pegadas en `window.__SUPABASE_URL` y `window.__SUPABASE_ANON_KEY`.

**Pasos:**
1. Recargar la app
2. Verificar consola
3. Ir a `/admin/diagnostico` (sin estar logueado primero → debe rechazar; loguearse con admin demo)
4. Observar la tarjeta "Backend activo"

**Resultado esperado:**
- Console: `[Backend] Modo Supabase · https://...` en verde
- Diag panel: `✓ Backend.init · supabase`, `✓ lib: supabase-js@2`
- Tarjeta de diagnóstico: Modo = **Supabase**, Estado = **Listo** o **Conectando→Listo**
- Banner de cuentas demo en `/iniciar-sesion` está oculto, indicador dice "Backend: Supabase · cuentas reales"

---

### TEST-1.4 · Cold-start es visible al usuario

**Precondición:** TEST-1.3 OK. Proyecto Supabase pausado (forzar pausa esperando 7 días o pausando manualmente desde dashboard).

**Pasos:**
1. Recargar la app
2. Observar parte superior de la pantalla durante 30 segundos

**Resultado esperado:**
- Banner gris "Conectando con el servidor…" aparece en <2 s
- A los 2 s pasa a ámbar: "El servidor está despertando. Puede tardar hasta 30 segundos."
- Botón "Reintentar" visible y funcional
- Cuando el server responde, banner desaparece
- Diag panel muestra `wakeup · ✓ XXXX ms` (típicamente 5000-20000 ms tras cold-start)

---

## 2 · Autenticación (5 escenarios)

### TEST-2.1 · SignUp crea usuario y perfil

**Precondición:** TEST-1.3 OK. Email no usado antes.

**Pasos:**
1. Ir a `/iniciar-sesion`, pestaña "Crear cuenta"
2. Llenar: nombre = "Test User", email = `test-{timestamp}@gmail.com`, password = 8+ chars
3. Submit
4. Si email confirmation está activada en Supabase Auth → ver mensaje
5. En Supabase: Table Editor → `users_profile` → buscar el email

**Resultado esperado:**
- Si confirmation OFF: redirect a `/denunciar`, sesión activa
- Si confirmation ON: toast "Te enviamos un correo de verificación a {email}"
- `users_profile` tiene fila con uid (uuid), email, name = "Test User", role = "ciudadano", created_at reciente
- Trigger `handle_new_user` ejecutado correctamente

---

### TEST-2.2 · Login con credenciales válidas

**Precondición:** TEST-2.1 OK (email confirmado si aplica).

**Pasos:**
1. Logout (si hay sesión)
2. Ir a `/iniciar-sesion`, pestaña Login
3. Ingresar email + password
4. Submit

**Resultado esperado:**
- Toast "Bienvenido, Test User"
- Redirect a `/denunciar`
- Botón "user chip" en header muestra inicial y nombre
- `audit_log` de Postgres tiene entrada nueva con `action = 'login'`, `user_id` = uid del usuario
- `Auth.current()` en consola devuelve objeto con uid, email, role, etc.

---

### TEST-2.3 · Login con credenciales inválidas

**Precondición:** TEST-1.3 OK.

**Pasos:**
1. Logout
2. Ingresar email válido + password incorrecto
3. Submit

**Resultado esperado:**
- Toast en rojo: "Correo o contraseña no válidos"
- No redirect, formulario sigue visible
- Botón "Entrar" reactivado tras el fail (no se queda deshabilitado)
- `audit_log` tiene entrada `action = 'login_failed'` con email pero sin user_id
- Después de 5 intentos rápidos: Supabase puede empezar a devolver "rate limit" → toast "Demasiados intentos…"

---

### TEST-2.4 · Logout limpia sesión cross-tab

**Precondición:** logueado en dos pestañas (A y B) del mismo navegador.

**Pasos:**
1. Pestaña A: hacer logout via user chip
2. Pestaña B: hacer cualquier navegación (click en un link interno)

**Resultado esperado:**
- Pestaña A: redirect a `/`, header muestra "Iniciar sesión"
- Pestaña B: el `onAuthStateChange` detecta el signOut y limpia el `Store.session`; en la siguiente render del Router la nav muestra estado sin sesión
- `audit_log` tiene `action = 'logout'` con el uid

---

### TEST-2.5 · Recuperar contraseña

**Precondición:** TEST-2.1 OK, cuenta con email real al que tengas acceso.

**Pasos:**
1. Ir a `/iniciar-sesion`, link "¿Olvidaste tu contraseña?"
2. Ingresar email registrado
3. Submit
4. Revisar inbox del email

**Resultado esperado:**
- Mensaje verde inline: "Si la cuenta existe, recibirás instrucciones por correo."
- Email llega de `noreply@mail.app.supabase.io` (o el sender configurado) con link de reset
- Click en link redirige a `/iniciar-sesion` con flag `?type=recovery` o similar
- `audit_log` tiene entrada `password_reset_request`

---

## 3 · Flujo de denuncia E2E (4 escenarios)

### TEST-3.1 · Denuncia completa autenticada

**Precondición:** sesión activa con cuenta ciudadano.

**Pasos:**
1. Ir a `/denunciar` → empezar
2. Recorrer árbol hasta una ruta terminal (por ej. "tala con financiador")
3. Responder las 5 preguntas CONESA
4. Ingresar ubicación (modo texto: "Sector La Macarena, Caquetá")
5. Subir 1 imagen pequeña (<500 KB)
6. Agregar descripción opcional
7. Revisar resumen
8. Click "Enviar denuncia"

**Resultado esperado:**
- Cada vista del flujo se renderiza sin error
- Botón "Enviar denuncia" muestra estado "Enviando…" durante el await
- Redirect a `/denunciar/enviado` con número de radicado
- En Supabase: `reports` tiene fila nueva con `user_id` = tu uid, `is_anonymous = false`, todos los campos esperados
- `audit_log`: entrada `report_send` con detalles
- En `/admin/diagnostico` la card "Últimas 5 denuncias" la muestra al recargar

---

### TEST-3.2 · Denuncia anónima

**Precondición:** sin sesión.

**Pasos:** mismo que TEST-3.1 pero entrar a `/denunciar` como invitado.

**Resultado esperado:**
- Toda la app permite avanzar sin login
- Banner "Modo invitado" visible durante el flujo
- Insert tiene `user_id = null`, `is_anonymous = true`
- RLS policy `reports_anon_insert` lo permite porque `is_anonymous = true` y `user_id is null`
- **Importante:** verificar en Supabase que el insert efectivamente entró (no fue rechazado por RLS)

---

### TEST-3.3 · Mi denuncia anónima NO aparece en /mis-denuncias

**Precondición:** después de TEST-3.2, login con cuenta ciudadano (cualquiera).

**Pasos:**
1. Ir a `/mis-denuncias`

**Resultado esperado:**
- No aparece la denuncia anónima (porque tiene `user_id = null` y la policy filtra por `user_id = auth.uid()`)
- Esto es por diseño (privacy by design en ADR-06): si la viera, se reconstruye la asociación denunciante↔caso

---

### TEST-3.4 · Rate limit local funciona

**Precondición:** sesión activa.

**Pasos:**
1. Hacer 4 denuncias rápidas en menos de 5 minutos (puedes usar el mismo flujo varias veces)

**Resultado esperado:**
- Las primeras 3 pasan
- La 4ª muestra toast: "Has enviado 3 denuncias en los últimos 5 minutos. Por seguridad esperamos unos minutos antes de aceptar otra…"
- En consola: `eco.rate_limit` tiene 3 timestamps en localStorage
- La 4ª denuncia NO se envía al server (verificable: count en `reports` no aumenta)

---

## 4 · Panel administrativo (3 escenarios)

### TEST-4.1 · Panel admin con datos reales

**Precondición:** TEST-3.1/3.2 ejecutados (≥2 denuncias en el server), sesión admin.

**Pasos:**
1. Ir a `/admin` (dashboard)
2. Verificar KPIs
3. Click en una denuncia → drawer derecho
4. Cambiar status a "Triada"
5. Cerrar drawer, verificar tabla actualizada
6. Ir a `/admin/diagnostico`

**Resultado esperado:**
- KPIs muestran números correctos
- Donut, bars y heatmap renderizan
- Drawer detalle muestra todo: árbol path, probabilidad, ubicación, evidencias, autoridades
- Cambio de status: toast confirmación, drawer se cierra, tabla refleja "Triada"
- En Supabase `reports` la fila tiene `status = 'triaged'` y `updated_at` actualizado por trigger
- `audit_log` tiene `status_change` con from/to
- En `/admin/diagnostico` el conteo `audit_log` aumentó

---

### TEST-4.2 · /admin/config persiste a Postgres

**Precondición:** sesión admin.

**Pasos:**
1. `/admin/config`
2. Cambiar el email de la banda BAJO (agregar uno nuevo en la textarea)
3. Click "💾 Guardar configuración"
4. En Supabase: Table Editor → `config` → key = `authorities`

**Resultado esperado:**
- Botón muestra "⏳ Guardando…" durante la operación
- Toast: "Configuración guardada en Supabase"
- En `config.authorities.value` aparece el email nuevo
- `updated_by` = tu uid
- `updated_at` reciente

---

### TEST-4.3 · RLS bloquea acciones de no-admin

**Precondición:** dos cuentas: A (admin), B (ciudadano).

**Pasos:**
1. Login con B
2. Intentar `/admin` directo via URL
3. Intentar leer `audit_log` desde DevTools (`supabase.from('audit_log').select()`)
4. Intentar update sobre un report ajeno

**Resultado esperado:**
- `/admin` → Toast "Esta sección requiere cuenta administrativa" + redirect a `/`
- `supabase.from('audit_log')` devuelve `data: []` o error de policy (RLS filtró)
- Update sobre report ajeno → error `new row violates row-level security policy`

---

## 5 · Realtime + Privacy by design (2 escenarios)

### TEST-5.1 · Realtime sync entre dispositivos

**Precondición:** dos navegadores (A y B), ambos logueados con admin. Ambos en `/admin/denuncias`.

**Pasos:**
1. Desde una pestaña C (anónima o ciudadano), crear una denuncia
2. Observar A y B sin recargar

**Resultado esperado:**
- A y B reciben el evento `INSERT` del canal `reports-watch`
- La denuncia aparece en la tabla de ambos sin recargar
- Cache local (`eco.reports`) se actualiza en ambos (visible en `/admin/diagnostico` después de recargar)
- En `/admin/diagnostico` → "Realtime: joined"

---

### TEST-5.2 · Consulta pública respeta privacy

**Precondición:** denuncia con radicado conocido + información sensible (ubicación, descripción, evidencias).

**Pasos:**
1. Logout (sin sesión)
2. Ir a `/consulta`
3. Ingresar radicado y consultar

**Resultado esperado:**
- Tarjeta de resultado muestra: radicado, banda, estado, fecha, artículos, timeline
- **NO muestra:** ubicación, evidencias, descripción del denunciante, autoridades específicas, indicador de anonimato
- DevTools Network: el request a `reports_public` solo trae 5 columnas (privacy by design vía VIEW SQL)
- Botones "Copiar radicado" y "Copiar enlace" funcionan

---

## 6 · Checklist pre-defensa de tesis (7 ítems)

Ejecutar en orden el día anterior y el día de la defensa:

| # | Acción | Resultado esperado | ✓/✗ |
|---|---|---|---|
| 1 | Despertar el proyecto Supabase desde dashboard (si pausado) | Badge "Active" verde | |
| 2 | Recargar la app en navegador limpio (incógnito) | Consola muestra v0.15.0 + Supabase verde | |
| 3 | `/admin/diagnostico` → ⚡ Wakeup ahora | Duración <500 ms (no cold-start) | |
| 4 | Verificar conteos del server (reports, users_profile, audit_log) | Cifras > 0 y consistentes | |
| 5 | Crear una denuncia demo en vivo durante la defensa | Aparece en `/admin/diagnostico` en <2 s vía Realtime | |
| 6 | Mostrar `/consulta` con un radicado válido sin sesión | Solo 5 columnas visibles | |
| 7 | Ir a `/admin/config`, mostrar que el email maestro guarda en server | Toast "guardada en Supabase" + verificar en Table Editor | |

---

## 7 · Resultados observados (a llenar)

Cuando ejecutes los tests, documenta aquí los hallazgos. Esto alimenta el capítulo de validación empírica de la tesis.

| TEST | Ejecutado el | Resultado | Notas |
|---|---|---|---|
| 1.1 | | | |
| 1.2 | | | |
| 1.3 | | | |
| 1.4 | | | |
| 2.1 | | | |
| 2.2 | | | |
| 2.3 | | | |
| 2.4 | | | |
| 2.5 | | | |
| 3.1 | | | |
| 3.2 | | | |
| 3.3 | | | |
| 3.4 | | | |
| 4.1 | | | |
| 4.2 | | | |
| 4.3 | | | |
| 5.1 | | | |
| 5.2 | | | |

---

## 8 · Próximas pruebas para Fases siguientes

Los siguientes escenarios entran cuando avancen las fases:

- **Fase 2** · Evidencias en Storage con URLs firmadas: descargar evidencia del email recibido, expiración del link
- **Fase 3** · Envío real de email a autoridades: bandeja real recibe el correo, formato HTML correcto, link al PDF
- **Fase 4** · Performance con 500+ reports: tabla admin se mantiene <1 s al filtrar, charts < 500 ms
- **Fase 5** · Auditoría OWASP: XSS en inputs, IDOR en URLs, accesibilidad WCAG 2.1 AA con axe-core

---

*Documento de QA · complemento de la memoria técnica de Fase 1.*
