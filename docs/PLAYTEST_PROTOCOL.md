# Release Balance Playtest Protocol

This protocol turns the remaining human-balance milestone into a reproducible release gate. It supplements automated combat tests; it does not treat bots, accelerated route smokes, or developer runs as player evidence.

## Privacy and recruitment

- Recruit by bullet-hell experience only: **novice** (under 5 lifetime hours), **core** (5–100 hours), and **expert** (over 100 hours or a prior one-credit clear).
- Do not enter names, email addresses, account IDs, free-form comments, or hardware serials into the game or its JSON export. Assign a temporary paper/session code outside the build only when longitudinal comparison is required.
- Obtain test consent before play. Explain that settings, progression, run metrics, and replay inputs stay on the test machine; export occurs only when the researcher selects `EXPORT PLAYTEST JSON`.
- Export after each cohort batch because the Combat Archive intentionally retains only the latest 60 campaign runs. Store cohort exports separately and delete them according to the study's retention policy.

## Sample and counterbalancing

The minimum release sample is 12 unassisted runs per cohort, with at least three runs for each character and three runs for each catalog stage. Assisted runs remain useful for accessibility review but do not satisfy the balance sample.

Assign Story to novice, Normal to core, and Expert to expert for the primary gate. Rotate character and starting order with a Latin-square schedule so one vector or operation does not always receive the learning advantage. Every participant should:

1. Start from the normal title flow and complete or intentionally skip calibration.
2. Attempt the assigned route without coaching; record only observed blockers and a 1–5 readability rating on the external session sheet.
3. Review the result screen, then make one informed retry with the same character and difficulty.
4. For campaign-order testing, reach NULL TEMPEST and then HELIOS FORGE through the actual sequential unlocks at least once per cohort; do not edit save data to manufacture progression evidence.

Crashes, soft locks, lost input, unreadable attacks, progression failures, and save/replay corruption are release blockers regardless of aggregate balance results.

## Quantitative gates

The checked-in analyzer applies these provisional targets:

| Cohort | Difficulty | Clear-rate window | Maximum boss overdrive rate |
| --- | --- | ---: | ---: |
| Novice | Story | 50–95% | 70% |
| Core | Normal | 30–80% | 55% |
| Expert | Expert | 10–60% | 45% |

Across each cohort, cleared-run median scores for the three characters must remain within an 18% spread. At least 25% of runs must bank a nonzero RISK reserve; a lower value signals that the route decision is invisible, unattractive, or too punishing. These thresholds are hypotheses until the first full cohort pass; changes require a written reason and a new baseline, not silent edits after an unfavorable result.

## Running the aggregate gate

From the Combat Archive, export one or more JSON batches for each cohort, then run:

```bash
python3 tools/playtest_gate.py \
  --novice playtests/novice_01.json \
  --core playtests/core_01.json \
  --expert playtests/expert_01.json \
  --output playtests/release_balance_report.json \
  --require-ready
```

Flags may be repeated to combine batches. The output contains aggregate counts, medians, rates, and gate results only; it deliberately omits raw runs, timestamps, input paths, and participant identity. Exit code `0` means all cohort gates pass, `1` means valid evidence is not release-ready, and `2` means an input/export error.

Because each Combat Archive export is a rolling snapshot, adjacent files can overlap. The analyzer removes exact duplicate run records before counting sample coverage, so repeated exports cannot inflate a cohort. Raw exports and generated reports belong under the git-ignored `playtests/` directory and should move only to the study's access-controlled retention location.

## Decision record

For every candidate build, archive the aggregate report alongside the unsigned build manifest and record:

- build version and source revision;
- platform and controller model as aggregate coverage, without device serials;
- blocker count and disposition;
- any balance change made after the first cohort;
- the rerun report that demonstrates the change fixed the intended cohort without breaking the other two.

Human observation and the aggregate report must both pass before the roadmap's structured-balance milestone can be checked off.
