# ============================================================
#  UTI do Windows v6 (PowerShell) - Limpeza + Reparo profundo
#  Para Win10/11 travado / iniciando mal. Roda direto da web:
#    irm https://raw.githubusercontent.com/GCintra00/limpeza/master/uti-v6.ps1 | iex
#  (se nao for admin, se re-invoca elevado sozinho - zero arquivo)
#  Fases: mata apps -> desintoxica startup (backup) -> temp/caches
#  -> cache WU -> rede -> DISM completo -> SFC -> disco -> relatorio
#  Log completo: Desktop\UTI-backup\uti-log.txt
# ============================================================

$URL = 'https://raw.githubusercontent.com/GCintra00/limpeza/master/uti-v6.ps1'

# ---- auto-elevacao (re-baixa a si mesmo elevado, sem arquivo) ----
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
           ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host 'Elevando para Administrador...' -ForegroundColor Yellow
    Start-Process powershell -Verb RunAs -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-Command',"irm $URL | iex"
    return
}

$Host.UI.RawUI.WindowTitle = 'UTI do Windows v6 - nao feche esta janela'
$UTIDIR = Join-Path ([Environment]::GetFolderPath('Desktop')) 'UTI-backup'
New-Item -ItemType Directory -Path $UTIDIR -Force | Out-Null
Start-Transcript -Path (Join-Path $UTIDIR 'uti-log.txt') -Append | Out-Null
Write-Host "`n===== UTI v6 - $(Get-Date) =====" -ForegroundColor Cyan

# ---- escolha do modo das etapas longas (DISM/SFC/chkdsk/defrag) ----
Write-Host ''
Write-Host 'Como rodar as etapas longas?' -ForegroundColor Cyan
Write-Host '  [1] WATCHDOG  - limite de tempo por etapa + barras ao vivo (padrao, atendimento)'
Write-Host '  [2] LOG COMPLETO - grava TODA a saida do DISM/SFC no uti-log.txt (pericia do paciente; sem watchdog)'
$modo = Read-Host 'Escolha [Enter = 1]'
$MODO_LOG = ($modo -eq '2')
if ($MODO_LOG) { Write-Host '>> Modo LOG COMPLETO: tudo vai pro uti-log.txt (sem limite de tempo).' -ForegroundColor Yellow }
else { Write-Host '>> Modo WATCHDOG: etapas com limite de tempo; detalhe fino fica em C:\Windows\Logs (DISM/CBS).' -ForegroundColor Yellow }

# ---- cabecalho info-pc no log (registro de atendimento) ----
try {
    $cs = Get-CimInstance Win32_ComputerSystem; $bios = Get-CimInstance Win32_BIOS
    $os = Get-CimInstance Win32_OperatingSystem; $cpu = (Get-CimInstance Win32_Processor | Select-Object -First 1).Name
    Write-Host ''
    Write-Host ('PC: {0} | {1} {2} | Serial: {3}' -f $env:COMPUTERNAME, $cs.Manufacturer, $cs.Model, $bios.SerialNumber)
    Write-Host ('CPU: {0} | RAM: {1} GB | {2} (build {3})' -f $cpu, [math]::Round($cs.TotalPhysicalMemory/1GB,1), $os.Caption, $os.BuildNumber)
    $boot = $os.LastBootUpTime
    Write-Host ('Ligado ha: {0:N1} dias (ultimo boot: {1})' -f ((Get-Date) - $boot).TotalDays, $boot)
} catch {}

# ---- reboot pendente? (diagnostico sujo se rodar assim) ----
$pend = @()
if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') { $pend += 'CBS' }
if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired') { $pend += 'WindowsUpdate' }
if ((Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -Name PendingFileRenameOperations -ErrorAction SilentlyContinue)) { $pend += 'RenamePendente' }
if ($pend) {
    Write-Host ''
    Write-Host ("AVISO: este PC tem REINICIO PENDENTE ($($pend -join ', ')) - reparos/updates anteriores ainda nao assentaram.") -ForegroundColor Yellow
    Write-Host '  -> o ideal e REINICIAR antes da UTI, senao o diagnostico sai sujo.' -ForegroundColor Yellow
    $cont = Read-Host 'Continuar mesmo assim? [s/N]'
    if ($cont -notmatch '^[sSyY]') { Write-Host 'OK - reinicie e rode a UTI de novo.'; Stop-Transcript | Out-Null; return }
}

# ---- nao deixar o PC dormir no meio ----
$sig = '[DllImport("kernel32.dll")] public static extern uint SetThreadExecutionState(uint f);'
try { (Add-Type -MemberDefinition $sig -Name S -Namespace W -PassThru)::SetThreadExecutionState(0x80000003) | Out-Null } catch {}

$espacoAntes = (Get-PSDrive -Name C).Free

# ============ [1/9] MATAR APPS ============
Write-Host "`n[1/9] Fechando todos os aplicativos abertos..." -ForegroundColor Cyan
$whitelist = @('explorer','cmd','powershell','pwsh','powershell_ise','conhost','WindowsTerminal',
               'AnyDesk','TeamViewer','TeamViewer_Service','rustdesk','Taskmgr','dwm','TextInputHost')
Get-Process | Where-Object { $_.MainWindowHandle -ne 0 -and $whitelist -notcontains $_.ProcessName } |
    ForEach-Object { Write-Host "   matando: $($_.ProcessName)"; Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue }
# sanguessugas de segundo plano (sem janela)
@('steam','steamwebhelper','Discord','Spotify','EpicGamesLauncher','RiotClientServices','Battle.net',
  'GogGalaxy','Overwolf','uTorrent','BitTorrent','Skype','WhatsApp','Telegram','iTunes',
  'wallpaper64','wallpaper32','CCleaner64') | ForEach-Object {
    Get-Process -Name $_ -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue }

# ============ [1.5/9] EXTERMINADOR DE McAFEE (se detectado) ============
$temMcafee = (Get-Service -DisplayName '*McAfee*' -ErrorAction SilentlyContinue) -or
             (Test-Path "$env:ProgramFiles\McAfee") -or (Test-Path "${env:ProgramFiles(x86)}\McAfee") -or
             (Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.Name -match 'mcafee|mcuicnt|mcshield' })
if ($temMcafee) {
    Write-Host "`n[1.5/9] McAfee residual DETECTADO neste PC." -ForegroundColor Yellow
    $r = Read-Host 'Remover o McAfee de vez (servicos + tarefas + uninstall silencioso + pastas)? [S/n]'
    if ($r -notmatch '^[nN]') {
        Write-Host '   parando e desativando servicos McAfee...'
        Get-Service -DisplayName '*McAfee*' -ErrorAction SilentlyContinue | ForEach-Object {
            Stop-Service -Name $_.Name -Force -ErrorAction SilentlyContinue -WarningAction SilentlyContinue
            Set-Service -Name $_.Name -StartupType Disabled -ErrorAction SilentlyContinue }
        Get-Process -ErrorAction SilentlyContinue | Where-Object {
            $_.Name -match 'mcafee|mcshield|mcuicnt|ModuleCore|MMSSHOST|McPvTray|WebAdvisor|McInstaller|mfemms|mfevtps|mcods|mfefire|mfetp|protectedmodulehost'
        } | Stop-Process -Force -ErrorAction SilentlyContinue
        Write-Host '   removendo tarefas agendadas (as das notificacoes)...'
        Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object { $_.TaskName -like '*McAfee*' -or $_.TaskPath -like '*McAfee*' } | ForEach-Object {
            try { Unregister-ScheduledTask -TaskName $_.TaskName -TaskPath $_.TaskPath -Confirm:$false -ErrorAction Stop
                  Write-Host "     tarefa removida: $($_.TaskName)" } catch {} }
        Write-Host '   desinstalando (silencioso, ate 3 min por item)...'
        $regs = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
                'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
                'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
        Get-ItemProperty $regs -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -like '*McAfee*' } | ForEach-Object {
            $unins = $_.QuietUninstallString; if (-not $unins) { $unins = $_.UninstallString }
            if ($unins) {
                try {
                    if ($unins -match '^"([^"]+)"\s*(.*)$') { $exe = $matches[1]; $argStr = $matches[2] }
                    else { $tk = $unins -split ' ',2; $exe = $tk[0]; $argStr = if ($tk.Count -gt 1) { $tk[1] } else { '' } }
                    if ($argStr -notmatch '/quiet|/qn|/silent|/S\b') { $argStr = "$argStr /quiet /norestart" }
                    if (Test-Path $exe) {
                        $pu = Start-Process -FilePath $exe -ArgumentList $argStr -WindowStyle Hidden -PassThru -ErrorAction SilentlyContinue
                        if ($pu) { if (-not $pu.WaitForExit(180000)) { try { $pu.Kill() } catch {} }
                                   Write-Host "     desinstalado: $($_.DisplayName)" }
                    }
                } catch {}
            } }
        Write-Host '   apagando pastas residuais...'
        @("$env:ProgramFiles\McAfee","${env:ProgramFiles(x86)}\McAfee","$env:ProgramData\McAfee","$env:LOCALAPPDATA\McAfee","$env:APPDATA\McAfee") |
            ForEach-Object { if (Test-Path $_) { Remove-Item $_ -Recurse -Force -ErrorAction SilentlyContinue } }
        sc.exe delete 'McAfee WebAdvisor' 2>$null | Out-Null
        $resto = Get-ItemProperty $regs -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -like '*McAfee*' }
        if ($resto) {
            Write-Host '   !! Ainda ha produto McAfee registrado (uninstall interativo):' -ForegroundColor Yellow
            $resto | ForEach-Object { Write-Host "      - $($_.DisplayName)" -ForegroundColor Yellow }
            Write-Host '   -> desinstalar pelo Painel de Controle e/ou rodar o MCPR (ferramenta oficial McAfee).' -ForegroundColor Yellow
        } else {
            Write-Host '   McAfee exterminado (confirmacao final apos o reboot).' -ForegroundColor Green
        }
    } else { Write-Host '   ok, McAfee mantido.' }
}

# ============ [2/9] DESINTOXICAR INICIALIZACAO ============
Write-Host "`n[2/9] Desintoxicando a inicializacao (backup em $UTIDIR)..." -ForegroundColor Cyan
reg export "HKCU\Software\Microsoft\Windows\CurrentVersion\Run" "$UTIDIR\backup-run-hkcu.reg" /y 2>$null | Out-Null
reg export "HKLM\Software\Microsoft\Windows\CurrentVersion\Run" "$UTIDIR\backup-run-hklm.reg" /y 2>$null | Out-Null
$bad = 'Steam|Discord|Spotify|Epic|Riot|Battle\.net|GOG|Overwolf|uTorrent|BitTorrent|Skype|WhatsApp|Telegram|iTunes|Wallpaper|CCleaner'
foreach ($hive in 'HKCU:','HKLM:') {
    $k = "$hive\Software\Microsoft\Windows\CurrentVersion\Run"
    if (Test-Path $k) {
        (Get-Item $k).Property | Where-Object { $_ -match $bad } | ForEach-Object {
            Write-Host "   removido da inicializacao: $_" -ForegroundColor Yellow
            Remove-ItemProperty -Path $k -Name $_ -ErrorAction SilentlyContinue } } }
$startupDirs = @("$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup",
                 "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\StartUp")
foreach ($d in $startupDirs) {
    Get-ChildItem $d -Filter *.lnk -ErrorAction SilentlyContinue | Where-Object { $_.Name -match $bad } |
        ForEach-Object { Write-Host "   atalho movido p/ backup: $($_.Name)" -ForegroundColor Yellow
                         Move-Item $_.FullName $UTIDIR -Force } }
Write-Host '   --- Sobrou na inicializacao (revisar se precisa): ---'
foreach ($hive in 'HKCU:','HKLM:') {
    $k = "$hive\Software\Microsoft\Windows\CurrentVersion\Run"
    if (Test-Path $k) { (Get-Item $k).Property | ForEach-Object { Write-Host "   [$hive] $_" } } }
# Fast Startup OFF (causa classica de "iniciando mal")
powercfg /hibernate off 2>$null
New-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power' -Name HiberbootEnabled -Value 0 -PropertyType DWord -Force | Out-Null
Write-Host '   Fast Startup desativado (boot limpo de verdade).'

# ============ [3/9] TEMP / LIXEIRA / CACHES ============
Write-Host "`n[3/9] Limpando TEMP, lixeira, logs e caches..." -ForegroundColor Cyan
Clear-RecycleBin -Confirm:$false -ErrorAction SilentlyContinue
foreach ($u in Get-ChildItem C:\Users -Directory -ErrorAction SilentlyContinue) {
    $p = $u.FullName
    Remove-Item "$p\AppData\Local\Temp\*" -Recurse -Force -ErrorAction SilentlyContinue
    # caches em TODOS os perfis dos navegadores Chromium (Default, Profile 1, 2...)
    foreach ($udroot in @("$p\AppData\Local\Microsoft\Edge\User Data",
                          "$p\AppData\Local\Google\Chrome\User Data",
                          "$p\AppData\Local\BraveSoftware\Brave-Browser\User Data",
                          "$p\AppData\Local\Vivaldi\User Data")) {
        Get-ChildItem $udroot -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match '^(Default|Profile \d+)$' } | ForEach-Object {
                Remove-Item "$($_.FullName)\Cache\Cache_Data\*" -Recurse -Force -ErrorAction SilentlyContinue
                Remove-Item "$($_.FullName)\Code Cache\js\*" -Recurse -Force -ErrorAction SilentlyContinue } }
    @("$p\AppData\Local\Microsoft\Windows\INetCache\IE",
      "$p\AppData\Roaming\Adobe\Common\Media Cache Files") | ForEach-Object {
        Remove-Item "$_\*" -Recurse -Force -ErrorAction SilentlyContinue }
    Get-ChildItem "$p\AppData\Local\Mozilla\Firefox\Profiles" -Directory -ErrorAction SilentlyContinue |
        ForEach-Object { Remove-Item "$($_.FullName)\cache2\*" -Recurse -Force -ErrorAction SilentlyContinue }
}
Remove-Item 'C:\Windows\Temp\*' -Recurse -Force -ErrorAction SilentlyContinue
@('C:\Windows\Logs\CBS\*.log','C:\Windows\Logs\MoSetup\*.log','C:\Windows\Panther\*.log',
  'C:\Windows\inf\*.log','C:\Windows\Logs\*.log') | ForEach-Object {
    Remove-Item $_ -Force -ErrorAction SilentlyContinue }

# ============ [4/9] CACHE DO WINDOWS UPDATE ============
Write-Host "`n[4/9] Limpando cache do Windows Update..." -ForegroundColor Cyan
Write-Host '   parando servicos do WU (pode levar 1-2 min)...'
Stop-Service wuauserv,bits -Force -ErrorAction SilentlyContinue -WarningAction SilentlyContinue
Remove-Item 'C:\Windows\SoftwareDistribution\Download\*' -Recurse -Force -ErrorAction SilentlyContinue
Start-Service bits,wuauserv -ErrorAction SilentlyContinue
Delete-DeliveryOptimizationCache -Force -ErrorAction SilentlyContinue

# ============ [5/9] REDE ============
Write-Host "`n[5/9] Rede: flush DNS + reset Winsock..." -ForegroundColor Cyan
ipconfig /flushdns | Out-Null
netsh winsock reset | Out-Null
Write-Host '   (winsock reset completa no proximo reboot)'

# ---- watchdog: roda etapa com limite de tempo ----
# MataSeTravar=$true  -> etapa so-leitura: aborta no timeout e segue a vida
# MataSeTravar=$false -> etapa que ESCREVE no sistema: NUNCA mata (perigoso);
#                        avisa a cada 15 min e continua esperando
# Quando a saida vai por PIPE (transcript/Out-String), cada nativo fala uma lingua:
# DISM emite ANSI (1252) e SFC emite UTF-16 - decodificar errado da "Manutenbòo"/"V e r i f".
$ENC_PADRAO = [Console]::OutputEncoding
function Set-EncNativo([string]$exe) {
    # dism e defrag falam ANSI 1252; sfc fala UTF-16; chkdsk usa o padrao do console.
    # (defrag confirmado no log do Vostro 5320 em 30/07: saia "A opera??o foi conclu?da")
    if     ($exe -match 'dism|defrag') { [Console]::OutputEncoding = [Text.Encoding]::GetEncoding(1252) }
    elseif ($exe -match 'sfc')         { [Console]::OutputEncoding = [Text.Encoding]::Unicode }
    else                               { [Console]::OutputEncoding = $ENC_PADRAO }
}

function Run-Etapa {
    param([string]$Desc, [string]$Exe, [string]$Argumentos, [int]$TimeoutMin, [bool]$MataSeTravar)
    $t0 = Get-Date
    if ($MODO_LOG) {
        # modo pericia: chamada direta -> transcript captura toda a saida; sem watchdog
        Write-Host "   --- $Desc (log completo, sem limite) ---" -ForegroundColor Cyan
        Set-EncNativo $Exe
        try { & $Exe ($Argumentos -split ' ') } finally { [Console]::OutputEncoding = $ENC_PADRAO }
        Write-Host ("   ('{0}' terminou em {1} min)" -f $Desc, [math]::Round(((Get-Date) - $t0).TotalMinutes, 1))
        return
    }
    Write-Host "   --- $Desc (limite ${TimeoutMin} min) ---" -ForegroundColor Cyan
    $p = Start-Process -FilePath $Exe -ArgumentList $Argumentos -NoNewWindow -PassThru
    $limite = $TimeoutMin
    while (-not $p.HasExited) {
        Start-Sleep -Seconds 15
        $min = ((Get-Date) - $t0).TotalMinutes
        if ($min -ge $limite) {
            if ($MataSeTravar) {
                Write-Host "   !! '$Desc' passou de $limite min - ABORTANDO etapa e seguindo" -ForegroundColor Red
                Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue; break
            } else {
                Write-Host "   !! '$Desc' passou de $limite min - etapa de ESCRITA, nao vou matar. Aguardando mais 15 min... (Ctrl+C aborta tudo)" -ForegroundColor Yellow
                $limite += 15
            }
        }
    }
    Write-Host ("   ('{0}' terminou em {1} min)" -f $Desc, [math]::Round(((Get-Date) - $t0).TotalMinutes, 1))
}

# ============ [6/9] DISM COMPLETO ============
Write-Host "`n[6/9] BATERIA DISM - fase LONGA (15 a 60+ min no total; '62% parado' e normal, NAO e travamento)" -ForegroundColor Cyan
Set-EncNativo 'dism'
dism /Online /Cleanup-Image /CheckHealth
[Console]::OutputEncoding = $ENC_PADRAO
Run-Etapa 'ScanHealth'            'dism' '/Online /Cleanup-Image /ScanHealth'            30 $true
Run-Etapa 'RestoreHealth'         'dism' '/Online /Cleanup-Image /RestoreHealth'         60 $false
Run-Etapa 'AnalyzeComponentStore' 'dism' '/Online /Cleanup-Image /AnalyzeComponentStore' 15 $true
Run-Etapa 'StartComponentCleanup' 'dism' '/Online /Cleanup-Image /StartComponentCleanup' 60 $false

# ---- pericia pos-DISM: se continuar "reparavel", extrai o laudo do CBS.log ----
Set-EncNativo 'dism'
$chk = (dism /Online /Cleanup-Image /CheckHealth | Out-String)
[Console]::OutputEncoding = $ENC_PADRAO
if ($chk -match 'repairable|reparable|reparavel|repar') {
    Write-Host ''
    Write-Host '   PERICIA: repositorio segue "reparavel" apos RestoreHealth - extraindo laudo do CBS.log...' -ForegroundColor Yellow
    try {
        $cbs = Get-Content C:\Windows\Logs\CBS\CBS.log -ErrorAction Stop
        $num = ($cbs | Select-String 'numCorruptions = (\d+)' | Select-Object -Last 1)
        if ($num) { Write-Host ('   Corrupcoes detectadas: ' + $num.Matches[0].Groups[1].Value) -ForegroundColor Yellow }
        $comp = @($cbs | Select-String 'CSI Payload Corrupt' | Select-Object -Last 8)
        if ($comp) {
            Write-Host '   Componentes corrompidos (ultimos 8):' -ForegroundColor Yellow
            $comp | ForEach-Object { Write-Host ('     ' + ($_.Line -replace '^.*\(n\)\s*','').Trim()) }
            if ($comp[-1].Line -match '_(10\.0\.\d+\.\d+)_') {
                $verBase = $matches[1]; $verSo = (Get-CimInstance Win32_OperatingSystem).Version
                if (-not $verBase.StartsWith($verSo)) {
                    Write-Host ("   -> Payloads de baseline SUPERADA ($verBase; SO atual $verSo): o WU nao distribui mais esses arquivos = flag tende a ser CRONICA e COSMETICA (sistema vivo integro se o SFC abaixo vier limpo).") -ForegroundColor Yellow
                }
            }
        }
        Write-Host '   ESCADA DE TRATAMENTO (avaliar depois - NADA disso roda automatico):' -ForegroundColor Yellow
        Write-Host '     1. (manual) DISM /Online /Cleanup-Image /StartComponentCleanup /ResetBase + reboot'
        Write-Host '        ATENCAO: ResetBase impede desinstalar updates antigos - por isso NAO roda sozinho.'
        Write-Host '     2. In-place upgrade (ISO da MESMA versao -> setup.exe -> manter arquivos/apps) = fix definitivo.'
        Write-Host '     3. Conviver com a flag se a maquina esta funcional (SFC limpo = sistema vivo integro).'
    } catch { Write-Host '   (nao consegui ler o CBS.log)' }
}

# ============ [7/9] SFC ============
Write-Host "`n[7/9] SFC /scannow - pode levar de 5 a 60+ min (depois do DISM, na ordem certa)..." -ForegroundColor Cyan
Run-Etapa 'SFC /scannow' 'sfc' '/scannow' 60 $false

# ============ [8/9] DISCO ============
Write-Host "`n[8/9] Disco: chkdsk online + otimizacao (TRIM/defrag)..." -ForegroundColor Cyan
Run-Etapa 'chkdsk /scan' 'chkdsk' 'C: /scan' 30 $true
Run-Etapa 'defrag /O'    'defrag' 'C: /O'    45 $true

# ============ [8.5/9] COLETA DE DIAGNOSTICO (so leitura - tudo pro log) ============
Write-Host "`n[8.5/9] Coletando diagnosticos do sistema (rapido, so leitura)..." -ForegroundColor Cyan
try {
    $des = (Get-WinEvent -FilterHashtable @{LogName='System'; Id=41,6008; StartTime=(Get-Date).AddDays(-30)} -ErrorAction SilentlyContinue | Measure-Object).Count
    $flag = if ($des -gt 3) { ' <- SUSPEITO (causa classica de corrupcao de store)' } else { '' }
    Write-Host "   Desligamentos SUJOS nos ultimos 30 dias (Kernel-Power 41/6008): $des$flag"
} catch { Write-Host '   Desligamentos sujos: (sem dados)' }
try {
    Write-Host '   Ultimos erros criticos do sistema (14 dias, max 15):'
    Get-WinEvent -FilterHashtable @{LogName='System'; Level=1,2; StartTime=(Get-Date).AddDays(-14)} -MaxEvents 15 -ErrorAction Stop |
        ForEach-Object { $m = ($_.Message -split "`n")[0]; if ($m.Length -gt 90) { $m = $m.Substring(0,90) }
                         Write-Host ('     {0:MM/dd HH:mm} [{1}] {2}' -f $_.TimeCreated, $_.ProviderName, $m) }
} catch { Write-Host '   Erros do sistema: (nenhum critico recente ou sem acesso)' }
try {
    $mp = Get-MpComputerStatus -ErrorAction Stop
    $velho = if (((Get-Date) - $mp.AntivirusSignatureLastUpdated).TotalDays -gt 7) { ' <- DEFINICOES VELHAS' } else { '' }
    Write-Host ('   Defender: ativo={0} | tempo-real={1} | definicoes de {2:MM/dd}{3}' -f $mp.AntivirusEnabled, $mp.RealTimeProtectionEnabled, $mp.AntivirusSignatureLastUpdated, $velho)
} catch { Write-Host '   Defender: (nao consegui ler - CONFERIR manualmente, principalmente se antivirus foi removido)' }
try {
    Get-PhysicalDisk | ForEach-Object {
        $r = $_ | Get-StorageReliabilityCounter -ErrorAction SilentlyContinue
        Write-Host ('   Disco: {0} | Saude: {1} | Desgaste: {2}% | Temp: {3}C | ErrosLeitura: {4}' -f $_.FriendlyName, $_.HealthStatus, "$($r.Wear)", "$($r.Temperature)", "$($r.ReadErrorsTotal)") }
} catch { Write-Host '   Discos: (sem contadores de confiabilidade)' }
try {
    Write-Host '   Ultimos 5 updates instalados:'
    Get-HotFix -ErrorAction Stop | Sort-Object InstalledOn -Descending | Select-Object -First 5 |
        ForEach-Object { Write-Host ('     {0} - {1:yyyy-MM-dd}' -f $_.HotFixID, $_.InstalledOn) }
} catch { Write-Host '   Updates: (sem dados)' }

# ============ [9/9] RELATORIO ============
$espacoDepois = (Get-PSDrive -Name C).Free
$liberadoMB = [math]::Round(($espacoAntes - $espacoDepois) / 1MB)
$liberado = if ($liberadoMB -ge 0) { "$liberadoMB MB" }
            else { "0 MB (disco ate cresceu $(-$liberadoMB) MB durante o reparo - normal: Windows Update rebaixando updates apos a limpeza do cache)" }
Write-Host "`n"
Write-Host '           UTI CONCLUIDA - PACIENTE RESPIRANDO' -ForegroundColor Green
Write-Host '====================================================='
Write-Host " Espaco liberado ............ $liberado"
Write-Host ' Apps + inicializacao ....... limpos (backup em Desktop\UTI-backup)'
Write-Host ' DISM + SFC ................. rodados (resultados acima e no log)'
Write-Host ' WU cache / DNS / Winsock ... resetados'
Write-Host ' Fast Startup ............... desativado'
Write-Host '====================================================='
Write-Host ' REINICIE O PC agora: winsock + DISM + boot limpo' -ForegroundColor Yellow
Write-Host '   so valem apos o reboot.' -ForegroundColor Yellow
Write-Host ' Log completo + backups: Desktop\UTI-backup'
Write-Host '   (reverter startup: duplo clique no .reg / mover o .lnk de volta)'
Write-Host '====================================================='
Stop-Transcript | Out-Null
$rb = Read-Host 'REINICIAR AGORA (recomendado - os reparos so valem apos o reboot)? [S/n]'
if ($rb -notmatch '^[nN]') {
    Write-Host 'Reiniciando em 20 segundos... (feche o que precisar; cancelar: shutdown /a)' -ForegroundColor Yellow
    shutdown /r /t 20 /c "UTI do Windows: reinicio para aplicar os reparos (DISM/winsock/boot limpo)"
} else {
    Write-Host 'OK - mas REINICIE assim que puder: DISM/winsock/boot limpo so valem apos o reboot.' -ForegroundColor Yellow
    Read-Host 'Pressione ENTER para sair'
}
