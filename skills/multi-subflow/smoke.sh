#!/usr/bin/env bash
# Smoke-test the multi-subflow IPC protocol end-to-end, driving the REAL
# ipc/*.sh scripts. Simulates both roles with background shell processes (no
# live agents needed) so the file-lock handshake + bidirectional failure
# protocol + the lint.sh compliance checker are all exercised deterministically.
#
# Usage:  bash .claude/skills/multi-subflow/smoke.sh
# Exit 0 = all scenarios pass.
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
IPC="$HERE/ipc"
LINT="$HERE/lint.sh"
WORK=$(mktemp -d)
cd "$WORK" || exit 1
mkdir -p .multi-subflow
PASS=0; FAIL=0
ok()  { echo "  ✅ $1"; PASS=$((PASS+1)); }
bad() { echo "  ❌ $1"; FAIL=$((FAIL+1)); }

echo "workdir: $WORK"
echo

echo "[1] happy path — subagent suspends → Director approves → terminal status=ok"
( bash "$IPC/await_director_review.sh" s1 15 >s1.out 2>&1
  [ $? -eq 0 ] && echo '{"slug":"s1","status":"ok","tier1_rc":0}' > .multi-subflow/task_completed_s1.json ) &
for _ in $(seq 1 40); do [ -f .multi-subflow/review_request_s1.json ] && break; sleep 0.3; done
[ -f .multi-subflow/review_request_s1.json ] && ok "subagent suspended (review_request_s1 written)" || bad "subagent never suspended"
bash "$IPC/approve_fork.sh" s1 "proceed" >/dev/null 2>&1
bash "$IPC/await_terminal.sh" s1 15 >term1.out 2>&1; rc=$?
{ [ $rc -eq 0 ] && grep -q '"status":"ok"' .multi-subflow/task_completed_s1.json; } \
  && ok "Director saw terminal ok (status=ok)" || bad "no ok terminal (rc=$rc)"
grep -q APPROVED s1.out && ok "subagent received the APPROVED key on stdout" || bad "subagent did not get key"
wait
echo

echo "[2] subagent-side failure — Director withholds the key (never approves)"
( bash "$IPC/await_director_review.sh" s2 5 >s2.out 2>&1 ) &   # 5s, no approval coming
wait
{ [ -f .multi-subflow/task_failed_s2.json ] && grep -q approval_timeout .multi-subflow/task_failed_s2.json; } \
  && ok "subagent self-failed with approval_timeout" || bad "no task_failed_s2"
[ ! -f .multi-subflow/task_completed_s2.json ] && ok "subagent did NOT write completion (refused to proceed/code)" || bad "subagent wrote completion despite no key"
grep -qi 'FAILED-NOKEY' s2.out && ok "subagent reported refusal on stdout" || bad "no refusal message"
echo

echo "[3] Director-side failure — worker dies after approval (no terminal signal)"
echo '{"waiting":"s3"}' > .multi-subflow/review_request_s3.json
bash "$IPC/approve_fork.sh" s3 "proceed" >/dev/null 2>&1   # key written, but no worker will complete
bash "$IPC/await_terminal.sh" s3 5 >term3.out 2>&1; rc=$?
{ [ $rc -eq 42 ] && grep -qi 'presumed DEAD' term3.out; } \
  && ok "Director detected presumed-DEAD via deadline (exit 42)" || bad "deadline guard failed (rc=$rc)"
echo

echo "[4] compliance linter (lint.sh) catches both sides' violations"
# 4a: subagent wrote a NAKED completion (no status) -> director-lint must flag
echo '{"slug":"nk"}' > .multi-subflow/task_completed_nk.json
LINT_THRESH=0 bash "$LINT" director .multi-subflow >lint_d.out 2>&1
grep -qi 'NAKED completion' lint_d.out && ok "director-lint flags naked completion + reminds subagent" || bad "director-lint missed naked completion"
# 4b: Director left a request unanswered -> subagent-lint must flag + remind director
echo '{"status":"WAITING","slug":"st"}' > .multi-subflow/review_request_st.json
LINT_THRESH=0 bash "$LINT" subagent .multi-subflow >lint_s.out 2>&1
grep -qi 'REMIND DIRECTOR' lint_s.out && ok "subagent-lint flags stale request + reminds Director" || bad "subagent-lint missed stale request"
echo

rm -rf "$WORK"
echo "──────────────────────────────────────────"
echo "RESULT: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && echo "GATE: PASS" || echo "GATE: FAIL"
[ "$FAIL" -eq 0 ]
