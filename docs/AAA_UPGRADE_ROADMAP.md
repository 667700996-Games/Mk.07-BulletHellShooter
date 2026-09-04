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
- [ ] Complete normal-speed playtests for all three characters. The local Combat Archive now retains the latest 60 campaign runs, separates difficulty/character cohorts, measures real session time, deaths, barrier use, score, and boss overdrive exposure, and exports privacy-safe JSON; novice/core/expert human sessions remain to be run.

Exit target: no progression blocker, no boss phase bypass, stable frame pacing at the
4,000-bullet stress target, and reproducible automated validation.

### P1 — Premium vertical slice

- [x] Author distinct attack choreography for all three midboss and five final-boss phases.
- [x] Give each boss phase a unique entrance, transition, destruction beat, and sound identity.
- [ ] Replace static combat cutouts with animated player, enemy, and boss presentation. (All three playable characters and all four regular-enemy visual archetypes now use authored four-pose combat sheets with state-driven cross-fades over fixed hitboxes. Enemies select idle, left-bank, right-bank, and firing/recoil frames from live velocity and attack state. Procedural boss hover, banking, recoil, deformation, and damage states remain active; authored boss frame/skeletal animation remains.)
- [x] Build multi-layer stage environments with route-specific landmarks and destruction states.
- [ ] Add onboarding, remappable controls, reduced-flash presets, bullet contrast controls, and assist options. (A skippable first-run tutorial now verifies movement, primary fire, focus fire, and barrier use with the player's live bindings and can be replayed from the combat briefing. Keyboard/gamepad remapping, controller hot-plug feedback, contrast control, always-visible hitbox, auto-fire, auto-barrier, and Standard/Comfort/Guardian presets are available; assisted runs cannot submit records. External accessibility review remains.)
- [x] Add Korean and English localization infrastructure and remove player-facing hardcoded strings.
- [ ] Produce a mastered stage theme, boss suite, UI set, combat SFX set, and voice/event stingers. (Adaptive route/boss intensity mixing and eight phase cues are implemented; authored mastered assets and voice remain.)

Exit target: a first-time player can learn, finish, and understand the entire stage;
combat reads clearly under maximum density; presentation has no obvious placeholder.

### P2 — Full production content

- [ ] Expand to multiple stages with distinct enemies, hazards, bosses, music, and story beats.
- [ ] Add progression, difficulty modes, scoring depth, training/boss practice, replay data, and leaderboards. (Story/Normal/Expert modes preserve the original Normal curve while varying pressure and starting lives, with isolated records. Final-boss practice supports selecting any of five starting phases and cannot overwrite campaign records. The latest campaign run now records quantized analog input, action state, frame timing, and deterministic encounter seeds; compatible playback verifies its final metrics and can never submit records. Progression, online leaderboards, additional stages, and a multi-replay library remain.)
- [ ] Establish content budgets, asset naming rules, localization tables, save migration, and telemetry events. (Versioned save migration, validation, bilingual tables, local run/boss metrics, aggregate archive views, and user-triggered JSON export are implemented; production telemetry policy and consent are not.)
- [ ] Run structured balance sessions across novice, core, and expert player cohorts.

Exit target: target campaign length and replay value are met without recycling the
vertical slice as filler.

### P3 — Release readiness

- [ ] Validate Windows, macOS, Linux, controller hot-plug, display modes, and supported aspect ratios.
- [ ] Add crash reporting, privacy disclosures, accessibility review, store assets, credits, and legal review.
- [ ] Perform compatibility, soak, save-corruption, localization, and performance certification passes. (Version 8 saves now use integrity hashes, verified staging writes, a last-known-good backup, automatic recovery, and an automated corruption/interrupted-write test while preserving v6/v7 migration; multi-platform soak and external certification remain.)
- [ ] Build signed release candidates and a rollback-capable patch pipeline.

Exit target: zero release-blocking defects, platform builds are reproducible, and the
game can be supported after launch.

## Current measurement targets

| Area | Gate |
|---|---|
| Route | Final boss appears at 180 seconds of route time; midboss time is excluded |
| Boss rules | Phase change occurs only at zero phase HP |
| Readability | Every boss attack has a visible warning; no immediate same-pattern repeat |
| Performance | 4,000-bullet update benchmark remains below the agreed frame budget on target hardware |
| Regression | Parser, UI, combat, route, and bullet benchmark jobs pass in CI |
| Accessibility | Core actions are remappable and high-density combat remains readable with reduced effects |
| Playtest data | Latest 60 campaign runs are summarized by difficulty and character; exported files contain gameplay metrics only |
| Save integrity | A modified or incomplete primary save is rejected and the last valid backup is restored |
| Replay integrity | Compatible last-run playback must reproduce score, losses, barriers, time, and boss-phase count exactly or report a desync |

Performance and balance targets should be promoted from provisional to final only
after target hardware and player cohorts are defined.
