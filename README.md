# my-minecraft-server

Servidor **Paper 26.2** — roda igual no Windows e numa VPS.

| | |
|---|---|
| Software | Paper 26.2 (build 112) |
| Java | 25 (no Docker ja vem na imagem) |
| Porta | 25565 |
| Heap | 6 GB, ajustavel no `.env` |

Paper e um fork do Spigot, entao **roda plugins Bukkit e Spigot** sem adaptacao.
Quem entra usa o Minecraft normal, sem instalar nada.

---

## Como isto e organizado

Duas regras explicam quase tudo:

**1. `data/` e descartavel-ish e fica fora do git.** Mundo, logs, plugins,
libraries e as configs geradas pelo Paper vivem la. Backup e feito por
`scripts/backup-world.sh`, nunca por commit.

**2. O repositorio e a fonte de verdade da configuracao.** O `server.properties`
da raiz sobrescreve `data/server.properties` a cada boot. Entao **edite na raiz**
— o de `data/` e arquivo gerado, mexer la nao adianta. Em troca, toda mudanca de
config aparece no `git diff` e uma VPS nova sobe identica a sua maquina.

O mundo fica em `data/` nos dois modos de execucao, entao voce pode alternar
entre nativo e Docker sem perder nada.

---

## Configuracao

```bash
cp .env.example .env
```

O `.env` vale para os dois caminhos:

| Chave | Para que serve |
|---|---|
| `MEMORY` | heap da JVM. Numa VPS, no maximo ~70% da RAM da maquina |
| `MEMORY_LIMIT` | teto de RAM do container. Precisa ser maior que `MEMORY` |
| `SERVER_PORT` | porta no host (so no Docker) |
| `EULA` | `true` declara que voce leu e aceitou os termos da Mojang |

O servidor **se recusa a iniciar** com `EULA=false`. Leia os
[termos](https://aka.ms/MinecraftEULA) e decida — a aceitacao e um ato seu, por
isso ela mora numa variavel sua e nao num arquivo commitado.

---

## Caminho A — Windows nativo

Instale o Java 25 (o Paper 26.2 exige 25+):

```powershell
winget install --id EclipseAdoptium.Temurin.25.JDK
```

**Feche e reabra o PowerShell** depois, senao o `java` nao aparece no PATH.

```powershell
.\start.ps1
```

Na primeira vez ele baixa o Paper (59 MB, conferindo o SHA-256) e gera o mundo.
Para dar mais RAM que o `.env` diz: `.\start.ps1 -Memory 8G`

Desligue digitando `stop` no console — nunca feche a janela no X, isso corrompe
chunks nao salvos.

---

## Caminho B — Docker (VPS)

```bash
docker compose up -d --build
```

Acompanhe com `docker compose logs -f` ate aparecer `Done (Xs)!`.

Numa VPS, o fluxo completo:

```bash
git clone https://github.com/decibelzin/my-minecraft-server.git
```

```bash
cd my-minecraft-server && cp .env.example .env
```

Ajuste `MEMORY`, coloque `EULA=true` e **ceda a pasta de dados ao usuario do
container** antes de subir:

```bash
mkdir -p data && sudo chown -R 1000:1000 data
```

O container roda como uid 1000 (nao-root) e monta `./data` do host. Se a pasta
pertencer ao root — o caso normal quando voce clona logado como root — o servidor
sobe e morre sem conseguir escrever o mundo. Depois:

```bash
docker compose up -d --build
```

```bash
sudo ufw allow 25565
```

Antes de expor para a internet, edite o `server.properties` da raiz: troque
`white-list` e `enforce-whitelist` para `true` e libere cada amigo com
`whitelist add <nick>` no console. Mantenha `online-mode=true` sempre — desligar
isso com o servidor aberto permite qualquer um entrar com qualquer nick.

> **Docker no Windows:** se o Docker Desktop nao subir e o log em
> `%LOCALAPPDATA%\Docker\log\host\Docker Desktop.exe.log` acusar
> `cannot find registry key "SOFTWARE\Docker Inc.\Docker Desktop"`, a instalacao
> esta corrompida. Desinstale e reinstale com
> `winget install --id Docker.DockerDesktop`. Ou simplesmente use o Caminho A.

---

## Entrar no jogo

Minecraft na versao **26.2** → Multijogador → Adicionar servidor:

| Onde voce esta | Endereco |
|---|---|
| No mesmo PC | `localhost` |
| No mesmo wifi | o IP local da maquina, ex. `192.168.0.10` |
| Pela internet | IP publico da VPS |

Para virar admin, digite no console: `op SeuNick`

---

## Console do servidor

No modo nativo o console e a propria janela do PowerShell. No Docker:

```bash
docker attach minecraft
```

Para sair **sem derrubar o servidor**, use `Ctrl+P` seguido de `Ctrl+Q` —
`Ctrl+C` mata o container.

Parar: `docker compose stop` (espera ate 2 min o Paper salvar os chunks).
Religar: `docker compose start`

---

## Plugins

Jogue os `.jar` em `data/plugins/` e reinicie. Fontes confiaveis:
[Hangar](https://hangar.papermc.io), [Modrinth](https://modrinth.com/plugins),
[SpigotMC](https://www.spigotmc.org/resources/).

Um aviso sobre a 26.2: por ser recem-lancada, plugin que mexe em interno do
servidor (NMS) pode levar semanas para atualizar. Plugin de API normal funciona
de cara.

---

## Backup

```bash
./scripts/backup-world.sh
```

Compacta o mundo em `backups/` e mantem os 7 mais recentes. Ele detecta como o
servidor esta rodando: se for container, para e religa sozinho; se for nativo,
**se recusa a rodar** com o servidor no ar e pede que voce digite `stop` no
console primeiro. Use `--hot` para copiar mesmo assim, sabendo que pode pegar um
chunk no meio da gravacao.

---

## Atualizar o Paper

A versao e pinada **em um lugar so**: os tres `ARG` no topo do `Dockerfile`. O
`download-server.ps1` le de la, entao nativo e container nunca divergem.

Pegue o build novo:

```bash
curl -s https://fill.papermc.io/v3/projects/paper/versions/26.2/builds/latest
```

Atualize `PAPER_VERSION`, `PAPER_BUILD` e `PAPER_SHA256` no `Dockerfile` — os
tres juntos, porque o SHA compoe a URL de download. Depois rode `.\start.ps1`
(baixa o jar novo) ou `docker compose up -d --build`. O mundo em `data/` nao e
afetado.

---

## O que esta versionado

A receita: `Dockerfile`, `docker-compose.yml`, `entrypoint.sh`,
`server.properties`, os scripts e este README.

Fora do git de proposito: `data/` inteiro (mundo, logs, plugins, dados de
jogador), os `.jar`, os backups e o `.env`. Mundo e binario que muda por inteiro
a cada save — versionar isso infla o repositorio para varios GB em poucas
semanas.
