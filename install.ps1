# install.ps1 — установка и настройка пропатченного CarBitLink по adb
# Требования: Windows 10/11, телефон с включённой отладкой по USB/Wi-Fi.
# Скрипт идемпотентный — можно запускать повторно.
$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}
$Host.UI.RawUI.WindowTitle = 'CarBitLink Setup'

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$Adb  = Join-Path $Root 'platform-tools\adb.exe'
$Pkg  = 'net.easyconn.carman.wws'
$A11y = "$Pkg/net.easyconn.carman.accessibility.AccessibilityResultService"
$Nls  = "$Pkg/net.easyconn.carman.NotificationService"

function Fail($m) { Write-Host "ОШИБКА: $m" -ForegroundColor Red; Read-Host 'Enter — выход'; exit 1 }
function Step($m)  { Write-Host "`n=== $m" -ForegroundColor Cyan }
function Ok($m)    { Write-Host "  [OK] $m" -ForegroundColor Green }
function Warn($m)  { Write-Host "  [!!] $m" -ForegroundColor Yellow }

if (-not (Test-Path $Adb)) { Fail "не найден adb.exe: $Adb" }
$Apk = Get-ChildItem -Path (Join-Path $Root 'apk') -Filter 'carbitlink-*.apk' -ErrorAction SilentlyContinue |
       Sort-Object LastWriteTime -Descending | Select-Object -First 1
if (-not $Apk) { Fail "нет APK в папке apk\ — положите carbitlink-*-patched-*.apk туда" }

& $Adb start-server | Out-Null

function Get-ReadySerials {
    @(& $Adb devices | Select-Object -Skip 1 | Where-Object { $_ -match '\sdevice\s*$' } |
      ForEach-Object { ($_ -split '\t')[0].Trim() })
}

# --- выбор устройства -------------------------------------------------
Step 'Поиск телефона'
$serials = Get-ReadySerials
if (-not $serials) {
    Write-Host "  Телефон не найден. Подключите по USB (отладка по USB должна быть включена)"
    Write-Host "  и подтвердите запрос 'Разрешить отладку по USB' на телефоне."
    $choice = Read-Host '  Ждать USB [1] или подключиться по Wi-Fi [2]? (1/2)'
    if ($choice -eq '2') {
        $addr = Read-Host '  IP:порт телефона (напр. 192.168.1.109:40413)'
        for ($try = 1; $try -le 3; $try++) {
            & $Adb connect $addr 2>&1 | Write-Host
            if (Get-ReadySerials) { break }
            if ($try -lt 3) {
                Write-Host "  Попытка $try не удалась (первое рукопожатие часто таймаутится) — повторяю..." -ForegroundColor Yellow
                Start-Sleep -Seconds 3
            }
        }
    }
    $deadline = (Get-Date).AddSeconds(90)
    while ((Get-Date) -lt $deadline) {
        $serials = Get-ReadySerials
        if ($serials) { break }
        $st = & $Adb devices | Select-Object -Skip 1 | Where-Object { $_ -match 'unauthorized' }
        if ($st) { Write-Host "  Телефон найден, но не подтверждён — нажмите 'Разрешить' на телефоне" -ForegroundColor Yellow }
        Start-Sleep -Seconds 2
    }
    if (-not $serials) { Fail "телефон так и не подключился" }
}
$serial = $serials[0]
if ($serials.Count -gt 1) {
    Write-Host "  Найдено несколько устройств:"
    for ($i=0; $i -lt $serials.Count; $i++) { Write-Host "   [$($i+1)] $($serials[$i])" }
    $n = 0
    $raw = Read-Host '  Номер устройства [1]'
    if ($raw -match '^\d+$') { $n = [int]$raw - 1 }
    if ($n -lt 0 -or $n -ge $serials.Count) { $n = 0 }
    $serial = $serials[$n]
}
Ok "телефон: $serial"
$serial | Out-File -Encoding ascii (Join-Path $Root 'last-device.txt')

function Adb { & $Adb -s $serial @args }

# --- информация о телефоне --------------------------------------------
$model = (Adb shell getprop ro.product.model).Trim()
$ver   = (Adb shell getprop ro.build.version.release).Trim()
Write-Host "  $model, Android $ver"

# --- установка APK ----------------------------------------------------
Step "Установка $($Apk.Name)"
$out = (Adb install -r -i com.android.vending "$($Apk.FullName)" 2>&1 | Out-String)
if ($out -match 'Success') {
    Ok 'установлено (атрибуция установщика: Play Store — защита XOS/Android 13+ не сработает)'
} elseif ($out -match 'UPDATE_INCOMPATIBLE|INSTALL_FAILED') {
    Warn $out.Trim()
    $yn = Read-Host '  Установлено другое (официальное) приложение. Удалить его и продолжить? Данные приложения будут потеряны! (y/N)'
    if ($yn -match '^(y|д)') {
        Adb uninstall $Pkg | Out-Null
        $out = (Adb install -r -i com.android.vending "$($Apk.FullName)" 2>&1 | Out-String)
        if ($out -match 'Success') { Ok 'установлено' } else { Fail "установка не удалась: $($out.Trim())" }
    } else { Fail 'установка отменена' }
} else { Fail "установка не удалась: $($out.Trim())" }

# --- runtime-разрешения ------------------------------------------------
Step 'Разрешения (микрофон, контакты, гео, уведомления...)'
$perms = @(
 'android.permission.RECORD_AUDIO',
 'android.permission.READ_MEDIA_AUDIO',
 'android.permission.READ_EXTERNAL_STORAGE',
 'android.permission.WRITE_EXTERNAL_STORAGE',
 'android.permission.ACCESS_COARSE_LOCATION',
 'android.permission.ACCESS_FINE_LOCATION',
 'android.permission.ACCESS_BACKGROUND_LOCATION',
 'android.permission.BLUETOOTH_CONNECT',
 'android.permission.BLUETOOTH_SCAN',
 'android.permission.NEARBY_WIFI_DEVICES',
 'android.permission.POST_NOTIFICATIONS',
 'android.permission.READ_CONTACTS',
 'android.permission.READ_PHONE_STATE',
 'android.permission.CALL_PHONE'
)
$granted = 0
foreach ($p in $perms) {
    $r = (Adb shell pm grant --user 0 $Pkg $p 2>&1 | Out-String)
    if ($LASTEXITCODE -eq 0) { $granted++ }
}
Ok "выдано разрешений: $granted из $($perms.Count) (остальные не существуют на этой Android-версии — нормально)"

# --- appops -------------------------------------------------------------
Step 'Спец-доступы (appops)'
Adb shell appops set --user 0 $Pkg android:get_usage_stats allow
Adb shell appops set --user 0 $Pkg SYSTEM_ALERT_WINDOW allow
Adb shell appops set --user 0 $Pkg WRITE_SETTINGS allow
Ok 'использование приложений / поверх окон / изменение настроек — allow'

# --- чтение уведомлений --------------------------------------------------
Step 'Чтение уведомлений (уведомления телефона на голове)'
Adb shell cmd notification allow_listener $Nls
Ok 'NotificationService добавлен в слушатели'

# --- accessibility -------------------------------------------------------
Step 'Touch-back: включение CarBitLink Accessibility'
$cur = ((Adb shell settings get secure enabled_accessibility_services) | Out-String).Trim()
if ($cur -eq 'null' -or [string]::IsNullOrWhiteSpace($cur)) { $new = $A11y }
elseif ($cur.Contains($A11y)) { $new = $cur }
else { $new = "$cur`:$A11y" }
Adb shell settings put secure enabled_accessibility_services $new
Adb shell settings put secure accessibility_enabled 1
Ok "enabled_accessibility_services = $new"

# --- батарея -------------------------------------------------------------
Step 'Отключение оптимизации батареи для приложения'
Adb shell dumpsys deviceidle whitelist +"$Pkg" | Out-Null
Ok 'добавлено в whitelist'

# --- запуск и проверка ----------------------------------------------------
Step 'Запуск приложения'
Adb shell "monkey -p $Pkg -c android.intent.category.LAUNCHER 1" 2>&1 | Out-Null
Start-Sleep -Seconds 5

Step 'Проверка'
$bound = (Adb shell "dumpsys accessibility" | Out-String) -match 'CarBitLink Accessibility'
if ($bound) { Ok 'accessibility-сервис привязан (touch-back готов)' }
else { Warn 'accessibility не привязан! Откройте Настройки -> Доступность -> CarBitLink Accessibility и включите вручную' }
$inst = ((Adb shell "pm dump $Pkg" | Select-String -Pattern 'installerPackage' | Select-Object -First 1) | Out-String).Trim()
Write-Host "  $inst"
Write-Host ""
Write-Host '=== Готово. Проверьте на экране About: строка "patched: p9" под версией ===' -ForegroundColor Cyan
Write-Host 'Подключите телефон к голове. Зеркало приложений работает без "Доступа к истории использования".'
Read-Host 'Enter — выход'
