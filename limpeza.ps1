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

# Desativar todas as confirmacoes (ja roda como Admin)
$ConfirmPreference = "None"

# Contador de uso
Invoke-RestMethod -Uri "https://script.google.com/macros/s/AKfycbwZwJrHL2SnECPzx5inz2K5_AVxbVvukXMra0grAgSbVuNjbxeNnP8sLDGdy-Sf2yfvoA/exec?script=limpeza" -ErrorAction SilentlyContinue | Out-Null

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

Write-Host "[1/8] Fechando navegadores..." -ForegroundColor Cyan

$navegadores = @("iexplore", "chrome", "firefox", "msedge", "brave", "vivaldi", "opera")
foreach ($nav in $navegadores) {
    Stop-Process -Name $nav -Force -ErrorAction SilentlyContinue
}
Write-Host "  Navegadores fechados" -ForegroundColor Green

# ============================================
# [2] ESVAZIAR LIXEIRA
# ============================================

Write-Host "[2/8] Esvaziando lixeira..." -ForegroundColor Cyan

try {
    Clear-RecycleBin -Confirm:$false -ErrorAction SilentlyContinue
    Write-Host "  Lixeira esvaziada" -ForegroundColor Green
} catch {
    Write-Host "  Lixeira ja vazia" -ForegroundColor Gray
}

# ============================================
# [3] LIMPAR PASTAS TEMP
# ============================================

Write-Host "[3/8] Limpando pastas temporarias..." -ForegroundColor Cyan

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

Write-Host "[4/8] Limpando logs..." -ForegroundColor Cyan

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

Write-Host "[5/8] Limpando cache do Windows..." -ForegroundColor Cyan

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

Write-Host "[6/8] Limpando cache dos navegadores..." -ForegroundColor Cyan

# Funcao para limpar cache de navegador Chromium
function Clear-ChromiumCache {
    param([string]$Name, [string]$RelPath)

    foreach ($user in $usuarios) {
        $basePath = "$($user.FullName)\AppData\Local\$RelPath"
        if (-not (Test-Path $basePath)) { continue }

        # Cache principal
        Remove-Item "$basePath\Default\Cache\Cache_Data\*" -Recurse -Force -ErrorAction SilentlyContinue
        # Storage
        Remove-Item "$basePath\Default\Storage\*" -Recurse -Force -ErrorAction SilentlyContinue
        # GPU Cache
        Remove-Item "$basePath\Default\GPUCache\*" -Recurse -Force -ErrorAction SilentlyContinue
        # Code Cache
        Remove-Item "$basePath\Default\Code Cache\js\*" -Recurse -Force -ErrorAction SilentlyContinue
        # Service Worker
        Remove-Item "$basePath\Default\Service Worker\CacheStorage\*" -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item "$basePath\Default\Service Worker\Database\*" -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item "$basePath\Default\Service Worker\ScriptCache\*" -Recurse -Force -ErrorAction SilentlyContinue
        # Browser Metrics
        Remove-Item "$basePath\BrowserMetrics\*.pma" -Force -ErrorAction SilentlyContinue
        # Edge Coupons
        Remove-Item "$basePath\Default\EdgeCoupons\coupons_data.db\*" -Recurse -Force -ErrorAction SilentlyContinue

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

Write-Host "[7/8] Limpando Adobe Media Cache..." -ForegroundColor Cyan

foreach ($user in $usuarios) {
    $adobePath = "$($user.FullName)\AppData\Roaming\Adobe\Common\Media Cache Files"
    if (Test-Path $adobePath) {
        Remove-Item "$adobePath\*" -Recurse -Force -ErrorAction SilentlyContinue
        Write-Host "  Adobe cache ($($user.Name))" -ForegroundColor Green
    }
}

Write-Host "  Adobe cache limpo" -ForegroundColor Green

# ============================================
# [8] REMOVER AUTO-INICIO DE PROGRAMAS
# ============================================

Write-Host "[8/8] Removendo programas do inicio automatico..." -ForegroundColor Cyan

# Itens que DEVEM permanecer no auto-inicio
$manter = @("SecurityHealth", "RtkAudUService")

# Limpar HKCU Run (remover TUDO exceto os mantidos e AnyDesk)
$regRun = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
if (Test-Path $regRun) {
    $entries = Get-ItemProperty $regRun -ErrorAction SilentlyContinue
    foreach ($prop in $entries.PSObject.Properties) {
        if ($prop.Name -match "^PS" -or $prop.Name -eq "(default)") { continue }
        $keep = $false
        foreach ($m in $manter) { if ($prop.Name -like "*$m*") { $keep = $true } }
        if ($prop.Name -like "*AnyDesk*") { $keep = $true }
        if (-not $keep) {
            Remove-ItemProperty -Path $regRun -Name $prop.Name -ErrorAction SilentlyContinue
            Write-Host "  Removido HKCU: $($prop.Name)" -ForegroundColor Green
        }
    }
}

# Limpar HKLM Run (remover TUDO exceto mantidos e AnyDesk)
$regRunLM = "HKLM:\Software\Microsoft\Windows\CurrentVersion\Run"
if (Test-Path $regRunLM) {
    $entries = Get-ItemProperty $regRunLM -ErrorAction SilentlyContinue
    foreach ($prop in $entries.PSObject.Properties) {
        if ($prop.Name -match "^PS" -or $prop.Name -eq "(default)") { continue }
        $keep = $false
        foreach ($m in $manter) { if ($prop.Name -like "*$m*") { $keep = $true } }
        if ($prop.Name -like "*AnyDesk*") { $keep = $true }
        if (-not $keep) {
            Remove-ItemProperty -Path $regRunLM -Name $prop.Name -ErrorAction SilentlyContinue
            Write-Host "  Removido HKLM: $($prop.Name)" -ForegroundColor Green
        }
    }
}

# Corrigir AnyDesk para executar em segundo plano (--control) se existir
$anydeskPaths = @(
    "$env:ProgramFiles\AnyDesk\AnyDesk.exe",
    "${env:ProgramFiles(x86)}\AnyDesk\AnyDesk.exe"
)
foreach ($adPath in $anydeskPaths) {
    if (Test-Path $adPath) {
        Set-ItemProperty -Path $regRunLM -Name "AnyDesk" -Value "`"$adPath`" --control" -ErrorAction SilentlyContinue
        Write-Host "  AnyDesk configurado em segundo plano (--control)" -ForegroundColor Green
        break
    }
}

# Limpar pasta Startup do usuario
$startupFolder = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup"
if (Test-Path $startupFolder) {
    Get-ChildItem $startupFolder -ErrorAction SilentlyContinue | ForEach-Object {
        Remove-Item $_.FullName -Force -ErrorAction SilentlyContinue
        Write-Host "  Removido Startup: $($_.Name)" -ForegroundColor Green
    }
}

# Limpar pasta Common Startup
$commonStartup = "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\Startup"
if (Test-Path $commonStartup) {
    Get-ChildItem $commonStartup -ErrorAction SilentlyContinue | ForEach-Object {
        Remove-Item $_.FullName -Force -ErrorAction SilentlyContinue
        Write-Host "  Removido Common Startup: $($_.Name)" -ForegroundColor Green
    }
}

# Desativar via StartupApproved (Gerenciador de Tarefas)
$permitidos = @("SecurityHealth", "RtkAudUService", "AnyDesk")
$disabledBytes = [byte[]](0x03,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00)

$regApproved = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run"
if (Test-Path $regApproved) {
    (Get-Item $regApproved).GetValueNames() | ForEach-Object {
        if ($_ -eq "(default)") { return }
        $permitido = $false
        foreach ($p in $permitidos) { if ($_ -like "*$p*") { $permitido = $true } }
        if (-not $permitido) {
            Set-ItemProperty -Path $regApproved -Name $_ -Value $disabledBytes -Type Binary -ErrorAction SilentlyContinue
            Write-Host "  Desativado startup: $_" -ForegroundColor Green
        }
    }
}

$regApprovedLM = "HKLM:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run"
if (Test-Path $regApprovedLM) {
    (Get-Item $regApprovedLM).GetValueNames() | ForEach-Object {
        if ($_ -eq "(default)") { return }
        $permitido = $false
        foreach ($p in $permitidos) { if ($_ -like "*$p*") { $permitido = $true } }
        if (-not $permitido) {
            Set-ItemProperty -Path $regApprovedLM -Name $_ -Value $disabledBytes -Type Binary -ErrorAction SilentlyContinue
            Write-Host "  Desativado startup HKLM: $_" -ForegroundColor Green
        }
    }
}

$regApprovedFolder = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\StartupFolder"
if (Test-Path $regApprovedFolder) {
    (Get-Item $regApprovedFolder).GetValueNames() | ForEach-Object {
        if ($_ -eq "(default)") { return }
        $permitido = $false
        foreach ($p in $permitidos) { if ($_ -like "*$p*") { $permitido = $true } }
        if (-not $permitido) {
            Set-ItemProperty -Path $regApprovedFolder -Name $_ -Value $disabledBytes -Type Binary -ErrorAction SilentlyContinue
            Write-Host "  Desativado startup folder: $_" -ForegroundColor Green
        }
    }
}

# Remover programas que se readicionam
Remove-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" -Name "OneDrive" -ErrorAction SilentlyContinue
Remove-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" -Name "OneDriveSetup" -ErrorAction SilentlyContinue
Remove-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" -Name "Discord" -ErrorAction SilentlyContinue
Remove-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" -Name "com.squirrel.slack.slack" -ErrorAction SilentlyContinue
Remove-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" -Name "Steam" -ErrorAction SilentlyContinue
Remove-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" -Name "EpicGamesLauncher" -ErrorAction SilentlyContinue
Remove-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" -Name "Spotify" -ErrorAction SilentlyContinue
Remove-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" -Name "LGHUB" -ErrorAction SilentlyContinue

# Desativar tarefas agendadas de logon (exceto sistema)
$tarefasManter = @("MicrosoftEdgeUpdateTask", "SecurityHealth", "Windows", "Microsoft\Windows")
Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object {
    $_.Triggers | Where-Object { $_ -is [Microsoft.Management.Infrastructure.CimInstance] -and $_.CimClass.CimClassName -eq "MSFT_TaskLogonTrigger" }
} | ForEach-Object {
    $skip = $false
    foreach ($m in $tarefasManter) { if ($_.TaskPath -like "*$m*") { $skip = $true } }
    if (-not $skip) {
        Disable-ScheduledTask -TaskName $_.TaskName -TaskPath $_.TaskPath -ErrorAction SilentlyContinue
        Write-Host "  Tarefa desativada: $($_.TaskName)" -ForegroundColor Green
    }
}

Write-Host "  Auto-inicio limpo (Defender + AnyDesk + audio mantidos)" -ForegroundColor Green

# ============================================
# ESPACO LIBERADO
# ============================================

$espacoDepois = (Get-PSDrive -Name C).Free
$liberadoMB = [math]::Round(($espacoDepois - $espacoAntes) / 1MB, 2)
$liberadoGB = [math]::Round(($espacoDepois - $espacoAntes) / 1GB, 2)

# ============================================
# SFC /SCANNOW
# ============================================

Write-Host ""
Write-Host "Verificando integridade do sistema (sfc /scannow)..." -ForegroundColor Cyan
Write-Host "Isso pode demorar alguns minutos..." -ForegroundColor Gray
Write-Host ""

# Forcar encoding correto para caracteres especiais (espanhol/portugues)
[Console]::OutputEncoding = [System.Text.Encoding]::GetEncoding([System.Globalization.CultureInfo]::CurrentCulture.TextInfo.OEMCodePage)

$sfcOutput = ""
sfc /scannow 2>&1 | ForEach-Object {
    $line = $_.ToString()
    $sfcOutput += "$line`n"
    Write-Host $line
}

# Detectar resultado do SFC
if ($sfcOutput -match "did not find any integrity|no encontr.*ninguna infracci|nao encontrou nenhum.*violac|no integrity violations") {
    $sfcResultado = "Nenhum problema detectado"
    $sfcCor = "Green"
} elseif ($sfcOutput -match "successfully repaired|repar.*correctamente|reparado com sucesso|reparados com exito|da.*ados y los repar") {
    $sfcResultado = "Problemas encontrados e reparados"
    $sfcCor = "Yellow"
} elseif ($sfcOutput -match "could not perform|unable to fix|no pudo reparar|nao pode reparar|no pudo corregir") {
    $sfcResultado = "Problemas encontrados - NAO reparados (rodar DISM)"
    $sfcCor = "Red"
} else {
    $sfcResultado = "Verifique o resultado acima"
    $sfcCor = "Gray"
}

# ============================================
# TELA FINAL
# ============================================

Clear-Host
Write-Host ""
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "  RESULTADO DA LIMPEZA" -ForegroundColor Cyan
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Espaco liberado: $liberadoMB MB ($liberadoGB GB)" -ForegroundColor Yellow
Write-Host "  SFC: $sfcResultado" -ForegroundColor $sfcCor
Write-Host ""
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Pressione qualquer tecla para sair..." -ForegroundColor Gray
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
