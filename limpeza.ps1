# ============================================
# LIMPEZA DO SISTEMA
# Limpa cache, temp, logs, navegadores
# Verifica integridade com SFC
# Compativel com Windows 10 e 11
# ============================================

# Verificar se esta rodando como Administrador
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "ERRO: Execute este script como Administrador!" -ForegroundColor Red
    Write-Host "Clique com botao direito no PowerShell > Executar como Administrador" -ForegroundColor Yellow
    pause
    exit
}

# Contador de uso
Invoke-RestMethod -Uri "https://script.google.com/a/macros/ignetworks.com/s/AKfycbwt3WtOgyWIj-EBXPSbhji7uMKhUt2A3yOZT2igyvHKYioOtWvBsrCb_CP2-4Ah7qc/exec?script=limpeza" -ErrorAction SilentlyContinue | Out-Null

Write-Host ""
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "  LIMPEZA DO SISTEMA" -ForegroundColor Cyan
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host ""

# ============================================
# ESPACO ANTES
# ============================================

$espacoAntes = (Get-PSDrive -Name C).Free
Write-Host "Espaco livre antes: $([math]::Round($espacoAntes / 1GB, 2)) GB" -ForegroundColor Gray
Write-Host ""

# ============================================
# [1] FECHAR NAVEGADORES
# ============================================

Write-Host "[1/7] Fechando navegadores..." -ForegroundColor Cyan

$navegadores = @("iexplore", "chrome", "firefox", "msedge", "brave", "vivaldi", "opera")
foreach ($nav in $navegadores) {
    Stop-Process -Name $nav -Force -ErrorAction SilentlyContinue
}
Write-Host "  Navegadores fechados" -ForegroundColor Green

# ============================================
# [2] ESVAZIAR LIXEIRA
# ============================================

Write-Host "[2/7] Esvaziando lixeira..." -ForegroundColor Cyan

try {
    Clear-RecycleBin -Confirm:$false -ErrorAction SilentlyContinue
    Write-Host "  Lixeira esvaziada" -ForegroundColor Green
} catch {
    Write-Host "  Lixeira ja vazia" -ForegroundColor Gray
}

# ============================================
# [3] LIMPAR PASTAS TEMP
# ============================================

Write-Host "[3/7] Limpando pastas temporarias..." -ForegroundColor Cyan

# Temp de todos os usuarios
$usuarios = Get-ChildItem "C:\Users" -Directory -ErrorAction SilentlyContinue
foreach ($user in $usuarios) {
    $tempPath = "$($user.FullName)\AppData\Local\Temp"
    if (Test-Path $tempPath) {
        Remove-Item "$tempPath\*" -Recurse -Force -ErrorAction SilentlyContinue
        Write-Host "  Temp: $($user.Name)" -ForegroundColor Green
    }
}

# Windows Temp
Remove-Item "C:\Windows\Temp\*" -Recurse -Force -ErrorAction SilentlyContinue
Write-Host "  Temp: Windows" -ForegroundColor Green

# ============================================
# [4] LIMPAR LOGS DO WINDOWS
# ============================================

Write-Host "[4/7] Limpando logs..." -ForegroundColor Cyan

$logPaths = @(
    "C:\Windows\Logs\CBS\*.log",
    "C:\Windows\Logs\MoSetup\*.log",
    "C:\Windows\Panther\*.log",
    "C:\Windows\inf\*.log",
    "C:\Windows\Logs\*.log",
    "C:\Windows\SoftwareDistribution\*.log",
    "C:\Windows\Microsoft.NET\*.log"
)

foreach ($logPath in $logPaths) {
    Remove-Item $logPath -Recurse -Force -ErrorAction SilentlyContinue
}

# Logs do OneDrive de todos os usuarios
foreach ($user in $usuarios) {
    Remove-Item "$($user.FullName)\AppData\Local\Microsoft\OneDrive\setup\logs\*.log" -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host "  Logs limpos" -ForegroundColor Green

# ============================================
# [5] LIMPAR CACHE DO WINDOWS E IE
# ============================================

Write-Host "[5/7] Limpando cache do Windows..." -ForegroundColor Cyan

foreach ($user in $usuarios) {
    $base = $user.FullName

    # Explorer thumbnails e DB
    Remove-Item "$base\AppData\Local\Microsoft\Windows\Explorer\*.db" -Force -ErrorAction SilentlyContinue
    Remove-Item "$base\AppData\Local\Microsoft\Windows\Explorer\ThumbCacheToDelete\*.tmp" -Force -ErrorAction SilentlyContinue

    # WebCache
    Remove-Item "$base\AppData\Local\Microsoft\Windows\WebCache\*.log" -Force -ErrorAction SilentlyContinue

    # SettingSync
    Remove-Item "$base\AppData\Local\Microsoft\Windows\SettingSync\*.log" -Force -ErrorAction SilentlyContinue

    # Terminal Server Client cache
    Remove-Item "$base\AppData\Local\Microsoft\Terminal Server Client\Cache\*.bin" -Force -ErrorAction SilentlyContinue

    # INetCache (IE)
    Remove-Item "$base\AppData\Local\Microsoft\Windows\INetCache\IE\*" -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item "$base\AppData\Local\Microsoft\Windows\INetCache\Low\*" -Recurse -Force -ErrorAction SilentlyContinue

    # Temporary Internet Files
    Remove-Item "$base\AppData\Local\Microsoft\Windows\Temporary Internet Files\*" -Recurse -Force -ErrorAction SilentlyContinue
}

# Limpar cache IE via RunDll
Start-Process "RunDll32.exe" -ArgumentList "InetCpl.cpl,ClearMyTracksByProcess 8" -Wait -ErrorAction SilentlyContinue

Write-Host "  Cache do Windows limpo" -ForegroundColor Green

# ============================================
# [6] LIMPAR CACHE DOS NAVEGADORES
# ============================================

Write-Host "[6/7] Limpando cache dos navegadores..." -ForegroundColor Cyan

# Funcao para limpar cache de navegador Chromium
function Clear-ChromiumCache {
    param([string]$Name, [string]$RelPath)

    foreach ($user in $usuarios) {
        $basePath = "$($user.FullName)\AppData\Local\$RelPath"
        if (-not (Test-Path $basePath)) { continue }

        # Cache principal
        Remove-Item "$basePath\Default\Cache\Cache_Data\*" -Force -ErrorAction SilentlyContinue
        # Storage
        Remove-Item "$basePath\Default\Storage\*" -Recurse -Force -ErrorAction SilentlyContinue
        # GPU Cache
        Remove-Item "$basePath\Default\GPUCache\*" -Force -ErrorAction SilentlyContinue
        # Code Cache
        Remove-Item "$basePath\Default\Code Cache\js\*" -Recurse -Force -ErrorAction SilentlyContinue
        # Service Worker
        Remove-Item "$basePath\Default\Service Worker\CacheStorage\*" -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item "$basePath\Default\Service Worker\Database\*" -Force -ErrorAction SilentlyContinue
        Remove-Item "$basePath\Default\Service Worker\ScriptCache\*" -Force -ErrorAction SilentlyContinue
        # Browser Metrics
        Remove-Item "$basePath\BrowserMetrics\*.pma" -Force -ErrorAction SilentlyContinue
        # Edge Coupons
        Remove-Item "$basePath\Default\EdgeCoupons\coupons_data.db\*" -Force -ErrorAction SilentlyContinue

        Write-Host "  $Name ($($user.Name))" -ForegroundColor Green
    }
}

# Edge
Clear-ChromiumCache -Name "Edge" -RelPath "Microsoft\Edge\User Data"

# Chrome
Clear-ChromiumCache -Name "Chrome" -RelPath "Google\Chrome\User Data"

# Brave
Clear-ChromiumCache -Name "Brave" -RelPath "BraveSoftware\Brave-Browser\User Data"

# Vivaldi
Clear-ChromiumCache -Name "Vivaldi" -RelPath "Vivaldi\User Data"

# Firefox
foreach ($user in $usuarios) {
    $ffPath = "$($user.FullName)\AppData\Local\Mozilla\Firefox\Profiles"
    if (Test-Path $ffPath) {
        Remove-Item "$ffPath\*" -Recurse -Force -ErrorAction SilentlyContinue
        Write-Host "  Firefox ($($user.Name))" -ForegroundColor Green
    }
}

# ============================================
# [7] LIMPAR ADOBE MEDIA CACHE
# ============================================

Write-Host "[7/7] Limpando Adobe Media Cache..." -ForegroundColor Cyan

foreach ($user in $usuarios) {
    $adobePath = "$($user.FullName)\AppData\Roaming\Adobe\Common\Media Cache Files"
    if (Test-Path $adobePath) {
        Remove-Item "$adobePath\*" -Recurse -Force -ErrorAction SilentlyContinue
        Write-Host "  Adobe cache ($($user.Name))" -ForegroundColor Green
    }
}

Write-Host "  Adobe cache limpo" -ForegroundColor Green

# ============================================
# ESPACO LIBERADO
# ============================================

$espacoDepois = (Get-PSDrive -Name C).Free
$liberadoMB = [math]::Round(($espacoDepois - $espacoAntes) / 1MB, 2)
$liberadoGB = [math]::Round(($espacoDepois - $espacoAntes) / 1GB, 2)

Write-Host ""
Write-Host "=========================================" -ForegroundColor Green
Write-Host "  LIMPEZA CONCLUIDA" -ForegroundColor Green
Write-Host "=========================================" -ForegroundColor Green
Write-Host ""
Write-Host "  Espaco liberado: $liberadoMB MB ($liberadoGB GB)" -ForegroundColor Yellow
Write-Host ""
Write-Host "=========================================" -ForegroundColor Green

# ============================================
# SFC /SCANNOW
# ============================================

Write-Host ""
Write-Host "Executando verificacao de integridade do sistema (sfc /scannow)..." -ForegroundColor Cyan
Write-Host "Isso pode demorar alguns minutos..." -ForegroundColor Gray
Write-Host ""

$sfcOutput = sfc /scannow | Out-String

Write-Host $sfcOutput

# Detectar resultado do SFC
if ($sfcOutput -match "did not find any integrity violations|nao encontrou nenhuma violacao de integridade|no encontro ninguna infraccion|no integrity violations") {
    Write-Host "=========================================" -ForegroundColor Green
    Write-Host "  SFC: Nenhum problema encontrado" -ForegroundColor Green
    Write-Host "=========================================" -ForegroundColor Green
} elseif ($sfcOutput -match "successfully repaired|reparados com exito|reparado com sucesso") {
    Write-Host "=========================================" -ForegroundColor Yellow
    Write-Host "  SFC: Problemas encontrados e REPARADOS" -ForegroundColor Yellow
    Write-Host "=========================================" -ForegroundColor Yellow
} elseif ($sfcOutput -match "could not perform|unable to fix|nao pode reparar|no pudo reparar") {
    Write-Host "=========================================" -ForegroundColor Red
    Write-Host "  SFC: Problemas encontrados mas NAO reparados" -ForegroundColor Red
    Write-Host "  Recomendado: DISM /Online /Cleanup-Image /RestoreHealth" -ForegroundColor Red
    Write-Host "=========================================" -ForegroundColor Red
} else {
    Write-Host "=========================================" -ForegroundColor Gray
    Write-Host "  SFC: Verifique o resultado acima" -ForegroundColor Gray
    Write-Host "=========================================" -ForegroundColor Gray
}

Write-Host ""
Write-Host "Espaco liberado: $liberadoMB MB ($liberadoGB GB)" -ForegroundColor Yellow
Write-Host ""
Write-Host "Pressione qualquer tecla para sair..." -ForegroundColor Gray
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
