@echo off
setlocal EnableDelayedExpansion
chcp 65001 >nul
title 🏥 UTI do Windows (v6) - Limpeza + Reparo profundo

:: ============================================================
::  LIMPEZA DISM v6 - "UTI" p/ Win10/11 todo travado
::  v5 (temp/lixeira/caches) + DISM completo + SFC + matar apps
::  + desintoxicar inicializacao (com BACKUP) + WU cache + rede
::  + chkdsk/defrag. Log e backups no Desktop.
:: ============================================================

:: ==== AUTOELEVAÇÃO ====
net session >nul 2>&1
if %errorlevel% neq 0 (
    powershell -Command "Start-Process '%~f0' -Verb RunAs"
    exit /b
)

:: ==== PASTA DE BACKUP/LOG ====
set "UTIDIR=%USERPROFILE%\Desktop\UTI-backup"
mkdir "%UTIDIR%" 2>nul
set "LOG=%UTIDIR%\uti-log.txt"
echo ===== UTI v6 - %date% %time% ===== > "%LOG%"

:: ==== NAO DEIXAR O PC DORMIR NO MEIO ====
powershell -Command "$s='[DllImport(\"kernel32.dll\")] public static extern uint SetThreadExecutionState(uint f);'; (Add-Type -MemberDefinition $s -Name S -Namespace W -PassThru)::SetThreadExecutionState(0x80000003)" >nul 2>&1

:: ==== ESPAÇO ANTES ====
for /f %%A in ('powershell -command "(Get-PSDrive -Name C).Free"') do set "espaco_antes=%%A"

echo.
echo [1/9] Fechando TODOS os aplicativos abertos...
echo   (preservando: Explorer, AnyDesk/TeamViewer/RustDesk, Terminal, Gerenciador)
:: mata tudo que tem janela visivel, exceto whitelist (nao derruba acesso remoto!)
powershell -NoProfile -Command "$wl=@('explorer','cmd','powershell','pwsh','conhost','WindowsTerminal','AnyDesk','TeamViewer','TeamViewer_Service','rustdesk','Taskmgr','dwm','TextInputHost'); Get-Process | Where-Object { $_.MainWindowHandle -ne 0 -and $wl -notcontains $_.ProcessName } | ForEach-Object { Write-Host ('   matando: ' + $_.ProcessName); Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue }" 2>>"%LOG%"
:: e os sanguessugas de segundo plano (sem janela)
for %%P in (steam.exe steamwebhelper.exe Discord.exe Spotify.exe EpicGamesLauncher.exe RiotClientServices.exe Battle.net.exe GogGalaxy.exe Overwolf.exe uTorrent.exe BitTorrent.exe Skype.exe WhatsApp.exe Telegram.exe iTunes.exe wallpaper64.exe wallpaper32.exe CCleaner64.exe) do taskkill /f /im %%P >nul 2>&1

echo.
echo [2/9] Desintoxicando a INICIALIZACAO (backup em %UTIDIR%)...
:: backup das chaves Run antes de mexer
reg export "HKCU\Software\Microsoft\Windows\CurrentVersion\Run" "%UTIDIR%\backup-run-hkcu.reg" /y >nul 2>&1
reg export "HKLM\Software\Microsoft\Windows\CurrentVersion\Run" "%UTIDIR%\backup-run-hklm.reg" /y >nul 2>&1
:: remove da inicializacao os folgados conhecidos (jogos/lazer) - HKCU e HKLM
powershell -NoProfile -Command "$bad='Steam|Discord|Spotify|Epic|Riot|Battle\.net|GOG|Overwolf|uTorrent|BitTorrent|Skype|WhatsApp|Telegram|iTunes|Wallpaper|CCleaner'; foreach($hive in 'HKCU:','HKLM:'){ $k=\"$hive\Software\Microsoft\Windows\CurrentVersion\Run\"; if(Test-Path $k){ (Get-Item $k).Property | Where-Object { $_ -match $bad } | ForEach-Object { Write-Host ('   removido da inicializacao: ' + $_); Remove-ItemProperty -Path $k -Name $_ -ErrorAction SilentlyContinue } } }" 2>>"%LOG%"
:: atalhos das pastas Startup -> movidos pro backup (reversivel)
powershell -NoProfile -Command "$bad='Steam|Discord|Spotify|Epic|Riot|GOG|uTorrent|Skype|WhatsApp|Telegram|iTunes|Wallpaper'; $dirs=@(\"$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup\", \"$env:ProgramData\Microsoft\Windows\Start Menu\Programs\StartUp\"); foreach($d in $dirs){ Get-ChildItem $d -Filter *.lnk -ErrorAction SilentlyContinue | Where-Object { $_.Name -match $bad } | ForEach-Object { Write-Host ('   atalho movido p/ backup: ' + $_.Name); Move-Item $_.FullName '%UTIDIR%' -Force } }" 2>>"%LOG%"
:: lista o que SOBROU na inicializacao (pra revisao manual)
echo   --- Sobrou na inicializacao (revisar se precisa): ---
powershell -NoProfile -Command "foreach($hive in 'HKCU:','HKLM:'){ $k=\"$hive\Software\Microsoft\Windows\CurrentVersion\Run\"; if(Test-Path $k){ (Get-Item $k).Property | ForEach-Object { $l='   [' + $hive + '] ' + $_; Write-Host $l; Add-Content -Path '%LOG%' -Value $l } } }"
:: desliga Fast Startup (causa classica de "iniciando mal")
powercfg /hibernate off >nul 2>&1
REG ADD "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Power" /V HiberbootEnabled /T REG_DWORD /D 0 /F >nul 2>&1
echo   Fast Startup desativado (boot limpo de verdade).

echo.
echo [3/9] Limpando TEMP, lixeira, logs e caches (motor da v5)...
:: LIXEIRA
PowerShell.exe -NoProfile -Command Clear-RecycleBin -Confirm:$false >nul 2>&1
:: TEMP de todos os usuarios
for /d %%F in (C:\Users\*) do del "%%F\AppData\Local\Temp\*" /s /q >nul 2>&1
for /d %%F in (C:\Users\*) do robocopy "%%F\AppData\Local\Temp" "%%F\AppData\Local\Temp" /s /move /NFL /NDL /NJH /NJS /nc /ns /np >nul 2>&1
:: WINDOWS TEMP
del c:\Windows\Temp\* /s /q >nul 2>&1
robocopy c:\Windows\Temp c:\Windows\Temp /s /move /NFL /NDL /NJH /NJS /nc /ns /np >nul 2>&1
:: LOGS DO WINDOWS
del c:\windows\logs\cbs\*.log >nul 2>&1
del C:\Windows\Logs\MoSetup\*.log >nul 2>&1
del C:\Windows\Panther\*.log /s /q >nul 2>&1
del C:\Windows\inf\*.log /s /q >nul 2>&1
del C:\Windows\logs\*.log /s /q >nul 2>&1
del C:\Windows\Microsoft.NET\*.log /s /q >nul 2>&1
:: CACHES DE NAVEGADOR (Edge/Chrome/Firefox/Brave/Vivaldi - ja mortos no passo 1)
for /d %%F in (C:\Users\*) do (
  del "%%F\AppData\Local\Microsoft\Edge\User Data\Default\Cache\Cache_Data\*" /s /q >nul 2>&1
  del "%%F\AppData\Local\Microsoft\Edge\User Data\Default\Code Cache\js\*" /s /q >nul 2>&1
  del "%%F\AppData\Local\Google\Chrome\User Data\Default\Cache\Cache_Data\*" /s /q >nul 2>&1
  del "%%F\AppData\Local\Google\Chrome\User Data\Default\Code Cache\js\*" /s /q >nul 2>&1
  del "%%F\AppData\Local\Mozilla\Firefox\Profiles\*.default*\cache2\*" /s /q >nul 2>&1
  del "%%F\AppData\Local\BraveSoftware\Brave-Browser\User Data\Default\Cache\Cache_Data\*" /s /q >nul 2>&1
  del "%%F\AppData\Local\Vivaldi\User Data\Default\Cache\Cache_Data\*" /s /q >nul 2>&1
  del "%%F\AppData\Local\Microsoft\Windows\INetCache\IE\*" /s /q >nul 2>&1
  del "%%F\AppData\Local\Microsoft\Windows\Explorer\ThumbCacheToDelete\*.tmp" /s /q >nul 2>&1
  del "%%F\AppData\Roaming\Adobe\Common\Media Cache Files\*.*" /s /q >nul 2>&1
)

echo.
echo [4/9] Limpando cache do WINDOWS UPDATE (classico de update travado)...
net stop wuauserv >nul 2>&1
net stop bits >nul 2>&1
del /s /q C:\Windows\SoftwareDistribution\Download\* >nul 2>&1
net start bits >nul 2>&1
net start wuauserv >nul 2>&1
powershell -NoProfile -Command "Delete-DeliveryOptimizationCache -Force -ErrorAction SilentlyContinue" >nul 2>&1

echo.
echo [5/9] Rede: flush DNS + reset Winsock (conf errada de rede)...
ipconfig /flushdns >nul 2>&1
netsh winsock reset >nul 2>&1
echo   (winsock reset completa no proximo reboot)

echo.
echo [6/9] BATERIA DISM COMPLETA (a parte demorada - pode "parar" em 62%%, e normal)
echo   --- CheckHealth ---
DISM /Online /Cleanup-Image /CheckHealth
echo   --- ScanHealth ---
DISM /Online /Cleanup-Image /ScanHealth
echo   --- RestoreHealth (baixa componentes sadios do Windows Update) ---
DISM /Online /Cleanup-Image /RestoreHealth
echo   --- AnalyzeComponentStore ---
DISM /Online /Cleanup-Image /AnalyzeComponentStore
echo   --- StartComponentCleanup (enxuga o WinSxS) ---
DISM /Online /Cleanup-Image /StartComponentCleanup

echo.
echo [7/9] SFC /scannow (DEPOIS do DISM, na ordem certa)...
sfc /scannow

echo.
echo [8/9] Disco: chkdsk online + otimizacao (TRIM/defrag)...
chkdsk C: /scan
defrag C: /O

:: ==== ESPAÇO DEPOIS ====
for /f %%B in ('powershell -command "(Get-PSDrive -Name C).Free"') do set "espaco_depois=%%B"
for /f %%R in ('powershell -command "('{0:N0}' -f (([int64]%espaco_antes% - [int64]%espaco_depois%) / 1MB))"') do set "espaco_liberado=%%R"

echo.
echo [9/9] Relatorio final
echo ===================================================== >> "%LOG%"
echo Espaco liberado: %espaco_liberado% MB >> "%LOG%"
cls
echo.
echo            🏥 UTI CONCLUIDA - PACIENTE RESPIRANDO
echo =====================================================
echo  Espaco liberado ............ %espaco_liberado% MB
echo  Apps + inicializacao ....... limpos (backup em UTI-backup no Desktop)
echo  DISM + SFC ................. rodados (veja resultados acima)
echo  WU cache / DNS / Winsock ... resetados
echo  Fast Startup ............... desativado
echo =====================================================
echo  ⚠ REINICIE O PC agora: winsock + DISM + boot limpo
echo    so valem apos o reboot.
echo  Backup da inicializacao: Desktop\UTI-backup
echo    (pra reverter algo: duplo clique no .reg / mover o .lnk de volta)
echo =====================================================
echo.
echo Pressione qualquer tecla para sair...
pause >nul
endlocal
exit
