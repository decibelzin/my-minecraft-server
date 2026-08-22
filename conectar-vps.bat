@echo off
REM Abre um shell na VPS, ja dentro da pasta do projeto.
REM A autenticacao e por chave (%USERPROFILE%\.ssh\id_ed25519), sem senha.

title VPS - my-minecraft-server
echo Conectando em root@168.231.89.180 ...
echo.

REM -t forca a alocacao de terminal: sem isso o shell remoto abre sem prompt.
ssh -t root@168.231.89.180 "cd /opt/my-minecraft-server 2>/dev/null; exec bash"

echo.
echo Conexao encerrada.
pause
