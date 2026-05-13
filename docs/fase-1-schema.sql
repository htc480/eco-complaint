-- =============================================================================
-- Eco-Complaint · Fase 1 · Schema Postgres + RLS · STEP-103
-- =============================================================================
-- Aplicación:
--   1. Crea el proyecto Supabase (Dashboard → New project).
--   2. Abre SQL Editor (icono </> en el sidebar).
--   3. Crea una nueva query, pega TODO este archivo y ejecuta (▶ Run).
--   4. Verifica en Table Editor que aparecen: users_profile, reports,
--      audit_log, config.
--   5. Vuelve al HTML, reemplaza window.__SUPABASE_URL y __SUPABASE_ANON_KEY
--      con los valores reales (Project Settings → API), recarga la app y
--      pulsa "Verificar conexión" en /admin/config.
--
-- Idempotencia: el script usa IF EXISTS / IF NOT EXISTS donde es seguro;
-- las policies se DROP-CREATE para que re-ejecutar el archivo no falle.
-- Las tablas NO se borran (DROP TABLE solo manualmente para evitar
-- pérdida accidental de datos en producción).
-- =============================================================================


-- =============================================================================
-- 0 · EXTENSIONES Y ESQUEMA
-- =============================================================================
create extension if not exists "pgcrypto";  -- gen_random_uuid()


-- =============================================================================
-- 1 · TABLAS
-- =============================================================================

-- 1.1 · users_profile
-- Extensión de auth.users con rol y nombre. Se crea automáticamente vía
-- trigger cuando alguien hace signUp.
create table if not exists public.users_profile (
  uid         uuid primary key references auth.users(id) on delete cascade,
  email       text not null,
  name        text not null default '',
  role        text not null default 'ciudadano' check (role in ('ciudadano', 'admin')),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

create index if not exists idx_users_profile_role  on public.users_profile(role);
create index if not exists idx_users_profile_email on public.users_profile(email);


-- 1.2 · reports
-- Denuncias. Columnas JSON para campos compuestos para reducir joins
-- en consultas analíticas del dashboard admin. Las 5 columnas marcadas
-- como /* public */ son las únicas legibles por el rol anonymous.
create table if not exists public.reports (
  id                    uuid primary key default gen_random_uuid(),
  radicado              text unique not null,                           /* public */
  delitos               text[] not null,                                /* public */
  severity              smallint not null check (severity between 1 and 5),
  probability           smallint not null check (probability between 1 and 5),
  probability_answers   smallint[] not null,
  score                 smallint not null check (score between 1 and 25),
  band                  text not null check (band in ('bajo','medio','alto','critico','extremo')),  /* public */
  location              jsonb,
  evidence              jsonb default '[]'::jsonb,
  reporter_description  text,
  tree_path             jsonb,
  user_id               uuid references auth.users(id) on delete set null,
  is_anonymous          boolean not null default false,
  authorities_notified  text[] not null default '{}',
  master_email          text,
  status                text not null default 'received'                /* public */
                        check (status in ('received','triaged','in_progress','resolved')),
  created_at            timestamptz not null default now(),             /* public */
  updated_at            timestamptz not null default now()
);

create index if not exists idx_reports_radicado    on public.reports(radicado);
create index if not exists idx_reports_status      on public.reports(status);
create index if not exists idx_reports_band        on public.reports(band);
create index if not exists idx_reports_created_at  on public.reports(created_at desc);
create index if not exists idx_reports_user_id     on public.reports(user_id);
create index if not exists idx_reports_severity_probability on public.reports(severity, probability);


-- 1.3 · audit_log
-- Bitácora completa. Sólo escribible por usuarios autenticados o el sistema;
-- legible por admin.
create table if not exists public.audit_log (
  log_id      text primary key default ('log_' || extract(epoch from now())::bigint || '_' || substr(md5(random()::text), 1, 8)),
  timestamp   timestamptz not null default now(),
  user_id     uuid references auth.users(id) on delete set null,
  action      text not null,
  entity      text not null default 'system',
  entity_id   text,
  details     jsonb default '{}'::jsonb,
  ip          text,
  user_agent  text
);

create index if not exists idx_audit_log_timestamp on public.audit_log(timestamp desc);
create index if not exists idx_audit_log_user      on public.audit_log(user_id);
create index if not exists idx_audit_log_entity    on public.audit_log(entity, entity_id);
create index if not exists idx_audit_log_action    on public.audit_log(action);


-- 1.4 · config
-- Singleton key-value para autoridades por banda, contacto público, etc.
-- Sólo admin puede modificar.
create table if not exists public.config (
  key         text primary key,
  value       jsonb not null,
  updated_at  timestamptz not null default now(),
  updated_by  uuid references auth.users(id) on delete set null
);


-- =============================================================================
-- 2 · FUNCIONES HELPER
-- =============================================================================

-- 2.1 · is_admin()
-- Helper invocable desde policies: ¿el usuario actual es admin?
-- Usa SECURITY DEFINER para poder leer users_profile sin estar
-- bloqueado por su propia RLS (que requiere ser admin para leer todo).
create or replace function public.is_admin()
returns boolean
language sql
security definer
set search_path = public
as $$
  select coalesce(
    (select role = 'admin' from public.users_profile where uid = auth.uid()),
    false
  );
$$;


-- 2.2 · handle_new_user()
-- Trigger sobre auth.users para crear automáticamente el perfil
-- correspondiente. El nombre y rol se toman de raw_user_meta_data,
-- con valores por defecto seguros.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.users_profile (uid, email, name, role)
  values (
    new.id,
    new.email,
    coalesce(new.raw_user_meta_data ->> 'name', split_part(new.email, '@', 1)),
    'ciudadano'  -- todos arrancan como ciudadano; el admin promueve manualmente
  )
  on conflict (uid) do nothing;
  return new;
end;
$$;


-- 2.3 · update_updated_at()
-- Trigger genérico para mantener updated_at fresco en cualquier UPDATE.
create or replace function public.update_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;


-- =============================================================================
-- 3 · TRIGGERS
-- =============================================================================

-- 3.1 · Auto-perfil al crear usuario en auth.users
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();

-- 3.2 · Auto-updated_at en reports y users_profile y config
drop trigger if exists set_updated_at_reports on public.reports;
create trigger set_updated_at_reports
  before update on public.reports
  for each row execute procedure public.update_updated_at();

drop trigger if exists set_updated_at_users on public.users_profile;
create trigger set_updated_at_users
  before update on public.users_profile
  for each row execute procedure public.update_updated_at();

drop trigger if exists set_updated_at_config on public.config;
create trigger set_updated_at_config
  before update on public.config
  for each row execute procedure public.update_updated_at();


-- =============================================================================
-- 4 · ROW-LEVEL SECURITY (RLS)
-- =============================================================================

alter table public.users_profile enable row level security;
alter table public.reports       enable row level security;
alter table public.audit_log     enable row level security;
alter table public.config        enable row level security;


-- 4.1 · users_profile
drop policy if exists "users_profile_self_read"  on public.users_profile;
drop policy if exists "users_profile_admin_all"  on public.users_profile;
drop policy if exists "users_profile_self_update" on public.users_profile;

create policy "users_profile_self_read"
  on public.users_profile for select
  using (auth.uid() = uid or public.is_admin());

create policy "users_profile_self_update"
  on public.users_profile for update
  using (auth.uid() = uid)
  with check (auth.uid() = uid and role = (select role from public.users_profile where uid = auth.uid()));
  -- el usuario puede editar su nombre pero NO su rol (solo admin)

create policy "users_profile_admin_all"
  on public.users_profile for all
  using (public.is_admin())
  with check (public.is_admin());


-- 4.2 · reports
-- Privacy by design (ADR-06): el rol anonymous puede INSERT (denuncia
-- ciudadana) pero su SELECT está limitado por una VIEW pública que solo
-- expone las 5 columnas no sensibles. NO se aplica vía policy SELECT
-- directa porque Postgres RLS no permite restringir columnas; se hace
-- por una view (reports_public) más abajo.

drop policy if exists "reports_anon_insert"           on public.reports;
drop policy if exists "reports_authenticated_insert"  on public.reports;
drop policy if exists "reports_owner_select"          on public.reports;
drop policy if exists "reports_admin_all"             on public.reports;

create policy "reports_anon_insert"
  on public.reports for insert
  to anon
  with check (is_anonymous = true and user_id is null);

create policy "reports_authenticated_insert"
  on public.reports for insert
  to authenticated
  with check (user_id = auth.uid() or (is_anonymous = true and user_id is null));

create policy "reports_owner_select"
  on public.reports for select
  to authenticated
  using (user_id = auth.uid());

create policy "reports_admin_all"
  on public.reports for all
  using (public.is_admin())
  with check (public.is_admin());


-- 4.3 · audit_log
drop policy if exists "audit_log_insert_any"   on public.audit_log;
drop policy if exists "audit_log_admin_read"   on public.audit_log;

create policy "audit_log_insert_any"
  on public.audit_log for insert
  with check (true);
  -- cualquier rol (incluyendo anon) puede insertar; el contenido lo
  -- determina la app, y el user_id se valida server-side si está presente

create policy "audit_log_admin_read"
  on public.audit_log for select
  using (public.is_admin());


-- 4.4 · config
drop policy if exists "config_public_read"   on public.config;
drop policy if exists "config_admin_write"   on public.config;

create policy "config_public_read"
  on public.config for select
  using (key in ('contact', 'authorities_meta'));
  -- contact y meta de bandas son públicos; los correos por banda no

create policy "config_admin_write"
  on public.config for all
  using (public.is_admin())
  with check (public.is_admin());


-- =============================================================================
-- 5 · VISTA PÚBLICA DE REPORTES
-- =============================================================================
-- ADR-06: la consulta ciudadana muestra solo 5 columnas. Esta view aplica
-- esa restricción a nivel SQL (más defendible que filtrar en cliente).

drop view if exists public.reports_public;
create view public.reports_public
with (security_invoker = true)
as
  select
    radicado,
    delitos,
    band,
    status,
    created_at
  from public.reports;

grant select on public.reports_public to anon, authenticated;


-- =============================================================================
-- 6 · SEED · datos iniciales mínimos
-- =============================================================================

-- 6.1 · config singleton: autoridades_meta + contact (públicos)
insert into public.config (key, value) values
  ('authorities_meta', '{
    "bajo":    {"label": "UMATA municipal",           "urgency": "estándar"},
    "medio":   {"label": "CAR regional",              "urgency": "atención prioritaria"},
    "alto":    {"label": "ANLA",                      "urgency": "alta prioridad"},
    "critico": {"label": "Fiscalía · Unidad 122",     "urgency": "ruta penal inmediata"},
    "extremo": {"label": "MinAmbiente + Pol. Amb.",   "urgency": "respuesta nacional"}
  }'::jsonb),
  ('contact', '{
    "org_name": "Eco-Complaint",
    "tagline":  "Plataforma ciudadana de denuncia ambiental",
    "email":    "contacto@eco-complaint.demo.co",
    "phone":    "+57 1 555-0001",
    "phone_emergency": "+57 320 555-0002",
    "hours":    "Lunes a viernes 8:00 a 17:00",
    "address":  "Bogotá, Colombia"
  }'::jsonb),
  ('authorities', '{
    "bajo":         ["umata@demo.co"],
    "medio":        ["car-regional@demo.co"],
    "alto":         ["anla@demo.co", "car-regional@demo.co"],
    "critico":      ["fiscalia122@demo.co", "anla@demo.co", "car-regional@demo.co"],
    "extremo":      ["fiscalia122@demo.co", "anla@demo.co", "denuncias@minambiente.gov.co", "policia-ambiental@demo.co", "car-regional@demo.co"],
    "master_email": "radicacion@eco-complaint.demo.co"
  }'::jsonb)
on conflict (key) do nothing;


-- =============================================================================
-- 7 · NOTAS POST-APLICACIÓN
-- =============================================================================
--
-- A. Promover un usuario a admin:
--    Después de que el usuario haga signUp normal por la app, ve a
--    Table Editor → users_profile → busca su uid → cambia role a 'admin'.
--    O ejecuta en SQL Editor:
--      update public.users_profile set role = 'admin' where email = 'tu@correo.com';
--
-- B. Email confirmation:
--    Authentication → Providers → Email → "Confirm email"
--    - Activado (default): el usuario debe abrir el link de confirmación
--      antes de poder iniciar sesión. Recomendado para producción.
--    - Desactivado: signUp entra directo. Útil para desarrollo y pruebas.
--
-- C. Smoke test rápido:
--    1) En SQL Editor:
--       select count(*) from public.config;     -- debe devolver 3
--       select * from public.reports_public;    -- vacío al inicio, sin error
--    2) En la app: signUp con un correo de prueba; verifica que aparece
--       en users_profile.
--    3) Envía una denuncia desde /denunciar; debería aparecer en
--       reports y reports_public (en STEP-104 cuando ReportsRepo esté
--       conectado).
--
-- D. Backup pre-defensa:
--    Project Settings → Database → Backups · Supabase Free guarda
--    un snapshot diario por 7 días. Para backups manuales antes de la
--    defensa de tesis usa pg_dump o el botón "Download backup".
--
-- =============================================================================
-- FIN DEL SCHEMA
-- =============================================================================
