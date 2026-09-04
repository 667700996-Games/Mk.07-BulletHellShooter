# PSYCHIC VECTOR production roadmap

The current build is a strong arcade vertical slice. The target is a release-quality
game with production depth and polish; "AAA" is treated as a quality bar, not a label
that can be reached by visual effects alone.

## Quality gates

A milestone is complete only when its acceptance tests pass, its content has been
played at normal speed, and no placeholder-quality asset remains in that milestone's
scope.

### P0 — Reliable combat foundation

- [x] Put the three-minute route, five-enemy wave rules, and midboss gate in an editable timeline resource.
- [x] Make every boss phase HP-gated; use phase duration for escalating overdrive pressure instead of automatic clears.
- [x] Replace unrestricted boss pattern rolls with a shuffled, no-repeat deck.
- [x] Add readable boss attack telegraphs and snapshot aimed attacks at warning time.
- [x] Cover balance rules, UI flow, combat behavior, the full route, and bullet throughput with automated smoke tests.
- [x] Run the validation suite on pushes and pull requests.
- [ ] Hold the 60 FPS frame budget at the 4,000-bullet destruction stress target on defined minimum hardware. (The deterministic GUI benchmark measures about 9.6 ms / 104 FPS on the Apple M4 development machine and now fails above 16.667 ms; minimum-spec hardware remains to be defined and certified.)
- [ ] Complete normal-speed playtests for all three characters. The local Combat Archive now retains the latest 60 campaign runs, separates difficulty/character cohorts, measures real session time, deaths, barrier use, score, and boss overdrive exposure, and exports privacy-safe JSON. A checked-in protocol and aggregate-only gate enforce sample, character/stage coverage, clear-rate, overdrive, score-spread, and RISK-engagement targets without double-counting overlapping exports; novice/core/expert human sessions remain to be run.

Exit target: no progression blocker, no boss phase bypass, stable frame pacing at the
4,000-bullet stress target, and reproducible automated validation.

### P1 — Premium vertical slice

- [x] Author distinct attack choreography for all three midboss and five final-boss phases.
- [x] Give each boss phase a unique entrance, transition, destruction beat, and sound identity.
- [x] Replace static combat cutouts with animated player, enemy, and boss presentation. (All three playable characters, all seven regular-enemy visual archetypes across both operations, and every mid/final boss now use authored four-pose combat sheets with state-driven cross-fades over fixed hitboxes. Bosses select neutral, telegraph, attack-release, and overdrive/damaged frames while retaining phase-specific procedural transitions and readability effects.)
- [x] Build multi-layer stage environments with route-specific landmarks and destruction states.
- [ ] Add onboarding, remappable controls, reduced-flash presets, bullet contrast controls, and assist options. (A skippable first-run tutorial now verifies movement, primary fire, focus fire, and barrier use with the player's live bindings and can be replayed from the combat briefing. Keyboard/gamepad remapping, controller hot-plug feedback, contrast control, always-visible hitbox, auto-fire, auto-barrier, and Standard/Comfort/Guardian presets are available; assisted runs cannot submit records. External accessibility review remains.)
- [x] Add Korean and English localization infrastructure and remove player-facing hardcoded strings.
- [ ] Produce a mastered stage theme, boss suite, UI set, combat SFX set, and voice/event stingers. (The original adaptive fallback now has distinct melodic theme signatures, seamless transition fades, stereo-designed one-shots, a dedicated UI bus, priority-safe combat voices, music ducking, and tuned compressor/hard-limiter chains. All 23 SFX are PCM-validated in CI and headless tests no longer instantiate a dummy realtime music playback. Externally authored/mastered music, final SFX recording, and voice remain.)

Exit target: a first-time player can learn, finish, and understand the entire stage;
combat reads clearly under maximum density; presentation has no obvious placeholder.

### P2 — Full production content

- [ ] Expand to multiple stages with distinct enemies, hazards, bosses, music, and story beats. (Neon District and NULL TEMPEST are now complete catalog entries with separate environments/post effects, original three-grade combat-sheet rosters, music signatures, deterministic route hazards, original mid/final boss art, independently verified 3+5 phase encounters, localized operation briefings, four non-blocking route-time radio beats per stage, and a final-clear ending with three character epilogues. Boss support attacks and phase-transition visuals now use a tested registry where new signature subclasses can be injected without editing the boss controller. More campaign stages remain.)
- [ ] Add progression, difficulty modes, scoring depth, training/boss practice, replay data, and leaderboards. (The route selector, sequential unlocks, result-screen `NEXT OPERATION` handoff, save-v12 progression, per-stage Story/Normal/Expert records, three data-driven performance medals, and a bounded graze-charged RISK reserve with two boss-gate banks are implemented with visible HUD/result feedback. The stage-filtered Combat Archive, stage-bound practice, and 12-entry replay vault now verify the checkpoint units in replay v4 while retaining v1-v3 compatibility. Online leaderboards, further scoring routes, and the complete campaign progression arc remain.)
- [ ] Establish content budgets, asset naming rules, localization tables, save migration, and telemetry events. (Versioned save migration, validated stage manifests, bilingual tables, local run/boss metrics, stage-aware aggregate archive data, user-triggered JSON export, and a CI content gate for stable IDs, route budgets, hazard isolation, boss presentation sheets, and localization parity are implemented; telemetry policy, consent, and production-scale per-category content budgets remain.)
- [ ] Run structured balance sessions across novice, core, and expert player cohorts. (`docs/PLAYTEST_PROTOCOL.md` and `tools/playtest_gate.py` define and test the release decision, but no human evidence is fabricated or checked off.)

Exit target: target campaign length and replay value are met without recycling the
vertical slice as filler.

### P3 — Release readiness

- [ ] Validate Windows, macOS, Linux, controller hot-plug, display modes, and supported aspect ratios. (An automated platform contract now gates all three desktop presets, architecture and release feature tags, production-only resource filters, the 540×960 `canvas_items`/`keep` display contract, windowed/fullscreen settings, the project icon, and keyboard/controller action parity. Native exports, signing/notarization, hot-plug hardware, alternate monitors, and platform certification remain.)
- [ ] Add crash reporting, privacy disclosures, accessibility review, store assets, credits, and legal review. (A bilingual in-build Credits & Data screen now documents Godot, AI-assisted raster production, runtime-synthesized audio, local save/replay/session-journal storage, manual JSON exports, and the absence of network telemetry. A bounded local journal detects a missing clean-exit marker and offers an identity-free manual diagnostic export, but it is explicitly not native crash capture. Native crash dumps/symbolication, store assets, external accessibility review, and formal privacy/legal review remain.)
- [ ] Perform compatibility, soak, save-corruption, localization, and performance certification passes. (Version 13 saves use integrity hashes, verified staging writes, a last-known-good backup, automatic recovery, and legacy migration. Automated tests now cover save corruption, progression and per-stage scores, medal and RISK migration/anti-forgery rules, both stage-manifest contracts and full routes, deterministic hazards, stage-aware run migration, replay-vault capacity/pinning/filtering, v1-to-v4 replay compatibility, unavailable-stage isolation, individual replay corruption, interrupted replay promotion/rollback, bounded session-journal corruption/recovery and clean-exit inference, bilingual key/format-token parity, and 64 major-screen layout states across both languages and effect profiles; multi-platform soak and external certification remain.)
- [ ] Build signed release candidates and a rollback-capable patch pipeline. (A pinned SemVer/build contract now validates the Windows x86_64, macOS universal, and Linux x86_64 presets against project and CI engine metadata. A manual, read-only CI workflow provisions matching templates, runs all validation, exports every target, packages byte-deterministic unsigned archives, strictly re-verifies them, and uploads a 14-day artifact. Embedded/outer SHA-256 manifests bind source configuration and both workflows; self-tests reject contract/pipeline drift and tampering. Owned platform identities, signing/notarization credentials, protected long-term artifact hosting, post-signing provenance, staged rollout, and delta-patch rollback remain external production gates.)

Exit target: zero release-blocking defects, platform builds are reproducible, and the
game can be supported after launch.

## Current measurement targets

| Area | Gate |
|---|---|
| Route | Final boss appears at 180 seconds of route time; midboss time is excluded |
| Boss rules | Phase change occurs only at zero phase HP |
| Readability | Every boss attack has a visible warning; no immediate same-pattern repeat |
| Score routing | RISK reserve caps at 40; boss-gate banks cap at 60,000 total; death/barrier forfeits unbanked units |
| Performance | 4,000-bullet update benchmark remains below the agreed frame budget on target hardware |
| Regression | Parser, UI, combat, both full routes, and bullet benchmark jobs pass in CI |
| UI layout | All major 540×960 screens remain in bounds and focusable in English/Korean and standard/reduced effects |
| Platform config | Windows x86_64, macOS universal, and Linux x86_64 presets satisfy the static release contract; native build/hardware certification remains manual |
| Accessibility | Core actions are remappable and high-density combat remains readable with reduced effects |
| Playtest data | Latest 60 campaign runs are summarized by difficulty and character; exported files contain gameplay metrics only |
| Human balance gate | 12 unassisted runs per novice/core/expert cohort, with character/stage coverage and the provisional release thresholds in `docs/PLAYTEST_PROTOCOL.md` |
| Save integrity | A modified or incomplete primary save is rejected and the last valid backup is restored |
| Replay integrity | Every compatible vault entry must reproduce stage, score, losses, barriers, time, and boss-phase count exactly or report a desync; one corrupt or unavailable-stage entry cannot invalidate others |
| Session diagnostics | Missing clean markers are inferred on next launch; history is capped at 12; corrupt primary falls back safely; export is manual, local, and identity-free |

Performance and balance targets should be promoted from provisional to final only
after target hardware and player cohorts are defined.
