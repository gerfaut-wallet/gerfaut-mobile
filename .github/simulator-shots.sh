#!/usr/bin/env bash
# Keeps the pictures integration_test/screens_test.dart takes, and takes
# the simulator's own: the test leaves <name>.ready in a `shots` folder
# of the app's Documents and waits; this photographs the simulator as
# <name>-simulator.png and answers with <name>.done. The app's own
# drawings (<name>-*.png) are copied out as they appear. A picture the
# simulator refuses is logged in simctl.log, and the test still goes on.
# Runs until it is stopped.
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
  shots="$data/Documents/shots"
  for picture in "$shots"/*.png; do
    [ -e "$picture" ] && cp -n "$picture" "$out/"
  done
  for ready in "$shots"/*.ready; do
    [ -e "$ready" ] || continue
    name=$(basename "$ready" .ready)
    [ -e "$shots/$name.done" ] && continue
    # A simulator with two displays, the iPhone Duo, wants one named:
    # each display it lists is photographed, as <name>-simulator-<n>.png.
    if ! answer=$(xcrun simctl io "$udid" screenshot "$out/$name-simulator.png" 2>&1); then
      displays=$(grep -o -- '--display=[0-9]*' <<<"$answer" | cut -d= -f2)
      [ -n "$displays" ] || echo "$answer" >> "$out/simctl.log"
      for display in $displays; do
        xcrun simctl io "$udid" screenshot --display="$display" \
          "$out/$name-simulator-$display.png" >> "$out/simctl.log" 2>&1 \
          || echo "no picture of $name on display $display" | tee -a "$out/simctl.log"
      done
    fi
    echo "pictured $name"
    touch "$shots/$name.done"
  done
  sleep 0.5
done
