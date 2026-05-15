-- =============================================================================
-- Eco-Complaint · Fase 5 · Rate limit server-side · STEP-503
-- =============================================================================
-- Aplicación:
--   1. Aplica antes los SQL de fases anteriores.
--   2. SQL Editor → New query → pega este archivo → Run.
--   3. Verifica con:
--        select tgname from pg_trigger where tgname = 'reports_rate_limit';
--      Debe retornar 1 fila.
--
-- Motivación · RSK-69:
--   El rate limit actual (Report.checkRateLimit) vive solo en cliente.
--   Un atacante puede borrar localStorage o usar otro browser para
--   saltarlo. El plan free de Supabase no expone un App Check propio
--   ni un Edge Function gratuito ilimitado; pero PostgreSQL sí permite
--   un trigger sobre INSERT que rechace la operación si el rate excede.
--
-- Reglas implementadas (mismo valor que el cliente):
--   - Máximo 3 INSERTs en 5 minutos por user_id (autenticado).
--   - Máximo 10 INSERTs en 1 hora por user_id.
--   - Para anónimos (user_id IS NULL): rate limit más agresivo basado
--     en created_at del lote del último minuto · max 5 reports/min global
--     (evitamos discriminar anónimos uno por uno · no tenemos IP en
--     PostgreSQL desde un trigger sin Edge Function).
--
-- Trade-off: el límite anon es global. Un actor malicioso puede saturar
-- el límite y dejar fuera a anónimos legítimos por hasta 60 segundos.
-- Aceptable para Fase 5 con métricas; si en producción real esto causa
-- problemas, migrar a Edge Function con caché Redis-compatible.
-- =============================================================================


-- 1 · Función trigger · valida rate antes del INSERT en reports
create or replace function public.reports_rate_limit()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_short_window interval := interval '5 minutes';
  v_long_window  interval := interval '60 minutes';
  v_anon_window  interval := interval '1 minute';
  v_max_short int := 3;
  v_max_long  int := 10;
  v_max_anon  int := 5;
  v_count int;
begin
  /* CASO 1 · authenticated (user_id presente) · rate por usuario */
  if new.user_id is not null then
    select count(*) into v_count
      from public.reports
      where user_id = new.user_id
        and created_at >= now() - v_short_window;
    if v_count >= v_max_short then
      raise exception 'rate_limit_short: máximo % denuncias en 5 minutos para este usuario', v_max_short
        using errcode = '23505';
    end if;
    select count(*) into v_count
      from public.reports
      where user_id = new.user_id
        and created_at >= now() - v_long_window;
    if v_count >= v_max_long then
      raise exception 'rate_limit_long: máximo % denuncias por hora para este usuario', v_max_long
        using errcode = '23505';
    end if;
  else
    /* CASO 2 · anónimo (user_id null) · rate global por ventana
       corta · sin IP no podemos discriminar mejor que esto. */
    select count(*) into v_count
      from public.reports
      where user_id is null
        and created_at >= now() - v_anon_window;
    if v_count >= v_max_anon then
      raise exception 'rate_limit_anon: máximo % denuncias anónimas por minuto en todo el sistema', v_max_anon
        using errcode = '23505';
    end if;
  end if;

  return new;
end;
$$;


-- 2 · Trigger BEFORE INSERT en reports

drop trigger if exists reports_rate_limit on public.reports;
create trigger reports_rate_limit
  before insert on public.reports
  for each row execute procedure public.reports_rate_limit();


-- =============================================================================
-- 3 · NOTAS POST-APLICACIÓN
-- =============================================================================
--
-- A. Smoke test (autenticado):
--    1) Crear 3 denuncias rápidas. Las 3 deberían pasar.
--    2) La 4ª debería fallar con:
--         "rate_limit_short: máximo 3 denuncias en 5 minutos para este usuario"
--    3) Esperar 5 minutos. Ahora debería poder insertar de nuevo.
--    En el cliente este error aparece como:
--      Error al enviar: rate_limit_short: máximo 3 denuncias en 5 minutos...
--    El usuario ve un Toast con ese mensaje.
--
-- B. Smoke test (anónimo desde browsers distintos):
--    Crear 5+ denuncias anónimas en menos de 1 minuto desde browsers
--    diferentes. La 6ª debería fallar con rate_limit_anon.
--
-- C. Cliente sigue teniendo rate limit local · double check:
--    El rate limit del cliente (Report.checkRateLimit) sigue intacto
--    como defensa de UX rápida (sin round-trip al server). El server
--    es la garantía real porque no se puede burlar desde cliente.
--
-- D. Si en una emergencia operativa hay que desactivar temporalmente:
--      drop trigger reports_rate_limit on public.reports;
--    Y recrearlo después aplicando este script de nuevo.
--
-- =============================================================================
