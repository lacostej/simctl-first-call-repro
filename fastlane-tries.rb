# Runs `xcodebuild -showBuildSettings` the way fastlane_core's Project#build_settings does for
# gym/spec/platform_detection_spec.rb's visionOS example (fastlane#30410): optionally resolve packages
# first, then FastlaneCore::Project.run_command's tries of 3, 6, 12 and 24 s.
# Usage: ruby fastlane-tries.rb <project> <skip|resolve>. Writes one line of JSON to result.json.
require 'json'
require 'timeout'

project, mode = ARGV
def now
  Process.clock_gettime(Process::CLOCK_MONOTONIC)
end

def xcodebuilds
  `pgrep -x xcodebuild`.split.size
end

r = { image: "#{ENV['ImageOS']} #{ENV['ImageVersion']}", xcode: `xcodebuild -version`.lines.first.strip, ruby: RUBY_VERSION, mode: mode }

if mode == "resolve"
  start = now
  `xcodebuild -resolvePackageDependencies -project #{project} 2>&1`
  r[:resolve_s] = (now - start).round(1)
  r[:resolve_exit] = $?.exitstatus
end

# Same as run_command, with timeout 3 and retries 3
command = "xcodebuild -showBuildSettings -project #{project} 2>&1"
result = nil
tries = []
try_timeout = 3
start_all = now
4.times do
  start = now
  begin
    Timeout.timeout(try_timeout) { result = `#{command}`.to_s }
    tries << { timeout: try_timeout, s: (now - start).round(1), ok: true, xcodebuilds_after: xcodebuilds }
    break
  rescue Timeout::Error
    tries << { timeout: try_timeout, s: (now - start).round(1), ok: false, xcodebuilds_after: xcodebuilds }
    try_timeout *= 2
  end
end
r[:show_s] = (now - start_all).round(1)
r[:succeeded] = tries.last[:ok]
r[:tries] = tries
r[:supported_platforms] = result.to_s[/ SUPPORTED_PLATFORMS = (.*)/, 1]

# How long the abandoned xcodebuilds keep running
start = now
sleep 1 while xcodebuilds > 0 && now - start < 180
r[:orphans_done_after_s] = (now - start).round(1)
r[:orphans_left] = xcodebuilds

line = JSON.generate(r)
puts line
File.write("result.json", line + "\n")
