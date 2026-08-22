@echo off
REM Abre o console do servidor de Minecraft que roda na VPS.
REM
REM Detalhes que evitam acidente:
REM  --detach-keys=ctrl-x  troca a sequencia padrao (Ctrl+P Ctrl+Q) por algo
REM                        que da para lembrar.
REM  --sig-proxy=false     impede que um Ctrl+C seja repassado ao servidor.
REM                        Sem isso, um Ctrl+C distraido derruba o Minecraft.

title Console do servidor Minecraft
echo ==============================================================
echo   CONSOLE DO SERVIDOR
echo.
echo   Para SAIR sem derrubar o servidor:   Ctrl + X
echo.
echo   Tudo que voce digitar vai direto para o console do jogo.
echo   Digitar "stop" DESLIGA o servidor de verdade.
echo.
echo   Exemplos:  list           quem esta online
echo              lp info        estado do LuckPerms
echo              worldborder get
echo ==============================================================
echo.
pause

ssh -t root@168.231.89.180 "docker attach --detach-keys=ctrl-x --sig-proxy=false minecraft"

echo.
echo Console fechado. O servidor continua rodando.
pause
