#!/usr/bin/env bash
# Wait for the Director to approve a subagent's spec review.
# SUBAGENT side (its own failure-handling version): safe to run FOREGROUND (the
# subagent is background relative to the Director, so blocking holds only the
# subagent's own turn — proven).
#
# Failure handling (so the Director always learns, and the subagent never writes
# code without approval):
#   - no key within MAX (Director failure/forgot)  -> write task_failed{approval_timeout}, exit 42
#   - key says REJECTED / CHANGES                   -> write task_failed{rejected},        exit 7
#   - key has no APPROVED token (malformed)         -> write task_failed{malformed_key},   exit 8
#   - key says APPROVED                             -> cat the key to stdout (caller flips role), exit 0
SLUG=$1
MAX=${2:-1800}
if [ -z "$SLUG" ]; then
  echo "Error: Missing slug"
  exit 1
fi

# repo-root .multi-subflow as the shared lock dir (run from repo root)
IPC_DIR=".multi-subflow"
mkdir -p "$IPC_DIR"

REQ_FILE="$IPC_DIR/review_request_${SLUG}.json"
RES_FILE="$IPC_DIR/review_response_${SLUG}.json"
FAIL_FILE="$IPC_DIR/task_failed_${SLUG}.json"

echo "{\"status\": \"WAITING\", \"slug\": \"$SLUG\"}" > "$REQ_FILE"

# Block and poll (0 token cost — the model does not generate while bash blocks)
t0=$SECONDS
while [ ! -f "$RES_FILE" ]; do
  if [ $((SECONDS - t0)) -ge "$MAX" ]; then
    echo "{\"slug\":\"$SLUG\",\"status\":\"failed\",\"reason\":\"approval_timeout\",\"waited_s\":$((SECONDS-t0))}" > "$FAIL_FILE"
    rm -f "$REQ_FILE"
    echo "[FAILED-NOKEY $SLUG] approval_timeout after ${MAX}s — refused to proceed without APPROVED"
    exit 42
  fi
  sleep 5
done

KEY=$(cat "$RES_FILE")
rm -f "$REQ_FILE" "$RES_FILE"

if printf '%s' "$KEY" | grep -qiE 'REJECT|CHANGES_REQUESTED'; then
  echo "{\"slug\":\"$SLUG\",\"status\":\"failed\",\"reason\":\"rejected\"}" > "$FAIL_FILE"
  echo "[REJECTED $SLUG] Director did not approve — no production code may be written"
  exit 7
fi
if ! printf '%s' "$KEY" | grep -q 'APPROVED'; then
  echo "{\"slug\":\"$SLUG\",\"status\":\"failed\",\"reason\":\"malformed_key\"}" > "$FAIL_FILE"
  echo "[BADKEY $SLUG] no APPROVED token — refusing to proceed"
  exit 8
fi

# Approved: emit the key (approval + contract) to stdout — the subagent reads it
# as the Bash tool result and flips role. No hook required.
cat <<EOF
$KEY
EOF
