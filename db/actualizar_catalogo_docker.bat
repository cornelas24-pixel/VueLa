@echo off
chcp 65001 >nul
rem Carga fotos y textos del catálogo en vuela_db (contenedor de Docker), sin borrar datos.
set CONTENEDOR=postgres-clase
set USUARIO=admin
set BASE=vuela_db
cd /d "%~dp0"
docker exec -i %CONTENEDOR% psql -X -q -U %USUARIO% -d %BASE% < actualizar_catalogo.sql > actualizar_catalogo.log 2>&1
type actualizar_catalogo.log
echo.
pause
