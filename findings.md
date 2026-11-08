# Findings

Severity-ranked findings from the validation runs. Every finding was
reproduced by a runnable script; the "Trigger" line is the exact
command (run from the pack root), and "Evidence" names the unedited
log and trace files. All ticks are virtual-clock ticks, not wall time.

## F-01 — High — Position-based result attribution misattributes outputs on out-of-order completion

**Trigger:** `python3 scenarios/run_out_of_order.py --out-dir outputs/run1`

**Observed:** Three calls are issued in order slow (5 ticks), fast
(1 tick), mid (3 ticks) and complete in order fast, mid, slow. A
collector that pairs completion-order results with issue-order call
ids — the position-based collector in `harness/dispatcher.py`
(`collect_by_position`) — assigns `fast-result` to the slow call,
`mid-result` to the fast call, and `slow-result` to the mid call: all
three results are misattributed.

**Expected:** Results are matched to calls by `tool_call_id` only
(OpenAI: each output references its `call_id`; Anthropic: each result
is matched by `tool_use_id`). The by-id collector
(`collect_by_id`) returns the correct mapping for all three calls.

**Evidence:** `outputs/run1/out-of-order.log`,
`outputs/run1/batch-reorder.trace.jsonl`
(`trace_sha256` in the log). Replay: byte-identical
(`outputs/run1/replay-batch-reorder.log`).

## F-02 — High — Cancellation that drops pending calls leaves issued calls without a result

**Trigger:** `python3 scenarios/run_cancellation.py --out-dir outputs/run1`

**Observed:** Batch cancelled at tick 4 with two calls in flight. The
naive cancel path (`--naive-cancel`) reports only 1 of 3 results: the
two cancelled calls are missing from the result set entirely, and no
`call_cancelled` event is emitted.

**Expected:** One result per issued call (Anthropic: "return one
`tool_result` for each `tool_use` block ... If you choose not to run a
particular call ... still return a `tool_result` for it with
`is_error: true`"). The correct path emits `call_cancelled` for both
in-flight calls at tick 4, reports 3/3 results, and ends the batch at
tick 4 with status `cancelled`. This matches CorbanuTerminal's abort
path, which records an aborted output per pending call
(`PendingToolCalls::take_unrecorded_outputs`).

**Evidence:** `outputs/run1/cancellation.log`,
`outputs/run1/batch-cancel.trace.jsonl`,
`outputs/run1/batch-cancel-naive.trace.jsonl`. Replay:
byte-identical (`outputs/run1/replay-batch-cancel.log`,
`outputs/run1/replay-cancel-naive.log`).

## F-03 — Medium — Aborting the batch on the first error loses later siblings' results

**Trigger:** `python3 scenarios/run_partial_failure.py --out-dir outputs/run1`

**Observed:** The middle call fails at tick 3 with a declared
`upstream 503` error. The naive gather path (`--naive-gather`,
abort-on-first-error, the `asyncio.TaskGroup` pattern: "the first
time any of the tasks belonging to the group fails ... the remaining
tasks in the group are cancelled") aborts the batch: status `aborted`,
`batch_aborted` emitted, and only 1 of 3 results reported — the later
sibling (4 ticks) never reports.

**Expected:** Per-call error isolation: the failing call is reported
with `is_error: true`, both siblings complete, batch status
`partial_failure`, 3/3 results reported, batch ends at tick 4.

**Evidence:** `outputs/run1/partial-failure.log`,
`outputs/run1/batch-partial.trace.jsonl`,
`outputs/run1/batch-partial-naive.trace.jsonl`. Replay:
byte-identical (`outputs/run1/replay-batch-partial.log`,
`outputs/run1/replay-partial-naive.log`).

## F-04 — Medium — No per-call deadline lets a slow call hold the whole batch

**Trigger:** `python3 scenarios/run_timeout.py --out-dir outputs/run1`

**Observed:** One call has a 20-tick duration. Without a per-call
deadline (`--no-timeout`) the batch ends at tick 20, held by the
slowest call, and no timeout is reported.

**Expected:** With a 5-tick deadline the slow call is cut at tick 5
(`call_timeout` carrying `deadline_ticks: 5`), both siblings finish on
schedule, and the batch ends at tick 6 with status `partial_failure`.

**Evidence:** `outputs/run1/timeout.log`,
`outputs/run1/batch-timeout.trace.jsonl`,
`outputs/run1/batch-timeout-naive.trace.jsonl`. Replay:
byte-identical (`outputs/run1/replay-batch-timeout.log`,
`outputs/run1/replay-timeout-naive.log`).

## F-05 — Low — Unguarded nested-call timing events overlap the outer call and double-count latency

**Trigger:** `python3 scenarios/run_nested_timing.py --out-dir outputs/run1`

**Observed:** An outer call (ticks 0–6) runs a nested sub-call
(ticks 2–5). Without the timing guard (`--unguarded-nested`) the
nested call emits its own `call_start`/`call_end` events strictly
inside the outer interval; a consumer summing per-call durations
counts the nested 3 ticks twice.

**Expected:** Nested calls are excluded from timing events
(CorbanuTerminal `ToolCallTimingGuard::capture`: "Suppress nested
guards so consumers do not mistake overlapping events for independent
tool-call latency"; test `tool_call_timing_guard_ignores_code_mode_source`).
The guarded trace contains zero events with `parent_tool_call_id`
set, while the outer call still returns its own result.

**Evidence:** `outputs/run1/nested-timing.log`,
`outputs/run1/batch-nested.trace.jsonl`,
`outputs/run1/batch-nested-unguarded.trace.jsonl`. Replay:
byte-identical (`outputs/run1/replay-batch-nested.log`,
`outputs/run1/replay-nested-unguarded.log`).

## F-06 — Low — Unbounded identical-call repetition loops without a per-turn cap

**Trigger:** `python3 scenarios/run_repeat_cap.py --out-dir outputs/run1`

**Observed:** Four identical calls (same tool, same arguments) are
issued. The fourth is refused without running: a `call_refused`
event names the cap ("identical tool call refused after 3 identical
calls in one turn"), the refused call never starts, and it is still
reported in the result set (4/4 reported, batch status
`partial_failure`).

**Expected:** The cap mirrors CorbanuTerminal's
`MAX_IDENTICAL_TOOL_CALLS_PER_TURN: u8 = 3` (`parallel.rs` line 37):
repeating an identical call cannot produce new information, so the
dispatcher refuses it instead of looping.

**Evidence:** `outputs/run1/repeat-cap.log`,
`outputs/run1/batch-repeat.trace.jsonl`. Replay: byte-identical
(`outputs/run1/replay-batch-repeat.log`).

## Reference implementation notes (source inspection, not executed)

CorbanuTerminal `codex-rs/core/src/tools/parallel.rs`, commit
`7b5b368f896081c499c94d25faf4ea4b7ec44ca0`:

- Parallel-execution gate (lines 161, 328–330): parallel-capable
  tools share a read lock; non-parallel tools take the exclusive write
  lock. The harness models this as: every call in a batch runs
  concurrently unless the batch is declared sequential.
- Cancellation (lines 381–410): `tokio::select!` between the dispatch
  task and the `CancellationToken`; the abort path still records an
  output per pending call. The harness models this in F-02.
- Repeat caps (lines 37–47): 3 identical calls / 3 consecutive
  identical calls / 3 identical results per turn; the turn stops
  after 8 refused repeats. The harness models the 3-call cap in F-06.
- Nested timing guard (lines 558–583) and its tests (lines 665, 709).
  The harness models the guard in F-05.

The Rust unit tests in that file were **not** executed: the VM has
~600 MB free memory and building the `codex-core` test binary
exhausts it (the same build failed out-of-memory in earlier work on
this machine). This is a stated environment limitation, not a passing
result. The shell runner (`components/shell_runner/`) is the second
runnable validation component instead: four real concurrent processes
complete in the manifest's declared order with matching output
digests (see `outputs/run1/shell.log`).

## Validation summary

- 7 asyncio batches recorded and replayed byte-identically, plus 4
  naive-variant traces replayed byte-identically
  (`outputs/run1/replay-*.log`).
- Shell runner: 4 real parallel processes, completion order matches
  the manifest, exit codes and output digests match, trace replayed
  byte-identically (`outputs/run1/shell.log`,
  `outputs/run1/replay-shell.log`).
- Clean-environment reproduction from a fresh copy:
  `outputs/run2-clean/` is byte-identical to `outputs/run1/`
  (`outputs/run2-clean/clean-reproduce.log`).
- Digests: `SHA256SUMS` (verify with `bash scripts/verify_digests.sh`).
