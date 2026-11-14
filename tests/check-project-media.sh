#!/usr/bin/env bash
# Проверка: зеркалирование без подтверждения (PROJECT_MEDIA pre-grant).
#
# Использование:
#   ./check-project-media.sh [serial]
#   serial — опционально; без аргумента берётся первое device из `adb devices`
#
# Проверяет appop PROJECT_MEDIA у установленных клиентов (Yilian `net.easyconn.carman`
# и/или CarBitLink `net.easyconn.carman.wws`):
#   allow  → системный диалог «Показать экран приложению…?» не появляется,
#            зеркалирование включается без подтверждения;
#   иначе  → диалог будет появляться при каждом включении зеркала
#            (лечится: adb shell appops set --user 0 <pkg> PROJECT_MEDIA allow,
#             либо install.ps1 ставит это автоматически).
#
# Итог: PASS/FAIL, exit code = число проваленных проверок.

set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ADB="$ROOT/platform-tools/adb.exe"
[ -x "$ADB" ] || ADB="$(command -v adb)"

FAILS=0
ok()  { echo "  [OK] $1"; }
bad() { echo "  [FAIL] $1"; FAILS=$((FAILS+1)); }

"${ADB}" start-server >/dev/null 2>&1
SERIAL="${1:-}"
if [ -z "$SERIAL" ]; then
  SERIAL=$("${ADB}" devices | awk '$2=="device"{print $1; exit}')
fi
[ -n "$SERIAL" ] || { echo "ОШИБКА: устройство не найдено"; exit 1; }
echo "Устройство: $SERIAL"

s() { "${ADB}" -s "$SERIAL" "$@"; }

FOUND=0
for PKG in net.easyconn.carman net.easyconn.carman.wws; do
  INSTALLED=$(s shell pm list packages 2>/dev/null | grep -c "$PKG$")
  if [ "${INSTALLED:-0}" -eq 0 ]; then
    echo "  [--] $PKG не установлен — пропуск"
    continue
  fi
  FOUND=$((FOUND+1))
  V=$(s shell appops get --user 0 "$PKG" PROJECT_MEDIA 2>/dev/null | tr -d '\r')
  if echo "$V" | grep -q "allow"; then
    ok "$PKG: PROJECT_MEDIA allow (зеркало без подтверждения)"
  else
    bad "$PKG: PROJECT_MEDIA = $V — подтверждение зеркала будет запрашиваться"
    echo "       лечение: adb shell appops set --user 0 $PKG PROJECT_MEDIA allow"
  fi
done

if [ "$FOUND" -eq 0 ]; then
  echo "  ни один клиент EasyConnection не установлен"
fi

echo
if [ "$FAILS" -eq 0 ] && [ "$FOUND" -ge 1 ]; then
  echo "=== ИТОГ: PASS"
else
  echo "=== ИТОГ: FAIL (провалено проверок: $FAILS)"
fi
exit "$FAILS"
