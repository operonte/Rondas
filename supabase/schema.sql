-- =========================================================
-- ESQUEMA DE BASE DE DATOS SEGÚN ESTÁNDARES OWASP MOBILE (MASVS)
-- =========================================================

-- 1. Extensión UUID
create extension if not exists "uuid-ossp";
create extension if not exists "pgcrypto";

-- 2. Tabla de Instalaciones
create table if not exists public.installations (
  id uuid primary key default uuid_generate_v4(),
  name text not null,
  access_code text not null unique,
  address text,
  created_at timestamptz default now()
);

-- 3. Tabla de Configuración de Sistema
create table if not exists public.system_config (
  key text primary key,
  value text not null
);

-- 4. Perfiles y Roles
create table if not exists public.profiles (
  id uuid primary key default uuid_generate_v4(),
  role text not null check (role in ('guardia', 'superusuario')),
  full_name text not null,
  password_hash text not null,
  installation_id uuid references public.installations(id),
  created_at timestamptz default now(),
  constraint unique_full_name_per_role unique (role, full_name)
);

-- 4.1 Migración de bases desplegadas con la versión anterior del esquema.
-- Ahí `profiles` existe pero SIN password_hash ni installation_id, y como
-- `create table if not exists` no toca una tabla que ya existe, esas columnas
-- nunca se agregaban: la app fallaba con "column does not exist" y el error
-- quedaba enterrado en un `catch (_)`.
alter table public.profiles add column if not exists password_hash text;
alter table public.profiles add column if not exists installation_id uuid references public.installations(id);

do $$
begin
  alter table public.profiles add constraint unique_full_name_per_role unique (role, full_name);
exception
  when duplicate_table then null;
  when duplicate_object then null;
end $$;

-- 5. Histórico de GPS (Registro cada 100s)
create table if not exists public.gps_logs (
  id uuid primary key default uuid_generate_v4(),
  user_id uuid references public.profiles(id),
  latitude double precision not null,
  longitude double precision not null,
  accuracy double precision,
  is_mock boolean default false,
  battery_level int,
  recorded_at timestamptz not null,
  synced_at timestamptz default now()
);

-- 6. Alertas Aleatorias y Emergencias
create table if not exists public.alerts (
  id uuid primary key default uuid_generate_v4(),
  target_user_id uuid references public.profiles(id),
  type text not null check (type in ('random_check', 'low_battery', 'panic')),
  status text not null default 'pending' check (status in ('pending', 'acknowledged', 'expired')),
  photo_url text,
  triggered_at timestamptz default now(),
  responded_at timestamptz
);

-- 7. Reporte de Incidentes / Novedades
create table if not exists public.incidents (
  id uuid primary key default uuid_generate_v4(),
  user_id uuid references public.profiles(id),
  title text not null,
  description text not null,
  photo_url text,
  recorded_at timestamptz default now()
);

-- 8. Logs de Actividad Diaria del Sistema
-- El CHECK debe cubrir TODOS los event_type que escribe la app. Si falta uno,
-- Postgres rechaza el insert, OfflineService.syncAllData se come el error y la
-- cola local nunca se vacía -- los logs se pierden en silencio.
create table if not exists public.system_logs (
  id uuid primary key default uuid_generate_v4(),
  user_id uuid references public.profiles(id),
  event_type text not null,
  details text not null,
  created_at timestamptz default now()
);

-- Idempotente: recrea el CHECK con el set completo, también en bases que ya
-- existían con la versión vieja (solo permitía 5 de los 10 tipos reales).
alter table public.system_logs drop constraint if exists system_logs_event_type_check;
alter table public.system_logs add constraint system_logs_event_type_check
  check (event_type in (
    'incident', 'alert_response', 'offline_event', 'mock_gps_detected', 'audit',
    'round_start', 'round_end', 'checkin_qr', 'checkin_nfc', 'checkin_manual',
    'low_battery', 'random_check'
  ));

-- 9. Datos Iniciales por Defecto ("demo" y superusuario)
-- IMPORTANTE: estos son valores de ejemplo. Cambiarlos apenas se despliegue
-- (UPDATE en profiles/installations) y no commitear jamás credenciales reales
-- en este archivo — queda en el historial de git.
--
-- Los seeds están condicionados a que la tabla esté vacía, NO a `on conflict`:
-- en una base ya desplegada, un `on conflict do nothing` igual insertaría un
-- SEGUNDO superusuario (con esta password placeholder conocida) si el que ya
-- existe tiene otro full_name. Eso sería una cuenta de acceso abierta.
insert into public.installations (name, access_code)
select 'demo', 'CAMBIAR_ESTE_CODIGO_AL_DESPLEGAR'
where not exists (select 1 from public.installations);

-- 9.1 Migración de la contraseña del superusuario.
-- La versión anterior la guardaba EN TEXTO PLANO en system_config.super_password.
-- Se copia a profiles.password_hash como SHA-256, conservando la contraseña que
-- el usuario ya tiene (no la cambia). El texto plano se elimina en el script
-- `cleanup_after_cutover.sql`, recién cuando la app nueva esté desplegada.
insert into public.profiles (role, full_name, password_hash)
select 'superusuario', 'Supervisor de Central', encode(digest(value, 'sha256'), 'hex')
from public.system_config
where key = 'super_password'
  and not exists (select 1 from public.profiles where role = 'superusuario');

-- Solo si no había ni perfil ni super_password previo (instalación desde cero).
insert into public.profiles (role, full_name, password_hash)
select 'superusuario', 'Supervisor de Central', encode(digest('CAMBIAR_ESTA_PASSWORD_AL_DESPLEGAR', 'sha256'), 'hex')
where not exists (select 1 from public.profiles where role = 'superusuario');

-- 10. Habilitar Supabase Realtime
-- El bloque evita el error "table is already member of publication" al
-- reejecutar este archivo sobre una base ya desplegada.
do $$
begin
  alter publication supabase_realtime add table public.alerts;
exception
  when duplicate_object then null;
end $$;

-- 10.1 Bucket de fotos de incidentes/alertas (reemplaza guardar Base64 en
-- columnas `text`). Público de lectura porque no hay Auth real para armar
-- URLs firmadas por rol; la ruta incluye un sufijo aleatorio, no es listable
-- ni adivinable, pero cualquiera con el link directo puede verla -- mismo
-- nivel de exposición que el resto de esta base mientras no se migre a
-- Supabase Auth real (ver nota en la sección de RLS).
insert into storage.buckets (id, name, public)
values ('incident-photos', 'incident-photos', true)
on conflict (id) do nothing;

-- Postgres no soporta `create policy if not exists`, así que se dropea antes
-- de crear -- de otro modo reejecutar este archivo aborta con "already exists".
drop policy if exists "OWASP_Storage_IncidentPhotos_Insert" on storage.objects;
create policy "OWASP_Storage_IncidentPhotos_Insert" on storage.objects
  for insert with check (bucket_id = 'incident-photos');

drop policy if exists "OWASP_Storage_IncidentPhotos_Select" on storage.objects;
create policy "OWASP_Storage_IncidentPhotos_Select" on storage.objects
  for select using (bucket_id = 'incident-photos');

-- 11. Intentos de login, para frenar fuerza bruta (ver funciones is_rate_limited /
-- record_attempt más abajo). Sin políticas de RLS para anon: solo lo tocan
-- las funciones security definer, nadie puede leerlo ni escribirlo directo.
create table if not exists public.auth_attempts (
  id bigint generated always as identity primary key,
  identifier text not null,
  success boolean not null,
  attempted_at timestamptz not null default now()
);
create index if not exists idx_auth_attempts_identifier_time
  on public.auth_attempts (identifier, attempted_at desc);
alter table public.auth_attempts enable row level security;

-- =========================================================
-- POLITICAS DE SEGURIDAD ROW LEVEL SECURITY (OWASP M8)
-- =========================================================
-- NOTA: la app todavía no usa Supabase Auth (login propio contra la tabla
-- `profiles`), así que Postgres no puede distinguir guardia vs superusuario
-- a nivel de fila -- toda conexión llega con el mismo rol `anon`. Mientras
-- eso no se migre a Supabase Auth real, estas políticas son un piso mínimo:
-- cortan la lectura masiva de password_hash y fuerzan el login a pasar por
-- funciones RPC controladas (ver más abajo) en vez de un select directo.
alter table public.installations enable row level security;
alter table public.system_config enable row level security;
alter table public.profiles enable row level security;
alter table public.gps_logs enable row level security;
alter table public.alerts enable row level security;
alter table public.incidents enable row level security;
alter table public.system_logs enable row level security;

-- CRÍTICO: estas dos políticas existían en la versión anterior del esquema y
-- son las que permitían `select * from profiles` (o sea, llevarse todos los
-- password_hash). Hay que eliminarlas explícitamente: si esta base ya estaba
-- desplegada, siguen activas y ninguna de las mejoras de abajo sirve de nada.
drop policy if exists "OWASP_Profiles_Select" on public.profiles;
drop policy if exists "OWASP_Profiles_All" on public.profiles;

-- Políticas de Lectura y Escritura Seguras.
-- Postgres no soporta `create policy if not exists`; se dropea antes de crear
-- para que este archivo se pueda reejecutar sin abortar.
drop policy if exists "OWASP_Installations_Select" on public.installations;
create policy "OWASP_Installations_Select" on public.installations for select using (true);
drop policy if exists "OWASP_Installations_All" on public.installations;
create policy "OWASP_Installations_All" on public.installations for all using (true);

drop policy if exists "OWASP_SystemConfig_Select" on public.system_config;
create policy "OWASP_SystemConfig_Select" on public.system_config for select using (true);

-- profiles: SIN política de select -> nadie puede hacer
-- `select * from profiles` y llevarse todos los password_hash de una.
-- Insert/update/delete quedan abiertos porque el panel de administración
-- los sigue necesitando (mismo límite de arriba: sin Auth real no hay forma
-- de exigir "solo superusuario" en la base).
drop policy if exists "OWASP_Profiles_Insert" on public.profiles;
create policy "OWASP_Profiles_Insert" on public.profiles for insert with check (true);
drop policy if exists "OWASP_Profiles_Update" on public.profiles;
create policy "OWASP_Profiles_Update" on public.profiles for update using (true);
drop policy if exists "OWASP_Profiles_Delete" on public.profiles;
create policy "OWASP_Profiles_Delete" on public.profiles for delete using (true);

drop policy if exists "OWASP_GPS_Insert" on public.gps_logs;
create policy "OWASP_GPS_Insert" on public.gps_logs for insert with check (true);
drop policy if exists "OWASP_GPS_Select" on public.gps_logs;
create policy "OWASP_GPS_Select" on public.gps_logs for select using (true);

drop policy if exists "OWASP_Alerts_All" on public.alerts;
create policy "OWASP_Alerts_All" on public.alerts for all using (true);

drop policy if exists "OWASP_Incidents_Insert" on public.incidents;
create policy "OWASP_Incidents_Insert" on public.incidents for insert with check (true);
drop policy if exists "OWASP_Incidents_Select" on public.incidents;
create policy "OWASP_Incidents_Select" on public.incidents for select using (true);

drop policy if exists "OWASP_SystemLogs_Insert" on public.system_logs;
create policy "OWASP_SystemLogs_Insert" on public.system_logs for insert with check (true);
drop policy if exists "OWASP_SystemLogs_Select" on public.system_logs;
create policy "OWASP_SystemLogs_Select" on public.system_logs for select using (true);

-- =========================================================
-- FUNCIONES RPC PARA LOGIN Y GESTIÓN DE PERFILES
-- SECURITY DEFINER: corren con permisos del owner y devuelven solo las
-- columnas necesarias -- nunca password_hash -- así compensan que la
-- tabla profiles ya no tiene política de select para anon.
-- =========================================================
-- Rate limiting básico contra fuerza bruta: bloquea un identificador
-- (nombre de guardia, "superuser", etc.) tras demasiados fallos recientes.
-- No frena a un atacante distribuido con muchas IPs, pero sí el caso común
-- de probar contraseñas en loop contra una sola cuenta.
create or replace function public.is_rate_limited(p_identifier text, p_max_attempts int default 8, p_window_minutes int default 5)
returns boolean
language sql security definer set search_path = public as $$
  select count(*) >= p_max_attempts
  from public.auth_attempts
  where identifier = p_identifier
    and success = false
    and attempted_at > now() - (p_window_minutes || ' minutes')::interval;
$$;

create or replace function public.record_attempt(p_identifier text, p_success boolean)
returns void
language sql security definer set search_path = public as $$
  insert into public.auth_attempts (identifier, success) values (p_identifier, p_success);
$$;

-- IMPORTANTE sobre el orden de las comprobaciones:
-- la credencial se verifica ANTES de aplicar el bloqueo, y el bloqueo solo
-- afecta a los intentos FALLIDOS. Si se bloqueara antes de verificar, ocho
-- intentos fallidos -- que cualquiera con la anon key puede lanzar a propósito
-- y en bucle -- dejarían al supervisor real sin poder entrar de forma
-- indefinida. En una app de vigilancia, negarle el acceso al supervisor
-- durante una emergencia es peor que el ataque que se intenta frenar.
--
-- Límite de este enfoque: sin Supabase Auth no hay IP ni sesión, así que esto
-- no frena a un atacante decidido, solo encarece el ataque ingenuo y deja
-- rastro auditable en auth_attempts. El throttling real llega al migrar a
-- Supabase Auth, que sí aplica límites por IP.
create or replace function public.login_profile(p_full_name text, p_password_hash text)
returns table (id uuid, full_name text, role text, installation_id uuid)
language plpgsql security definer set search_path = public as $$
declare
  v_identifier text := 'profile:' || lower(trim(p_full_name));
  v_matched boolean := false;
begin
  for id, full_name, role, installation_id in
    select p.id, p.full_name, p.role, p.installation_id
    from public.profiles p
    where p.full_name = p_full_name and p.password_hash = p_password_hash
  loop
    v_matched := true;
    return next;
  end loop;

  if not v_matched then
    perform public.record_attempt(v_identifier, false);
  end if;
  return;
end;
$$;

create or replace function public.login_superuser(p_password_hash text)
returns table (id uuid, full_name text)
language plpgsql security definer set search_path = public as $$
declare
  v_matched boolean := false;
begin
  for id, full_name in
    select p.id, p.full_name
    from public.profiles p
    where p.role = 'superusuario' and p.password_hash = p_password_hash
  loop
    v_matched := true;
    return next;
  end loop;

  if not v_matched then
    perform public.record_attempt('superuser', false);
  end if;
  return;
end;
$$;

-- Reemplaza el select directo a `installations` desde el cliente: mismo
-- resultado, pero con rate limit global (más laxo porque no hay un
-- identificador fijo por instalación -- el código adivinado ES el secreto).
-- Misma lógica que las anteriores: un código válido nunca queda bloqueado, así
-- un guardia no se queda sin poder iniciar su ronda porque otro (o un atacante)
-- gastó los intentos.
create or replace function public.login_installation(p_access_code text)
returns table (id uuid, name text, address text)
language plpgsql security definer set search_path = public as $$
declare
  v_matched boolean := false;
begin
  for id, name, address in
    select i.id, i.name, i.address
    from public.installations i
    where i.access_code = p_access_code
  loop
    v_matched := true;
    return next;
  end loop;

  if not v_matched then
    perform public.record_attempt('installation_global', false);
  end if;
  return;
end;
$$;

create or replace function public.list_guard_profiles()
returns table (id uuid, full_name text, installation_id uuid)
language sql security definer set search_path = public as $$
  select p.id, p.full_name, p.installation_id
  from public.profiles p
  where p.role = 'guardia';
$$;

-- Usada por el picker de guardia tras login con password de instalación:
-- deja registrar la ronda a nombre de una persona, no solo del sitio.
create or replace function public.list_guard_profiles_by_installation(p_installation_id uuid)
returns table (id uuid, full_name text)
language sql security definer set search_path = public as $$
  select p.id, p.full_name
  from public.profiles p
  where p.role = 'guardia' and p.installation_id = p_installation_id
  order by p.full_name;
$$;

create or replace function public.guard_name_available(p_full_name text, p_exclude_id uuid default null)
returns boolean
language sql security definer set search_path = public as $$
  select not exists (
    select 1 from public.profiles p
    where p.role = 'guardia'
      and p.full_name ilike p_full_name
      and (p_exclude_id is null or p.id <> p_exclude_id)
  );
$$;

create or replace function public.update_superuser_password(p_current_hash text, p_new_hash text)
returns boolean
language plpgsql security definer set search_path = public as $$
declare
  v_updated boolean := false;
begin
  update public.profiles
  set password_hash = p_new_hash
  where role = 'superusuario' and password_hash = p_current_hash;
  v_updated := found;

  if not v_updated then
    perform public.record_attempt('superuser_pwchange', false);
  end if;
  return v_updated;
end;
$$;

grant execute on function public.login_profile(text, text) to anon, authenticated;
grant execute on function public.login_superuser(text) to anon, authenticated;
grant execute on function public.login_installation(text) to anon, authenticated;
grant execute on function public.list_guard_profiles() to anon, authenticated;
grant execute on function public.list_guard_profiles_by_installation(uuid) to anon, authenticated;
grant execute on function public.guard_name_available(text, uuid) to anon, authenticated;
grant execute on function public.update_superuser_password(text, text) to anon, authenticated;
