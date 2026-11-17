@echo off
chcp 65001 >nul
rem Arranca el servidor de VueLa en http://localhost:3000 (doble clic en este archivo).
cd /d "%~dp0"
where node >nul 2>nul
if errorlevel 1 (
  echo No se encontro Node.js. Instala la version LTS desde https://nodejs.org y vuelve a abrir este archivo.
  pause
  exit /b 1
)
echo Node.js:
node -v
if not exist node_modules (
  echo Instalando dependencias, solo la primera vez...
  call npm install
  if errorlevel 1 ( pause & exit /b 1 )
)
if not exist .env (
  copy .env.example .env >nul
  echo Se creo server\.env: escribe tu contrasena de PostgreSQL, guarda y vuelve a abrir este archivo.
  notepad .env
  pause
  exit /b 1
)
echo.
echo Abre http://localhost:3000 en el navegador. Para apagar el servidor presiona Ctrl+C.
echo.
call npm start
pause
