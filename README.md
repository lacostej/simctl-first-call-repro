# First `simctl` call on GitHub-hosted macOS runners

On the `macos-15` and `macos-26` runners, the first `xcrun simctl` command of a job can take from a few seconds to several minutes. Later calls take under a few seconds. On the runners where it is slow, `simdiskimaged` walks the whole file tree of one or more simulator runtimes before it finishes mounting them, and `simctl` waits for it.

This repository measures that, and compares it with the same runners after installing the CoreSimulator that comes with the `xcode-27` image's Xcode.

## Run it

Run the "First simctl call" workflow from the Actions tab, or:

```sh
gh workflow run repro.yml --ref measure
```

Each run measures 5 jobs per image (`macos-15`, `macos-26`, `xcode-27`), and with `newer_coresimulator` 5 more on `macos-15` and `macos-26` with the newer CoreSimulator installed. The run's summary page shows a table.

To combine several runs:

```sh
./aggregate.py              # every completed run
./aggregate.py RUN_ID ...   # these runs only
```

## What a job does

`measure.sh`:

1. traces the file system calls of `simdiskimaged` with `fs_usage` from the moment it starts;
2. times two `xcrun simctl list -j devices` calls;
3. counts a runtime as walked when over 50,000 traced calls fall inside its `.simruntime` bundle (a runtime that is only mounted gets about 500);
4. writes `result.json`: runner image, macOS and CoreSimulator versions, both times, the number of devices listed, the runtimes walked.

With `newer_coresimulator`, a job on `xcode-27` copies `XcodeSystemResources.pkg` from its Xcode and passes it to the other jobs through the Actions cache; they install it with `installer` before measuring. The image's default Xcode stays selected. The last job deletes the cache entry. Run the workflow from a branch other than the default branch: pull requests against a branch can read that branch's cache entries.

## Does the newer CoreSimulator break anything?

The "Validate the newer CoreSimulator" workflow (`validate.yml`) runs `validate.sh` on `macos-15` (Xcode 16.4 and 26.3) and `macos-26` (Xcode 26.6 and 26.2), with and without the newer CoreSimulator. For the selected Xcode it boots an iPhone simulator on the iOS runtime matching its SDK, runs a command in it with `simctl spawn`, and runs the tests of `probe-package` on it with `xcodebuild test`. That covers a build, a simulator boot, and installing and running a test runner; it does not cover everything CI does with simulators.

```sh
gh workflow run validate.yml --ref measure
```

## FastlanePty and very short commands

`pty-short-output.rb` runs `echo foo` (also with `FASTLANE_EXEC_FLUSH_PTY_WORKAROUND`) and `printf foo` many times through the `FastlanePty.spawn` of a fastlane checkout, reading the output with `IO#each`, as `CommandExecutor.execute` does, and with `readpartial`, and counts the runs whose output was lost ([fastlane#21792](https://github.com/fastlane/fastlane/issues/21792)). Each run also records how the read ended (end-of-file or `Errno::EIO`) and after how long, the script variants make the spawned shell pause after or before printing, and the perl and `exec /bin/echo` variants print with no shell, to tell the shell from the time the child lives. `-f variants=<regexp>` runs only the matching variants. Run the "FastlanePty short output" workflow, or `gh workflow run pty-short-output.yml -f ref=master`.

The "Repeat fastlane specs" workflow (`spec-repeat.yml`) runs given examples of a fastlane spec file thousands of times, in 4 rspec processes at once, and reports how often they fail. `spec-repeat/repeat_spec.rb` loads the spec file repeatedly in one process.
