-- =============================================================================
-- Eco-Complaint · Fase 2 · Supabase Storage setup · STEP-201
-- =============================================================================
-- Aplicación:
--   1. En el Dashboard de Supabase, asegúrate de haber aplicado primero
--      docs/fase-1-schema.sql (este script asume que existe public.is_admin()).
--   2. Abre SQL Editor → New query → pega TODO este archivo → Run.
--   3. Verifica en Storage del Dashboard que aparece el bucket "evidencias"
--      marcado como Private (no Public).
--   4. Verifica en Authentication → Policies → storage.objects que aparecen
--      las 4 policies de este archivo.
--
-- Modelo de seguridad:
--   - Bucket privado: nadie ve los objetos sin signed URL.
--   - Subida (INSERT en storage.objects):
--       * anon  → puede subir solo a paths que empiecen con 'anon/' o que
--                 NO contengan slash de usuario (denuncia anónima).
--       * authenticated → puede subir si su uid es el primer segmento del path.
--   - Lectura directa (SELECT en storage.objects):
--       * El dueño del objeto (uploader) puede leer su propio path.
--       * Admin puede leer cualquier path.
--       * Anónimos NO pueden listar ni descargar directamente.
--         Acceden únicamente mediante signed URLs (firmadas server-side).
--   - DELETE: solo admin.
--
-- Esto se complementa con la generación de signed URLs en cliente
-- (EvidenceRepo.signUrl) que usa la API de storage de Supabase con la
-- anon key del usuario actual.
--
-- Idempotencia: las policies usan DROP-CREATE, el bucket se crea con
-- ON CONFLICT DO NOTHING.
-- =============================================================================


-- =============================================================================
-- 1 · BUCKET
-- =============================================================================
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'evidencias',
  'evidencias',
  false,                                       -- PRIVADO
  10485760,                                    -- 10 MB por archivo
  array[
    'image/jpeg', 'image/png', 'image/webp', 'image/heic', 'image/heif',
    'video/mp4', 'video/quicktime', 'video/webm',
    'application/pdf'
  ]
) on conflict (id) do nothing;


-- =============================================================================
-- 2 · POLICIES sobre storage.objects (RLS)
-- =============================================================================
-- Estas policies operan sobre la tabla storage.objects que Supabase mantiene
-- automáticamente. Filtramos por bucket_id = 'evidencias' para no afectar
-- otros buckets futuros.

-- 2.1 · INSERT anon (denuncia anónima)
-- El path debe empezar con 'anon/' para no chocar con paths de usuarios reales.
drop policy if exists "evidencias_anon_insert" on storage.objects;
create policy "evidencias_anon_insert"
  on storage.objects for insert
  to anon
  with check (
    bucket_id = 'evidencias'
    and (storage.foldername(name))[1] = 'anon'
  );

-- 2.2 · INSERT authenticated
-- El primer segmento del path debe ser el uid del usuario actual.
-- O 'anon/' si decide denunciar anónimamente aún estando logueado.
drop policy if exists "evidencias_auth_insert" on storage.objects;
create policy "evidencias_auth_insert"
  on storage.objects for insert
  to authenticated
  with check (
    bucket_id = 'evidencias'
    and (
      (storage.foldername(name))[1] = auth.uid()::text
      or (storage.foldername(name))[1] = 'anon'
    )
  );

-- 2.3 · SELECT (lectura directa)
-- Owner: solo el uid que subió puede leer (primer segmento del path).
-- Admin: puede leer todo.
-- Nota: anon NO tiene SELECT — accede solo vía signed URLs.
drop policy if exists "evidencias_owner_select" on storage.objects;
create policy "evidencias_owner_select"
  on storage.objects for select
  to authenticated
  using (
    bucket_id = 'evidencias'
    and (
      (storage.foldername(name))[1] = auth.uid()::text
      or public.is_admin()
    )
  );

-- 2.4 · DELETE (solo admin)
drop policy if exists "evidencias_admin_delete" on storage.objects;
create policy "evidencias_admin_delete"
  on storage.objects for delete
  to authenticated
  using (
    bucket_id = 'evidencias'
    and public.is_admin()
  );


-- =============================================================================
-- 3 · CONFIG DEFAULTS (retención + duración de signed URLs)
-- =============================================================================
-- Estos defaults se leen desde el cliente vía ConfigRepo.get('storage').
-- El admin puede editarlos desde /admin/config en un STEP futuro.

insert into public.config (key, value) values
  ('storage', '{
    "bucket": "evidencias",
    "signed_url_expires_seconds": 604800,
    "retention_days": 365,
    "max_file_mb": 10,
    "max_files_per_report": 8
  }'::jsonb)
on conflict (key) do nothing;


-- =============================================================================
-- 4 · NOTAS POST-APLICACIÓN
-- =============================================================================
--
-- A. Verificación rápida:
--    select id, name, public from storage.buckets where id = 'evidencias';
--    -- debe retornar 1 fila con public = false
--
--    select policyname from pg_policies
--    where schemaname = 'storage' and tablename = 'objects'
--      and policyname like 'evidencias_%';
--    -- debe retornar 4 policies
--
-- B. Probar manualmente desde SQL Editor (autenticado como service_role):
--    select storage.create_signed_url('evidencias', 'PATH', 3600);
--    -- devuelve una URL firmada con expiración de 1 hora
--
-- C. Limpieza por retención (cron futuro · STEP-207):
--    Una Edge Function programada borrará objetos cuya antigüedad
--    supere config.storage.retention_days. Pseudo-SQL:
--      delete from storage.objects
--      where bucket_id = 'evidencias'
--        and created_at < now() - interval '365 days';
--    No se incluye en este script porque requiere infraestructura adicional;
--    queda como tarea operativa de Fase 5 (hardening).
--
-- D. Migración de evidencias legacy (base64 → Storage):
--    El tool de /admin/diagnostico (STEP-206) ofrece migrar las evidencias
--    inline existentes en reports.evidence al bucket. La operación reemplaza
--    `dataUrl` por `path` en el JSON del report y libera espacio en la fila.
--
-- =============================================================================
-- FIN DEL SETUP DE STORAGE
-- =============================================================================
