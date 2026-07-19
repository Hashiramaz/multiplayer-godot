# Exporta a build Windows e publica no itch.io via butler (upload diferencial).
# Uso:   powershell -ExecutionPolicy Bypass -File tools\publish_itch.ps1
#
# Pré-requisitos (uma vez só):
#   1. butler instalado (ja esta em D:\tools\butler) + "butler login" feito.
#   2. Export templates da Godot 4.7 instalados.
#   3. $ItchTarget abaixo apontando pro seu jogo no itch.
#
# Depois: rode este script sempre que quiser mandar uma versao nova. Ele SOBRESCREVE
# o canal "windows" e quem tem o app do itch recebe a atualizacao automaticamente.

$ErrorActionPreference = "Stop"

# --- AJUSTE AQUI ----------------------------------------------------------
$Godot      = "D:\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe"
$Butler     = "D:\tools\butler\butler.exe"
# Seu alvo no itch, no formato usuario/jogo:canal
$ItchTarget = "jappa/escape-the-island:windows"
# --------------------------------------------------------------------------

$ProjectDir = Split-Path -Parent $PSScriptRoot
$OutDir     = Join-Path $ProjectDir "build\windows"
$OutExe     = Join-Path $OutDir "EscapeTheIsland.exe"
$AppIdSrc   = Join-Path $ProjectDir "steam_appid.txt"

# O editor aberto trava os .dll das GDExtensions e suja o export. Aborta cedo.
if (Get-Process -Name "Godot_v4.7*" -ErrorAction SilentlyContinue) {
	throw "O editor da Godot 4.7 esta aberto. Feche-o antes de exportar."
}
if ($ItchTarget -like "SEU-USUARIO/*") {
	throw "Configure `$ItchTarget no topo deste script (formato usuario/jogo:windows)."
}

Write-Host "==> Gravando version.txt (local)..." -ForegroundColor Cyan
$sha = (git -C $ProjectDir rev-parse --short HEAD).Trim()
"local ($sha)" | Set-Content -Path (Join-Path $ProjectDir "version.txt") -Encoding utf8 -NoNewline

Write-Host "==> Exportando build (Windows Desktop)..." -ForegroundColor Cyan
if (Test-Path $OutDir) { Remove-Item -Recurse -Force $OutDir }
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
& $Godot --headless --path $ProjectDir --export-release "Windows Desktop" $OutExe
if ($LASTEXITCODE -ne 0) { throw "Falha na exportacao da Godot (exit $LASTEXITCODE)." }

Write-Host "==> Copiando steam_appid.txt pra pasta da build..." -ForegroundColor Cyan
# Sem isso a build nao inicializa a Steam -> rede nao funciona.
Copy-Item $AppIdSrc (Join-Path $OutDir "steam_appid.txt") -Force

Write-Host "==> Publicando no itch via butler..." -ForegroundColor Cyan
& $Butler push $OutDir $ItchTarget
if ($LASTEXITCODE -ne 0) { throw "Falha no butler push (exit $LASTEXITCODE)." }

Write-Host "==> Pronto! Versao publicada em $ItchTarget" -ForegroundColor Green
& $Butler status $ItchTarget
