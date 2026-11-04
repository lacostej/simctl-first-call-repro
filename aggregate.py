#!/usr/bin/env python3
"""Combines the results of several runs of the "First simctl call" workflow.

    ./aggregate.py                  every completed run of the workflow in this repository
    ./aggregate.py RUN_ID [...]     these runs only

Needs the gh CLI, signed in.
"""
import collections, glob, json, math, os, statistics, subprocess, sys, tempfile

WORKFLOW = "repro.yml"


def gh(*args):
    return subprocess.run(["gh", *args], check=True, capture_output=True, text=True).stdout


def wilson(k, n, z=1.96):
    p = k / n
    centre = (p + z * z / (2 * n)) / (1 + z * z / n)
    half = z * math.sqrt(p * (1 - p) / n + z * z / (4 * n * n)) / (1 + z * z / n)
    return max(0.0, centre - half), min(1.0, centre + half)


runs = sys.argv[1:] or [str(r["databaseId"]) for r in json.loads(gh(
    "run", "list", "--workflow", WORKFLOW, "--status", "completed", "--limit", "100", "--json", "databaseId"))]

groups = collections.defaultdict(list)
with tempfile.TemporaryDirectory() as tmp:
    for run in runs:
        target = os.path.join(tmp, run)
        try:
            gh("run", "download", run, "--pattern", "result-*", "--dir", target)
        except subprocess.CalledProcessError as e:
            print(f"run {run}: no results ({e.stderr.strip()})", file=sys.stderr)
            continue
        for f in glob.glob(os.path.join(target, "result-*", "result.json")):
            r = json.load(open(f))
            groups[(r["image"].split()[0], r["macos"], r["coresimulator"])].append(r)

print(f"{len(runs)} runs\n")
print("| Image | macOS | CoreSimulator | Jobs | Walked a runtime | 95% interval | First call, median | First call, range | Second call, max |")
print("|---|---|---|---|---|---|---|---|---|")
for (image, macos, version), rs in sorted(groups.items()):
    n, k = len(rs), sum(1 for r in rs if r["walked"])
    lo, hi = wilson(k, n)
    firsts = [r["first_call_s"] for r in rs]
    print(f"| {image} | {macos} | {version} | {n} | {k} | {lo:.0%} to {hi:.0%} | {statistics.median(firsts):.1f} s "
          f"| {min(firsts):.1f} to {max(firsts):.1f} s | {max(r['second_call_s'] for r in rs):.1f} s |")
