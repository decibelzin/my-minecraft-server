#!/usr/bin/env bash
set -euo pipefail

DATA_DIR=/data
JAR=/opt/paper.jar

# --- de onde vem a configuracao -------------------------------------
# Se o repositorio estiver montado (o compose monta em /opt/repo), ele
# manda. Sem o mount, usa o que foi embutido na imagem no build.
# O mount e o que faz "git pull + restart" bastar: sem ele seria
# preciso rebuildar a imagem a cada mudanca de config.
if [ -d /opt/repo ]; then
  ORIGEM=/opt/repo
else
  ORIGEM=/opt/defaults
fi
echo "[init] configuracao vinda de $ORIGEM"

# --- server.properties -----------------------------------------------
# O arquivo versionado e a fonte de verdade e sobrescreve o de /data a
# cada boot, tornando impossivel a config divergir em silencio do git.
cp "$ORIGEM/server.properties" "$DATA_DIR/server.properties"

# --- configs de plugin -----------------------------------------------
# Copia por cima somente os arquivos versionados, preservando o que o
# plugin cria sozinho: contas registradas, caches, estatisticas.
if [ -d "$ORIGEM/plugins-config" ]; then
  mkdir -p "$DATA_DIR/plugins"
  cp -r "$ORIGEM/plugins-config/." "$DATA_DIR/plugins/"
  echo "[init] configs de plugin sincronizadas"
fi
# --- EULA -------------------------------------------------------------
# Escrito exclusivamente a partir da variavel de ambiente: e o unico
# ponto onde voce declara que leu e aceitou os termos da Mojang.
if [ "${EULA:-false}" = "true" ]; then
  echo "eula=true" > "$DATA_DIR/eula.txt"
else
  cat >&2 <<'MSG'

================================================================
  O servidor nao pode iniciar: o EULA da Mojang nao foi aceito.

  1. Leia:  https://aka.ms/MinecraftEULA
  2. Se concordar, coloque EULA=true no arquivo .env
  3. Suba de novo:  docker compose up -d

  Essa aceitacao precisa ser um ato seu, entao o padrao e false.
================================================================

MSG
  exit 1
fi

MEMORY="${MEMORY:-6G}"
echo "[init] Paper subindo com heap de ${MEMORY}"

# Flags de GC recomendadas oficialmente pelo PaperMC (G1GC / "Aikar's flags"),
# obtidas da API deles para a versao 26.2.
JVM_FLAGS=(
  -Xms"${MEMORY}" -Xmx"${MEMORY}"
  -XX:+AlwaysPreTouch
  -XX:+DisableExplicitGC
  -XX:+ParallelRefProcEnabled
  -XX:+PerfDisableSharedMem
  -XX:+UnlockExperimentalVMOptions
  -XX:+UseG1GC
  -XX:G1HeapRegionSize=8M
  -XX:G1HeapWastePercent=5
  -XX:G1MaxNewSizePercent=40
  -XX:G1MixedGCCountTarget=4
  -XX:G1MixedGCLiveThresholdPercent=90
  -XX:G1NewSizePercent=30
  -XX:G1RSetUpdatingPauseTimePercent=5
  -XX:G1ReservePercent=20
  -XX:InitiatingHeapOccupancyPercent=15
  -XX:MaxGCPauseMillis=200
  -XX:MaxTenuringThreshold=1
  -XX:SurvivorRatio=32
)

# exec: o java vira PID 1 e recebe o SIGTERM do "docker stop" direto,
# salvando o mundo antes de morrer.
exec java "${JVM_FLAGS[@]}" -jar "$JAR" --nogui
