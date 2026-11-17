@echo off
chcp 65001 >nul
rem Crea vuela_db y vuela_restore (si no existen) y carga 01, 02 y 03 en vuela_db
rem dentro del contenedor de Docker. Cambia estos valores si tu contenedor es otro.
set CONTENEDOR=postgres-clase
set USUARIO=admin
set BASE=vuela_db

cd /d "%~dp0"
echo Contenedor %CONTENEDOR%, base %BASE% > cargar_base.log
for %%b in (%BASE% vuela_restore) do (
  docker exec %CONTENEDOR% psql -X -q -U %USUARIO% -d postgres -tAc "SELECT 1 FROM pg_database WHERE datname = '%%b'" | findstr 1 >nul || (
    echo Creando la base %%b... >> cargar_base.log
    docker exec %CONTENEDOR% createdb -U %USUARIO% %%b >> cargar_base.log 2>&1
  )
)
for %%f in (01_estructura.sql 02_datos.sql 03_triggers_procedimientos.sql) do (
  echo ===== %%f >> cargar_base.log
  docker exec -i %CONTENEDOR% psql -X -q -U %USUARIO% -d %BASE% < %%f >> cargar_base.log 2>&1
)
echo ===== FIN >> cargar_base.log
type cargar_base.log
echo.
echo Revisa arriba: no debe aparecer ninguna linea con FALLA ni ERROR.
pause
