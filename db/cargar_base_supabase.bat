@echo off
chcp 65001 >nul
setlocal
rem Carga 01, 02 y 03 en la base de Supabase usando los datos de server\.env.
rem Usa el psql que ya trae el contenedor de Docker (no hace falta instalar nada).
rem La contraseña nunca se escribe en este archivo: se lee de server\.env.
set CONTENEDOR=postgres-clase
cd /d "%~dp0"
for /f "usebackq eol=# tokens=1,* delims==" %%a in ("%~dp0..\server\.env") do set "%%a=%%b"
echo Conectando a %PGHOST%:%PGPORT% base %PGDATABASE% usuario %PGUSER% > cargar_supabase.log
docker exec -e PGPASSWORD -e PGSSLMODE=require %CONTENEDOR% psql -X -q -h %PGHOST% -p %PGPORT% -U %PGUSER% -d %PGDATABASE% -tAc "SELECT 'Conectado: ' || version()" >> cargar_supabase.log 2>&1
for %%f in (01_estructura.sql 02_datos.sql 03_triggers_procedimientos.sql) do (
  echo ===== %%f >> cargar_supabase.log
  docker exec -i -e PGPASSWORD -e PGSSLMODE=require %CONTENEDOR% psql -X -q -h %PGHOST% -p %PGPORT% -U %PGUSER% -d %PGDATABASE% < %%f >> cargar_supabase.log 2>&1
)
echo ===== FIN >> cargar_supabase.log
type cargar_supabase.log
endlocal
