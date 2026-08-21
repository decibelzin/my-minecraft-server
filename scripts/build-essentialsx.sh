#!/usr/bin/env bash
# Compila o EssentialsX de commits fixados e instala em data/plugins.
#
#   ./scripts/build-essentialsx.sh
#
# Por que compilar em vez de baixar. Sao dois motivos somados:
#
#   1. O suporte a 26.2 foi mergeado no branch 2.x em junho (PRs #6561 e
#      #6575), mas a ultima release e a 2.22.0, de 31 de maio - anterior a
#      isso. Nenhuma versao publicada conhece a 26.2.
#
#   2. Toda build publicada, estavel ou de CI, tem a issue #6608: um
#      IndexOutOfBoundsException a cada entrada de jogador, no evento que
#      envia a lista de comandos ao cliente. A correcao esta no PR #6609,
#      aberto e ainda nao lancado. Aqui ela e aplicada por cherry-pick.
#
# O commit base e o commit da correcao sao fixados para que qualquer
# maquina reconstrua exatamente o mesmo jar, no mesmo espirito do
# download-plugins.sh, que fixa URL e SHA-512 de cada plugin baixado.
#
# Ao atualizar: se o #6609 tiver sido mergeado, apague o cherry-pick e so
# mova o COMMIT. Se uma release com 26.2 sair, este script inteiro pode dar
# lugar a uma entrada no download-plugins.sh - que e o caminho preferido.
set -euo pipefail

cd "$(dirname "$0")/.."

REPO=https://github.com/EssentialsX/Essentials.git
COMMIT=382de4ff3b03928841346070cf7aa92d408738f0   # branch 2.x em 2026-08-08
CORRECAO=42978602ce52c9e40426fada59d33b001c95819e # PR #6609
DEST=data/plugins

# Modulos instalados. O EssentialsX e modular e compila todos, mas so estes
# dois sobem no servidor:
#   EssentialsX      - o nucleo: /home /tpa /warp /back /msg /kit /heal ...
#   EssentialsXSpawn - /spawn e /setspawn, que nao estao no nucleo
# Ficam de fora de proposito: Protect e AntiBuild duplicam o que o
# GriefPrevention ja faz; Discord e GeoIP exigem token e licenca externos;
# Chat mudaria a aparencia do chat sem ninguem pedir.
MODULOS="EssentialsX EssentialsXSpawn"

# O Gradle roda sobre o JDK 21 e provisiona sozinho a toolchain que o build
# pedir (o foojay-resolver esta no settings.gradle.kts). Fazer isso num
# container evita instalar JDK e Gradle na maquina.
IMAGEM=eclipse-temurin:21-jdk

if ! command -v docker >/dev/null 2>&1; then
  echo "erro: este script precisa do docker para compilar." >&2
  exit 1
fi

SRC=.build/essentialsx
GRADLE_HOME=.build/gradle-home   # cache; sem ele cada build rebaixa tudo
mkdir -p "$SRC" "$GRADLE_HOME" "$DEST"

if [ ! -d "$SRC/.git" ]; then
  echo "[..] clonando o EssentialsX"
  git clone -q --branch 2.x "$REPO" "$SRC"
fi

echo "[..] fixando no commit ${COMMIT:0:9}"
git -C "$SRC" fetch -q origin
git -C "$SRC" checkout -q --detach "$COMMIT"

echo "[..] aplicando a correcao ${CORRECAO:0:9} (PR #6609)"
git -C "$SRC" fetch -q origin "pull/6609/head"
git -C "$SRC" -c user.email=deploy@local -c user.name=deploy \
  cherry-pick "$CORRECAO" >/dev/null

# Se o cherry-pick virar no-op um dia (porque o PR foi mergeado antes do
# COMMIT), o build seguiria sem a correcao e ninguem notaria. Falhar aqui e
# melhor que descobrir pelo console cheio de excecao.
if ! grep -q "firstAlias" "$SRC/Essentials/src/main/java/com/earth2me/essentials/AlternativeCommandsHandler.java"; then
  echo "[ERRO] a correcao do #6609 nao esta no codigo apos o cherry-pick." >&2
  exit 1
fi

VERSAO="$(git -C "$SRC" describe --tags --always)"
echo "[..] compilando (o primeiro build baixa o Gradle inteiro, demora)"

docker run --rm \
  -v "$PWD/$SRC:/src" -v "$PWD/$GRADLE_HOME:/gradle" \
  -e GRADLE_USER_HOME=/gradle \
  -w /src "$IMAGEM" \
  ./gradlew --no-daemon --console=plain build -x test

instalados=0
for m in $MODULOS; do
  jar="$(find "$SRC" -path "*/build/libs/$m-*.jar" \
         -not -name "*unshaded*" -not -name "*sources*" 2>/dev/null | head -1)"
  if [ -z "$jar" ]; then
    echo "[ERRO] o build nao produziu o modulo $m." >&2
    exit 1
  fi
  # Remove versoes anteriores: dois jars do mesmo plugin na pasta fazem o
  # Paper carregar os dois e brigar entre si.
  rm -f "$DEST/$m-"*.jar
  alvo="$DEST/$(basename "$jar")"
  cp "$jar" "$alvo"
  # O servidor roda como uid 1000 e sem isto nao le o jar.
  [ "$(id -u)" = "0" ] && chown 1000:1000 "$alvo"
  echo "[ok] $alvo ($(du -h "$alvo" | cut -f1))"
  instalados=$((instalados + 1))
done

echo
echo "[ok] $instalados modulo(s) instalado(s), versao $VERSAO"
echo
echo "A configuracao vive em plugins-config/Essentials/ e e copiada por cima"
echo "a cada boot. Edite la, nunca em data/plugins."
