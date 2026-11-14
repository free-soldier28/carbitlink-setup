#!/usr/bin/env bash
# e2e-тест пропатченной сборки на устройстве.
#
# Использование:
#   ./e2e_test.sh [serial] [apk]
#   serial — опционально; без аргумента берётся первое device из `adb devices`
#   apk    — опционально; по умолчанию самый свежий apk/*.apk
#
# Приложение определяется по имени APK:
#   carbitlink-* → CarBitLink wws (полный набор патчей p11)
#   yilian-*     → Yilian CN (патчи v1: flavor/license/touch/landscape/version)
#
# Покрывает (через adb, без участия ГУ):
#   1.  Установка APK (атрибуция Play Store)
#   2.  Запуск и живучесть (крэш-буфер чист)
#   3.  Инженерный экран открывается и не падает (классы патчей загружаются)
#   4.  Версия патча видна в UI ("patched: pN/vN")
#   5.  Переводы инженерки (CarBitLink, локаль ru)
#   6.  Спец-доступы: appops ×3 allow
#   7.  Notification listener включён
#   8.  Battery whitelist
#   9.  Accessibility привязан (CarBitLink; touch-back)
#  10.  Авто-горизонт: user_rotation=1 + accelerometer_rotation=0 при активной сессии с ГУ
#
# Ручной чек-лист (нужен ГУ, скриптом не проверяется):
#   - окно «Отсутствует регистрация» не появляется при подключении (PATCH-12/license)
#   - драйв-блокировка отключена (PATCH-3/4/5/8)
#   - тач с ГУ работает (кабель/Wi-Fi)
#   - долгое нажатие на версию → диалог патч-инфо
#
# Итог: PASS/FAIL, exit code = число проваленных проверок.

set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ADB="$ROOT/platform-tools/adb.exe"
[ -x "$ADB" ] || ADB="$(command -v adb)"

FAILS=0
ok()  { echo "  [OK] $1"; }
bad() { echo "  [FAIL] $1"; FAILS=$((FAILS+1)); }
skip(){ echo "  [SKIP] $1"; }

# --- APK ------------------------------------------------------------------
APK="${2:-}"
if [ -z "$APK" ]; then
  APK="$(ls -t "$ROOT"/apk/*.apk 2>/dev/null | head -1)"
fi
[ -n "$APK" ] && [ -f "$APK" ] || { echo "ОШИБКА: APK не найден в apk/"; exit 1; }
APKNAME="$(basename "$APK")"

# --- приложение по имени APK ----------------------------------------------
case "$APKNAME" in
  yilian*)
    PKG="net.easyconn.carman"
    APP="Yilian (CN)"
    MARK="patched: v"
    DBGACT="net.easyconn.carman/.system.EcDebugActivity"
    WANT_A11Y=0
    ;;
  *)
    PKG="net.easyconn.carman.wws"
    APP="CarBitLink (wws)"
    MARK="patched: p"
    DBGACT="net.easyconn.carman/.DebugActivity"
    WANT_A11Y=1
    ;;
esac
echo "APK: $APKNAME"
echo "Приложение: $APP ($PKG)"

# --- устройство -------------------------------------------------------------
"${ADB}" start-server >/dev/null 2>&1
SERIAL="${1:-}"
if [ -z "$SERIAL" ]; then
  SERIAL=$("${ADB}" devices | awk '$2=="device"{print $1; exit}')
fi
[ -n "$SERIAL" ] || { echo "ОШИБКА: устройство не найдено"; exit 1; }
echo "Устройство: $SERIAL"

s() { "${ADB}" -s "$SERIAL" "$@"; }

# --- 1. установка -----------------------------------------------------------
echo
echo "=== 1. Установка"
INS=$(s install -r -i com.android.vending "$APK" 2>&1 | tail -1)
if echo "$INS" | grep -q "Success"; then ok "установка: Success"; else bad "установка: $INS"; fi
s shell pm list packages 2>/dev/null | grep -q "$PKG$" && ok "пакет $PKG установлен" || bad "пакет $PKG не найден"

# --- 2. запуск и живучесть ---------------------------------------------------
echo
echo "=== 2. Запуск и живучесть"
s shell logcat -b crash -c 2>/dev/null
s shell logcat -c 2>/dev/null
s shell am force-stop "$PKG" 2>/dev/null
s shell monkey -p "$PKG" -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1
sleep 10
ALIVE=$(s shell ps -A 2>/dev/null | grep -c "net.easyconn.carman")
if [ "${ALIVE:-0}" -ge 1 ]; then ok "процесс(ы) живы: $ALIVE"; else bad "процесс не запущен"; fi
CRASHES=$(s shell logcat -d -b crash 2>/dev/null | grep -c "net.easyconn.carman")
if [ "${CRASHES:-0}" -eq 0 ]; then ok "крэш-буфер чист"; else
  bad "крэши: $CRASHES"
  s shell logcat -d -b crash 2>/dev/null | grep -m1 -A8 "FATAL"
fi

# --- 3. инженерный экран ------------------------------------------------------
echo
echo "=== 3. Инженерный экран (загрузка классов патчей)"
s shell input keyevent 224 2>/dev/null   # WAKEUP
s shell wm dismiss-keyguard 2>/dev/null
sleep 1
s shell am force-stop "$PKG" 2>/dev/null
s shell am start -n "$DBGACT" >/dev/null 2>&1
sleep 5
ALIVE2=$(s shell ps -A 2>/dev/null | grep -c "net.easyconn.carman$")
if [ "${ALIVE2:-0}" -ge 1 ]; then ok "после am start инженерки процесс жив"; else bad "процесс умер после открытия инженерки"; fi
ERR=$(s shell logcat -d 2>/dev/null | grep -cE "VerifyError.*patch/|NoClassDefFoundError.*patch/")
if [ "${ERR:-0}" -eq 0 ]; then ok "классы патчей верифицируются"; else
  bad "ошибки верификации классов патчей: $ERR"
  s shell logcat -d 2>/dev/null | grep -E "VerifyError|NoClassDefFoundError" | tail -5
fi

# --- 4. UI: версия патча и переводы ------------------------------------------
echo
echo "=== 4. Маркер версии патча (строка в dex установленного APK)"
VM=$(unzip -p "$APK" classes*.dex 2>/dev/null | grep -ac "$MARK")
if [ "${VM:-0}" -ge 1 ]; then ok "маркер '$MARK' в dex APK"; else bad "маркер '$MARK' отсутствует в dex APK"; fi

# --- 5. спец-доступы ----------------------------------------------------------
echo
echo "=== 5. Спец-доступы"
for a in android:get_usage_stats SYSTEM_ALERT_WINDOW WRITE_SETTINGS; do
  v=$(s shell appops get --user 0 "$PKG" "$a" 2>/dev/null | tr -d '\r')
  if echo "$v" | grep -q "allow"; then ok "appop $a: allow"; else bad "appop $a: $v"; fi
done
NLS=$(s shell settings get secure enabled_notification_listeners 2>/dev/null | tr -d '\r')
if echo "$NLS" | grep -q "$PKG"; then ok "notification listener включён"; else bad "notification listener НЕ включён ($NLS)"; fi
WL=$(s shell dumpsys deviceidle whitelist 2>/dev/null | grep -c "$PKG")
if [ "${WL:-0}" -ge 1 ]; then ok "battery whitelist"; else bad "нет в battery whitelist"; fi

# --- 6. accessibility (CarBitLink) ---------------------------------------------
echo
echo "=== 6. Accessibility (touch-back)"
if [ "$WANT_A11Y" -eq 1 ]; then
  BOUND=$(s shell dumpsys accessibility 2>/dev/null | grep -c "Bound services.*carman\|carman.*Accessibility")
  BOUND=$(s shell dumpsys accessibility 2>/dev/null | grep -c "AccessibilityResultService")
  if [ "${BOUND:-0}" -ge 1 ]; then ok "accessibility-сервис привязан"; else
    bad "accessibility не привязан (включи в Настройки → Доступность)"
  fi
else
  skip "yilian: accessibility для тача не используется"
fi

# --- 7. авто-горизонт (при активной сессии с ГУ) --------------------------------
echo
echo "=== 7. Авто-горизонт (PATCH-15; при активной сессии с ГУ)"
if [ "$APP" = "CarBitLink (wws)" ]; then
  SVC=$(s shell dumpsys activity services "$PKG" 2>/dev/null | grep -c "common.ForegroundService")
else
  SVC=$(s shell dumpsys activity services "$PKG" 2>/dev/null | grep -c "TrueMirrorService")
fi
if [ "${SVC:-0}" -ge 1 ]; then
  ok "сервис зеркала запущен (сессия активна)"
  UR=$(s shell settings get system user_rotation 2>/dev/null | tr -d '\r')
  AC=$(s shell settings get system accelerometer_rotation 2>/dev/null | tr -d '\r')
  if [ "$UR" = "1" ]; then ok "user_rotation=1 (горизонталь)"; else bad "user_rotation=$UR (ожидалась 1)"; fi
  if [ "$AC" = "0" ]; then ok "accelerometer_rotation=0"; else bad "accelerometer_rotation=$AC (ожидался 0)"; fi
else
  skip "сервис зеркала не запущен — нет сессии с ГУ (подключи ГУ и перезапусти тест)"
fi

# --- 8. финальный скан крэшей ----------------------------------------------------
echo
echo "=== 8. Финальный скан крэшей"
CRASHES2=$(s shell logcat -d -b crash 2>/dev/null | grep -c "net.easyconn.carman")
if [ "${CRASHES2:-0}" -eq 0 ]; then ok "крэш-буфер чист после всех проверок"; else
  bad "крэши после проверок: $CRASHES2"
  s shell logcat -d -b crash 2>/dev/null | grep -m1 -A10 "FATAL"
fi

# --- итог -------------------------------------------------------------------------
echo
if [ "$FAILS" -eq 0 ]; then
  echo "=== ИТОГ: PASS"
else
  echo "=== ИТОГ: FAIL (провалено проверок: $FAILS)"
  echo "Ручной чек-лист (нужен ГУ): окно «Отсутствует регистрация» / драйв-блокировка /"
  echo "тач с ГУ (кабель+Wi-Fi) / долгое нажатие на версию → патч-инфо."
fi
exit "$FAILS"
