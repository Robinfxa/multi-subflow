#!/usr/bin/env bash
# DIRECTOR side (its own failure-handling version): wait for a TERMINAL signal
# for one <slug> — either task_completed (with status) or task_failed — with a
# hard DEADLINE. On deadline the worker is presumed DEAD (it never even wrote a
# failure signal, e.g. drifted / crashed mid-flight) and the Director must
# handle it (retry / fall back to single-shot / abort) instead of hanging.
#
# 🔴 Launch via `run_in_background: true` and YIELD the turn; the script exits
# (re-invoking the Director) the instant a terminal signal lands or the deadline
# is hit. Exit code: 0 = terminal signal found (read status from stdout);
# 42 = deadline hit, worker presumed dead.
SLUG=$1
MAX=${2:-1800}
if [ -z "$SLUG" ]; then
  echo "Error: Missing slug"
  exit 1
fi

IPC_DIR=".multi-subflow"
mkdir -p "$IPC_DIR"
DONE="$IPC_DIR/task_completed_${SLUG}.json"
FAIL="$IPC_DIR/task_failed_${SLUG}.json"

t0=$SECONDS
while true; do
  if [ -f "$DONE" ]; then echo "[TERMINAL ok $SLUG]"; cat "$DONE"; exit 0; fi
  if [ -f "$FAIL" ]; then echo "[TERMINAL failed $SLUG]"; cat "$FAIL"; exit 0; fi
  if [ $((SECONDS - t0)) -ge "$MAX" ]; then
    echo "[TERMINAL timeout $SLUG] ${MAX}s elapsed — worker presumed DEAD (no completed/failed signal); Director must handle"
    exit 42
  fi
  sleep 3
done
