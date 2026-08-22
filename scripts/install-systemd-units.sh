#!/usr/bin/env bash
# Instala no host as unidades systemd deste repositorio.
#
#   sudo ./scripts/install-systemd-units.sh
#
# Por que isto nao esta no entrypoint: as unidades rodam no host, fora do
# container, e o container nao pode nem deve mexer no systemd da maquina.
# Entao elas vivem versionadas em systemd/ e sao instaladas por aqui.
#
# E idempotente: rodar de novo apenas reescreve e recarrega.
set -euo pipefail

cd "$(dirname "$0")/.."
RAIZ="$PWD"
DEST=/etc/systemd/system

if [ "$(id -u)" != "0" ]; then
  echo "erro: precisa de root para escrever em $DEST." >&2
  exit 1
fi

if ! command -v systemctl >/dev/null 2>&1; then
  echo "erro: este host nao usa systemd (no Windows, use o Agendador de Tarefas)." >&2
  exit 1
fi

instaladas=0
for unidade in systemd/*.service systemd/*.timer; do
  [ -e "$unidade" ] || continue
  nome="$(basename "$unidade")"
  # @RAIZ@ vira o caminho real do clone. As unidades no git nao chumbam
  # /opt/my-minecraft-server para nao dependerem de onde foi clonado.
  sed "s|@RAIZ@|$RAIZ|g" "$unidade" > "$DEST/$nome"
  echo "[ok] $DEST/$nome"
  instaladas=$((instaladas + 1))
done

if [ "$instaladas" -eq 0 ]; then
  echo "erro: nenhuma unidade encontrada em systemd/." >&2
  exit 1
fi

systemctl daemon-reload

# Só os .timer sao habilitados: o .service e disparado por eles, e habilita-lo
# faria o backup rodar a cada boot da maquina.
for t in systemd/*.timer; do
  [ -e "$t" ] || continue
  nome="$(basename "$t")"
  systemctl enable --now "$nome" >/dev/null
  echo "[ok] $nome habilitado"
done

echo
systemctl list-timers --no-pager minecraft-* 2>/dev/null | head -3
