#!/usr/bin/env bash
# e2e-тест пропатченной сборки CarBitLink на устройстве (без ГУ).
#
# Использование:
#   ./e2e_test.sh [serial] [apk]
#   serial — опционально; без аргумента берётся первое device из `adb devices`
#   apk    — опционально; по умолчанию самый свежий apk/carbitlink-*.apk
#
# Проверяет:
#   1. Установку APK (adb install -r -i com.android.vending)
#   2. Запуск приложения: процесс жив, в крэш-буфере нет записей приложения
#   3. Класс patch/Landscape верифицируется и работает: если ForegroundService
#      запущен (есть сессия с ГУ) — system user_rotation=1 и
#      accelerometer_rotation=0 (эффект PATCH-15 LANDSCAPE_MIRROR)
#
# Итог: PASS/FAIL и счётчик проваленных проверок (exit code = число провалов).

set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ADB="$ROOT/platform-tools/adb.exe"
[ -x "$ADB" ] || ADB="$(command -v adb)"
PKG="net.easyconn.carman.wws"

FAILS=0
ok()  { echo "  [OK] $1"; }
bad() { echo "  [FAIL] $1"; FAILS=$((FAILS+1)); }

# --- APK ------------------------------------------------------------------
APK="${2:-}"
if [ -z "$APK" ]; then
  APK="$(ls -t "$ROOT"/apk/carbitlink-*.apk 2>/dev/null | head -1)"
fi
[ -n "$APK" ] && [ -f "$APK" ] || { echo "ОШИБКА: APK не найден в apk/"; exit 1; }
echo "APK: $APK"

# --- устройство ------------------------------------------------------------
"${ADB}" start-server >/dev/null 2>&1
SERIAL="${1:-}"
if [ -z "$SERIAL" ]; then
  SERIAL=$("${ADB}" devices | awk '$2=="device"{print $1; exit}')
fi
[ -n "$SERIAL" ] || { echo "ОШИБКА: устройство не найдено (adb devices пуст)"; exit 1; }
echo "Устройство: $SERIAL"

s() { "${ADB}" -s "$SERIAL" "$@"; }

# --- 1. установка -----------------------------------------------------------
echo
echo "=== 1. Установка"
INS=$(s install -r -i com.android.vending "$APK" 2>&1 | tail -1)
if echo "$INS" | grep -q "Success"; then ok "установка: Success"; else bad "установка: $INS"; fi

# --- 2. запуск и живучесть ---------------------------------------------------
echo
echo "=== 2. Запуск приложения"
s shell logcat -b crash -c 2>/dev/null
s shell logcat -c 2>/dev/null
s shell am force-stop "$PKG" 2>/dev/null
s shell monkey -p "$PKG" -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1
sleep 8
ALIVE=$(s shell ps -A 2>/dev/null | grep -c "net.easyconn.carman.wws$")
if [ "${ALIVE:-0}" -ge 1 ]; then ok "процесс жив"; else bad "процесс не запущен"; fi
CRASHES=$(s shell logcat -d -b crash 2>/dev/null | grep -c "carman.wws")
if [ "${CRASHES:-0}" -eq 0 ]; then ok "крэш-буфер чист (нет FATAL/VerifyError)"; else
  bad "крэши: $CRASHES"
  s shell logcat -d -b crash 2>/dev/null | grep -A6 "carman.wws" | tail -20
fi

# --- 3. PATCH-15 (нужна активная сессия с ГУ) --------------------------------
echo
echo "=== 3. PATCH-15 (авто-горизонт; проверяется при активной сессии с ГУ)"
SVC=$(s shell dumpsys activity services "$PKG" 2>/dev/null | grep -c "common.ForegroundService")
if [ "${SVC:-0}" -ge 1 ]; then
  ok "ForegroundService запущен (сессия активна)"
  UR=$(s shell settings get system user_rotation 2>/dev/null | tr -d '\r')
  AC=$(s shell settings get system accelerometer_rotation 2>/dev/null | tr -d '\r')
  if [ "$UR" = "1" ]; then ok "user_rotation=1 (горизонталь)"; else bad "user_rotation=$UR (ожидалась 1)"; fi
  if [ "$AC" = "0" ]; then ok "accelerometer_rotation=0"; else bad "accelerometer_rotation=$AC (ожидался 0)"; fi
else
  echo "  [SKIP] ForegroundService не запущен — нет сессии с ГУ (подключи ГУ и перезапусти тест)"
fi

# --- итог ----------------------------------------------------------------------
echo
if [ "$FAILS" -eq 0 ]; then
  echo "=== ИТОГ: PASS"
else
  echo "=== ИТОГ: FAIL (провалено проверок: $FAILS)"
fi
exit "$FAILS"
