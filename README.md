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

## Aplicar mudancas na VPS

O ciclo e sempre o mesmo: edita na sua maquina, commita, envia, e a VPS puxa.

```
edita no Windows -> commit -> push -> deploy na VPS
```

Na VPS, um comando so resolve:

```bash
./scripts/deploy.sh
```

Ele puxa, olha o que mudou e escolhe a acao certa: baixa plugins novos se a
lista mudou, faz rebuild se `Dockerfile`, `entrypoint.sh` ou `docker-compose.yml`
mudaram, e so reinicia se foi apenas configuracao. No fim, espera o container
ficar `healthy` e falha em voz alta se nao ficar.

Essa distincao importa mais do que parece: `server.properties`,
`plugins-config/` e `paper-config/` chegam ao container por um mount
somente-leitura do repositorio, entao para eles restart basta. Ja o `entrypoint.sh` vive **dentro**
da imagem — mexer nele e so reiniciar significa rodar a versao antiga sem
perceber.

O `.env` e a excecao proposital: ele guarda valores que *devem* variar por
maquina (`MEMORY=3G` na VPS, `6G` no PC). Esse voce edita direto la.

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

Os plugins nao ficam no git (sao .jar), mas a **lista** fica. O
`scripts/download-plugins.sh` fixa nome, URL e SHA-512 de cada um, entao
qualquer maquina recebe exatamente os mesmos, com integridade verificada:

```bash
./scripts/download-plugins.sh
```

As **configuracoes** dos plugins ficam em `plugins-config/` e sao copiadas por
cima de `data/plugins/` a cada boot, igual ao `server.properties`. Ou seja:
edite em `plugins-config/`, nunca em `data/plugins/`. O que o plugin cria
sozinho — contas registradas, caches, banco de dados — e preservado.

O mesmo vale para o **Paper**: `paper-config/` guarda o `paper-global.yml` e o
`paper-world-defaults.yml`, copiados para `data/config/` a cada boot. E ali que
vive o anti-xray, por exemplo. Sem versionar, um ajuste desses existiria so no
volume da VPS e sumiria numa recriacao dele, sem nada no log avisando.

Um custo a conhecer: o Paper reescreve esses arquivos no boot para acrescentar
chaves que versoes novas trouxeram. Como o repositorio manda, uma chave nova
volta ao padrao a cada restart enquanto nao for trazida para o `paper-config/`.
Ao subir a versao do Paper, vale comparar os dois.

Instalados hoje:

| Plugin | Para que |
|---|---|
| LoginTo 3.8.1 | login por senha, com autologin para contas originais |
| SkinsRestorer 15.12.5 | skins em modo offline, e `/skin <nick>` no jogo |
| LuckPerms 5.5.71 | permissoes e grupos, administrados com `/lp` |
| TreeTimber 1.8.4 | derruba a arvore inteira ao cortar o tronco |
| GriefPrevention 16.18.7-2 | claim de terreno com pa de ouro; blocos acumulam jogando |
| EssentialsX 2.22.1-dev | /home, /tpa, /warp, /back, /msg, /kit e mais uma centena |
| EssentialsX Spawn | /spawn e /setspawn, que nao vem no nucleo |
| Geyser 2.11.2 | deixa quem joga Bedrock (celular, console) entrar |
| Floodgate 2.2.5 | dispensa conta Java para esses jogadores |

Para adicionar outro, pegue os dados na API do Modrinth e acrescente uma linha
em `PLUGINS` no script:

```bash
curl -s "https://api.modrinth.com/v2/project/<slug>/version?game_versions=%5B%2226.2%22%5D&loaders=%5B%22paper%22%5D"
```

Um aviso sobre a 26.2: por ser recente, plugin que mexe em interno do servidor
(NMS) pode levar semanas para atualizar. Confira sempre se ha release para
`26.2` **e** para o loader `paper` — varios projetos publicam so a build de
Forge/NeoForge primeiro.

---

## GriefPrevention: compilado, nao baixado

O GriefPrevention e o unico plugin que nao vem do `download-plugins.sh`, porque
o projeto **nao publica binario**: nenhuma release no GitHub tem `.jar` anexado
desde 2024, e o Hangar parou na 16.18.4, do mesmo ano. Compilar do fonte e o
caminho normal para ter uma versao atual dele.

```bash
./scripts/build-griefprevention.sh
```

O script fixa um commit (`cd1fce4`, do branch `legacy/v16`) e compila dentro de
um container com JDK 25, entao nao e preciso instalar um JDK na maquina. Fixar o
commit da a mesma reprodutibilidade que o `download-plugins.sh` consegue com
SHA-512: um hash de commit no git e enderecado por conteudo, entao aquele SHA so
pode apontar para exatamente aquela arvore de arquivos, hoje e daqui a dez anos.

Duas escolhas que vale entender antes de mexer:

**Por que `legacy/v16` e nao `master`.** O README do proprio projeto diz que o
`master` carrega a linha 18, com breaking changes, e pede explicitamente para
nao usar em producao. Existe um PR aberto ([#2628]) atualizando para a API 26.2,
mas ele mira o `master`. A `legacy/v16` e a linha que eles recomendam.

**O upstream nao declara suporte a 26.2.** O jar sobe limpo e as claims
funcionam, mas o codigo e de junho e nao conhece conteudo novo da 26.2 — ha
issue aberta la sobre sulfur cubes nao sendo protegidos. Bau, porta, bloco e mob
estao cobertos; novidades da versao, talvez nao. Ao bumpar o commit, teste no
jogo antes de confiar.

As 235 mensagens que o plugin mostra ao jogador estao traduzidas para pt-BR em
`plugins-config/GriefPreventionData/messages.yml`. Ao bumpar o commit, confira
se a versao nova acrescentou mensagens: como o arquivo do repositorio sobrescreve
o de `data/` a cada boot, uma chave nova que so exista no plugin seria apagada
todo restart e o jogador veria o texto cru no lugar da frase.

[#2628]: https://github.com/GriefPrevention/GriefPrevention/pull/2628

---

## EssentialsX: compilado, e por dois motivos

Como o GriefPrevention, o EssentialsX nao vem do `download-plugins.sh`. Aqui os
motivos se somam:

**A 26.2 esta mergeada mas nao lancada.** Os PRs #6561 e #6575 entraram no
branch `2.x` em junho; a ultima release e a 2.22.0, de 31 de maio. Nenhuma
versao publicada conhece a 26.2.

**Toda build publicada tem a issue [#6608].** Um `IndexOutOfBoundsException` a
cada entrada de jogador, no evento que envia a lista de comandos ao cliente -
o que quebra o autocompletar e enche o console. Reproduz na 2.22.0 e na build
de CI. A correcao esta no PR [#6609], aberto e nao lancado, e o script a aplica
por cherry-pick sobre o commit fixado.

```bash
./scripts/build-essentialsx.sh
```

O script verifica que a correcao entrou no codigo antes de compilar. Se um dia o
cherry-pick virar no-op, ele falha em vez de gerar silenciosamente um jar com o
bug de volta.

Sobem so dois modulos: o nucleo e o Spawn. Protect e AntiBuild ficam de fora
porque duplicam o GriefPrevention; Discord e GeoIP exigem token e licenca; Chat
mudaria a aparencia do chat sem necessidade.

**Portugues sai de graca.** Diferente do GriefPrevention, o EssentialsX embarca
48 idiomas no proprio jar, incluindo `pt_BR`. Basta o `locale: pt_BR` no
`plugins-config/Essentials/config.yml` - nao ha traducao a manter.

Quando sair uma release estavel com a 26.2 e com o #6609, este script pode ser
apagado e o plugin volta para o `download-plugins.sh`, que e o caminho preferido.

[#6608]: https://github.com/EssentialsX/Essentials/issues/6608
[#6609]: https://github.com/EssentialsX/Essentials/pull/6609

---

## Bedrock: celular e console

O **Geyser** traduz o protocolo do Bedrock para o do Java, e o **Floodgate**
deixa esse pessoal entrar sem conta Java. Os dois sao binarios prontos, entao
vivem no `download-plugins.sh`, com URL e SHA-512 fixados como os demais - nao
precisam ser compilados.

Uma pegadinha: o Modrinth so publica `fabric` e `neoforge` do Floodgate. A build
de Paper vem do servidor do proprio projeto, e o SHA-512 no script foi calculado
do arquivo baixado, depois de conferir que o SHA-256 batia com o anunciado pela
API deles.

**A porta e outra.** O Java entra pela 25565 em TCP; o Bedrock fala **UDP na
19132**, mapeada no `docker-compose.yml`. Sem esse mapeamento o servidor
simplesmente nao aparece na lista de quem joga no celular - e nada no log diz
por que.

Para conectar no celular: adicionar servidor com o IP da VPS e a porta `19132`.

O Floodgate tambem melhora a vida de quem entra por ali no nosso caso especifico:
como ele verifica o jogador por conta propria, o LoginTo o deixa passar sem pedir
`/login` - digitar senha em teclado de celular a cada entrada seria bem chato.

---

## Autenticacao e modo offline

O servidor roda com `online-mode=false`, o que permite entrar sem conta paga da
Microsoft. Isso tem duas consequencias que os plugins acima resolvem:

**Qualquer um pode dizer que e voce.** Sem verificacao da Mojang, o nick e
autodeclarado. O LoginTo cobre isso exigindo senha — e, com
`enable-premium-features: true`, ele ainda faz a verificacao real na Mojang para
nicks que existem la, deixando esses jogadores entrarem direto. Quem e original
nao digita senha; quem nao e, digita.

**Quem registra um nick primeiro fica dono dele.** Registre o seu assim que o
servidor subir, e reserve os dos amigos.

Comandos: `/register <senha> <senha>` no primeiro acesso, `/login <senha>`
depois. Skin: `/skin <nick>`.

Uma observacao sobre UUIDs: em modo offline eles derivam do nick, nao da Mojang.
Ao migrar de online para offline, o UUID de cada jogador muda — o op se perde e
o personagem recomeca. Por isso vale fazer essa troca cedo.

---

## Atalhos do Windows

Dois `.bat` na raiz, para nao precisar decorar comando:

| Arquivo | O que abre |
|---|---|
| `conectar-vps.bat` | um shell na VPS, ja dentro de `/opt/my-minecraft-server` |
| `console-servidor.bat` | o console do servidor de Minecraft, onde da para digitar `list`, `lp`, `worldborder get` |

O console usa `--detach-keys=ctrl-x`, entao **Ctrl+X sai sem derrubar o
servidor**, no lugar da sequencia padrao Ctrl+P Ctrl+Q. E usa
`--sig-proxy=false` para que um Ctrl+C distraido nao seja repassado ao
processo do Minecraft - sem isso, essa tecla derruba o servidor.

Digitar `stop` ali dentro desliga o servidor de verdade: e o console real, nao
uma copia.

---

## Backup

```bash
./scripts/backup-world.sh
```

Compacta em `backups/` o mundo **e os dados dos plugins**, mantendo os 7 mais
recentes. Os plugins entram porque guardam o que nao se recompra: terrenos do
GriefPrevention, contas do LoginTo, homes e warps do Essentials, grupos do
LuckPerms, chave do Floodgate. Restaurar so o mundo devolveria o terreno e
perderia tudo isso.

Os jars, as bibliotecas que cada plugin baixa sozinho e a wordlist de 134 MB do
LoginTo ficam de fora - sao regeneraveis, e sem essas exclusoes o arquivo
passaria de ~35 MB para mais de 250. Ele detecta como o
servidor esta rodando: se for container, para e religa sozinho; se for nativo,
**se recusa a rodar** com o servidor no ar e pede que voce digite `stop` no
console primeiro. Use `--hot` para copiar mesmo assim, sabendo que pode pegar um
chunk no meio da gravacao.

### Automatico, todo dia

Rodar o backup na mao funciona ate a noite em que voce esquecer. Na VPS, um
timer do systemd chama o script sozinho:

```bash
sudo ./scripts/install-systemd-units.sh
```

As unidades vivem versionadas em `systemd/` e o script as instala no host,
substituindo `@RAIZ@` pelo caminho real do clone - elas nao chumbam
`/opt/my-minecraft-server`, entao funcionam de onde quer que o repositorio
esteja. Isso fica fora do `entrypoint.sh` de proposito: o container nao pode
nem deve mexer no systemd da maquina.

O horario e **05:00 de Brasilia**, declarado com fuso no `OnCalendar` para nao
depender de o host estar em UTC. Com `Persistent=true`, uma noite com a VPS
desligada nao vira um dia sem backup: ele roda assim que a maquina voltar.

Vale saber que **o servidor cai por alguns minutos** durante a copia - e o
preco de um backup consistente, e o motivo do horario escolhido.

Para conferir quando roda ou disparar na hora:

```bash
systemctl list-timers minecraft-backup.timer
```

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
`server.properties`, `plugins-config/`, `paper-config/`, os scripts e este
README.

Fora do git de proposito: `data/` inteiro (mundo, logs, plugins, dados de
jogador), os `.jar`, os backups e o `.env`. Mundo e binario que muda por inteiro
a cada save — versionar isso infla o repositorio para varios GB em poucas
semanas.
