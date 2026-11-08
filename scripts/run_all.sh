#!/usr/bin/env bash
# Run every scenario and the independent replay checks.
# Usage: run_all.sh <out-dir>   (relative to the pack root)
# Every scenario prints only deterministic values (ticks, counts,
# digests) to stdout; logs are captured unedited under <out-dir>.
set -u
cd "$(dirname "$0")/.." || exit 1
export PYTHONHASHSEED=0
export LC_ALL=C
export PYTHONDONTWRITEBYTECODE=1

OUT_DIR="${1:-outputs/run1}"
mkdir -p "$OUT_DIR"
fail=0

run() { # run <log-name> <command...>
  local name="$1"; shift
  if "$@" > "$OUT_DIR/$name.log" 2>&1; then
    echo "ok: $name"
  else
    echo "FAIL: $name (see $OUT_DIR/$name.log)"
    fail=1
  fi
}

run basic python3 scenarios/run_basic.py --out-dir "$OUT_DIR"
run timeout python3 scenarios/run_timeout.py --out-dir "$OUT_DIR"
run cancellation python3 scenarios/run_cancellation.py --out-dir "$OUT_DIR"
run partial-failure python3 scenarios/run_partial_failure.py --out-dir "$OUT_DIR"
run out-of-order python3 scenarios/run_out_of_order.py --out-dir "$OUT_DIR"
run repeat-cap python3 scenarios/run_repeat_cap.py --out-dir "$OUT_DIR"
run nested-timing python3 scenarios/run_nested_timing.py --out-dir "$OUT_DIR"
run shell bash components/shell_runner/run_parallel.sh components/shell_runner/manifest.json "$OUT_DIR/shell"

# Independent replay checks through the replayer CLI (not the scenario scripts).
for batch in batch-basic batch-timeout batch-cancel batch-partial batch-reorder batch-repeat batch-nested; do
  run "replay-$batch" python3 -m harness.replayer "fixtures/$batch.json" "$OUT_DIR/$batch.trace.jsonl"
done
run replay-timeout-naive python3 -m harness.replayer --no-timeout fixtures/batch-timeout.json "$OUT_DIR/batch-timeout-naive.trace.jsonl"
run replay-cancel-naive python3 -m harness.replayer --naive-cancel fixtures/batch-cancel.json "$OUT_DIR/batch-cancel-naive.trace.jsonl"
run replay-partial-naive python3 -m harness.replayer --naive-gather fixtures/batch-partial.json "$OUT_DIR/batch-partial-naive.trace.jsonl"
run replay-nested-unguarded python3 -m harness.replayer --unguarded-nested fixtures/batch-nested.json "$OUT_DIR/batch-nested-unguarded.trace.jsonl"

# Shell replay: re-run into a fixed scratch dir (same path in every run,
# so the log stays reproducible) and compare traces byte-for-byte.
SHELL_REPLAY_DIR="/tmp/ptrh-shell-replay"
rm -rf "$SHELL_REPLAY_DIR"
run shell-replay bash components/shell_runner/run_parallel.sh components/shell_runner/manifest.json "$SHELL_REPLAY_DIR"
if cmp -s "$OUT_DIR/shell/batch-shell.trace.jsonl" "$SHELL_REPLAY_DIR/batch-shell.trace.jsonl"; then
  echo "ok: shell trace replay is byte-identical"
  printf 'shell replay: MATCH (byte-identical)\n' > "$OUT_DIR/replay-shell.log"
else
  echo "FAIL: shell trace replay differs"
  printf 'shell replay: MISMATCH\n' > "$OUT_DIR/replay-shell.log"
  diff "$OUT_DIR/shell/batch-shell.trace.jsonl" "$SHELL_REPLAY_DIR/batch-shell.trace.jsonl" >> "$OUT_DIR/replay-shell.log" || true
  fail=1
fi
rm -rf "$SHELL_REPLAY_DIR"

if (( fail == 0 )); then
  echo "run_all: ALL PASS"
else
  echo "run_all: FAILURES PRESENT"
  exit 1
fi
