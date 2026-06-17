#!/usr/bin/env bash
# Mother A polling for the Director's next command (FORK / SYNC).
# MOTHER side: Mother is a subagent (background relative to the Director), so a
# FOREGROUND block here holds only Mother's own turn — safe. MAX bounds it.
PROJECT=$1
MAX=${2:-1800}
if [ -z "$PROJECT" ]; then
  echo "Error: Missing project name"
  exit 1
fi

IPC_DIR=".multi-subflow"
mkdir -p "$IPC_DIR"

REQ_FILE="$IPC_DIR/command_ready_${PROJECT}.json"
CMD_FILE="$IPC_DIR/command_payload_${PROJECT}.json"

echo "{\"status\": \"READY\", \"project\": \"$PROJECT\"}" > "$REQ_FILE"

# Block and poll (0 token cost)
t0=$SECONDS
while [ ! -f "$CMD_FILE" ]; do
  if [ $((SECONDS - t0)) -ge "$MAX" ]; then
    echo "[TIMEOUT after ${MAX}s waiting for a command on $PROJECT]"
    rm -f "$REQ_FILE"
    exit 42
  fi
  sleep 5
done

# output the command to stdout for the LLM to act on
cat "$CMD_FILE"

# Clean up
rm -f "$REQ_FILE" "$CMD_FILE"
