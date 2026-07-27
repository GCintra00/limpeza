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
    @("$p\AppData\Local\Microsoft\Edge\User Data\Default\Cache\Cache_Data",
      "$p\AppData\Local\Microsoft\Edge\User Data\Default\Code Cache\js",
      "$p\AppData\Local\Google\Chrome\User Data\Default\Cache\Cache_Data",
      "$p\AppData\Local\Google\Chrome\User Data\Default\Code Cache\js",
      "$p\AppData\Local\BraveSoftware\Brave-Browser\User Data\Default\Cache\Cache_Data",
      "$p\AppData\Local\Vivaldi\User Data\Default\Cache\Cache_Data",
      "$p\AppData\Local\Microsoft\Windows\INetCache\IE",
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
Stop-Service wuauserv,bits -Force -ErrorAction SilentlyContinue
Remove-Item 'C:\Windows\SoftwareDistribution\Download\*' -Recurse -Force -ErrorAction SilentlyContinue
Start-Service bits,wuauserv -ErrorAction SilentlyContinue
Delete-DeliveryOptimizationCache -Force -ErrorAction SilentlyContinue

# ============ [5/9] REDE ============
Write-Host "`n[5/9] Rede: flush DNS + reset Winsock..." -ForegroundColor Cyan
ipconfig /flushdns | Out-Null
netsh winsock reset | Out-Null
Write-Host '   (winsock reset completa no proximo reboot)'

# ============ [6/9] DISM COMPLETO ============
Write-Host "`n[6/9] BATERIA DISM (a parte demorada - '62% parado' e normal)" -ForegroundColor Cyan
Write-Host '   --- CheckHealth ---';            dism /Online /Cleanup-Image /CheckHealth
Write-Host '   --- ScanHealth ---';             dism /Online /Cleanup-Image /ScanHealth
Write-Host '   --- RestoreHealth ---';          dism /Online /Cleanup-Image /RestoreHealth
Write-Host '   --- AnalyzeComponentStore ---';  dism /Online /Cleanup-Image /AnalyzeComponentStore
Write-Host '   --- StartComponentCleanup ---';  dism /Online /Cleanup-Image /StartComponentCleanup

# ============ [7/9] SFC ============
Write-Host "`n[7/9] SFC /scannow (depois do DISM, na ordem certa)..." -ForegroundColor Cyan
sfc /scannow

# ============ [8/9] DISCO ============
Write-Host "`n[8/9] Disco: chkdsk online + otimizacao (TRIM/defrag)..." -ForegroundColor Cyan
chkdsk C: /scan
defrag C: /O

# ============ [9/9] RELATORIO ============
$espacoDepois = (Get-PSDrive -Name C).Free
$liberado = [math]::Round(($espacoAntes - $espacoDepois) / 1MB)
Write-Host "`n"
Write-Host '           UTI CONCLUIDA - PACIENTE RESPIRANDO' -ForegroundColor Green
Write-Host '====================================================='
Write-Host " Espaco liberado ............ $liberado MB"
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
Read-Host 'Pressione ENTER para sair'
