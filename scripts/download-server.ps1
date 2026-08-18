#Requires -Version 5.1
<#
.SYNOPSIS
  Baixa o Paper e confere o checksum SHA-256.
.DESCRIPTION
  A versao NAO e definida aqui: e lida dos ARGs do Dockerfile, que sao a
  fonte unica. Assim o servidor nativo e o container usam exatamente o
  mesmo build, e bumpar o Paper e editar um arquivo so.
#>
[CmdletBinding()]
param([switch]$Force)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$Root       = Split-Path -Parent $PSScriptRoot
$Dockerfile = Join-Path $Root 'Dockerfile'

if (-not (Test-Path $Dockerfile)) { throw "Dockerfile nao encontrado em $Root" }
$df = Get-Content $Dockerfile -Raw

function Read-Arg([string]$nome) {
    if ($df -match ("ARG\s+" + $nome + "=(\S+)")) { return $Matches[1] }
    throw "ARG $nome nao encontrado no Dockerfile"
}

$PaperVersion = Read-Arg 'PAPER_VERSION'
$PaperBuild   = Read-Arg 'PAPER_BUILD'
$Sha256       = (Read-Arg 'PAPER_SHA256').ToLower()

$JarName = "paper-$PaperVersion-$PaperBuild.jar"
$Url     = "https://fill-data.papermc.io/v1/objects/$Sha256/$JarName"
$Dest    = Join-Path $Root $JarName

Write-Host "[..] Versao lida do Dockerfile: Paper $PaperVersion build $PaperBuild" -ForegroundColor DarkGray

if ((Test-Path $Dest) -and -not $Force) {
    $existing = (Get-FileHash -Path $Dest -Algorithm SHA256).Hash.ToLower()
    if ($existing -eq $Sha256) {
        Write-Host "[ok] $JarName ja esta aqui e o checksum confere." -ForegroundColor Green
        exit 0
    }
    Write-Warning "Checksum nao confere. Baixando de novo."
}

Write-Host "[..] Baixando $JarName (~59 MB)" -ForegroundColor Cyan

# Sem isso o Invoke-WebRequest fica lento por causa da barra de progresso
$oldPref = $ProgressPreference
$ProgressPreference = 'SilentlyContinue'
try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -Uri $Url -OutFile $Dest -UseBasicParsing
} finally {
    $ProgressPreference = $oldPref
}

$actual = (Get-FileHash -Path $Dest -Algorithm SHA256).Hash.ToLower()
if ($actual -ne $Sha256) {
    Remove-Item $Dest -Force
    throw "CHECKSUM NAO CONFERE. Esperado $Sha256, veio $actual. Arquivo apagado."
}

$sizeMb = [math]::Round((Get-Item $Dest).Length / 1MB, 1)
Write-Host "[ok] $JarName baixado e verificado ($sizeMb MB)." -ForegroundColor Green
