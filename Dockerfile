# syntax=docker/dockerfile:1

# ---------------------------------------------------------------------
# FONTE UNICA DA VERSAO DO PAPER.
# Estes tres ARGs sao o unico lugar onde a versao e pinada. O compose
# nao os sobrescreve e o download-server.ps1 le daqui, entao bumpar o
# Paper e editar somente este bloco.
# ---------------------------------------------------------------------
ARG PAPER_VERSION=26.2
ARG PAPER_BUILD=112
ARG PAPER_SHA256=bd3a58cf96874e5ea6643f5f6fe9b4f5bf9e34b795fa078c2f0ee8b98b2f907e

# ---------------------------------------------------------------------
# Estagio 1: baixa o Paper e confere o checksum.
# Separado para que curl/apt nao sobrem na imagem final.
# ---------------------------------------------------------------------
FROM eclipse-temurin:25-jre-noble AS fetch
ARG PAPER_VERSION
ARG PAPER_BUILD
ARG PAPER_SHA256

RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends curl ca-certificates; \
    rm -rf /var/lib/apt/lists/*; \
    curl -fsSL -o /paper.jar \
      "https://fill-data.papermc.io/v1/objects/${PAPER_SHA256}/paper-${PAPER_VERSION}-${PAPER_BUILD}.jar"; \
    echo "${PAPER_SHA256}  /paper.jar" | sha256sum -c -

# ---------------------------------------------------------------------
# Estagio 2: imagem final
# ---------------------------------------------------------------------
FROM eclipse-temurin:25-jre-noble

LABEL org.opencontainers.image.title="my-minecraft-server" \
      org.opencontainers.image.description="Servidor Paper containerizado" \
      org.opencontainers.image.source="https://github.com/decibelzin/my-minecraft-server"

# uid/gid fixos: facilitam o chown do volume na VPS
RUN groupadd --gid 1000 minecraft \
 && useradd --uid 1000 --gid 1000 --create-home --shell /bin/bash minecraft

COPY --from=fetch /paper.jar /opt/paper.jar

# server.properties e a fonte de verdade; o entrypoint copia por cima
# de /data a cada boot. Nao existe eula.txt aqui: ele e escrito a
# partir da variavel EULA, que e onde voce declara o aceite.
COPY server.properties /opt/defaults/
COPY docker/entrypoint.sh /usr/local/bin/entrypoint.sh

RUN chmod +x /usr/local/bin/entrypoint.sh \
 && mkdir -p /data \
 && chown -R minecraft:minecraft /data /opt/defaults

USER minecraft
WORKDIR /data

# Minecraft Java Edition e TCP. UDP so serviria para enable-query,
# que esta desligado no server.properties.
EXPOSE 25565

ENV MEMORY=6G EULA=false

# start-period longo: o primeiro boot gera o mundo e demora.
HEALTHCHECK --interval=30s --timeout=5s --start-period=5m --retries=3 \
  CMD bash -c 'exec 3<>/dev/tcp/127.0.0.1/25565' || exit 1

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
