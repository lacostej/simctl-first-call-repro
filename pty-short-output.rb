# Does fastlane's FastlanePty.spawn lose the output of very short commands (fastlane#21792)?
# Runs each command many times through the FastlanePty of a fastlane checkout, reading the output
# with IO#each, as CommandExecutor.execute does, and with readpartial, and counts what came back.
# For each run it also records how the read ended (end-of-file or Errno::EIO) and after how long.
# Usage: ruby pty-short-output.rb <path to fastlane_pty.rb> <runs per variant> <parallel processes>
# Writes one line of JSON to result.json.
require 'json'
require 'tmpdir'
require_relative File.expand_path(ARGV[0])

runs = Integer(ARGV[1])
processes = Integer(ARGV[2])

# Scripts whose shell is the spawned child: it prints, and pauses before or after printing
SCRIPTS = Dir.mktmpdir("pty-short-output")
def script(name, body)
  path = File.join(SCRIPTS, name)
  File.write(path, "#!/bin/sh\n#{body}\n")
  File.chmod(0o755, path)
  path
end

# max_runs keeps the variants that pause within a few minutes
VARIANTS = [
  { name: "echo foo", command: "echo foo" },
  { name: "echo foo, flush workaround", command: "echo foo", env: { "FASTLANE_EXEC_FLUSH_PTY_WORKAROUND" => "1" } },
  { name: "printf foo (no newline)", command: "printf foo" },
  { name: "script: echo", command: script("echo", "echo foo") },
  { name: "script: echo, pause 10 ms", command: script("after10", "echo foo\nsleep 0.01"), max_runs: 4000 },
  { name: "script: echo, pause 100 ms", command: script("after100", "echo foo\nsleep 0.1"), max_runs: 800 },
  { name: "script: echo, pause 1000 ms", command: script("after1000", "echo foo\nsleep 1"), max_runs: 120 },
  { name: "script: pause 10 ms, echo", command: script("before10", "sleep 0.01\necho foo"), max_runs: 4000 },
  { name: "script: pause 100 ms, echo", command: script("before100", "sleep 0.1\necho foo"), max_runs: 800 }
].map { |v| { env: {}, expected: "foo" }.merge(v) }.freeze

# Each reader returns how the read ended
READERS = {
  "each" => lambda do |io, out|
    io.each { |line| out << line }
    "EOF"
  rescue Errno::EIO
    "EIO"
  end,
  "readpartial" => lambda do |io, out|
    loop { out << io.readpartial(4096) }
  rescue EOFError
    "EOF"
  rescue Errno::EIO
    "EIO"
  end
}.freeze

def now_ms
  Process.clock_gettime(Process::CLOCK_MONOTONIC, :float_millisecond)
end

def run_once(variant, reader)
  out = +""
  ending = "none"
  start = now_ms
  ENV.update(variant[:env])
  FastlaneCore::FastlanePty.spawn(variant[:command]) { |stdout, _stdin, _pid| ending = reader.call(stdout, out) }
  [out.delete("\r").chomp, ending, (now_ms - start).round(2)]
rescue StandardError => e
  ["<#{e.class}: #{e.message}>", "raised", (now_ms - start).round(2)]
ensure
  variant[:env].each_key { |k| ENV.delete(k) }
end

# Each process runs its share of every variant, so the processes load the machine at the same time
def rows_for(runs, processes)
  VARIANTS.flat_map do |variant|
    share = ([runs, variant[:max_runs] || runs].min.to_f / processes).ceil
    READERS.map do |reader_name, reader|
      outputs = Hash.new(0)
      endings = { "ok" => Hash.new(0), "lost" => Hash.new(0) }
      ms = { "ok" => [], "lost" => [] }
      share.times do
        output, ending, elapsed = run_once(variant, reader)
        outcome = output == variant[:expected] ? "ok" : "lost"
        outputs[output] += 1
        endings[outcome][ending] += 1
        ms[outcome] << elapsed
      end
      { variant: variant[:name], reader: reader_name, expected: variant[:expected], outputs: outputs, endings: endings, ms: ms }
    end
  end
end

children = processes.times.map do
  r, w = IO.pipe
  pid = fork do
    r.close
    w.write(JSON.generate(rows_for(runs, processes)))
    w.close
  end
  w.close
  [pid, r]
end
partials = children.map do |pid, r|
  data = r.read
  Process.wait(pid)
  JSON.parse(data)
end

def quantiles(values)
  return nil if values.empty?
  sorted = values.sort
  { "min" => sorted.first, "median" => sorted[sorted.size / 2], "p99" => sorted[(sorted.size * 0.99).floor.clamp(0, sorted.size - 1)], "max" => sorted.last }
end

merged = partials.first.each_index.map do |i|
  first = partials.first[i]
  row = { "variant" => first["variant"], "reader" => first["reader"], "expected" => first["expected"] }
  row["outputs"] = Hash.new(0)
  row["endings"] = { "ok" => Hash.new(0), "lost" => Hash.new(0) }
  ms = { "ok" => [], "lost" => [] }
  partials.each do |p|
    p[i]["outputs"].each { |k, v| row["outputs"][k] += v }
    %w[ok lost].each do |outcome|
      p[i]["endings"][outcome].each { |k, v| row["endings"][outcome][k] += v }
      ms[outcome].concat(p[i]["ms"][outcome])
    end
  end
  row["runs"] = row["outputs"].values.sum
  row["lost"] = row["runs"] - row["outputs"].fetch(row["expected"], 0)
  row["ms"] = { "ok" => quantiles(ms["ok"]), "lost" => quantiles(ms["lost"]) }
  row
end

result = {
  image: "#{ENV['ImageOS']} #{ENV['ImageVersion']}".strip,
  platform: RUBY_PLATFORM,
  ruby: RUBY_VERSION,
  processes: processes,
  rows: merged
}
File.write("result.json", JSON.generate(result) + "\n")
merged.each do |row|
  puts "#{row['variant'].ljust(30)} #{row['reader'].ljust(11)} lost #{row['lost']}/#{row['runs']} " \
       "endings #{row['endings']} ms ok #{row['ms']['ok']&.values_at('median', 'p99')} lost #{row['ms']['lost']&.values_at('min', 'median', 'max')}"
end
