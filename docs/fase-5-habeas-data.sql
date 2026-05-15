-- =============================================================================
-- Eco-Complaint · Fase 5 · Habeas Data · Ley 1581 de 2012 · STEP-504
-- =============================================================================
-- Aplicación:
--   1. Asegúrate de haber aplicado primero docs/fase-1-schema.sql y
--      docs/fase-3-audit-public-view.sql.
--   2. Abre SQL Editor → New query → pega TODO este archivo → Run.
--   3. Verifica que la función public.erase_my_data() está creada con:
--        select proname from pg_proc where proname = 'erase_my_data';
--
-- Esta migración implementa los derechos ARCO (Acceso, Rectificación,
-- Cancelación, Oposición) que exige la Ley 1581 de 2012 de Habeas Data
-- de Colombia, en particular el derecho al olvido (cancelación):
--
-- - Acceso · cubierto por las policies users_profile_self_read y
--   reports_owner_select existentes (cada usuario lee sus propios datos).
-- - Rectificación · cubierto por users_profile_self_update y la UI
--   de admin para corregir datos.
-- - Cancelación (derecho al olvido) · ESTE SCRIPT.
-- - Oposición · documentado en /privacidad como derecho a no consentir
--   ciertos tratamientos.
--
-- La función erase_my_data() permite al usuario eliminar TODO lo asociado
-- a su cuenta sin pasar por admin: sus reports identificados, sus audit
-- logs, y su perfil. Los reports anónimos (user_id IS NULL) que el
-- usuario creó pero no asoció a su cuenta NO se eliminan porque no son
-- atribuibles a él (es deliberado · privacy by design).
-- =============================================================================


-- 1 · Función SECURITY DEFINER que elimina datos del usuario autenticado.
--     Solo afecta al uid de auth.uid() · no se puede pasar otro uid
--     como argumento (esa es la garantía de seguridad).

create or replace function public.erase_my_data()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_reports_deleted int := 0;
  v_audit_deleted int := 0;
begin
  if v_uid is null then
    return jsonb_build_object(
      'ok', false,
      'error', 'No hay sesión activa · no se puede borrar datos sin auth.'
    );
  end if;

  -- Borrar reports asociados a la cuenta (no los anónimos)
  delete from public.reports where user_id = v_uid;
  get diagnostics v_reports_deleted = row_count;

  -- Borrar entradas del audit_log atribuibles al usuario
  delete from public.audit_log where user_id = v_uid;
  get diagnostics v_audit_deleted = row_count;

  -- Borrar perfil. El trigger ON DELETE CASCADE sobre auth.users es lo
  -- que finalmente debería disparar limpiezas adicionales; aquí solo
  -- borramos users_profile · el admin tendrá que borrar la entrada en
  -- auth.users desde el dashboard de Supabase si quiere eliminar el
  -- registro de autenticación. Esto es por diseño · auth.users en
  -- Supabase no se puede borrar desde Postgres regular.
  delete from public.users_profile where uid = v_uid;

  -- Registrar la operación en audit_log (last entry antes de salir)
  insert into public.audit_log (action, entity, entity_id, details)
  values (
    'erase_my_data',
    'session',
    v_uid::text,
    jsonb_build_object(
      'reports_deleted', v_reports_deleted,
      'audit_deleted', v_audit_deleted
    )
  );

  return jsonb_build_object(
    'ok', true,
    'reports_deleted', v_reports_deleted,
    'audit_deleted', v_audit_deleted,
    'note', 'Tu cuenta de autenticación (auth.users) sigue activa. Solicita su eliminación al correo de privacidad si deseas eliminarla también.'
  );
end;
$$;

-- Permitir invocación a authenticated (la función verifica auth.uid())
grant execute on function public.erase_my_data() to authenticated;


-- 2 · Función helper para que un usuario exporte TODOS sus datos
--     (derecho de acceso explícito · cumple "portabilidad" de habeas data).

create or replace function public.export_my_data()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_profile jsonb;
  v_reports jsonb;
begin
  if v_uid is null then
    return jsonb_build_object('ok', false, 'error', 'no_session');
  end if;

  select to_jsonb(p) into v_profile
    from public.users_profile p where p.uid = v_uid;

  select coalesce(jsonb_agg(to_jsonb(r)), '[]'::jsonb) into v_reports
    from public.reports r where r.user_id = v_uid;

  return jsonb_build_object(
    'ok', true,
    'exported_at', now(),
    'profile', v_profile,
    'reports', v_reports
  );
end;
$$;

grant execute on function public.export_my_data() to authenticated;


-- =============================================================================
-- 3 · NOTAS POST-APLICACIÓN
-- =============================================================================
--
-- A. Smoke test (autenticado como usuario regular):
--      select public.export_my_data();
--      → debe devolver { ok: true, profile: {...}, reports: [...] }
--      select public.erase_my_data();
--      → debe devolver { ok: true, reports_deleted: N, audit_deleted: N }
--    Esto elimina los datos asociados al usuario en el momento.
--    Después de erase, refrescar la sesión revela que users_profile
--    no tiene fila para ese uid.
--
-- B. Limitación · auth.users:
--    La fila de auth.users con el email del usuario permanece tras
--    erase_my_data() porque Supabase no permite que un usuario regular
--    se borre a sí mismo desde Postgres. Para eliminación completa de
--    la cuenta, el admin (con service_role) debe ejecutar:
--      delete from auth.users where id = '<uid>';
--    Documentado al usuario en la vista /privacidad como "limitación
--    operativa actual; en proceso de implementación vía Edge Function
--    con privilegios elevados".
--
-- C. Trigger en cascada sobre auth.users:
--    Cuando un admin elimina la fila de auth.users, el FK ON DELETE
--    CASCADE de users_profile.uid se dispara y limpia el perfil
--    automáticamente. Los reports con user_id pierden la referencia
--    (ON DELETE SET NULL) · quedan como anónimos huérfanos.
--    Si la política de la organización exige eliminación completa
--    de reports también, agregar pre-trigger en auth.users que
--    haga DELETE de reports antes.
--
-- =============================================================================
