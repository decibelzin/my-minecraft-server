#!/usr/bin/env bash
# Aplica na VPS o que foi enviado ao repositorio.
#
#   ./scripts/deploy.sh
#
# Decide sozinho entre restart e rebuild, porque a escolha errada faz a
# mudanca simplesmente nao aparecer - e isso e dificil de perceber.
#
# O argumento opcional e interno: e o commit de antes do pull, usado quando o
# script se reexecuta. Nao passe na mao.
set -euo pipefail

cd "$(dirname "$0")/.."

if [ -n "${1:-}" ]; then
  ANTES="$1"                      # ja viemos de um pull; nao puxar de novo
else
  ANTES="$(git rev-parse HEAD)"
  echo "[deploy] buscando atualizacoes..."
  git pull --ff-only -q
fi
DEPOIS="$(git rev-parse HEAD)"

if [ "$ANTES" = "$DEPOIS" ]; then
  echo "[deploy] repositorio ja estava atualizado ($(git log --oneline -1))"
  echo "[deploy] nada a fazer."
  exit 0
fi

echo "[deploy] $(git log --oneline -1)"
MUDOU="$(git diff --name-only "$ANTES" "$DEPOIS")"
echo "[deploy] arquivos alterados:"
echo "$MUDOU" | sed 's/^/           /'
echo

# O git pull pode ter reescrito este proprio arquivo enquanto ele roda. O bash
# le o script conforme executa, entao continuar daqui usaria a logica antiga -
# foi assim que a etapa do GriefPrevention nao rodou no deploy que a
# introduziu. Reexecutar e a unica forma de rodar o que acabou de chegar.
if [ -z "${1:-}" ] && echo "$MUDOU" | grep -q '^scripts/deploy.sh$'; then
  echo "[deploy] o proprio deploy.sh mudou; reiniciando com a versao nova"
  echo
  exec "$0" "$ANTES"
fi

# Lista de plugins mudou: baixa antes de subir, senao o servidor sobe sem eles
if echo "$MUDOU" | grep -q '^scripts/download-plugins.sh$'; then
  echo "[deploy] lista de plugins mudou, sincronizando..."
  ./scripts/download-plugins.sh
  echo
fi

# O GriefPrevention e compilado do fonte, entao mudar o commit fixado na
# receita significa reconstruir o jar antes de subir.
if echo "$MUDOU" | grep -q '^scripts/build-griefprevention.sh$'; then
  echo "[deploy] receita do GriefPrevention mudou, recompilando..."
  ./scripts/build-griefprevention.sh
  echo
fi

# Dockerfile e entrypoint vivem dentro da imagem: exigem rebuild.
# server.properties e plugins-config vem do mount somente-leitura,
# entao para eles um restart basta.
if echo "$MUDOU" | grep -qE '^(Dockerfile|docker/entrypoint.sh|docker-compose.yml)$'; then
  echo "[deploy] a imagem mudou -> rebuild"
  docker compose up -d --build
else
  echo "[deploy] apenas configuracao -> restart"
  docker compose restart
fi

echo
echo "[deploy] aguardando o servidor ficar saudavel..."
for i in $(seq 1 40); do
  estado="$(docker inspect --format '{{.State.Health.Status}}' minecraft 2>/dev/null || echo desconhecido)"
  if [ "$estado" = "healthy" ]; then
    echo "[deploy] pronto: $(docker compose logs --tail 300 2>/dev/null | grep -oE 'Done \([0-9.]+s\)!' | tail -1)"
    exit 0
  fi
  if [ "$estado" = "unhealthy" ]; then
    echo "[deploy] ERRO: container unhealthy. Ultimas linhas:" >&2
    docker compose logs --tail 25 >&2
    exit 1
  fi
  sleep 6
done

echo "[deploy] AVISO: nao ficou healthy em 4 minutos. Ultimas linhas:" >&2
docker compose logs --tail 25 >&2
exit 1
