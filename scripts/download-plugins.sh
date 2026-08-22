#!/usr/bin/env bash
# Baixa os plugins com versao e checksum fixados.
#
#   ./scripts/download-plugins.sh
#
# Roda no Git Bash (Windows) e na VPS. Os .jar ficam fora do git, entao
# e este arquivo que torna a instalacao reproduzivel: uma VPS nova recebe
# exatamente os mesmos plugins, verificados por SHA-512.
#
# Para atualizar um plugin, troque a linha correspondente em PLUGINS.
# Os dados saem da API do Modrinth:
#   curl -s "https://api.modrinth.com/v2/project/<slug>/version?game_versions=%5B%2226.2%22%5D&loaders=%5B%22paper%22%5D"
set -euo pipefail

cd "$(dirname "$0")/.."
DEST=data/plugins

# formato: arquivo|url|sha512
# O Floodgate e a excecao ao comentario acima: no Modrinth ele so publica
# fabric e neoforge, entao a build de Paper vem do servidor do proprio
# projeto. O SHA-512 foi calculado do arquivo baixado, depois de conferir
# que o SHA-256 batia com o anunciado pela API deles.
PLUGINS="
LoginTo-3.8.1.jar|https://cdn.modrinth.com/data/A5foNgax/versions/r0FkwIn3/LoginTo-3.8.1.jar|cffdd118654fac01d952d52b3096c5b8bc34da739ee2906520c0087f487aa93b8ef96770af1d683adc41802e434c100d4eff0c4055b57c20e9a5fc2d8413d154
SkinsRestorer.jar|https://cdn.modrinth.com/data/TsLS8Py5/versions/wXS6bHiC/SkinsRestorer.jar|7819f6b1e8f8ddb2e86d3d3e54352dd040f381e9a094f8a9c80c7d3273ffd7b1cef6eca7369dcee4b0f5290e7837ef51cee1baeca906b3784f30d7ba2f58b7b4
LuckPerms-Bukkit-5.5.71.jar|https://cdn.modrinth.com/data/Vebnzrzj/versions/b0mk8uS6/LuckPerms-Bukkit-5.5.71.jar|188a91f0a543d23bfda32385fca6db63d61e49c8a422bd452a260bd9cbc6a7d7fe45071199e9fca8f3ce43c2b41ee84fd315bd15464577028ff3951a7d4fab27
timber-1.8.4.jar|https://cdn.modrinth.com/data/52W2RPUh/versions/Bc7hzkik/timber-1.8.4.jar|4daf352f3687de25afe4fd77b7d779ece2e2f610c734df17f612872a580f36936d9831e35b568d15b646c85722c5abae6e20d2ecb11b2f4d18b77bb74d729ca4
Geyser-Spigot.jar|https://cdn.modrinth.com/data/wKkoqHrH/versions/cEESv2Kx/Geyser-Spigot.jar|2a6c2940e05e5441db4595b2d72a503f933f5be486eb4780739e2ab67c32330c8eda2ec79d1fb6b077dbbeca0b3e83614ef67b963e15f92c056e3da1d307fc28
floodgate-spigot.jar|https://download.geysermc.org/v2/projects/floodgate/versions/2.2.5/builds/140/downloads/spigot|59598fc9ba1a5b233455273d63f62753078cb0e551f9fc93732a02571f28daf991e4b9161e73370aee72b89d51cf7d40a475628c1e2a8c09966776212ea87160
VaultUnlocked-2.20.2.jar|https://cdn.modrinth.com/data/ayRaM8J7/versions/cLNipSgw/VaultUnlocked-2.20.2.jar|9c5baefbe23ede10d00af580fc9d5d6da9a9baac40feef078bb951448b89df039131299bd5d3fe8ccd947367de8fe24b543dc9cce83fbf1687a3221baca8da8e
"

mkdir -p "$DEST"

conferir() {
  # $1 = arquivo, $2 = sha512 esperado
  [ -f "$1" ] || return 1
  local atual
  atual="$(sha512sum "$1" | cut -d' ' -f1)"
  [ "$atual" = "$2" ]
}

echo "$PLUGINS" | while IFS='|' read -r nome url hash; do
  [ -z "${nome:-}" ] && continue
  alvo="$DEST/$nome"

  if conferir "$alvo" "$hash"; then
    echo "[ok] $nome ja presente, checksum confere"
    continue
  fi

  echo "[..] baixando $nome"
  curl -fsSL -o "$alvo.parcial" "$url"

  if ! conferir "$alvo.parcial" "$hash"; then
    rm -f "$alvo.parcial"
    echo "[ERRO] checksum de $nome nao confere. Arquivo descartado." >&2
    exit 1
  fi

  mv "$alvo.parcial" "$alvo"
  echo "[ok] $nome verificado ($(du -h "$alvo" | cut -f1))"
done

# O servidor roda como uid 1000 no container; sem isto ele nao le os jars
# nem cria as pastas de config dos plugins.
if [ "$(id -u)" = "0" ]; then
  chown -R 1000:1000 "$DEST"
  echo "[ok] dono de $DEST ajustado para 1000:1000"
fi

echo
echo "Plugins instalados em $DEST:"
ls -1 "$DEST"/*.jar 2>/dev/null | sed 's|.*/|  - |'
