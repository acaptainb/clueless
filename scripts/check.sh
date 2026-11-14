#!/bin/sh
# Test a pushed branch on the Mac mini. This is the merge gate, and the only way code written on a
# laptop gets built or run. It uses a separate working copy, so the main checkout is left alone.
#
#   ./scripts/check.sh <branch>        build + answer and watcher benchmarks, prints PASS or FAIL
#   ./scripts/check.sh <branch> app    the same, then launches that branch's app for a live test
#
# Only one check or live test at a time: the Bonsai servers, the screen and the speakers are shared.
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BR="${1:?usage: check.sh <branch> [app]}"
WT="$ROOT/.worktrees/check"
LOG="$ROOT/.run/check.log"; mkdir -p "$ROOT/.run"

git -C "$ROOT" fetch -q origin || { echo "FAIL: cannot fetch"; exit 1; }
git -C "$ROOT" rev-parse -q --verify "origin/$BR" >/dev/null || { echo "FAIL: origin/$BR does not exist (push it first)"; exit 1; }
if [ -d "$WT" ]; then git -C "$WT" checkout -q --detach "origin/$BR" || exit 1
else git -C "$ROOT" worktree add -q --detach "$WT" "origin/$BR" || exit 1; fi
SHA="$(git -C "$WT" rev-parse --short HEAD)"
echo "== checking $BR @ $SHA"

cd "$WT"
if ! swift build -c release > "$ROOT/.run/check-build.log" 2>&1; then
  grep -E 'error' -A6 "$ROOT/.run/check-build.log" | head -40
  echo "FAIL $BR @ $SHA: build failed (full log: .run/check-build.log)" | tee -a "$LOG"; exit 1
fi
echo "build ok"
# Logic checks that need no servers or models. Shown, not part of the gate.
.build/release/clueless-bench selftest 2>&1 | grep -E '^FAIL|^== selftest' | cut -c1-200

# Servers and models always come from the main checkout.
curl -sf http://127.0.0.1:8080/health >/dev/null && curl -sf http://127.0.0.1:8082/health >/dev/null \
  || "$ROOT/scripts/servers.sh" start || { echo "FAIL: Bonsai servers did not start"; exit 1; }

export CLUELESS_ROOT="$ROOT"
ANS="$(.build/release/clueless-bench answer 2>&1)"; WAT="$(.build/release/clueless-bench watch 2>&1)"
echo "$ANS" | grep -E '^==|   x ' | cut -c1-200; echo "$WAT" | cut -c1-200
Q="$(echo "$ANS" | sed -n 's/.*questions: correct \([0-9]*\)\/\([0-9]*\).*/\1 \2/p')"
C="$(echo "$ANS" | sed -n 's/.*catch-up: \([0-9]*\)\/3.*/\1/p')"
W="$(echo "$WAT" | sed -n 's/^code check + model: \([0-9]*\)\/\([0-9]*\).*/\1 \2/p')"
QOK=${Q% *}; QN=${Q#* }; WOK=${W% *}; WN=${W#* }
SUMMARY="$BR @ $SHA: build ok, questions ${QOK:-?}/${QN:-?}, catch-up ${C:-?}/3, watcher ${WOK:-?}/${WN:-?} ($(date '+%a %H:%M'))"
# Gate: every question right, at most one watcher miss (the models sample, so allow one), catch-up 2 of 3.
if [ "${QOK:-0}" = "${QN:-1}" ] && [ "${WOK:-0}" -ge $(( ${WN:-99} - 1 )) ] && [ "${C:-0}" -ge 2 ]; then
  echo "PASS $SUMMARY" | tee -a "$LOG"
else
  echo "FAIL $SUMMARY" | tee -a "$LOG"; exit 1
fi

if [ "$2" = "app" ]; then ./scripts/make_app.sh run; echo "live app from $BR is running; log: $ROOT/.run/app.log"; fi
