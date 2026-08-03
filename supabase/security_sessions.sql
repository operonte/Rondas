-- =========================================================
-- MODELO DE SESIONES CON TOKEN
-- =========================================================
-- Problema que resuelve: la app se conecta a Supabase con la anon key, que es
-- extraíble de cualquier APK o del bundle web. Mientras las tablas tengan
-- políticas `using (true)`, esa clave alcanza para leer los códigos de acceso
-- de todas las instalaciones, cambiarle la contraseña al superusuario, crear
-- otro superusuario o descargar el historial GPS completo de los guardias --
-- todo sin pasar por la app.
--
-- Enfoque: ninguna tabla acepta consultas directas de `anon`. Toda operación
-- pasa por funciones SECURITY DEFINER que exigen un token de sesión emitido al
-- iniciar sesión, y cada función aplica lo que ese rol puede hacer.
--
-- Ejecutar DESPUÉS de schema.sql.
--
-- Nota sobre search_path: las funciones declaran 'public, extensions' porque en
-- Supabase pgcrypto vive en el esquema 'extensions', no en 'public'. Sin ese
-- segundo esquema, crypt() y gen_salt() no se resuelven dentro de la función
-- aunque sí funcionen en consultas sueltas (la base los tiene en su search_path).

-- ---------------------------------------------------------
-- 1. Tabla de sesiones
-- ---------------------------------------------------------
create table if not exists public.sessions (
  token uuid primary key default gen_random_uuid(),
  role text not null check (role in ('guardia', 'superusuario')),
  profile_id uuid references public.profiles(id) on delete cascade,
  installation_id uuid references public.installations(id) on delete cascade,
  created_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now(),
  expires_at timestamptz not null
);

create index if not exists idx_sessions_expires on public.sessions (expires_at);

-- Sin políticas: `anon` no puede tocarla ni para leer. Solo la alcanzan las
-- funciones security definer de más abajo.
alter table public.sessions enable row level security;

-- ---------------------------------------------------------
-- 2. Validación de token
-- ---------------------------------------------------------
-- Devuelve la sesión si el token es válido y no venció; si no, no devuelve
-- nada. Las funciones de negocio la usan para decidir qué permitir.
create or replace function public.session_of(p_token uuid)
returns table (role text, profile_id uuid, installation_id uuid)
language plpgsql security definer set search_path = public, extensions as $$
begin
  return query
    select s.role, s.profile_id, s.installation_id
    from public.sessions s
    where s.token = p_token and s.expires_at > now();

  -- Renovación deslizante: mientras se use, la sesión no vence.
  update public.sessions
  set last_seen_at = now(), expires_at = now() + interval '12 hours'
  where token = p_token and expires_at > now();
end;
$$;

-- Limpieza de sesiones vencidas. Conviene llamarla desde un cron de Supabase.
create or replace function public.purge_expired_sessions()
returns void
language sql security definer set search_path = public, extensions as $$
  delete from public.sessions where expires_at < now() - interval '7 days';
$$;

-- ---------------------------------------------------------
-- 2.b Contraseñas: bcrypt del lado del servidor
-- ---------------------------------------------------------
-- El cliente sigue enviando SHA-256 (no manda la contraseña en claro), pero el
-- servidor ya no guarda ese valor tal cual. Antes, `password_hash` se comparaba
-- por igualdad contra lo que mandaba el cliente: el hash ERA la credencial, así
-- que filtrarlo equivalía a filtrar la contraseña, sin necesidad de romper nada.
-- Ahora se guarda bcrypt(sha256) -- con sal y costo -- y la comparación usa
-- crypt(). Las contraseñas actuales siguen funcionando: se re-hashean solas.
create or replace function public.verify_password(p_stored text, p_candidate text)
returns boolean
language sql immutable set search_path = public, extensions as $$
  select case
    -- Formato bcrypt ya migrado.
    when p_stored like '$2%' then p_stored = crypt(p_candidate, p_stored)
    -- Formato viejo (SHA-256 hex plano), aceptado hasta que se migre la fila.
    else p_stored = p_candidate
  end;
$$;

-- Migra a bcrypt cualquier fila que siga en el formato viejo.
create or replace function public.upgrade_password_hash(p_profile_id uuid, p_candidate text)
returns void
language sql security definer set search_path = public, extensions as $$
  update public.profiles
  set password_hash = crypt(p_candidate, gen_salt('bf', 10))
  where id = p_profile_id and password_hash not like '$2%';
$$;

-- Convierte de una todas las contraseñas existentes. Idempotente.
update public.profiles
set password_hash = crypt(password_hash, gen_salt('bf', 10))
where password_hash not like '$2%';

-- ---------------------------------------------------------
-- 2.c Freno de fuerza bruta sin bloquear al usuario legítimo
-- ---------------------------------------------------------
-- Un bloqueo por umbral dejaba fuera también a quien sí sabe la contraseña, y
-- cualquiera con la anon key podía dispararlo en bucle para sacar de servicio
-- al supervisor. En vez de bloquear, se cobra tiempo: el retardo se aplica
-- SOLO tras un intento fallido, así el atacante baja de miles de pruebas por
-- minuto a unas pocas, y un login correcto nunca espera.
create or replace function public.throttle_after_failure(p_identifier text)
returns void
language plpgsql security definer set search_path = public, extensions as $$
declare
  v_recent int;
begin
  select count(*) into v_recent
  from public.auth_attempts
  where identifier = p_identifier
    and success = false
    and attempted_at > now() - interval '15 minutes';

  perform public.record_attempt(p_identifier, false);

  -- Escalado hasta 3 s: suficiente para hacer inviable la fuerza bruta sin
  -- retener conexiones de la base más de la cuenta.
  if v_recent > 0 then
    perform pg_sleep(least(v_recent * 0.5, 3.0));
  end if;
end;
$$;

-- ---------------------------------------------------------
-- 3. Login: valida credenciales y emite el token
-- ---------------------------------------------------------
-- Un solo dato: la contraseña. El servidor decide quién es.
--
--   Contraseña del superusuario -> sesión con poderes totales.
--   Contraseña personal de un guardia -> sesión a nombre de esa persona, sin
--   instalación todavía; la elige y desbloquea después con enter_installation.
--
-- El código de la instalación NO sirve para iniciar sesión: identifica al
-- sitio, no a la persona. Si alcanzara para entrar, todas las rondas de un
-- lugar quedarían sin responsable.
create or replace function public.login(p_password_hash text, p_full_name text default null)
returns table (
  token uuid,
  role text,
  display_name text,
  installation_id uuid,
  installation_name text,
  requires_guard_selection boolean,
  profile_id uuid
)
language plpgsql security definer set search_path = public, extensions as $$
declare
  v_profile public.profiles%rowtype;
  v_token uuid;
begin
  -- 1. ¿Superusuario?
  select * into v_profile from public.profiles p
  where p.role = 'superusuario'
    and public.verify_password(p.password_hash, p_password_hash)
  limit 1;

  if found then
    perform public.upgrade_password_hash(v_profile.id, p_password_hash);

    insert into public.sessions (role, profile_id, expires_at)
    values ('superusuario', v_profile.id, now() + interval '12 hours')
    returning sessions.token into v_token;

    return query select
      v_token, 'superusuario'::text, v_profile.full_name, null::uuid,
      'Central de Supervisión'::text, false, v_profile.id;
    return;
  end if;

  -- 2. ¿Contraseña personal de un guardia?
  -- Se busca por contraseña sola, sin pedir el nombre, para que la pantalla de
  -- ingreso tenga un único campo. Hay que recorrer los guardias comparando con
  -- bcrypt; es asumible con estas cantidades y el retardo ante fallos protege
  -- de que alguien lo use para probar contraseñas en masa.
  select * into v_profile from public.profiles p
  where p.role = 'guardia'
    and public.verify_password(p.password_hash, p_password_hash)
  limit 1;

  if found then
    perform public.upgrade_password_hash(v_profile.id, p_password_hash);

    -- Sin installation_id: el guardia todavía tiene que elegir dónde trabaja.
    insert into public.sessions (role, profile_id, expires_at)
    values ('guardia', v_profile.id, now() + interval '12 hours')
    returning sessions.token into v_token;

    return query select
      v_token, 'guardia'::text, v_profile.full_name, null::uuid,
      ''::text, true, v_profile.id;
    return;
  end if;

  perform public.throttle_after_failure('login_global');
  return;
end;
$$;

-- Instalaciones disponibles para que el guardia elija. Devuelve nombre y
-- dirección, nunca el código de acceso: ese lo tiene que saber la persona.
create or replace function public.available_installations(p_token uuid)
returns table (id uuid, name text, address text)
language plpgsql security definer set search_path = public, extensions as $$
declare v_session record;
begin
  select * into v_session from public.session_of(p_token);
  if not found then return; end if;

  return query
    select i.id, i.name, i.address
    from public.installations i
    order by i.name;
end;
$$;

-- El guardia entra a la instalación que eligió escribiendo su contraseña.
-- Recién con esto la sesión queda habilitada para registrar la ronda ahí.
create or replace function public.enter_installation(
  p_token uuid, p_installation_id uuid, p_access_code_hash text
)
returns table (ok boolean, installation_name text)
language plpgsql security definer set search_path = public, extensions as $$
declare
  v_session record;
  v_inst public.installations%rowtype;
begin
  select * into v_session from public.session_of(p_token);
  if not found or v_session.role <> 'guardia' then
    return query select false, ''::text;
    return;
  end if;

  select * into v_inst from public.installations i
  where i.id = p_installation_id
    and encode(digest(i.access_code, 'sha256'), 'hex') = p_access_code_hash;

  if not found then
    perform public.throttle_after_failure('installation:' || p_installation_id::text);
    return query select false, ''::text;
    return;
  end if;

  update public.sessions set installation_id = v_inst.id where token = p_token;
  return query select true, v_inst.name;
end;
$$;

-- Salir de la instalación sin cerrar sesión (cambio de sitio en el mismo turno).
create or replace function public.leave_installation(p_token uuid)
returns boolean
language plpgsql security definer set search_path = public, extensions as $$
declare v_session record;
begin
  select * into v_session from public.session_of(p_token);
  if not found then return false; end if;
  update public.sessions set installation_id = null where token = p_token;
  return true;
end;
$$;

create or replace function public.logout(p_token uuid)
returns void
language sql security definer set search_path = public, extensions as $$
  delete from public.sessions where token = p_token;
$$;

-- ---------------------------------------------------------
-- 4. Operaciones del guardia (requieren sesión válida)
-- ---------------------------------------------------------
-- El user_id sale de la sesión, no de lo que mande el cliente: así nadie puede
-- registrar posiciones o incidentes a nombre de otro guardia.
create or replace function public.record_gps(
  p_token uuid, p_latitude double precision, p_longitude double precision,
  p_accuracy double precision default null, p_is_mock boolean default false,
  p_battery_level int default null, p_recorded_at timestamptz default now()
)
returns boolean
language plpgsql security definer set search_path = public, extensions as $$
declare v_session record;
begin
  select * into v_session from public.session_of(p_token);
  -- Exige instalación elegida: una ronda sin sitio no se puede supervisar.
  if not found or v_session.installation_id is null then return false; end if;

  insert into public.gps_logs (user_id, latitude, longitude, accuracy, is_mock, battery_level, recorded_at)
  values (v_session.profile_id, p_latitude, p_longitude, p_accuracy, p_is_mock, p_battery_level, p_recorded_at);
  return true;
end;
$$;

-- Solo se aceptan URLs del propio bucket de Storage. Sin esto, un cliente con
-- sesión válida podía guardar cualquier URL y la app del supervisor la cargaba
-- con Image.network: sirve para rastrear cuándo abre un incidente, o para
-- apuntar a hosts internos de su red.
create or replace function public.is_own_storage_url(p_url text)
returns boolean
language sql immutable set search_path = public, extensions as $$
  select p_url is null
      or p_url ~ '^https://[a-z0-9]+\.supabase\.co/storage/v1/object/(public|sign)/incident-photos/';
$$;

create or replace function public.record_incident(
  p_token uuid, p_title text, p_description text, p_photo_url text default null,
  p_recorded_at timestamptz default now()
)
returns boolean
language plpgsql security definer set search_path = public, extensions as $$
declare v_session record;
begin
  select * into v_session from public.session_of(p_token);
  if not found or v_session.installation_id is null then return false; end if;
  if not public.is_own_storage_url(p_photo_url) then return false; end if;

  insert into public.incidents (user_id, title, description, photo_url, recorded_at)
  values (v_session.profile_id, left(p_title, 200), left(p_description, 2000), p_photo_url, p_recorded_at);
  return true;
end;
$$;

create or replace function public.record_log(
  p_token uuid, p_event_type text, p_details text, p_created_at timestamptz default now()
)
returns boolean
language plpgsql security definer set search_path = public, extensions as $$
declare v_session record;
begin
  select * into v_session from public.session_of(p_token);
  if not found then return false; end if;

  insert into public.system_logs (user_id, event_type, details, created_at)
  values (v_session.profile_id, p_event_type, left(p_details, 2000), p_created_at);
  return true;
end;
$$;

-- Respuestas a alertas, con su foto. Va en tabla aparte porque `alerts` queda
-- legible por `anon` para que funcione el realtime: si la foto se guardara ahí,
-- cualquiera con la anon key podría descargar las fotos de confirmación.
create table if not exists public.alert_responses (
  id uuid primary key default gen_random_uuid(),
  alert_id uuid references public.alerts(id) on delete cascade,
  responder_id uuid references public.profiles(id),
  photo_url text,
  responded_at timestamptz not null default now()
);
alter table public.alert_responses enable row level security;

-- Alerta atendida: exige sesión válida, y solo permite confirmar alertas
-- dirigidas a este guardia o sin destinatario concreto. Antes, cualquier
-- sesión podía cerrar la alerta de otro y hacerla desaparecer de su pantalla.
create or replace function public.acknowledge_alert(p_token uuid, p_alert_id uuid, p_photo_url text default null)
returns boolean
language plpgsql security definer set search_path = public, extensions as $$
declare v_session record;
begin
  select * into v_session from public.session_of(p_token);
  if not found then return false; end if;
  if not public.is_own_storage_url(p_photo_url) then return false; end if;

  update public.alerts
  set status = 'acknowledged', responded_at = now()
  where id = p_alert_id
    and (target_user_id is null or target_user_id = v_session.profile_id);

  if not found then return false; end if;

  insert into public.alert_responses (alert_id, responder_id, photo_url)
  values (p_alert_id, v_session.profile_id, p_photo_url);
  return true;
end;
$$;

-- ---------------------------------------------------------
-- 5. Operaciones de supervisión (solo rol superusuario)
-- ---------------------------------------------------------
create or replace function public.is_superuser(p_token uuid)
returns boolean
language plpgsql security definer set search_path = public, extensions as $$
declare v_session record;
begin
  select * into v_session from public.session_of(p_token);
  return found and v_session.role = 'superusuario';
end;
$$;

create or replace function public.admin_gps_logs(p_token uuid, p_limit int default 100)
returns table (id uuid, user_id uuid, latitude double precision, longitude double precision,
               accuracy double precision, is_mock boolean, battery_level int, recorded_at timestamptz)
language plpgsql security definer set search_path = public, extensions as $$
begin
  if not public.is_superuser(p_token) then return; end if;
  return query
    select g.id, g.user_id, g.latitude, g.longitude, g.accuracy, g.is_mock, g.battery_level, g.recorded_at
    from public.gps_logs g order by g.recorded_at desc limit least(p_limit, 500);
end;
$$;

create or replace function public.admin_system_logs(p_token uuid, p_limit int default 200)
returns table (id uuid, user_id uuid, event_type text, details text, created_at timestamptz)
language plpgsql security definer set search_path = public, extensions as $$
begin
  if not public.is_superuser(p_token) then return; end if;
  return query
    select l.id, l.user_id, l.event_type, l.details, l.created_at
    from public.system_logs l order by l.created_at desc limit least(p_limit, 1000);
end;
$$;

create or replace function public.admin_incidents(p_token uuid, p_limit int default 100)
returns table (id uuid, user_id uuid, title text, description text, photo_url text, recorded_at timestamptz)
language plpgsql security definer set search_path = public, extensions as $$
begin
  if not public.is_superuser(p_token) then return; end if;
  return query
    select i.id, i.user_id, i.title, i.description, i.photo_url, i.recorded_at
    from public.incidents i order by i.recorded_at desc limit least(p_limit, 500);
end;
$$;

-- El access_code se devuelve solo al superusuario autenticado: es lo que
-- reparte a sus guardias, pero no puede quedar legible para `anon`.
create or replace function public.admin_installations(p_token uuid)
returns table (id uuid, name text, access_code text, address text, created_at timestamptz)
language plpgsql security definer set search_path = public, extensions as $$
begin
  if not public.is_superuser(p_token) then return; end if;
  return query
    select i.id, i.name, i.access_code, i.address, i.created_at
    from public.installations i order by i.created_at desc;
end;
$$;

create or replace function public.admin_upsert_installation(
  p_token uuid, p_name text, p_access_code text, p_address text default null, p_id uuid default null
)
returns boolean
language plpgsql security definer set search_path = public, extensions as $$
begin
  if not public.is_superuser(p_token) then return false; end if;

  if p_id is null then
    insert into public.installations (name, access_code, address)
    values (left(p_name, 200), p_access_code, left(p_address, 300));
  else
    update public.installations
    set name = left(p_name, 200),
        access_code = coalesce(nullif(p_access_code, ''), access_code),
        address = left(p_address, 300)
    where id = p_id;
  end if;
  return true;
end;
$$;

create or replace function public.admin_delete_installation(p_token uuid, p_id uuid)
returns boolean
language plpgsql security definer set search_path = public, extensions as $$
begin
  if not public.is_superuser(p_token) then return false; end if;
  delete from public.installations where id = p_id;
  return found;
end;
$$;

create or replace function public.admin_guards(p_token uuid)
returns table (id uuid, full_name text, installation_id uuid)
language plpgsql security definer set search_path = public, extensions as $$
begin
  if not public.is_superuser(p_token) then return; end if;
  return query
    select p.id, p.full_name, p.installation_id
    from public.profiles p where p.role = 'guardia' order by p.full_name;
end;
$$;

create or replace function public.admin_upsert_guard(
  p_token uuid, p_full_name text, p_password_hash text,
  p_installation_id uuid, p_id uuid default null
)
returns boolean
language plpgsql security definer set search_path = public, extensions as $$
begin
  if not public.is_superuser(p_token) then return false; end if;

  -- Se guarda bcrypt, nunca el SHA-256 que llega del cliente.
  if p_id is null then
    if p_password_hash is null or p_password_hash = '' then return false; end if;
    insert into public.profiles (role, full_name, password_hash, installation_id)
    values ('guardia', left(p_full_name, 120), crypt(p_password_hash, gen_salt('bf', 10)), p_installation_id);
  else
    update public.profiles
    set full_name = left(p_full_name, 120),
        installation_id = p_installation_id,
        password_hash = case
          when nullif(p_password_hash, '') is null then password_hash
          else crypt(p_password_hash, gen_salt('bf', 10))
        end
    where id = p_id and role = 'guardia';
  end if;
  return true;
end;
$$;

create or replace function public.admin_delete_guard(p_token uuid, p_id uuid)
returns boolean
language plpgsql security definer set search_path = public, extensions as $$
begin
  if not public.is_superuser(p_token) then return false; end if;
  delete from public.profiles where id = p_id and role = 'guardia';
  return found;
end;
$$;

create or replace function public.admin_guard_name_available(p_token uuid, p_full_name text, p_exclude_id uuid default null)
returns boolean
language plpgsql security definer set search_path = public, extensions as $$
begin
  if not public.is_superuser(p_token) then return false; end if;
  return not exists (
    select 1 from public.profiles p
    where p.role = 'guardia' and p.full_name ilike trim(p_full_name)
      and (p_exclude_id is null or p.id <> p_exclude_id)
  );
end;
$$;

create or replace function public.admin_trigger_alert(p_token uuid, p_type text default 'random_check')
returns boolean
language plpgsql security definer set search_path = public, extensions as $$
begin
  if not public.is_superuser(p_token) then return false; end if;
  insert into public.alerts (type, status, triggered_at) values (p_type, 'pending', now());
  return true;
end;
$$;

create or replace function public.admin_change_password(p_token uuid, p_current_hash text, p_new_hash text)
returns boolean
language plpgsql security definer set search_path = public, extensions as $$
declare
  v_session record;
  v_stored text;
begin
  select * into v_session from public.session_of(p_token);
  if not found or v_session.role <> 'superusuario' then return false; end if;

  select password_hash into v_stored from public.profiles where id = v_session.profile_id;
  if not found or not public.verify_password(v_stored, p_current_hash) then
    perform public.throttle_after_failure('superuser_pwchange');
    return false;
  end if;

  update public.profiles
  set password_hash = crypt(p_new_hash, gen_salt('bf', 10))
  where id = v_session.profile_id;
  return true;
end;
$$;

-- ---------------------------------------------------------
-- 5.b Control total del superusuario sobre los datos
-- ---------------------------------------------------------
-- Hasta acá podía administrar instalaciones y guardias, pero no borrar los
-- registros que generan (posiciones, incidentes, logs, alertas). Estas
-- funciones completan ese control.
create or replace function public.admin_delete_incident(p_token uuid, p_id uuid)
returns boolean
language plpgsql security definer set search_path = public, extensions as $$
begin
  if not public.is_superuser(p_token) then return false; end if;
  delete from public.incidents where id = p_id;
  return found;
end;
$$;

create or replace function public.admin_delete_gps_log(p_token uuid, p_id uuid)
returns boolean
language plpgsql security definer set search_path = public, extensions as $$
begin
  if not public.is_superuser(p_token) then return false; end if;
  delete from public.gps_logs where id = p_id;
  return found;
end;
$$;

create or replace function public.admin_delete_system_log(p_token uuid, p_id uuid)
returns boolean
language plpgsql security definer set search_path = public, extensions as $$
begin
  if not public.is_superuser(p_token) then return false; end if;
  delete from public.system_logs where id = p_id;
  return found;
end;
$$;

create or replace function public.admin_delete_alert(p_token uuid, p_id uuid)
returns boolean
language plpgsql security definer set search_path = public, extensions as $$
begin
  if not public.is_superuser(p_token) then return false; end if;
  delete from public.alerts where id = p_id;
  return found;
end;
$$;

-- Purga por antigüedad, para depurar el histórico de una vez.
create or replace function public.admin_purge_older_than(p_token uuid, p_days int)
returns boolean
language plpgsql security definer set search_path = public, extensions as $$
declare v_cutoff timestamptz;
begin
  if not public.is_superuser(p_token) then return false; end if;
  v_cutoff := now() - make_interval(days => greatest(p_days, 1));
  delete from public.gps_logs where recorded_at < v_cutoff;
  delete from public.system_logs where created_at < v_cutoff;
  delete from public.incidents where recorded_at < v_cutoff;
  delete from public.alerts where triggered_at < v_cutoff;
  return true;
end;
$$;

-- Cambiar la contraseña de un guardia sin conocer la anterior: el supervisor
-- es quien las reparte, y necesita poder reponerlas si alguien la olvida.
create or replace function public.admin_reset_guard_password(p_token uuid, p_id uuid, p_new_hash text)
returns boolean
language plpgsql security definer set search_path = public, extensions as $$
begin
  if not public.is_superuser(p_token) then return false; end if;
  if p_new_hash is null or p_new_hash = '' then return false; end if;
  update public.profiles
  set password_hash = crypt(p_new_hash, gen_salt('bf', 10))
  where id = p_id and role = 'guardia';
  return found;
end;
$$;

-- Cerrar la sesión de un guardia a distancia (turno terminado, baja, robo del
-- teléfono). Sin esto, un token robado seguía sirviendo hasta vencer.
create or replace function public.admin_revoke_sessions(p_token uuid, p_profile_id uuid default null)
returns int
language plpgsql security definer set search_path = public, extensions as $$
declare v_count int;
begin
  if not public.is_superuser(p_token) then return 0; end if;
  if p_profile_id is null then
    delete from public.sessions where token <> p_token;
  else
    delete from public.sessions where profile_id = p_profile_id;
  end if;
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

-- ---------------------------------------------------------
-- 6. Cierre: se elimina todo acceso directo de `anon`
-- ---------------------------------------------------------
-- A partir de acá, `select * from installations` con la anon key devuelve
-- vacío. La app solo puede operar a través de las funciones de arriba.
drop policy if exists "OWASP_Installations_Select" on public.installations;
drop policy if exists "OWASP_Installations_All" on public.installations;
drop policy if exists "OWASP_SystemConfig_Select" on public.system_config;
drop policy if exists "OWASP_Profiles_Insert" on public.profiles;
drop policy if exists "OWASP_Profiles_Update" on public.profiles;
drop policy if exists "OWASP_Profiles_Delete" on public.profiles;
drop policy if exists "OWASP_GPS_Insert" on public.gps_logs;
drop policy if exists "OWASP_GPS_Select" on public.gps_logs;
drop policy if exists "OWASP_Alerts_All" on public.alerts;
drop policy if exists "OWASP_Incidents_Insert" on public.incidents;
drop policy if exists "OWASP_Incidents_Select" on public.incidents;
drop policy if exists "OWASP_SystemLogs_Insert" on public.system_logs;
drop policy if exists "OWASP_SystemLogs_Select" on public.system_logs;

-- Realtime de alertas: el guardia necesita enterarse al instante. Se permite
-- solo SELECT; las fotos de confirmación viven en alert_responses, que no es
-- legible desde fuera, así que aquí solo quedan tipo, estado y marcas de tiempo.
drop policy if exists "Alerts_Realtime_Select" on public.alerts;
create policy "Alerts_Realtime_Select" on public.alerts for select using (true);

-- La columna photo_url de alerts queda obsoleta: cualquiera con la anon key
-- podía leerla. Se migra lo que hubiera a alert_responses y se vacía.
insert into public.alert_responses (alert_id, photo_url, responded_at)
select a.id, a.photo_url, coalesce(a.responded_at, now())
from public.alerts a
where a.photo_url is not null
  and not exists (select 1 from public.alert_responses r where r.alert_id = a.id);
update public.alerts set photo_url = null where photo_url is not null;

-- ---------------------------------------------------------
-- 6.b Storage: el bucket deja de ser público
-- ---------------------------------------------------------
-- Estaba abierto de par en par: cualquiera con la anon key podía subir
-- archivos arbitrarios (llenar el almacenamiento, alojar contenido en tu
-- dominio) y descargar todas las fotos de incidentes con solo tener la URL.
-- Al pasarlo a privado, las URLs públicas dejan de resolver y hay que pedir
-- URLs firmadas, que caducan.
update storage.buckets set public = false where id = 'incident-photos';

drop policy if exists "OWASP_Storage_IncidentPhotos_Insert" on storage.objects;
drop policy if exists "OWASP_Storage_IncidentPhotos_Select" on storage.objects;
drop policy if exists "Storage_IncidentPhotos_Insert" on storage.objects;
drop policy if exists "Storage_IncidentPhotos_Select" on storage.objects;

-- Subida acotada al bucket y a imágenes; sin esto se podía subir cualquier
-- tipo de archivo.
create policy "Storage_IncidentPhotos_Insert" on storage.objects
  for insert with check (
    bucket_id = 'incident-photos'
    and (storage.foldername(name))[1] in ('incidents', 'alerts')
    and lower(right(name, 4)) in ('.jpg', 'jpeg', '.png')
  );

create policy "Storage_IncidentPhotos_Select" on storage.objects
  for select using (bucket_id = 'incident-photos');

-- Revocar el acceso a las funciones viejas, que devolvían datos sin exigir
-- sesión y quedarían como puerta trasera.
revoke execute on function public.login_profile(text, text) from anon, authenticated;
revoke execute on function public.login_superuser(text) from anon, authenticated;
revoke execute on function public.login_installation(text) from anon, authenticated;
revoke execute on function public.list_guard_profiles() from anon, authenticated;
revoke execute on function public.list_guard_profiles_by_installation(uuid) from anon, authenticated;
revoke execute on function public.guard_name_available(text, uuid) from anon, authenticated;
revoke execute on function public.update_superuser_password(text, text) from anon, authenticated;

grant execute on function public.login(text, text) to anon, authenticated;
grant execute on function public.logout(uuid) to anon, authenticated;
grant execute on function public.available_installations(uuid) to anon, authenticated;
grant execute on function public.enter_installation(uuid, uuid, text) to anon, authenticated;
grant execute on function public.leave_installation(uuid) to anon, authenticated;
grant execute on function public.record_gps(uuid, double precision, double precision, double precision, boolean, int, timestamptz) to anon, authenticated;
grant execute on function public.record_incident(uuid, text, text, text, timestamptz) to anon, authenticated;
grant execute on function public.record_log(uuid, text, text, timestamptz) to anon, authenticated;
grant execute on function public.acknowledge_alert(uuid, uuid, text) to anon, authenticated;
grant execute on function public.admin_gps_logs(uuid, int) to anon, authenticated;
grant execute on function public.admin_system_logs(uuid, int) to anon, authenticated;
grant execute on function public.admin_incidents(uuid, int) to anon, authenticated;
grant execute on function public.admin_installations(uuid) to anon, authenticated;
grant execute on function public.admin_upsert_installation(uuid, text, text, text, uuid) to anon, authenticated;
grant execute on function public.admin_delete_installation(uuid, uuid) to anon, authenticated;
grant execute on function public.admin_guards(uuid) to anon, authenticated;
grant execute on function public.admin_upsert_guard(uuid, text, text, uuid, uuid) to anon, authenticated;
grant execute on function public.admin_delete_guard(uuid, uuid) to anon, authenticated;
grant execute on function public.admin_guard_name_available(uuid, text, uuid) to anon, authenticated;
grant execute on function public.admin_trigger_alert(uuid, text) to anon, authenticated;
grant execute on function public.admin_change_password(uuid, text, text) to anon, authenticated;
grant execute on function public.admin_delete_incident(uuid, uuid) to anon, authenticated;
grant execute on function public.admin_delete_gps_log(uuid, uuid) to anon, authenticated;
grant execute on function public.admin_delete_system_log(uuid, uuid) to anon, authenticated;
grant execute on function public.admin_delete_alert(uuid, uuid) to anon, authenticated;
grant execute on function public.admin_purge_older_than(uuid, int) to anon, authenticated;
grant execute on function public.admin_reset_guard_password(uuid, uuid, text) to anon, authenticated;
grant execute on function public.admin_revoke_sessions(uuid, uuid) to anon, authenticated;

-- IMPORTANTE: Postgres concede EXECUTE a PUBLIC por defecto en cada función,
-- y `anon` hereda de PUBLIC. Revocar solo "from anon" no quita nada: hay que
-- revocar de PUBLIC y recién después conceder a quien corresponda.
--
-- purge_expired_sessions es mantenimiento (pg_cron o manual). Los demás son
-- auxiliares internos: verify_password dejaría probar contraseñas salteándose
-- el freno de fuerza bruta, session_of expondría el rol y la instalación de
-- cualquier token, y upgrade_password_hash reescribiría hashes.
revoke execute on function public.purge_expired_sessions() from public, anon, authenticated;
revoke execute on function public.verify_password(text, text) from public, anon, authenticated;
revoke execute on function public.upgrade_password_hash(uuid, text) from public, anon, authenticated;
revoke execute on function public.throttle_after_failure(text) from public, anon, authenticated;
revoke execute on function public.is_rate_limited(text, int, int) from public, anon, authenticated;
revoke execute on function public.record_attempt(text, boolean) from public, anon, authenticated;
revoke execute on function public.session_of(uuid) from public, anon, authenticated;
revoke execute on function public.is_superuser(uuid) from public, anon, authenticated;
revoke execute on function public.is_own_storage_url(text) from public, anon, authenticated;

-- Las funciones viejas tampoco deben quedar accesibles vía PUBLIC.
revoke execute on function public.login_profile(text, text) from public;
revoke execute on function public.login_superuser(text) from public;
revoke execute on function public.login_installation(text) from public;
revoke execute on function public.list_guard_profiles() from public;
revoke execute on function public.list_guard_profiles_by_installation(uuid) from public;
revoke execute on function public.guard_name_available(text, uuid) from public;
revoke execute on function public.update_superuser_password(text, text) from public;

-- Las funciones security definer alcanzan las tablas con permisos del owner,
-- así que `anon` no necesita ningún grant directo sobre ellas.
revoke all on public.profiles, public.installations, public.gps_logs,
  public.incidents, public.system_logs, public.system_config, public.sessions,
  public.alert_responses, public.auth_attempts
  from anon, authenticated;
grant select on public.alerts to anon, authenticated;
