# Eco-Complaint · Configuración del template HTML en EmailJS

**Fase 3 · STEP-305 · Referencia operativa**

Esta guía detalla cómo configurar el template HTML de EmailJS (dashboard) para que las denuncias se envíen formateadas correctamente a las autoridades. La app envía 9 variables al template; este documento describe qué poner en cada campo del dashboard de EmailJS.

---

## 1. Settings del template

Entra a tu template en https://dashboard.emailjs.com/admin/templates → pestaña **Settings** y configura los campos así:

| Campo | Valor |
|---|---|
| **To Email** | `{{to_email}}` |
| **From Name** | `{{from_name}}` |
| **From Email** | (default · tu email vinculado al servicio Gmail/SMTP) |
| **Reply To** | `{{reply_to}}` |
| **Subject** | `{{subject}}` |
| **CC** | (vacío) |
| **BCC** | (vacío) |

Las llaves dobles `{{...}}` son sintaxis de EmailJS para sustituir variables del request en tiempo de envío. Si pones un valor fijo en lugar de una variable, ese valor se usa siempre y la variable del request se ignora.

---

## 2. Content del template (HTML)

En la pestaña **Content** del template, en el editor de código (no el visual), pega exactamente esto como HTML del email:

```html
<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8">
  <title>{{subject}}</title>
</head>
<body style="margin:0;padding:0;background:#F8FBF5;font-family:-apple-system,'Segoe UI',Roboto,Helvetica,sans-serif;color:#0F1F1A;">
  <table role="presentation" cellpadding="0" cellspacing="0" border="0" width="100%" style="background:#F8FBF5;padding:24px 12px;">
    <tr>
      <td align="center">
        <table role="presentation" cellpadding="0" cellspacing="0" border="0" width="600" style="max-width:600px;background:#FFFFFF;border:1px solid #E5EDE2;border-radius:12px;overflow:hidden;">

          <!-- Header marca -->
          <tr>
            <td style="background:#2EAA70;padding:24px 32px;">
              <div style="font-size:20px;font-weight:700;color:#FFFFFF;letter-spacing:0.02em;">
                🌱 Eco-Complaint
              </div>
              <div style="font-size:13px;color:#DBF0E1;padding-top:4px;">
                Plataforma ciudadana de denuncia ambiental · Ley 2111 de 2021
              </div>
            </td>
          </tr>

          <!-- Radicado + banda -->
          <tr>
            <td style="padding:24px 32px 0 32px;">
              <p style="margin:0;font-size:11px;text-transform:uppercase;letter-spacing:0.08em;color:#8A9590;">
                Nueva denuncia recibida
              </p>
              <h1 style="margin:8px 0 0 0;font-size:22px;color:#0F1F1A;line-height:1.3;">
                Radicado <span style="font-family:'Courier New',Consolas,monospace;color:#1F6F4A;">{{radicado}}</span>
              </h1>
              <p style="margin:12px 0 0 0;font-size:14px;color:#5A6B62;">
                Banda de riesgo: <strong style="color:#0F1F1A;">{{band_label}}</strong>
              </p>
            </td>
          </tr>

          <!-- Cuerpo de la denuncia (texto plano con saltos preservados) -->
          <tr>
            <td style="padding:24px 32px;">
              <pre style="margin:0;padding:16px;background:#F8FBF5;border:1px solid #E5EDE2;border-radius:8px;font-family:'Courier New',Consolas,monospace;font-size:12px;line-height:1.6;color:#0F1F1A;white-space:pre-wrap;word-wrap:break-word;overflow-x:auto;">{{body}}</pre>
            </td>
          </tr>

          <!-- CTA · consulta pública -->
          <tr>
            <td style="padding:0 32px 24px 32px;">
              <table role="presentation" cellpadding="0" cellspacing="0" border="0" width="100%" style="background:#DBF0E1;border-radius:8px;">
                <tr>
                  <td style="padding:16px 20px;">
                    <p style="margin:0 0 8px 0;font-size:13px;color:#1F6F4A;font-weight:600;">
                      🔎 Consulta el estado de esta denuncia
                    </p>
                    <p style="margin:0 0 12px 0;font-size:12px;color:#5A6B62;line-height:1.5;">
                      Cualquier persona con el número de radicado puede ver el estado actualizado del caso (sin información sensible).
                    </p>
                    <a href="{{consulta_url}}" style="display:inline-block;background:#2EAA70;color:#FFFFFF;text-decoration:none;padding:10px 18px;border-radius:6px;font-size:13px;font-weight:600;">
                      Ver estado en línea →
                    </a>
                  </td>
                </tr>
              </table>
            </td>
          </tr>

          <!-- Footer -->
          <tr>
            <td style="padding:16px 32px 24px 32px;border-top:1px solid #E5EDE2;background:#F8FBF5;">
              <p style="margin:0;font-size:11px;color:#8A9590;line-height:1.5;">
                Correo enviado automáticamente a <strong>{{to_name}}</strong> (<a href="mailto:{{to_email}}" style="color:#8A9590;">{{to_email}}</a>)
                por la plataforma <strong>{{from_name}}</strong>.<br>
                Para responder o solicitar información adicional:
                <a href="mailto:{{reply_to}}" style="color:#1F6F4A;font-weight:600;">{{reply_to}}</a>
              </p>
            </td>
          </tr>

        </table>
      </td>
    </tr>
  </table>
</body>
</html>
```

Click en **Save Changes** del dashboard.

---

## 3. Cómo se ve el correo resultante

El receptor (autoridad ambiental) ve:

- **Header verde** con la marca Eco-Complaint y subtítulo legal
- **Radicado destacado** en monospace con número visible y color brand
- **Banda de riesgo** debajo (Bajo / Medio / Alto / Crítico / Extremo)
- **Cuerpo completo** de la denuncia en bloque preformateado (preserva los `═══ DELITOS IDENTIFICADOS ═══` y demás separadores del texto plano que genera la app)
- **Botón verde "Ver estado en línea"** que lleva a `/consulta?radicado=X` en GitHub Pages
- **Footer gris** con info de envío y email de respuesta del maestro

Compatible con Gmail, Outlook, Apple Mail, Yahoo Mail y la mayoría de clientes web. Renderizado de tabla anidada con inline styles para máxima compatibilidad (no usa flexbox, grid, ni CSS externo).

---

## 4. Versión solo texto plano (alternativa)

Si prefieres un correo solo texto (más rápido, sin riesgo de filtros HTML), reemplaza el contenido del template por esto (sin `<html>` ni nada) y guarda como **Plain Text** en EmailJS:

```text
═══════════════════════════════════════════════════
ECO-COMPLAINT · DENUNCIA AMBIENTAL
Ley 2111 de 2021 · Colombia
═══════════════════════════════════════════════════

RADICADO:        {{radicado}}
BANDA DE RIESGO: {{band_label}}
DESTINATARIO:    {{to_name}} ({{to_email}})

───────────────────────────────────────────────────

{{body}}

───────────────────────────────────────────────────

🔎 CONSULTAR ESTADO EN LÍNEA:
   {{consulta_url}}

📬 PARA RESPONDER O SOLICITAR INFORMACIÓN:
   {{reply_to}}

───────────────────────────────────────────────────
Enviado automáticamente por {{from_name}}.
Plataforma ciudadana de denuncia de delitos
ambientales en Colombia.
═══════════════════════════════════════════════════
```

---

## 5. Las 9 variables que la app envía

Para referencia técnica (si quieres modificar el template o crear variantes):

| Variable | Tipo | Ejemplo |
|---|---|---|
| `{{to_email}}` | string | `umata@municipio.gov.co` |
| `{{to_name}}` | string | `Autoridad ambiental` |
| `{{from_name}}` | string | `Eco-Complaint` |
| `{{reply_to}}` | string | `radicacion@eco-complaint.demo.co` |
| `{{subject}}` | string | `[ECO-20260515-330A-0042] Denuncia ambiental · Crítico` |
| `{{radicado}}` | string | `ECO-20260515-330A-0042` |
| `{{band_label}}` | string | `Bajo` / `Medio` / `Alto` / `Crítico` / `Extremo` |
| `{{body}}` | text multilínea | Cuerpo completo con headers `═══`, delitos, ubicación, evidencias, autoridades |
| `{{consulta_url}}` | URL | `https://htc480.github.io/eco-complaint/#/consulta?radicado=ECO-...` |

Las variables vienen de `EmailService._params(item)` en `index.html`. Si necesitas variables adicionales, agrégalas en ese método y en este documento.

---

## 6. Validación tras configurar

1. Guarda los cambios del template en el dashboard de EmailJS
2. Recarga la app
3. Ve a `/admin/config` → "📨 Probar configuración" → ingresa un email
4. Revisa la bandeja del email · debe llegar el correo con el formato descrito en sección 3
5. Si llega bien, prueba con una denuncia real desde `/denunciar` con cuenta de prueba — deben llegar correos formateados a las direcciones de `config.authorities` correspondientes a la banda

Si algún campo viene vacío en el correo recibido, verifica que el template tenga las llaves dobles `{{...}}` exactas (sin espacios extra dentro: `{{ to_email }}` no funciona, debe ser `{{to_email}}`).

---

## 7. Recursos del dashboard de EmailJS

- Lista de templates: https://dashboard.emailjs.com/admin/templates
- History de envíos (para debug): https://dashboard.emailjs.com/admin/history
- Settings del servicio Gmail/SMTP: https://dashboard.emailjs.com/admin
- Quotas y plan: https://dashboard.emailjs.com/admin/account

---

*Guía operativa · complemento de la memoria técnica de Fase 3.*
