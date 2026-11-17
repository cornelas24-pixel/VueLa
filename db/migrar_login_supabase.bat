@echo off
chcp 65001 >nul
setlocal
rem Agrega el inicio de sesión a la base de Supabase sin borrar datos (migracion_login.sql).
rem Antes saca un respaldo de Supabase en db\respaldo. Usa los datos de server\.env y el
rem psql/pg_dump del contenedor de Docker (Docker Desktop debe estar abierto).
set CONTENEDOR=postgres-clase
cd /d "%~dp0"
for /f "usebackq eol=# tokens=1,* delims==" %%a in ("%~dp0..\server\.env") do set "%%a=%%b"
for /f %%t in ('powershell -NoProfile -Command "Get-Date -Format yyyyMMdd-HHmm"') do set TS=%%t
set LOG=migrar_login_supabase.log
echo Migración del login en %PGHOST% (base %PGDATABASE%) %TS% > %LOG%
echo ===== 0. Docker >> %LOG%
docker info >nul 2>&1
if errorlevel 1 ( echo Docker Desktop no está abierto: ábrelo, espera a que diga que está listo y vuelve a correr este archivo. >> %LOG% & type %LOG% & pause & exit /b 1 )
docker start %CONTENEDOR% >> %LOG% 2>&1
echo ===== 1. Respaldo previo >> %LOG%
docker exec -e PGPASSWORD -e PGSSLMODE=require %CONTENEDOR% pg_dump -h %PGHOST% -p %PGPORT% -U %PGUSER% -d %PGDATABASE% -n public -Fc -f /tmp/supabase_antes_login.dump >> %LOG% 2>&1
if errorlevel 1 ( echo No se pudo sacar el respaldo: no se migra. >> %LOG% & type %LOG% & pause & exit /b 1 )
docker cp %CONTENEDOR%:/tmp/supabase_antes_login.dump "respaldo\supabase_antes_login_%TS%.dump" >> %LOG% 2>&1
echo Respaldo: respaldo\supabase_antes_login_%TS%.dump >> %LOG%
echo ===== 2. migracion_login.sql >> %LOG%
docker exec -i -e PGPASSWORD -e PGSSLMODE=require %CONTENEDOR% psql -X -q -v ON_ERROR_STOP=1 -h %PGHOST% -p %PGPORT% -U %PGUSER% -d %PGDATABASE% < migracion_login.sql >> %LOG% 2>&1
if errorlevel 1 ( echo ERROR: la migración no se aplicó; la base quedó como estaba. >> %LOG% ) else ( echo Migración aplicada. >> %LOG% )
echo ===== FIN >> %LOG%
type %LOG%
endlocal
