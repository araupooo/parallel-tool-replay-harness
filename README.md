# Parallel Tool Replay Harness

Record real parallel agent tool call graphs with timing and ordering,
replay them deterministically, and inject timeout, cancellation,
partial-failure, and out-of-order-completion faults. Every assertion
is deterministic: a virtual clock replaces wall-clock time, so a
replayed trace is byte-identical to the recorded one.

## Components validated

1. **Asyncio parallel tool dispatcher** (`harness/`) — a Python
   `asyncio` dispatcher that runs batches of parallel tool calls on a
   virtual clock, records a canonical JSONL trace, and replays it.
   Semantics follow the OpenAI function-calling guide (multiple calls
   per turn, matched by `call_id`) and the Anthropic parallel-tool-use
   guide (one `tool_result` per `tool_use` block, matched by
   `tool_use_id`, `is_error` for calls that were not run).
2. **Shell parallel runner** (`components/shell_runner/`) — the same
   trace schema applied to real concurrent shell processes
   (background jobs, `wait -n` completion order, exit codes, output
   digests).
3. **Reference implementation inspection** — CorbanuTerminal's
   parallel tool runtime (`codex-rs/core/src/tools/parallel.rs`,
   commit `7b5b368f896081c499c94d25faf4ea4b7ec44ca0`): the
   parallel-execution gate, `CancellationToken` abort path, nested-call
   timing guard, and the 3-per-turn identical-call cap. The harness
   models each of these rules; see `findings.md`.

## Layout

- `harness/` — virtual clock, asyncio dispatcher, recorder, replayer.
- `scenarios/` — seven runnable scenarios (basic record/replay,
  timeout, cancellation, partial failure, out-of-order completion,
  identical-call repeat cap, nested-call timing guard).
- `fixtures/` — batch manifests (tool calls, durations in ticks,
  faults) consumed by the scenarios.
- `components/shell_runner/` — shell parallel runner + manifest.
- `scripts/run_all.sh` — runs every scenario and every replay check.
- `scripts/clean_reproduce.sh` — clean-environment reproduction check.
- `outputs/` — unedited logs and traces from the two recorded runs
  (`run1`, `run2-clean`). Never edit these; verify with `SHA256SUMS`.
- `findings.md` — severity-ranked findings, each with a reproducible trigger.
- `citations.md` — primary sources for every specification-derived claim.
- `claims.md` — claim-to-evidence index (each claim → script + output + digest).
- `docs/index.html` — rendered findings page (self-contained; GitHub Pages reads `docs/`).

## Reproduce

```sh
bash scripts/run_all.sh outputs/run1
bash scripts/clean_reproduce.sh   # second run from a fresh copy; must match run1 byte-for-byte
bash scripts/verify_digests.sh    # verifies SHA256SUMS
```

Requirements: Python 3.11+ (standard library only), GNU bash 5.1+
(`wait -n -p`), `sha256sum`. No network access, no credentials, no
wall-clock assertions anywhere: all timing is in integer virtual ticks
for the asyncio dispatcher and in completion-order indices for the
shell runner.

## Trace schema

See `TRACE_SCHEMA.md`. One JSON object per line, keys sorted,
`seq` assigned in emission order, `tick` in virtual ticks. The
replayer asserts byte equality between the recorded and replayed trace.
