@echo off
REM Duplo-clique aqui (ou rode de qualquer pasta) pra exportar e publicar no itch.
REM %~dp0 = a pasta deste .bat, entao o caminho nunca depende de onde voce esta.
powershell -ExecutionPolicy Bypass -File "%~dp0tools\publish_itch.ps1"
echo.
pause
