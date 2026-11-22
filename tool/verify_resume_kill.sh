#!/usr/bin/env bash
# "Kill the app, reopen, resume" on a real device. Usage: tool/verify_resume_kill.sh <android|linux>
# Uses a separate test database; never touches the user's history.
# Android: the test build replaces the installed app (data kept, --no-uninstall).
set -uo pipefail
cd "$(dirname "$0")/.." && . tool/env.sh
target="${1:?android or linux}"
ADB="$HOME/Android/Sdk/platform-tools/adb"
mkdir -p build; log=build/verify_resume_kill_${target}.log; : > "$log"
if [ "$target" = android ]; then
  device=$("$ADB" devices | awk 'NR>1 && $2=="device"{print $1; exit}')
  kill_app() { "$ADB" shell am force-stop dev.dhakaflix.player; }
else
  device=linux
  kill_app() { pkill -KILL -f 'build/linux/x64/debug/bundle/dhakaflix_player'; }
fi
run() { flutter test integration_test/resume_kill_test.dart -d "$device" --no-uninstall --dart-define=step="$1" -r expanded 2>&1; }

# Step 1: play, then kill hard ~8 s after the seek.
last=""
while IFS= read -r line; do
  echo "$line" >> "$log"
  case "$line" in
    *"RK KILL_ME"*) ( sleep 8; echo ">>> KILL" >> "$log"; kill_app ) & ;;
    *"RK POS "*) last="${line##*RK POS }" ;;
  esac
done < <(run play)
echo "last position seen before kill: ${last:-none} ms"

# Step 2: fresh process, must resume near the saved position.
run resume | tee -a "$log" | grep -E 'RK (SAVED|RESUMED)|All tests|Some tests|Expected|Actual'
