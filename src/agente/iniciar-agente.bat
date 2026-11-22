@echo off
rem Inicia el agente de SON. Se puede poner un acceso directo de este archivo en la carpeta
rem de Inicio de Windows (shell:startup) para que arranque solo al prender la PC.
cd /d "%~dp0"
:reiniciar
node agente.js
echo El agente se cerro. Reiniciando en 10 segundos...
timeout /t 10 /nobreak >nul
goto reiniciar
