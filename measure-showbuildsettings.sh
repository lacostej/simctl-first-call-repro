#!/usr/bin/env bash
# Times `xcodebuild -showBuildSettings` as the first simulator-related call on a fresh runner, the way
# fastlane runs it, and records whether it starts simdiskimaged, waits on it, and which runtimes it walked.
# Usage: measure-showbuildsettings.sh <project> <scheme> [out]. Writes one line of JSON to result.json.
set -uo pipefail

project=$1
scheme=$2
out=${3:-out}
mkdir -p "$out"

now() { perl -MTime::HiRes=time -e 'printf "%.1f", time'; }
since() { perl -e "printf '%.1f', $(now) - $1"; }
coresim() { defaults read /Library/Developer/PrivateFrameworks/CoreSimulator.framework/Resources/Info.plist CFBundleShortVersionString; }

running_before=false
if pgrep -x simdiskimaged > /dev/null; then running_before=true; fi

t0=$(now)
# Note when simdiskimaged starts, then trace its file system calls
( until pid=$(pgrep -x simdiskimaged); do sleep 0.2; done
  since "$t0" > "$out/simdiskimaged_started_at"
  sudo fs_usage -w -f filesys "$pid" > "$out/fs_usage.txt" 2>&1 ) &
tracer=$!

# Same command as fastlane_core's Project#build_xcodebuild_showbuildsettings_command
xcodebuild -showBuildSettings -scheme "$scheme" -project "$project" > "$out/first.txt" 2>&1 &
xcb=$!
# If it is still running after 10 s, sample it to see where it waits
( sleep 10; if kill -0 "$xcb" 2>/dev/null; then sample "$xcb" 3 -file "$out/sample.txt" > /dev/null 2>&1; fi ) &
sampler=$!
wait "$xcb"; first_status=$?
first=$(since "$t0")
kill "$sampler" 2>/dev/null

start=$(now); xcodebuild -showBuildSettings -scheme "$scheme" -project "$project" > "$out/second.txt" 2>&1; second=$(since "$start")
start=$(now); xcrun simctl list -j devices > /dev/null; simctl_after=$(since "$start")

# Let a walk that outlasts the calls show up in the trace
sleep 5
sudo pkill -INT -x fs_usage; kill $tracer 2>/dev/null; sleep 1

running_after=false
if pgrep -x simdiskimaged > /dev/null; then running_after=true; fi
started_at=$(cat "$out/simdiskimaged_started_at" 2>/dev/null || echo null)
waited_in_kickstart=false
if grep -q "SimDiskImageManager kickstartService" "$out/sample.txt" 2>/dev/null; then waited_in_kickstart=true; fi
sampled=false
if [ -s "$out/sample.txt" ]; then sampled=true; fi
platforms=$(grep -m1 " SUPPORTED_PLATFORMS = " "$out/first.txt" | sed 's/.*= //')

# fs_usage cuts long paths from the left: count each line towards the last runtime named before it
walked=$(perl -ne '
  $cur = $1 if m{/((?:iOS|tvOS|watchOS|xrOS|visionOS) [\d.]+)\.simruntime\b};
  $n{$cur}++ if defined $cur;
  END { print join(",", map { "\"$_\"" } grep { $n{$_} > 50000 } sort keys %n) }' "$out/fs_usage.txt" 2>/dev/null)

printf '{"image": "%s %s", "macos": "%s", "xcode": "%s", "coresimulator": "%s", "project": "%s", "simdiskimaged_running_before": %s, "simdiskimaged_running_after": %s, "simdiskimaged_started_at_s": %s, "first_call_s": %s, "first_exit": %s, "sampled": %s, "waited_in_kickstart": %s, "second_call_s": %s, "simctl_after_s": %s, "supported_platforms": "%s", "walked": [%s]}\n' \
  "$ImageOS" "$ImageVersion" "$(sw_vers -productVersion)" "$(xcodebuild -version | head -1)" "$(coresim)" "$(basename "$project")" \
  "$running_before" "$running_after" "$started_at" "$first" "$first_status" "$sampled" "$waited_in_kickstart" "$second" "$simctl_after" "$platforms" "$walked" | tee result.json
