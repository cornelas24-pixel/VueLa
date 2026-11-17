@echo off
chcp 65001 >nul
rem Respaldo completo: base vuela_db (desde Docker) + copia de toda la carpeta del proyecto en el Escritorio.
set CONTENEDOR=postgres-clase
set USUARIO=admin
set BASE=vuela_db
cd /d "%~dp0"
for /f %%t in ('powershell -NoProfile -Command "Get-Date -Format yyyyMMdd-HHmm"') do set TS=%%t
set LOG=%~dp0respaldo\respaldo_%TS%.log
if not exist respaldo mkdir respaldo
echo Respaldo %TS% > "%LOG%"

echo ===== 1. Base %BASE% (formato custom, para pg_restore) >> "%LOG%"
docker exec %CONTENEDOR% pg_dump -U %USUARIO% -Fc -f /tmp/vuela_db.dump %BASE% >> "%LOG%" 2>&1
docker cp %CONTENEDOR%:/tmp/vuela_db.dump "respaldo\vuela_db_%TS%.dump" >> "%LOG%" 2>&1
echo ===== 2. Base %BASE% (SQL de texto, legible) >> "%LOG%"
docker exec %CONTENEDOR% pg_dump -U %USUARIO% --no-owner -f /tmp/vuela_db.sql %BASE% >> "%LOG%" 2>&1
docker cp %CONTENEDOR%:/tmp/vuela_db.sql "respaldo\vuela_db_%TS%.sql" >> "%LOG%" 2>&1
echo ===== 3. Contenido del respaldo (objetos) >> "%LOG%"
docker exec %CONTENEDOR% sh -c "pg_restore -l /tmp/vuela_db.dump | grep -c ';'" >> "%LOG%" 2>&1
echo ===== 4. Conteos por tabla al momento del respaldo >> "%LOG%"
docker exec %CONTENEDOR% psql -X -U %USUARIO% -d %BASE% -c "SELECT 'usuarios' t, count(*) FROM usuarios UNION ALL SELECT 'especies', count(*) FROM especies UNION ALL SELECT 'sitios', count(*) FROM sitios UNION ALL SELECT 'avistamientos', count(*) FROM avistamientos UNION ALL SELECT 'detecciones', count(*) FROM detecciones UNION ALL SELECT 'revisiones', count(*) FROM revisiones UNION ALL SELECT 'bitacora_auditoria', count(*) FROM bitacora_auditoria" >> "%LOG%" 2>&1

echo ===== 5. Copia de la carpeta del proyecto >> "%LOG%"
set DESTINO=%USERPROFILE%\Desktop\VueLa-respaldo-%TS%
robocopy "%~dp0.." "%DESTINO%" /E /NFL /NDL /NJH /NP >> "%LOG%" 2>&1
echo Destino: %DESTINO% >> "%LOG%"
dir /s "%DESTINO%" | findstr /c:"archivos" /c:"File(s)" >> "%LOG%"
copy "%LOG%" "%DESTINO%\db\respaldo\" >nul
echo ===== FIN >> "%LOG%"
type "%LOG%"
