#!/usr/bin/env bash
# Backup do mundo. Funciona no Git Bash (Windows) e na VPS, tanto com o
# servidor nativo quanto no container.
#
#   ./scripts/backup-world.sh          para o servidor se puder, copia, religa
#   ./scripts/backup-world.sh --hot    copia com o servidor no ar (assumindo o risco)
#
# Copiar chunks enquanto o servidor grava neles pode gerar um backup
# corrompido justamente no dia que voce precisar dele. Por isso o modo
# padrao se recusa a rodar com o servidor de pe quando nao consegue
# para-lo sozinho, em vez de fazer copia quente em silencio.
set -euo pipefail

cd "$(dirname "$0")/.."

HOT=false
[ "${1:-}" = "--hot" ] && HOT=true

KEEP=7
STAMP="$(date +%Y-%m-%d_%H%M%S)"
DEST="backups/world_${STAMP}.tar.gz"

if [ ! -d data ]; then
  echo "erro: pasta data/ nao existe - o servidor ainda nao rodou" >&2
  exit 1
fi

mkdir -p backups

# --- Descobre se o servidor esta no ar --------------------------------
# A porta vem do server.properties da raiz, que e a fonte de verdade.
# Deixar 25565 fixo aqui daria falso negativo em quem trocou a porta -
# e falso negativo, num script de backup, significa copia quente
# silenciosa. Por isso o fallback e conservador.
PORTA="$(grep -E '^server-port=' server.properties 2>/dev/null | head -1 | cut -d= -f2 | tr -d '[:space:]')"
: "${PORTA:=25565}"

porta_aberta() {
  (exec 3<>/dev/tcp/127.0.0.1/"$PORTA") 2>/dev/null && return 0 || return 1
}

container_rodando() {
  command -v docker >/dev/null 2>&1 || return 1
  docker compose ps --status running 2>/dev/null | grep -q minecraft
}

RELIGAR=false

if [ "$HOT" = false ]; then
  if container_rodando; then
    echo "[backup] container detectado; parando para copia consistente..."
    docker compose stop
    RELIGAR=true
  elif porta_aberta; then
    # Servidor nativo no ar: nao temos como para-lo daqui com seguranca,
    # porque quem salva o mundo e o comando "stop" no console dele.
    cat >&2 <<'MSG'

================================================================
  O servidor esta rodando, mas nao e um container - provavelmente
  foi iniciado pelo start.ps1.

  Nao da para para-lo daqui: quem salva o mundo direito e o comando
  "stop" digitado no console do proprio servidor.

  Escolha uma:
    a) digite "stop" no console, espere salvar, e rode este script
    b) rode com --hot para copiar mesmo assim, assumindo o risco
       de pegar um chunk no meio da gravacao
================================================================

MSG
    exit 1
  fi
fi

if [ "$HOT" = true ] && porta_aberta; then
  echo "[backup] AVISO: copia quente com o servidor no ar - pode sair inconsistente."
fi

# --- Compacta ---------------------------------------------------------
# Na 26.2 as tres dimensoes vivem dentro de world/dimensions/minecraft/,
# entao copiar "world" ja leva overworld, nether e end. Os nomes
# world_nether/world_the_end sao do layout antigo do Bukkit e ficam na
# lista so para quem restaurar um mundo velho; hoje sao ignorados.
ALVOS=()
for item in world world_nether world_the_end server.properties; do
  [ -e "data/$item" ] && ALVOS+=("$item")
done

if [ ${#ALVOS[@]} -eq 0 ]; then
  echo "erro: nada para copiar dentro de data/" >&2
  exit 1
fi

echo "[backup] compactando ${#ALVOS[@]} itens em ${DEST}"
tar -czf "$DEST" -C data "${ALVOS[@]}"

if [ "$RELIGAR" = true ]; then
  echo "[backup] religando o container..."
  docker compose start
fi

# --- Retencao: mantem os KEEP mais recentes ---------------------------
COUNT=$(ls -1 backups/world_*.tar.gz 2>/dev/null | wc -l)
if [ "$COUNT" -gt "$KEEP" ]; then
  ls -1t backups/world_*.tar.gz | tail -n +$((KEEP + 1)) | while read -r antigo; do
    echo "[backup] removendo antigo: $antigo"
    rm -f "$antigo"
  done
fi

echo "[backup] pronto: $(du -h "$DEST" | cut -f1)  ${DEST}"
