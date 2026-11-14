# check-project-media.ps1 — проверка: зеркалирование без подтверждения (PROJECT_MEDIA).
#
# Использование:
#   .\check-project-media.ps1                    # первое device из adb devices, оба клиента
#   .\check-project-media.ps1 -Serial 192.168.1.109:35909
#   .\check-project-media.ps1 -Pkg net.easyconn.carman        # только один клиент
#   .\check-project-media.ps1 -AdbPath C:\adb\adb.exe         # свой adb
#
# Проверяет appop PROJECT_MEDIA у установленных клиентов:
#   Yilian    net.easyconn.carman
#   CarBitLink net.easyconn.carman.wws
#   allow  → системный диалог «Показать экран приложению…?» не появляется,
#            зеркалирование включается без подтверждения;
#   иначе  → диалог будет появляться при каждом включении зеркала
#            (лечится: adb shell appops set --user 0 <pkg> PROJECT_MEDIA allow,
#             либо install.ps1 ставит это автоматически).
#
# Итог: PASS/FAIL, exit code = число проваленных проверок.
param(
    [string]$Serial = '',
    [string]$AdbPath = '',
    [string]$Pkg = 'both'
)
$ErrorActionPreference = 'Continue'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$Adb = $AdbPath
if (-not $Adb -or -not (Test-Path $Adb)) {
    $sib = Join-Path (Split-Path -Parent $Root) 'platform-tools\adb.exe'
    if (Test-Path $sib) { $Adb = $sib } else { $Adb = 'adb' }
}

$FAILS = 0
$FOUND = 0
function Ok($m)  { Write-Host "  [OK] $m" -ForegroundColor Green }
function Bad($m) { Write-Host "  [FAIL] $m" -ForegroundColor Red; $script:FAILS++ }
function Skip($m){ Write-Host "  [SKIP] $m" -ForegroundColor DarkGray }

& $Adb start-server 2>&1 | Out-Null

function Get-ReadySerials {
    @(& $Adb devices | Select-Object -Skip 1 | Where-Object { $_ -match '\sdevice\s*$' } |
      ForEach-Object { ($_ -split '\t')[0].Trim() })
}

if (-not $Serial) { $Serial = (Get-ReadySerials)[0] }
if (-not $Serial) { Write-Host 'ОШИБКА: устройство не найдено'; exit 1 }
Write-Host "Устройство: $Serial"

function Adb { & $Adb -s $Serial @args }

# --- клиенты к проверке -------------------------------------------------------
$targets = @()
if ($Pkg -eq 'both') {
    $targets = @('net.easyconn.carman', 'net.easyconn.carman.wws')
} else {
    $targets = @($Pkg)
}

foreach ($p in $targets) {
    $installed = ((Adb shell pm list packages 2>$null | Out-String) -match [regex]::Escape($p))
    if (-not $installed) { Skip "$p не установлен — пропуск"; continue }
    $script:FOUND++
    $v = ((Adb shell "appops get --user 0 $p PROJECT_MEDIA" | Out-String).Trim())
    if ($v -match 'allow') {
        Ok "$p`: PROJECT_MEDIA allow (зеркало без подтверждения)"
    } else {
        Bad "$p`: PROJECT_MEDIA = $v — подтверждение зеркала будет запрашиваться"
        Write-Host '       лечение: adb shell appops set --user 0 <pkg> PROJECT_MEDIA allow'
    }
}

Write-Host ''
if ($FAILS -eq 0 -and $FOUND -ge 1) {
    Write-Host '=== ИТОГ: PASS'
} else {
    Write-Host "=== ИТОГ: FAIL (провалено проверок: $FAILS)"
}
exit $FAILS
