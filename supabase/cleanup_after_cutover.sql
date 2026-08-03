-- =========================================================
-- LIMPIEZA POST-DESPLIEGUE
-- =========================================================
-- CORRER ESTO SOLO DESPUÉS de confirmar que la app nueva (compilada con
-- --dart-define-from-file=.env) entra correctamente como superusuario.
--
-- Por qué va aparte de schema.sql: la versión ANTERIOR de la app lee la
-- contraseña del superusuario desde system_config.super_password. Si se borra
-- esa fila antes del cambio de versión, la app vieja que está en producción
-- deja de poder iniciar sesión. schema.sql es aditivo a propósito -- deja las
-- dos versiones funcionando -- y este script cierra la puerta al final.
--
-- Qué resuelve: hoy esa contraseña está en texto plano en una tabla que
-- cualquiera con la anon key (extraíble del APK o del bundle web) puede leer
-- con un simple select. La app nueva ya no lee system_config en absoluto.

-- 1. Verificación previa: tiene que devolver 1 fila. Si devuelve 0, NO sigas:
--    significa que el superusuario no quedó migrado a profiles y te quedarías
--    sin acceso.
select id, full_name from public.profiles where role = 'superusuario';

-- 2. Eliminar la contraseña en texto plano.
delete from public.system_config where key = 'super_password';

-- 3. Cerrar la lectura pública de system_config. Ninguna parte de la app
--    la consulta, así que no hace falta exponerla a anon.
drop policy if exists "OWASP_SystemConfig_Select" on public.system_config;

-- 4. Confirmación: ambas consultas deben devolver 0 filas.
select * from public.system_config where key = 'super_password';
select policyname from pg_policies
where schemaname = 'public' and tablename = 'system_config';
