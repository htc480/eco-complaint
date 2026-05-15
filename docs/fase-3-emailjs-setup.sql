-- =============================================================================
-- Eco-Complaint · Fase 3 · Configuración pública de EmailJS · STEP-301
-- =============================================================================
-- Aplicación:
--   1. Asegúrate de haber aplicado primero docs/fase-1-schema.sql.
--   2. Abre SQL Editor → New query → pega este archivo → Run.
--   3. Verifica con:
--        select policyname from pg_policies
--          where schemaname='public' and tablename='config';
--      Debe aparecer la policy "config_public_read" actualizada incluyendo
--      'emailjs' además de 'contact' y 'authorities_meta'.
--   4. Ve a /admin/config en la app y configura los 3 valores de EmailJS
--      (service_id, template_id, public_key) desde la nueva sección.
--
-- Justificación · ADR-16:
--   Las credenciales de EmailJS NO son secretas en el cliente:
--     - public_key: pública por diseño (igual que la anon key de Supabase)
--     - service_id: identificador de servicio configurado en el dashboard
--     - template_id: identificador del template HTML del email
--   El secreto real (el password de la cuenta SMTP/Gmail/SendGrid conectada
--   a EmailJS) vive en el dashboard de EmailJS y nunca se expone al cliente.
--   Permitir lectura anónima es necesario para que un denunciante anónimo
--   pueda enviar emails sin requerir login.
--
-- Adicionalmente, esta migración hace 'authorities' legible públicamente
-- (RSK-61). Las direcciones de correo de UMATA, CAR, ANLA, Fiscalía,
-- MinAmbiente, Policía Ambiental son emails INSTITUCIONALES públicos
-- (los publica el Estado en sus páginas de contacto). El secreto del
-- sistema está en QUÉ se denuncia, no en A QUIÉN se notifica.
-- =============================================================================


-- 1 · Actualizar policy de SELECT en config para incluir 'emailjs' y 'authorities'
drop policy if exists "config_public_read" on public.config;
create policy "config_public_read"
  on public.config for select
  using (key in ('contact', 'authorities_meta', 'authorities', 'emailjs', 'storage'));


-- 2 · Seed inicial de la key emailjs (vacío · el admin lo completa desde la UI)
insert into public.config (key, value) values
  ('emailjs', '{
    "service_id": "",
    "template_id": "",
    "public_key": "",
    "enabled": false
  }'::jsonb)
on conflict (key) do nothing;


-- =============================================================================
-- 3 · NOTAS POST-APLICACIÓN
-- =============================================================================
--
-- A. Después de aplicar este script, ve a la app:
--      /admin/config → sección "Notificaciones por correo (EmailJS)"
--    Pega los 3 valores que te dio EmailJS y haz click en "Guardar".
--    Después usa "Probar configuración" para enviar un email de prueba.
--
-- B. Template HTML de EmailJS (referencia):
--    El template debe aceptar como variables (entre llaves dobles):
--      {{to_email}}, {{to_name}}, {{from_name}}, {{subject}},
--      {{radicado}}, {{band_label}}, {{body}}, {{consulta_url}}
--    Si tu template usa otros nombres, ajusta EmailService._params() en
--    el cliente para mapear correctamente.
--
-- C. Cuotas del plan free de EmailJS (Mayo 2026):
--    200 emails/mes · suficiente para una tesis. Si excedes:
--      - Upgrade a EmailJS Personal ($7/mes · 1000 emails/mes), o
--      - Migrar a SendGrid / Mailgun / Resend que tienen free tiers
--        más generosos (3000/mes, 1000/mes, 3000/mes respectivamente)
--    pero requieren backend (Edge Function en Supabase, no cliente).
--
-- =============================================================================
-- FIN
-- =============================================================================
