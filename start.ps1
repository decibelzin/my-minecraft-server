#Requires -Version 5.1
<#
.SYNOPSIS
  Sobe o servidor Paper direto no Windows, sem Docker.
.DESCRIPTION
  Le a configuracao do .env, os mesmos valores que o docker compose usa.
  O server.properties do repositorio sobrescreve o de data/ a cada boot.
.EXAMPLE
  .\start.ps1
  .\start.ps1 -Memory 8G     # sobrepoe o MEMORY do .env
#>
[CmdletBinding()]
param([string]$Memory)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$Root    = $PSScriptRoot
$DataDir = Join-Path $Root 'data'
$EnvFile = Join-Path $Root '.env'

# --- .env -------------------------------------------------------------
# Mesma fonte de configuracao do docker compose, para os dois caminhos
# nao divergirem.
$conf = @{}
if (Test-Path $EnvFile) {
    foreach ($line in (Get-Content $EnvFile)) {
        $t = $line.Trim()
        if ($t -and -not $t.StartsWith('#') -and $t.Contains('=')) {
            $k, $v = $t -split '=', 2
            $conf[$k.Trim()] = $v.Trim()
        }
    }
} else {
    Write-Host ""
    Write-Host "Arquivo .env nao encontrado. Crie a partir do exemplo:" -ForegroundColor Red
    Write-Host "  Copy-Item .env.example .env" -ForegroundColor White
    Write-Host ""
    exit 1
}

# Precedencia: parametro > .env > padrao
if (-not $Memory) {
    $Memory = if ($conf.ContainsKey('MEMORY')) { $conf['MEMORY'] } else { '6G' }
}

# --- Java 25+ ---------------------------------------------------------
if (-not (Get-Command java -ErrorAction SilentlyContinue)) {
    Write-Host ""
    Write-Host "Java nao encontrado. O Paper 26.2 exige Java 25 ou superior." -ForegroundColor Red
    Write-Host "  winget install --id EclipseAdoptium.Temurin.25.JDK" -ForegroundColor White
    Write-Host "Depois FECHE e reabra o PowerShell para o PATH atualizar." -ForegroundColor Yellow
    Write-Host ""
    exit 1
}

# "java -version" escreve na stderr. No PowerShell 5.1, redirecionar
# stderr de um executavel nativo embrulha cada linha num ErrorRecord - e
# com ErrorActionPreference='Stop' isso vira erro terminante. Baixamos a
# guarda so nesta chamada.
$oldEA = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
try {
    $versionLine = (& java -version 2>&1 | Select-Object -First 1).ToString()
} finally {
    $ErrorActionPreference = $oldEA
}
if ($versionLine -match '"(\d+)') {
    $major = [int]$Matches[1]
    if ($major -lt 25) {
        Write-Host ""
        Write-Host "Java $major encontrado, mas o Paper 26.2 exige 25+." -ForegroundColor Red
        Write-Host "  winget install --id EclipseAdoptium.Temurin.25.JDK" -ForegroundColor White
        Write-Host ""
        exit 1
    }
    Write-Host "[ok] Java $major detectado." -ForegroundColor Green
}

# --- Jar do Paper -----------------------------------------------------
function Get-PaperJar {
    Get-ChildItem -Path $Root -Filter 'paper-*.jar' -File |
        Sort-Object Name -Descending | Select-Object -First 1
}
$jar = Get-PaperJar
if (-not $jar) {
    Write-Host "[..] Jar do Paper ausente. Baixando..." -ForegroundColor Cyan
    & (Join-Path $Root (Join-Path 'scripts' 'download-server.ps1'))
    $jar = Get-PaperJar
    if (-not $jar) { throw "Download falhou: nenhum paper-*.jar encontrado." }
}

# --- Pasta de dados ---------------------------------------------------
# Mesma pasta que o container usa, entao o mundo e o mesmo nos dois modos.
if (-not (Test-Path $DataDir)) { New-Item -ItemType Directory -Path $DataDir | Out-Null }

# O server.properties do repositorio e a fonte de verdade: sobrescreve
# sempre. Isso impede a config viva de divergir em silencio do git.
Copy-Item -Path (Join-Path $Root 'server.properties') `
          -Destination (Join-Path $DataDir 'server.properties') -Force

# --- EULA -------------------------------------------------------------
# Mesma variavel que o container usa, para nao haver dois mecanismos.
$eulaAceito = $conf.ContainsKey('EULA') -and $conf['EULA'] -eq 'true'
if ($eulaAceito) {
    Set-Content -Path (Join-Path $DataDir 'eula.txt') -Value 'eula=true' -Encoding ascii
} else {
    Write-Host ""
    Write-Host "================================================================" -ForegroundColor Yellow
    Write-Host " O servidor nao pode iniciar: o EULA da Mojang nao foi aceito."   -ForegroundColor Yellow
    Write-Host ""
    Write-Host " 1. Leia:  https://aka.ms/MinecraftEULA"                          -ForegroundColor White
    Write-Host " 2. Se concordar, coloque EULA=true no arquivo .env"              -ForegroundColor White
    Write-Host ""
    Write-Host " Essa aceitacao precisa ser um ato seu, entao o padrao e false."  -ForegroundColor DarkGray
    Write-Host "================================================================" -ForegroundColor Yellow
    Write-Host ""
    exit 1
}

# --- Flags de GC recomendadas oficialmente pelo PaperMC (G1GC / Aikar) --
$flags = @(
    "-Xms$Memory", "-Xmx$Memory",
    '-XX:+AlwaysPreTouch', '-XX:+DisableExplicitGC', '-XX:+ParallelRefProcEnabled',
    '-XX:+PerfDisableSharedMem', '-XX:+UnlockExperimentalVMOptions', '-XX:+UseG1GC',
    '-XX:G1HeapRegionSize=8M', '-XX:G1HeapWastePercent=5', '-XX:G1MaxNewSizePercent=40',
    '-XX:G1MixedGCCountTarget=4', '-XX:G1MixedGCLiveThresholdPercent=90',
    '-XX:G1NewSizePercent=30', '-XX:G1RSetUpdatingPauseTimePercent=5',
    '-XX:G1ReservePercent=20', '-XX:InitiatingHeapOccupancyPercent=15',
    '-XX:MaxGCPauseMillis=200', '-XX:MaxTenuringThreshold=1', '-XX:SurvivorRatio=32'
)

Write-Host "[..] Subindo $($jar.Name) com heap de $Memory" -ForegroundColor Cyan
Write-Host "     Para desligar com seguranca, digite 'stop' no console." -ForegroundColor DarkGray
Write-Host ""

Push-Location $DataDir
try {
    & java @flags -jar $jar.FullName --nogui
} finally {
    Pop-Location
}
