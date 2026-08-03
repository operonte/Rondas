-- =========================================================
-- ROTACIÓN DE CREDENCIALES
-- =========================================================
-- Correr DESPUÉS de schema.sql y security_sessions.sql, y después de
-- comprobar que la app nueva inicia sesión con la contraseña actual.
--
-- Por qué es necesaria, aunque las políticas ya estén cerradas:
--
-- 1. La contraseña inicial estuvo commiteada en texto plano en un repositorio público
--    de GitHub. Reescribir el historial la sacó de la rama, pero no hay forma
--    de saber quién la copió, ni de borrarla de clones, forks o cachés de
--    terceros. Una credencial que estuvo expuesta se considera comprometida
--    para siempre: lo único que la neutraliza es cambiarla.
--
-- 2. Además vivía en texto plano dentro de system_config.super_password, en
--    una tabla que cualquiera con la anon key podía leer con un select.
--
-- 3. Es corta y con forma de palabra + número: es justo el patrón que prueban
--    primero los ataques de diccionario.
--
-- ESTE ARCHIVO ES UNA PLANTILLA Y ESTÁ EN UN REPOSITORIO PÚBLICO.
-- Reemplazá los marcadores por las contraseñas reales EN TU COPIA LOCAL y no
-- commitees ese cambio. La versión con los valores reales está en
-- `rotate_credentials.local.sql`, que .gitignore excluye.
--
-- Escribir una contraseña real acá es justamente lo que dejó expuesta la
-- anterior: quedó en el historial de git de un repo público, y reescribir el
-- historial no la borra de los clones que otros ya hicieron.

-- 1. Nueva contraseña de superusuario (bcrypt, con sal).
update public.profiles
set password_hash = crypt(
      encode(digest('REEMPLAZAR_CONTRASENA_SUPERUSUARIO', 'sha256'), 'hex'),
      gen_salt('bf', 10))
where role = 'superusuario';

-- 2. Nuevo código de acceso de la instalación demo.
--    Si tenés más instalaciones, repetí el update cambiando el nombre.
update public.installations
set access_code = 'REEMPLAZAR_CODIGO_INSTALACION'
where name = 'demo';

-- 3. Eliminar la contraseña en texto plano que dejó la versión anterior.
delete from public.system_config where key = 'super_password';

-- 4. Cerrar todas las sesiones abiertas: si alguien tenía una sesión activa
--    con la credencial vieja, cambiar la contraseña no lo expulsa por sí solo.
delete from public.sessions;

-- 5. Verificación. La primera consulta debe devolver 1 fila; las otras dos, 0.
select 'superusuario migrado a bcrypt' as verificacion, count(*) as filas
from public.profiles
where role = 'superusuario' and password_hash like '$2%';

select 'texto plano restante (debe ser 0)', count(*)
from public.system_config where key = 'super_password';

select 'sesiones abiertas (debe ser 0)', count(*) from public.sessions;
