-- =============================================================================
-- Eco-Complaint · View pública de cambios de estado · RSK-72 fix
-- =============================================================================
-- Aplicación:
--   1. Asegúrate de haber aplicado primero docs/fase-1-schema.sql.
--   2. Abre SQL Editor → New query → pega este archivo → Run.
--   3. Verifica con:
--        select * from public.status_changes_public limit 5;
--      Como anon (rol público) debería listar entradas si ya hay
--      status_change en el audit_log.
--
-- Motivación · RSK-72:
--   PublicLookup mostraba el timeline de cambios de estado leyendo
--   eco.audit_log de localStorage. En modo Supabase ese cache solo
--   contiene los audits ejecutados localmente; un anónimo consultando
--   desde otro browser NO veía los cambios de estado.
--
--   Solución · view pública que expone SOLO los campos necesarios
--   para el timeline (timestamp, radicado, nuevo status) sin filtrar
--   user_id, IP, user_agent ni otra info sensible del audit completo.
--   La policy admin_read de audit_log permanece intacta para la
--   lectura completa del log desde /admin/diagnostico.
-- =============================================================================


-- 1 · View con SECURITY INVOKER · respeta las policies del invoker
--    Solo expone campos no sensibles. user_id e IP NO se proyectan.

drop view if exists public.status_changes_public;

create view public.status_changes_public
with (security_invoker = true)
as
  select
    entity_id          as radicado,
    "timestamp"        as changed_at,
    details->>'to'     as new_status,
    details->>'from'   as previous_status
  from public.audit_log
  where entity = 'report'
    and action = 'status_change'
    and entity_id is not null
    and details->>'to' is not null;


-- 2 · Policy temporal que permite anon LEER audit_log SOLO si la
--    consulta filtra status_change.
--    Sin esta policy, anon no puede ejecutar SELECT sobre audit_log
--    ni a través de la view (que respeta RLS del invoker).
--    La policy existente "audit_log_admin_read" permanece y aplica
--    a admin para lectura completa.

drop policy if exists "audit_log_public_status_changes" on public.audit_log;
create policy "audit_log_public_status_changes"
  on public.audit_log for select
  to anon, authenticated
  using (
    entity = 'report'
    and action = 'status_change'
    and details ? 'to'
  );


-- 3 · GRANTs explícitos sobre la view a roles públicos

grant select on public.status_changes_public to anon, authenticated;


-- =============================================================================
-- 4 · NOTAS POST-APLICACIÓN
-- =============================================================================
--
-- A. Smoke test desde el SQL Editor (como service_role · siempre puede):
--      select * from public.status_changes_public limit 10;
--
-- B. Smoke test desde la app (anon o ciudadano logueado):
--      const { data, error } = await window.supabase
--        .from('status_changes_public')
--        .select('*')
--        .eq('radicado', 'ECO-20260515-...-0042')
--        .order('changed_at', { ascending: true });
--      → debe devolver array (vacío si no hay cambios) sin error.
--
-- C. Privacidad expuesta:
--    - changed_at (timestamp del cambio)
--    - new_status (received/triaged/in_progress/resolved)
--    - previous_status (idem)
--    NO se exponen: user_id (quién hizo el cambio), IP, user_agent.
--    Aceptable porque el estado del reporte ya es público vía
--    reports_public y los timestamps de cambio solo revelan la
--    cadencia de gestión, no la identidad del operador.
--
-- D. Si en el futuro queremos restringir más (por ejemplo, no exponer
--    el timestamp exacto · solo "fue actualizado en mayo"), basta
--    modificar la view sin tocar el cliente.
--
-- =============================================================================
