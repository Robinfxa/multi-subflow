#!/usr/bin/env bash
# Event multiplexer (总机) for the Director to learn when a subagent has a
# pending review or has finished.
#
# 🔴 DIRECTOR side: do NOT run this in the foreground. Foreground-blocking the
# Director freezes it so it can never write the approval key — and an event
# (a subagent writing review_request) won't re-invoke the Director either.
# PROVEN-GOOD pattern: launch this via `run_in_background: true` and YIELD the
# turn. The script exits the instant it catches an event, which re-invokes the
# Director; the Director then approves and re-arms another background watcher.
#
# MAX bounds the watch so a quiet run doesn't leave an orphan poller.

IPC_DIR=".multi-subflow"
MAX=${1:-1800}
mkdir -p "$IPC_DIR"

echo "[IPC] Director watcher armed (bg); waiting for events..."
t0=$SECONDS
while true; do
  # 1. Pending review requests (not yet approved)
  for REQ in "$IPC_DIR"/review_request_*.json; do
    if [ -f "$REQ" ]; then
      SLUG=$(basename "$REQ" | sed 's/review_request_//;s/\.json//')
      RES="$IPC_DIR/review_response_${SLUG}.json"
      if [ ! -f "$RES" ]; then
        echo "[EVENT] 🔴 review request — wake! source: $SLUG"
        cat "$REQ"
        exit 0
      fi
    fi
  done

  # 2. Completion signals (not yet acknowledged) — carry {status, tier1_rc};
  #    the Director trusts the status field, NOT mere file presence.
  for COMP in "$IPC_DIR"/task_completed_*.json; do
    if [ -f "$COMP" ]; then
      SLUG=$(basename "$COMP" | sed 's/task_completed_//;s/\.json//')
      ACK="$IPC_DIR/task_acked_${SLUG}.json"
      if [ ! -f "$ACK" ]; then
        echo "[EVENT] 🟢 task completed — wake! source: $SLUG (check status field)"
        cat "$COMP"
        touch "$ACK" # auto-ack so it doesn't re-trigger
        exit 0
      fi
    fi
  done

  # 3. Failure signals (not yet acknowledged) — subagent self-reported failure
  #    (approval_timeout / rejected / tier1_red). Director must handle it.
  for FL in "$IPC_DIR"/task_failed_*.json; do
    if [ -f "$FL" ]; then
      SLUG=$(basename "$FL" | sed 's/task_failed_//;s/\.json//')
      ACK="$IPC_DIR/task_acked_${SLUG}.json"
      if [ ! -f "$ACK" ]; then
        echo "[EVENT] 🔴 task FAILED — wake! source: $SLUG"
        cat "$FL"
        touch "$ACK"
        exit 0
      fi
    fi
  done

  if [ $((SECONDS - t0)) -ge "$MAX" ]; then
    echo "[IPC] watcher timeout after ${MAX}s — no events"
    exit 42
  fi
  sleep 3
done
