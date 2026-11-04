#!/usr/bin/env bash
# Checks that the selected Xcode can still use the simulator: boots an iOS simulator matching its SDK,
# runs a command in it, and runs the probe package's tests on it. Writes one line of JSON to result.json.
set -uo pipefail

out=${1:-out}
mkdir -p "$out"

now() { perl -MTime::HiRes=time -e 'printf "%.1f", time'; }
since() { perl -e "printf '%.1f', $(now) - $1"; }

xcode=$(xcodebuild -version | head -1 | awk '{print $2}')
sdk=$(xcrun --sdk iphonesimulator --show-sdk-version)
coresim=$(defaults read /Library/Developer/PrivateFrameworks/CoreSimulator.framework/Resources/Info.plist CFBundleShortVersionString)

start=$(now); xcrun simctl list -j > "$out/list.json"; list_s=$(since "$start")

# An available iPhone on the iOS runtime matching the SDK version, which xcodebuild requires
udid=$(python3 - "$out/list.json" "$sdk" <<'EOF'
import json, sys
data, sdk = json.load(open(sys.argv[1])), tuple(int(p) for p in sys.argv[2].split("."))
def version(r): return tuple(int(p) for p in r["version"].split("."))
runtimes = [r for r in data["runtimes"] if r["platform"] == "iOS" and r["isAvailable"] and version(r)[:2] == sdk[:2]]
for r in sorted(runtimes, key=version, reverse=True):
    phones = [d for d in data["devices"].get(r["identifier"], []) if d["isAvailable"] and d["name"].startswith("iPhone")]
    if phones:
        print(phones[0]["udid"], r["version"], phones[0]["name"], sep="|")
        break
EOF
)
runtime=$(echo "$udid" | cut -d'|' -f2); device=$(echo "$udid" | cut -d'|' -f3); udid=$(echo "$udid" | cut -d'|' -f1)

boot=false; spawn=false; test=false; boot_s=0; test_s=0
if [ -n "$udid" ]; then
  start=$(now)
  xcrun simctl boot "$udid" > "$out/boot.txt" 2>&1 && xcrun simctl bootstatus "$udid" -b >> "$out/boot.txt" 2>&1 && boot=true
  boot_s=$(since "$start")
  xcrun simctl spawn "$udid" launchctl print system > "$out/spawn.txt" 2>&1 && spawn=true
  start=$(now)
  ( cd probe-package && xcodebuild test -scheme Probe -destination "id=$udid" -derivedDataPath "$RUNNER_TEMP/dd" ) > "$out/test.txt" 2>&1 && test=true
  test_s=$(since "$start")
  grep -E 'Executed [0-9]+ tests?|\*\* TEST (SUCCEEDED|FAILED) \*\*' "$out/test.txt" | tail -2
  xcrun simctl shutdown "$udid" > /dev/null 2>&1
fi

printf '{"image": "%s %s", "macos": "%s", "coresimulator": "%s", "xcode": "%s", "sdk": "%s", "runtime": "%s", "device": "%s", "list_s": %s, "boot": %s, "boot_s": %s, "spawn": %s, "test": %s, "test_s": %s}\n' \
  "$ImageOS" "$ImageVersion" "$(sw_vers -productVersion)" "$coresim" "$xcode" "$sdk" "$runtime" "$device" "$list_s" "$boot" "$boot_s" "$spawn" "$test" "$test_s" | tee result.json
$boot && $spawn && $test
