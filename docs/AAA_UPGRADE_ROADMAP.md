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
- [ ] Complete normal-speed playtests for all three characters; result data now records clear time, deaths, barrier use, and every boss phase duration/overdrive state.

Exit target: no progression blocker, no boss phase bypass, stable frame pacing at the
4,000-bullet stress target, and reproducible automated validation.

### P1 — Premium vertical slice

- [ ] Author distinct attack choreography for all three midboss and five final-boss phases.
- [ ] Give each boss phase a unique entrance, transition, destruction beat, and sound identity.
- [ ] Replace static combat cutouts with animated player, enemy, and boss presentation.
- [ ] Build multi-layer stage environments with route-specific landmarks and destruction states.
- [ ] Add onboarding, remappable controls, reduced-flash presets, bullet contrast controls, and assist options. (Core keyboard remapping, bullet contrast, and auto-fire are now available.)
- [ ] Add Korean and English localization infrastructure and remove player-facing hardcoded strings.
- [ ] Produce a mastered stage theme, boss suite, UI set, combat SFX set, and voice/event stingers.

Exit target: a first-time player can learn, finish, and understand the entire stage;
combat reads clearly under maximum density; presentation has no obvious placeholder.

### P2 — Full production content

- [ ] Expand to multiple stages with distinct enemies, hazards, bosses, music, and story beats.
- [ ] Add progression, difficulty modes, scoring depth, training/boss practice, replay data, and leaderboards.
- [ ] Establish content budgets, asset naming rules, localization tables, save migration, and telemetry events.
- [ ] Run structured balance sessions across novice, core, and expert player cohorts.

Exit target: target campaign length and replay value are met without recycling the
vertical slice as filler.

### P3 — Release readiness

- [ ] Validate Windows, macOS, Linux, controller hot-plug, display modes, and supported aspect ratios.
- [ ] Add crash reporting, privacy disclosures, accessibility review, store assets, credits, and legal review.
- [ ] Perform compatibility, soak, save-corruption, localization, and performance certification passes.
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

Performance and balance targets should be promoted from provisional to final only
after target hardware and player cohorts are defined.
