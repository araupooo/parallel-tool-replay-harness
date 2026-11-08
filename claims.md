# Claim-to-evidence index

Each claim links to the runnable script that produces it, the unedited log that records it, and the SHA-256 digests of the log and trace files. Verify any digest with `bash scripts/verify_digests.sh`.

| Claim | Statement | Script | Output log | Log SHA-256 | Trace SHA-256 |
|---|---|---|---|---|---|
| C-01 | All seven asyncio batches record and replay byte-identically, and all four naive-variant traces replay byte-identically. | `scripts/run_all.sh (scenarios/run_*.py, harness/replayer.py)` | `outputs/run1/replay-batch-basic.log` | `250a8c632f6ffe87…` | `batch-basic.trace.jsonl`: `190c6b631f84181a…` |
| C-02 | A per-call deadline cuts the slow call at tick 5; the batch ends at tick 6 on the siblings' schedule (status partial_failure). | `scenarios/run_timeout.py` | `outputs/run1/timeout.log` | `2d34a1b54ebdb147…` | `batch-timeout.trace.jsonl`: `a67e6f5cfdfa4f69…`<br>`batch-timeout-naive.trace.jsonl`: `923221cc90ded22d…` |
| C-03 | Batch cancellation at tick 4 reports a result for every issued call (3/3): the quick call completed, the two in-flight calls are reported cancelled. | `scenarios/run_cancellation.py` | `outputs/run1/cancellation.log` | `83b23f6ed82501e5…` | `batch-cancel.trace.jsonl`: `5c7d2e88368f5de0…`<br>`batch-cancel-naive.trace.jsonl`: `f7c3cab9f1be78fd…` |
| C-04 | A failing call is isolated: reported with is_error, both siblings complete, batch status partial_failure, 3/3 results. | `scenarios/run_partial_failure.py` | `outputs/run1/partial-failure.log` | `7e6fac0005ef63ee…` | `batch-partial.trace.jsonl`: `658c96c351dd9bad…`<br>`batch-partial-naive.trace.jsonl`: `3a34dc737d33c551…` |
| C-05 | Out-of-order completions (fast, mid, slow) are matched to calls by tool_call_id; position-based matching misattributes all three results. | `scenarios/run_out_of_order.py` | `outputs/run1/out-of-order.log` | `2564ceedd7b3e2f6…` | `batch-reorder.trace.jsonl`: `92b7959b3bd18a5d…` |
| C-06 | The fourth identical call in one turn is refused without running (cap 3); it is still reported (4/4 results). | `scenarios/run_repeat_cap.py` | `outputs/run1/repeat-cap.log` | `a8b8a5d6bb63bd53…` | `batch-repeat.trace.jsonl`: `cc1009b2b26ccd8b…` |
| C-07 | The nested-call timing guard emits no nested timing events; without the guard the nested interval (ticks 2..5) lies strictly inside the outer interval (ticks 0..6). | `scenarios/run_nested_timing.py` | `outputs/run1/nested-timing.log` | `76aa64d43bcbcf5b…` | `batch-nested.trace.jsonl`: `5b17ddcdb9115cd3…`<br>`batch-nested-unguarded.trace.jsonl`: `0a39af566402a6fa…` |
| C-08 | The shell runner's four real parallel processes complete in the manifest's declared order with matching exit codes and output digests; its trace replays byte-identically. | `components/shell_runner/run_parallel.sh` | `outputs/run1/shell.log` | `d2bccd7c2ed797c8…` | `shell/batch-shell.trace.jsonl`: `cd7a310e56bd06be…` |
| C-09 | A clean-environment reproduction from a fresh copy produces outputs byte-identical to the first run. | `scripts/clean_reproduce.sh` | `outputs/run2-clean/clean-reproduce.log` | `75221eb105e94f86…` | — |
| C-10 | The harness rules match the inspected reference implementation (CorbanuTerminal parallel.rs, commit 7b5b368f): parallel gate, cancellation reporting, nested timing guard, 3-call repeat cap. | `source inspection (see citations.md section 4)` | `findings.md` | `8811ccc7257d1866…` | — |

Full 64-hex digests are in `SHA256SUMS` and `evidence.json`.
