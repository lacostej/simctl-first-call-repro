#!/usr/bin/env bash
# Times the first and second `xcrun simctl list -j devices` on a fresh runner, and records which
# simulator runtimes simdiskimaged walked meanwhile. Writes one line of JSON to result.json.
set -uo pipefail

out=${1:-out}
mkdir -p "$out"

now() { perl -MTime::HiRes=time -e 'printf "%.1f", time'; }
coresim() { defaults read /Library/Developer/PrivateFrameworks/CoreSimulator.framework/Resources/Info.plist CFBundleShortVersionString; }

if pgrep -x simdiskimaged > /dev/null; then echo "simdiskimaged is already running" >&2; fi

# Trace simdiskimaged's file system calls from the moment the first call starts it
( until pid=$(pgrep -x simdiskimaged); do sleep 0.2; done
  sudo fs_usage -w -f filesys "$pid" > "$out/fs_usage.txt" 2>&1 ) &
tracer=$!

start=$(now); xcrun simctl list -j devices > "$out/first.json"; first=$(perl -e "printf '%.1f', $(now) - $start")
start=$(now); xcrun simctl list -j devices > "$out/second.json"; second=$(perl -e "printf '%.1f', $(now) - $start")

# Let a walk that outlasts the calls show up in the trace
sleep 5
sudo pkill -INT -x fs_usage; kill $tracer 2>/dev/null; sleep 1

# fs_usage cuts long paths from the left: count each line towards the last runtime named before it
walked=$(perl -ne '
  $cur = $1 if m{/((?:iOS|tvOS|watchOS|xrOS|visionOS) [\d.]+)\.simruntime\b};
  $n{$cur}++ if defined $cur;
  END { print join(",", map { "\"$_\"" } grep { $n{$_} > 50000 } sort keys %n) }' "$out/fs_usage.txt")
devices=$(python3 -c 'import json,sys; print(sum(len(d) for d in json.load(open(sys.argv[1]))["devices"].values()))' "$out/first.json")

printf '{"image": "%s %s", "macos": "%s", "coresimulator": "%s", "first_call_s": %s, "second_call_s": %s, "devices": %s, "walked": [%s]}\n' \
  "$ImageOS" "$ImageVersion" "$(sw_vers -productVersion)" "$(coresim)" "$first" "$second" "$devices" "$walked" | tee result.json
