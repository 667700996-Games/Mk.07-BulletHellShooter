# PSYCHIC VECTOR

An original vertical bullet-hell game built with Godot 4.x and GDScript. Fly one of three escaped psychics through two cataloged operations: breach the rain-soaked Neon District, then ascend through the shattered NULL TEMPEST arcology and collapse the VOID ARCHON.

## Play

Open the project in Godot 4.5 or newer and press **F6/F5**, or run:

```sh
godot --path .
```

The internal canvas is 540×960 (the 1080×1920 vertical ratio) and scales to the desktop window.

| Action | Keyboard | Controller |
|---|---|---|
| Move | WASD / arrows | D-pad / left stick |
| Primary shot | Z / J | A / Cross |
| Focus attack | X / K | X / Square |
| Psychic barrier | C / L | B / Circle |
| Pause | Esc | Menu / Start |

Debug builds also provide F1 invincibility, F2 maximum power, F3 final boss, F4 bullet clear, and F5 stage restart.

The presentation combines original project-bound character, enemy, boss, and city key art with four-pose animated combat sheets for all three playable characters, all seven regular-enemy archetypes across both operations, and every mid/final boss, alongside procedural city layers, projectiles, particles, UI, sound effects, and synthesized title/stage/boss music. Player, enemy, and boss poses cross-fade from live movement, telegraph, attack, and overdrive state without moving their gameplay hitboxes. The adaptive audio fallback uses theme-transition fades, stereo-designed one-shots, isolated UI routing, priority-safe combat voices, music ducking, and tuned dynamics protection. Asset provenance is documented in `assets/ART_PROVENANCE.md`; no existing game characters, logos, stages, or proprietary patterns are reproduced.

Combat tuning is centralized in `resources/balance.json`; enemy health, movement, fire cadence, bullet speed/count/radius, and boss scaling can be adjusted without changing gameplay scripts. The `StageData` catalog binds each route to its timeline, background scene, post shader, localized operation briefing and route-time radio beats, music, enemy roster, boss metadata, practice phases, deterministic hazards, ending data, and seed policy. Neon District and NULL TEMPEST each have their own grade roster, environment, score table, midboss, five-phase final boss, story transmissions, and music signature. Enemy bullets use one batched MultiMesh renderer with an SDF readability shader.

Campaign and boss-practice flows begin at a route selector. Neon District is initially available; clearing it unlocks NULL TEMPEST, whose campaign clear opens a localized character-specific ending before the after-action report. Campaign clears award data-driven performance medals for no-miss, no-barrier, and on-time boss-phase play. Grazes also charge a bounded RISK reserve that is automatically banked at the midboss and final-boss gates, while a life loss or barrier use forfeits the current reserve. Save version 13 keeps those results, per-stage Story/Normal/Expert records, and progression while migrating older Neon-only saves. The Combat Archive filters statistics and replays by route as well as difficulty. The title menu includes bilingual credits, asset-production notes, and an explicit disclosure of the build's local-only records, replay storage, and manual JSON exports.

A separate checksummed session journal retains at most 12 completed session markers plus the current marker. If the previous marker was never closed, the next launch reports an inferred abnormal exit; it does not claim to capture a native crash or stack trace. Settings and session files stay in the local application-data folder, and the diagnostic JSON is created only from the Combat Archive's manual export action. It contains timestamps, local sequence numbers, and exit reasons, but no player identity, hardware identifier, file-system path, or network data. This build performs no diagnostic upload.

## Validation

```sh
bash tools/validate.sh

# Or run individual checks:
python3 tools/release_candidate.py check
python3 tools/release_candidate.py self-test
python3 tools/playtest_gate_test.py
godot --headless --editor --path . --quit
godot --headless --path . --script res://tools/platform_release_audit.gd
godot --headless --path . --script res://tools/session_diagnostics_test.gd -- --smoke-session-diagnostics
godot --headless --path . --quit-after 120 res://tests/boss_signature_registry_smoke.tscn
godot --headless --path . --script res://tools/risk_route_test.gd
godot --headless --path . --script res://tools/ui_layout_audit.gd
godot --headless --path . --quit-after 1800 -- --smoke-stage
godot --headless --path . --quit-after 1800 -- --smoke-tempest
godot --headless --path . --quit-after 600 -- --smoke-ui
godot --headless --path . --quit-after 600 -- --smoke-combat
godot --headless --path . --quit-after 600 -- --benchmark-bullets
godot --path . --quit-after 600 -- --benchmark-render
godot --path . --quit-after 600 -- --capture-enemy-animation
godot --path . --quit-after 600 -- --capture-boss-animation
```

The production quality plan and milestone gates are tracked in `docs/AAA_UPGRADE_ROADMAP.md`. Human balance sessions use the privacy-safe protocol and aggregate release gate in `docs/PLAYTEST_PROTOCOL.md`; automated runs do not count as player evidence.

The Combat Archive keeps a local vault of up to 12 campaign replays, filters them by stage and difficulty, and allows three favorites to be pinned against automatic eviction. Each replay is stored as an independently checksummed, crash-recoverable file so one corrupt entry cannot invalidate the rest. Replay version 4 binds stage identity, performance-medal bonuses, and both RISK-bank checkpoints into result verification, while versions 1–3 remain playable through compatibility rules. Playback uses deterministic encounter and hazard seeds, verifies stage and result metrics at completion, and never modifies campaign records.

The validation suite runs both complete timelines at 90× simulation speed. Regular combat escalates across each three-minute route, with an untimed midboss gate and the final boss arriving when the resumed route clock reaches three minutes. It also checks hazard warning/collision determinism, injectable boss signatures, route-risk scoring, route unlocks, stage-isolated records, save migration, replay-vault recovery, corrupt session-journal recovery, clean/abnormal exit inference, privacy-safe manual diagnostic export, bilingual 540×960 UI layout states, and 4,000-bullet throughput. A static platform contract verifies the Windows, macOS, and Linux export targets, portrait stretch/window defaults, project icon, and keyboard/controller action parity. Matching Godot export templates, native builds, signing, hardware input, and platform certification remain separate release checks. Existing exports can be normalized into deterministic, versioned unsigned candidate archives and verified against embedded and outer SHA-256 manifests; the build/signing handoff is documented in `docs/RELEASE_CANDIDATES.md`.

Headless validation intentionally builds and verifies the complete PCM SFX library but does not instantiate a realtime music playback device. This keeps no-output CI deterministic and avoids the engine's dummy-audio playback cleanup path; normal desktop runs retain the adaptive music generator.
