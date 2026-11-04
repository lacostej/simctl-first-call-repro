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
