#!/usr/bin/env bash
# Photographs the screens integration_test/screens_test.dart draws, as
# the simulator shows them: the test leaves <name>.ready in a `shots`
# folder of the app's Documents and waits; this takes the picture and
# answers with <name>.done. Runs until it is stopped.
#
#   .github/simulator-shots.sh <simulator id> <bundle id> <folder>
set -uo pipefail

udid=${1:?usage: simulator-shots.sh <simulator id> <bundle id> <folder>}
bundle=${2:?bundle id}
out=${3:?folder}

while true; do
  # The app's folder exists only once flutter test has installed it,
  # and moves with each install.
  data=$(xcrun simctl get_app_container "$udid" "$bundle" data 2>/dev/null) || { sleep 1; continue; }
  for ready in "$data"/Documents/shots/*.ready; do
    [ -e "$ready" ] || continue
    name=$(basename "$ready" .ready)
    [ -e "$data/Documents/shots/$name.done" ] && continue
    xcrun simctl io "$udid" screenshot "$out/$name.png" >/dev/null
    touch "$data/Documents/shots/$name.done"
    echo "pictured $name"
  done
  sleep 0.5
done
