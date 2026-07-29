#!/usr/bin/env python3
"""Change-detection monitor for a shepherdr herd.

Polls `herdr pane list` and prints one line per agent status transition
(e.g. `1-3 working -> idle`). Silent while nothing changes, so it is safe
to leave running under the Monitor tool or a background Bash.

Python, not bash: macOS ships bash 3.2, which has no associative arrays.

Usage:
    herd-monitor.py <pane-id> [<pane-id> ...]      watch specific panes
    herd-monitor.py --all                          watch every detected agent
    herd-monitor.py --interval 15 <pane-id> ...    custom poll seconds (default 30)

A watched pane that disappears from `pane list` reports `-> gone`.

With SHEPHERDR_HERD_SESSION set, this watches the invisible herd session
instead of the visible one. Nothing else about the output changes.
"""
import json
import os
import subprocess
import sys
import time

# See scripts/hrd: one shim so the monitor treats visible and invisible
# panes identically.
HRD = os.path.join(os.path.dirname(os.path.abspath(__file__)), "hrd")


def collect_panes(node, found):
    """Find {pane_id: agent_status} anywhere in the pane-list JSON."""
    if isinstance(node, dict):
        if "pane_id" in node:
            found[node["pane_id"]] = node.get("agent_status", "unknown")
        for v in node.values():
            collect_panes(v, found)
    elif isinstance(node, list):
        for v in node:
            collect_panes(v, found)


def snapshot():
    proc = subprocess.run(
        [HRD, "pane", "list"], capture_output=True, text=True, timeout=30
    )
    if proc.returncode != 0:
        return None
    found = {}
    try:
        collect_panes(json.loads(proc.stdout), found)
    except json.JSONDecodeError:
        return None
    return found


def main():
    args = sys.argv[1:]
    interval = 30
    if "--interval" in args:
        i = args.index("--interval")
        interval = int(args[i + 1])
        del args[i : i + 2]
    watch_all = "--all" in args
    targets = [a for a in args if a != "--all"]
    if not watch_all and not targets:
        print(__doc__, file=sys.stderr)
        sys.exit(2)

    prev = {}
    first = True
    while True:
        snap = snapshot()
        if snap is None:
            print("herd-monitor: `herdr pane list` failed", flush=True)
        else:
            panes = snap if watch_all else {p: snap.get(p, "gone") for p in targets}
            if first:
                states = ", ".join(f"{p}={s}" for p, s in sorted(panes.items()))
                print(f"herd-monitor: watching {states}", flush=True)
                first = False
            for pane, status in panes.items():
                old = prev.get(pane)
                if old is not None and old != status:
                    print(f"{pane} {old} -> {status}", flush=True)
                prev[pane] = status
        time.sleep(interval)


if __name__ == "__main__":
    main()
