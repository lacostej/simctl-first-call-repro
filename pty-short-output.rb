# Does fastlane's FastlanePty.spawn lose the output of very short commands (fastlane#21792)?
# Runs each command many times through the FastlanePty of a fastlane checkout, reading the output
# with IO#each, as CommandExecutor.execute does, and with readpartial, and counts what came back.
# Usage: ruby pty-short-output.rb <path to fastlane_pty.rb> <runs per variant> <parallel processes>
# Writes one line of JSON to result.json.
require 'json'
require_relative File.expand_path(ARGV[0])

runs = Integer(ARGV[1])
processes = Integer(ARGV[2])

# The command and what it should print; env is passed to the whole spawn, as fastlane's workaround reads ENV
VARIANTS = [
  { name: "echo foo", command: "echo foo", env: {}, expected: "foo" },
  { name: "echo foo, flush workaround", command: "echo foo", env: { "FASTLANE_EXEC_FLUSH_PTY_WORKAROUND" => "1" }, expected: "foo" },
  { name: "printf foo (no newline)", command: "printf foo", env: {}, expected: "foo" }
].freeze

READERS = {
  "each" => lambda do |io, out|
    io.each { |line| out << line }
  end,
  "readpartial" => lambda do |io, out|
    loop { out << io.readpartial(4096) }
  rescue EOFError
    # FastlanePty itself rescues the Errno::EIO a Linux PTY raises at the end
  end
}.freeze

def run_once(variant, reader)
  out = +""
  ENV.update(variant[:env])
  FastlaneCore::FastlanePty.spawn(variant[:command]) { |stdout, _stdin, _pid| reader.call(stdout, out) }
  out.delete("\r").chomp
rescue StandardError => e
  "<#{e.class}: #{e.message}>"
ensure
  variant[:env].each_key { |k| ENV.delete(k) }
end

# Each process runs its share of every variant, so the processes load the machine at the same time
def counts_for(runs)
  VARIANTS.flat_map do |variant|
    READERS.map do |reader_name, reader|
      outputs = Hash.new(0)
      runs.times { outputs[run_once(variant, reader)] += 1 }
      { variant: variant[:name], reader: reader_name, expected: variant[:expected], outputs: outputs }
    end
  end
end

share = (runs.to_f / processes).ceil
readers = processes.times.map do
  r, w = IO.pipe
  pid = fork do
    r.close
    w.write(JSON.generate(counts_for(share)))
    w.close
  end
  w.close
  [pid, r]
end
partials = readers.map do |pid, r|
  data = r.read
  Process.wait(pid)
  JSON.parse(data)
end

merged = partials.first.each_index.map do |i|
  row = partials.first[i].dup
  row["outputs"] = Hash.new(0)
  partials.each { |p| p[i]["outputs"].each { |k, v| row["outputs"][k] += v } }
  row["runs"] = row["outputs"].values.sum
  row["lost"] = row["runs"] - row["outputs"].fetch(row["expected"], 0)
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
merged.each { |row| puts "#{row['variant'].ljust(28)} #{row['reader'].ljust(11)} lost #{row['lost']}/#{row['runs']} #{row['outputs'].reject { |k, _| k == row['expected'] }}" }
