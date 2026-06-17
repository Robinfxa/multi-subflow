#!/usr/bin/env bash
# Approve a fork's review and wake it up
SLUG=$1
INSTRUCTIONS=$2
if [ -z "$SLUG" ]; then 
  echo "Error: Missing slug"
  exit 1
fi

IPC_DIR=".multi-subflow"
mkdir -p "$IPC_DIR"

RES_FILE="$IPC_DIR/review_response_${SLUG}.json"

# The woken agent (arc-imp / code-reader fork) carries its Implementer-phase /
# developer contract INLINE — no external file to inject. The key only signals
# approval + any extra instructions.
cat <<EOF > "$RES_FILE"
[STATUS: APPROVED]
[INSTRUCTIONS]: $INSTRUCTIONS

Follow your own inline contract (arc-imp.md Implementer phase, or code-reader.md
fork→developer section): write production code + tests, run tier-1, then emit a
status-carrying task_completed_${SLUG}.json signal before returning.
EOF

echo "[IPC] Approved fork $SLUG with instructions. Key (review_response) written."
