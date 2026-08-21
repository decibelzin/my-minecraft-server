#!/usr/bin/env bash
# Compila o GriefPrevention a partir de um commit fixado e instala em data/plugins.
#
#   ./scripts/build-griefprevention.sh
#
# Por que compilar em vez de baixar: o projeto nao publica binario. Nenhuma
# release no GitHub tem .jar anexado desde 2024 e o Hangar parou na 16.18.4,
# tambem de 2024. Compilar do fonte e o caminho normal para ter uma versao
# atual deste plugin, nao uma gambiarra.
#
# Por que legacy/v16 e nao master: o README do projeto diz que o master
# carrega a linha 18, com breaking changes, e pede explicitamente para nao
# usar em producao. A legacy/v16 e a linha que eles recomendam. Existe um PR
# aberto (#2628) atualizando para a API 26.2, mas ele mira o master.
#
# ATENCAO: o upstream nao declara suporte a 26.2 em lugar nenhum. Este jar
# sobe limpo na 26.2, mas conteudo novo da versao pode nao estar protegido.
#
# O commit e fixado para que qualquer maquina reconstrua exatamente o mesmo
# jar, no mesmo espirito do download-plugins.sh, que fixa URL e SHA-512. Para
# atualizar, troque o COMMIT abaixo, rode, e teste antes de confiar.
set -euo pipefail

cd "$(dirname "$0")/.."

REPO=https://github.com/GriefPrevention/GriefPrevention.git
COMMIT=cd1fce495dcbe95867601bdfc6b534f0b386eae9   # legacy/v16 em 2026-06-20
DEST=data/plugins

# O build exige JDK 25 (a 26.x do Paper nao compila com menos). Fazer isso
# num container evita instalar um JDK inteiro na maquina so para este plugin.
IMAGEM=maven:3-eclipse-temurin-25

if ! command -v docker >/dev/null 2>&1; then
  echo "erro: este script precisa do docker para compilar com JDK 25." >&2
  exit 1
fi

SRC=.build/griefprevention
M2=.build/m2                    # cache do maven, senao cada build rebaixa tudo
mkdir -p "$SRC" "$M2" "$DEST"

if [ ! -d "$SRC/.git" ]; then
  echo "[..] clonando o GriefPrevention"
  git clone -q "$REPO" "$SRC"
fi

echo "[..] fixando no commit ${COMMIT:0:9}"
git -C "$SRC" fetch -q origin
git -C "$SRC" checkout -q "$COMMIT"

# A versao do jar sai do "git describe", entao o clone precisa das tags.
VERSAO="$(git -C "$SRC" describe --tags)"
echo "[..] compilando $VERSAO (pode demorar no primeiro build)"

rm -rf "$SRC/target"
docker run --rm \
  -v "$PWD/$SRC:/src" -v "$PWD/$M2:/root/.m2" \
  -w /src "$IMAGEM" \
  mvn -B -q -DskipTests package

JAR="$(ls -1 "$SRC"/target/*.jar 2>/dev/null | grep -vE 'sources|javadoc|original' | head -1)"
if [ -z "$JAR" ]; then
  echo "[ERRO] o build nao produziu jar nenhum." >&2
  exit 1
fi

# Remove versoes anteriores antes de copiar: dois jars do mesmo plugin na
# pasta fazem o Paper carregar os dois e brigar entre si.
rm -f "$DEST"/GriefPrevention-*.jar
ALVO="$DEST/GriefPrevention-$VERSAO.jar"
cp "$JAR" "$ALVO"

# Mesmo motivo do download-plugins.sh: o servidor roda como uid 1000 e sem
# isto nao le o jar.
if [ "$(id -u)" = "0" ]; then
  chown 1000:1000 "$ALVO"
fi

echo "[ok] $ALVO ($(du -h "$ALVO" | cut -f1))"
echo
echo "A configuracao vive em plugins-config/GriefPreventionData/ e e copiada"
echo "por cima a cada boot. Edite la, nunca em data/plugins."
