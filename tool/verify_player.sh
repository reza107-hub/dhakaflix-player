#!/usr/bin/env bash
# Runs the Phase 2 on-device player checks and simulates a Wi-Fi drop when
# the test prints DROP_NOW.  Usage: tool/verify_player.sh <android|linux> [test name filter]
set -uo pipefail
cd "$(dirname "$0")/.." && . tool/env.sh
target="${1:?android or linux}"
ADB="$HOME/Android/Sdk/platform-tools/adb"
log="build/verify_${target}.log"; mkdir -p build; : > "$log"

if [ "$target" = android ]; then
  device=$("$ADB" devices | awk 'NR>1 && $2=="device"{print $1; exit}')
  [ -n "$device" ] || { echo "No Android device"; exit 1; }
  net_off() { "$ADB" shell svc wifi disable; }
  net_on()  { "$ADB" shell svc wifi enable; }
else
  device=linux
  net_off() { nmcli radio wifi off; }
  net_on()  { nmcli radio wifi on; }
fi
trap net_on EXIT

flutter test integration_test/player_test.dart -d "$device" --no-uninstall ${2:+--plain-name "$2"} --reporter expanded 2>&1 | tee "$log" |
while IFS= read -r line; do
  case "$line" in
    *PH2*|*"+"*:*|*rror*|*FAIL*|*Expected*|*Actual*|*Reason*) echo "$line" ;;
  esac
  if [[ "$line" == *DROP_NOW* ]]; then
    ( echo ">>> network OFF"; net_off; sleep 90; echo ">>> network ON"; net_on ) &
  fi
done
