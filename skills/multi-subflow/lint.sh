#!/usr/bin/env bash
# Compliance linter for the multi-subflow IPC protocol — the "if you notice the
# OTHER side isn't following the protocol, remind them" tool, from each role's
# perspective. Inspects the shared .multi-subflow/ lock dir and prints
# violations + an actionable REMINDER for the responsible party.
#
# Usage:
#   bash lint.sh subagent [ipc_dir]   # I am a SUBAGENT — is the Director slacking?
#   bash lint.sh director  [ipc_dir]   # I am the DIRECTOR — are subagents (or I) slacking?
#
# ipc_dir defaults to ./.multi-subflow ; LINT_THRESH (seconds, default 30) is how
# long a pending item may sit before it counts as a violation.
# Exit 0 = clean, 1 = issues found, 2 = bad usage.
ROLE=${1:-}
IPC=${2:-.multi-subflow}
THRESH=${LINT_THRESH:-30}
[ -z "$ROLE" ] && { echo "usage: lint.sh director|subagent [ipc_dir]"; exit 2; }
[ -d "$IPC" ] || { echo "no IPC dir: $IPC"; exit 2; }

now=$(date +%s)
age() { local m; m=$(stat -f %m "$1" 2>/dev/null || stat -c %Y "$1" 2>/dev/null || echo "$now"); echo $(( now - m )); }
viol=0
note() { echo "⚠️  $1"; viol=$((viol+1)); }

case "$ROLE" in
  subagent)
    # I am a subagent. Detect the DIRECTOR breaking its end (didn't approve/reject in time).
    for r in "$IPC"/review_request_*.json; do
      [ -f "$r" ] || continue
      slug=$(basename "$r" | sed 's/review_request_//;s/\.json//')
      [ -f "$IPC/review_response_${slug}.json" ] && continue
      a=$(age "$r")
      if [ "$a" -ge "$THRESH" ]; then
        note "Director has NOT answered '$slug' for ${a}s (no review_response)."
        echo "    → REMIND DIRECTOR: 用 run_in_background 挂 await_events 并【让出 turn】，再 approve_fork 或写 REJECTED。前台阻塞会冻死你、收不到我的请求。"
      fi
    done
    ;;
  director)
    # I am the Director. Detect SUBAGENTS breaking the contract, and ME leaving work undone.
    for c in "$IPC"/task_completed_*.json; do
      [ -f "$c" ] || continue
      slug=$(basename "$c" | sed 's/task_completed_//;s/\.json//')
      if ! grep -q '"status"' "$c"; then
        note "'$slug' wrote a NAKED completion (no status field)."
        echo "    → REMIND SUBAGENT: 完工必须带 {\"status\":\"ok|failed\",\"tier1_rc\":N}；裸 'done' 不被当作通过。"
      fi
    done
    for t in "$IPC"/task_completed_*.json "$IPC"/task_failed_*.json; do
      [ -f "$t" ] || continue
      slug=$(basename "$t" | sed 's/task_completed_//;s/task_failed_//;s/\.json//')
      [ -f "$IPC/task_acked_${slug}.json" ] && continue
      [ -f "$IPC/acked_$(basename "$t")" ] && continue
      a=$(age "$t")
      if [ "$a" -ge "$THRESH" ]; then
        note "terminal signal for '$slug' left UNHANDLED for ${a}s."
        echo "    → REMIND DIRECTOR(自己): 重新挂 await_events、处理并 ack 这个信号；别让它堆积。"
      fi
    done
    for r in "$IPC"/review_request_*.json; do
      [ -f "$r" ] || continue
      slug=$(basename "$r" | sed 's/review_request_//;s/\.json//')
      [ -f "$IPC/review_response_${slug}.json" ] && continue
      a=$(age "$r")
      if [ "$a" -ge "$THRESH" ]; then
        note "'$slug' has been waiting ${a}s for your key."
        echo "    → REMIND DIRECTOR(自己): approve_fork 放行或写 REJECTED 回应；别让子代空等到超时。"
      fi
    done
    ;;
  *) echo "unknown role: $ROLE (use director|subagent)"; exit 2;;
esac

if [ "$viol" -eq 0 ]; then echo "✅ no $ROLE-side compliance issues"; exit 0; fi
echo "($viol issue(s) — surface the REMIND line(s) to the responsible party)"
exit 1
