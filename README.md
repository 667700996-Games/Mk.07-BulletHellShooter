# PSYCHIC VECTOR

An original vertical bullet-hell game built with Godot 4.x and GDScript. Fly one of three escaped psychics through the rain-soaked Neon District, destroy the three-phase ARBITER-03 platform, and break all five phases of the SERAPH EXECUTOR.

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

The presentation combines original project-bound character, enemy, boss, and city key art with procedural city layers, projectiles, particles, UI, sound effects, and synthesized title/stage/boss music. Asset provenance is documented in `assets/ART_PROVENANCE.md`; no existing game characters, logos, stages, or proprietary patterns are reproduced.

Combat tuning is centralized in `resources/balance.json`; enemy health, movement, fire cadence, bullet speed/count/radius, and boss scaling can be adjusted without changing gameplay scripts. Enemy bullets use one batched MultiMesh renderer with an SDF readability shader.

## Validation

```sh
godot --headless --editor --path . --quit
godot --headless --path . --quit-after 1800 -- --smoke-stage
godot --headless --path . --quit-after 600 -- --smoke-ui
godot --headless --path . --quit-after 600 -- --smoke-combat
godot --headless --path . --quit-after 600 -- --benchmark-bullets
godot --path . --quit-after 600 -- --benchmark-render
```

The stage smoke test runs the complete five-minute timeline at 90× simulation speed. Regular combat escalates across a two-minute route, with a compact midboss encounter at one minute and the final boss at two minutes. The render benchmark layers 4,000 live bullets, 160 erase sparks, and 320 explosion particles, then reports measured frame time. Desktop export presets are included for Windows, macOS, and Linux; matching Godot export templates are required to produce binaries.
