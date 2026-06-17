#!/usr/bin/env bash
# Director dispatching commands to Mother A
PROJECT=$1
COMMAND=$2
if [ -z "$PROJECT" ] || [ -z "$COMMAND" ]; then 
  echo "Error: Missing args"
  exit 1
fi

IPC_DIR=".multi-subflow"
mkdir -p "$IPC_DIR"

CMD_FILE="$IPC_DIR/command_payload_${PROJECT}.json"

echo "[COMMAND: $COMMAND]" > "$CMD_FILE"
echo "[IPC] Sent command to Code-Reader Mother on project $PROJECT. Command payload written."
