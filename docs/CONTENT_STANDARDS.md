# Production Content Standards

`tools/content_audit.gd` is the authoritative automated gate for campaign content. Every resource in `StageManager.STAGE_CATALOG` must pass it before a build is considered releasable. Source payload ceilings and naming/reference rules are independently enforced by `tools/content_budget_audit.py` under the reviewed contract in `resources/content_budgets.json`; see `docs/CONTENT_BUDGETS.md`.

## Stable naming and identity

- Stable IDs and localization keys use lowercase `snake_case`: ASCII letters and digits, no spaces, dashes, uppercase letters, or repeated/trailing underscores.
- Stage IDs additionally end in a two-digit campaign sequence, for example `neon_district_01`.
- Stage IDs and deterministic seed salts are unique across the catalog. Salts are positive integers and must never be changed after a stage ships because replay determinism depends on them.
- Boss IDs, route-enemy IDs, hazard IDs, and boss phase localization keys are unique across all catalog stages. Renaming any shipped ID is a save/replay schema migration, not an editorial cleanup.
- Catalog references must resolve exactly. Runtime fallbacks do not make invalid authored IDs acceptable.

## Route and encounter budgets

| Contract | Required value |
| --- | ---: |
| First wave | `5.0s` route time |
| Final boss spawn | `180.0s` route time |
| Enemies per wave | `5` |
| Early grade-3 enemies | `5` |
| Middle grade-3 enemies | `4` |
| Late grade-3 enemies | `3` |
| Midboss phases | `3` |
| Final boss phases | `5` |
| Total expected boss phases | `8` |
| Expected waves per route | `24..32` |
| Expected route enemies | `120..160` |

Timeline markers must be strictly ordered. The midboss may pause wall-clock play, but it does not advance the 180-second route clock.

Campaign preflight is ordered `stage -> difficulty -> character`. Boss practice is ordered `boss -> difficulty -> character`, applies the selected difficulty profile, and begins the complete final-boss encounter at phase 01. Character selection must not expose a boss-phase skip. Easy (the save-compatible internal `story` profile), Normal, and Expert start with 5, 3, and 2 lives respectively; all profiles start each life with five Psychic Barriers, and losing a life restores that stock to five.

The wave budget is calculated using the same schedule semantics as gameplay: the first wave occurs at `5.0s`, each spawned wave selects the interval for its current route section, and the final-warning boundary stops further waves. With the current authored timelines this predicts 29 waves/145 enemies for Neon District, 28 waves/140 enemies for Null Tempest, and 29 waves/145 enemies for Helios Forge.

Every stage roster is audited independently. Grade 3 must be the smallest, fastest-firing unit and emit one zero-spread three-shot straight burst. Grade 2 must be the middle size/cadence/durability tier and emit one eight-shot radial attack. Grade 1 must be largest and slowest, retain at least twice grade-2 durability, and emit three delayed ten-shot circles. Projectile speeds must descend in the same grade-3/2/1 order. This prevents a later stage from silently reintroducing boss-like regular-enemy patterns behind a familiar grade silhouette.

## Hazard readability and encounter isolation

- Route hazards use six explicit mechanics. Neon/Tempest hazards provide fixed lightning lanes, constant-velocity debris, and expanding shock rings; Helios Forge adds arena-sweeping solar flares, gravity-accelerated molten fragments, and contracting rotating corona waves. A route-specific name may not be mapped to another route's collision behavior.
- Every route hazard has at least `1.0s` of warning before it becomes dangerous.
- The audit models the entire emitted effect lifetime, not only the authored scheduling window. Debris lifetime includes its warning, burst stagger, playfield traversal, and cleanup tail.
- A hazard lifecycle may not include the midboss entry instant.
- A hazard lifecycle may not intersect the final warning-to-spawn interval. Boss encounters own those readability windows exclusively.
- A stage may schedule at most `24` hazard triggers across all of its hazard windows. This counts emitted triggers rather than resource entries; the current Null Tempest route schedules 9, Helios Forge schedules 8, and Neon District schedules 0.

## Route radio beats

- Each campaign stage contains `3..5` localized `StageRadioEvent` resources ordered by strictly increasing route time.
- The required narrative beats are an opening transmission within 15 seconds of the first wave, a transmission 2–20 seconds before the midboss, a post-midboss transmission within 20 route seconds of resumption, and a transmission 2–20 seconds before the final warning.
- Event IDs are globally unique and stable. Speaker and message keys must resolve in both English and Korean.
- Authored display windows must finish before the midboss entry or final-warning transition they precede.
- Radio scheduling uses route time, not wall-clock session time. The runtime must suspend admission while the midboss gate is active and must never fire the same event ID twice.
- Radio presentation is non-interactive, automatically exits, and scales its motion and luminous pulse with the existing screen-shake and flash accessibility settings.

## Boss combat budgets

Boss HP limits apply to authored phase resources before the global runtime `boss_hp_scale` multiplier. They protect relative encounter composition while allowing the global difficulty balance to be tuned independently.

| Contract | Midboss | Final boss |
| --- | ---: | ---: |
| HP per phase | `1100..2600` | `1700..4500` |
| Total encounter HP | `4000..6500` | `12000..17000` |
| Fire interval per phase | `0.40..0.85s` | `0.24..0.75s` |
| Attack-sequence entries per phase | `4..8` | `4..8` |
| Distinct patterns per phase | `2..4` | `2..4` |

The combined authored midboss and final-boss HP for one stage must be `16000..22000`. The current totals are 16,950 for Neon District, 19,950 for Null Tempest, and 21,950 for Helios Forge. Every sequence entry must belong to the phase's declared pattern set, exercise at least two distinct patterns, and avoid immediate duplicate attacks.

### Boss signature extension contract

- Every authored phase `signature_id` must resolve in `BossSignatureRegistry`; unknown signatures fail boss setup and the campaign content audit.
- Shipped signatures are declarative `BossSignatureBehavior` profiles. A new code-defined signature subclasses that behavior, overrides `emit_support` and/or `draw_transition`, and is registered on a registry passed to `BossController.set_signature_registry()` before setup. Adding one does not require a boss-controller edit.
- Support attacks receive only the snapshotted attack context: bullet manager, origin, target, primary pattern, attack cursor, rotation, difficulty, and accent. Implementations must not read wall-clock time or introduce an unseeded random source because replay determinism depends on identical output for identical contexts.
- Transition drawing is presentation-only and may not mutate combat state. Unknown runtime IDs fail closed instead of falling back to another attack.
- `tests/boss_signature_registry_smoke.tscn` protects all 16 shipped signatures' trigger, bullet-count, speed/modifier, deterministic-output, and custom-injection contracts.

## Route-risk scoring

- Campaign and replay routes charge one RISK unit per graze to a hard cap of `40`; boss practice disables this route entirely.
- Entering the midboss banks each held unit for `500` points. Entering the final boss banks each held unit for `1000` points and closes further charging. The maximum route bonus is therefore `60,000`.
- A life loss or barrier activation forfeits every currently unbanked unit. Ordinary graze score and combo behavior remain independent.
- The overlay reads the same authored capacity as `ScoreManager`, remains outside the top HUD and boss-health rectangles, ignores input, and exposes charge, bank, and loss feedback.
- Replay v4 records the total bonus and the units banked at both checkpoints. The checksum canonicalizes JSON number arrays, while v1-v3 comparisons remove score layers that did not exist in those formats.

## Boss presentation assets

- Boss key art must be at least `512x512` pixels.
- A combat sheet is a 2x2 pose atlas and must be at least `512x512` pixels.
- Both combat-sheet dimensions must be even, yielding four integer-sized cells of at least `256x256` pixels.
- Both key art and combat art must be explicit resource references; missing or unresolved textures fail the audit.

## Campaign ending

- A multi-stage campaign has exactly one authored ending, owned by the final catalog stage.
- The ending is eligible only for a successful campaign clear; failure, practice, replay, and non-final stages proceed directly to their normal result flow.
- Ending eyebrow, title, body, final transmission, and all three character epilogues must resolve in both supported languages.
- The ending hands the already-persisted run result to the after-action screen. It must not re-enter run-finalization or write the replay/save a second time.
- Reduced-effects profiles reveal all copy immediately and suppress decorative motion.

## Credits and local-data disclosure

- The title flow exposes the bilingual Credits & Data screen without requiring a completed run.
- The disclosure identifies engine and media-production sources, lists settings/progression/play-record/replay/session-journal storage, and distinguishes automatic local persistence from user-triggered JSON exports.
- The current build makes no network transmission and contains no online telemetry API. This factual build disclosure does not replace formal privacy, attribution, or platform legal review.

## Session diagnostics

- `SessionDiagnostics` writes a checksummed primary journal through a verified staging file and keeps a synchronized last-known-good backup.
- The journal retains at most 12 completed session markers plus the current marker. A marker contains only a local sequence number, start/end Unix timestamps, a clean-exit boolean, an allow-listed exit reason, and the non-player release candidate ID needed for build correlation. Schema-v1 entries migrate without loss and receive the explicit `legacy_unknown` build marker.
- A missing clean-exit marker is reported on the next launch as an inferred abnormal termination. It is not described as native crash capture and contains no stack trace, memory dump, hardware identifier, user identity, or local path.
- Window-close and normal scene-tree teardown paths persist a clean marker. Process kills and native crashes cannot run that callback, which is the intended detection boundary.
- Corrupt or oversized journals fail closed. A valid backup is preferred; if neither copy is valid, a fresh journal is created and the reset is exposed without interpreting corrupt bytes as a crash.
- Diagnostic JSON is created only by the explicit Combat Archive action, remains local, and contains no network transport. Its history is subject to the same retention bound as the journal.

## Localization

- English and Korean catalogs contain exactly the same keys, with no empty translations.
- Every stage title/subtitle/result/pause key, operation-briefing eyebrow/situation/objective/transmission key, route-radio key, campaign-ending/character-epilogue key, boss name/subtitle/defeat key, and boss phase key referenced by catalog content must exist in both languages.
- Runtime hazard announcement keys are also mandatory.
- `printf` placeholder sequences must match between languages so translated UI strings remain format-safe.

## Running the gate

```bash
godot --headless --editor --path . --quit
python3 tools/content_budget_audit.py
godot --headless --path . --script res://tools/content_audit.gd
godot --headless --path . --script res://tools/session_diagnostics_test.gd -- --smoke-session-diagnostics
```

Success prints one `CONTENT_AUDIT_OK` summary and exits with status 0. The summary includes aggregate `waves`, `enemies`, `hazard_triggers`, `boss_phases`, and independently checked `grade_rosters` counts so CI logs expose content-volume drift. Violations print a `CONTENT_AUDIT_FAILED` summary with the same counters followed by contextual `CONTENT_AUDIT_ERROR` lines and exit nonzero. `tools/validate.sh` runs the audit before smoke and benchmark suites.
