# Art provenance

The raster key art in this directory was generated for **PSYCHIC VECTOR** with OpenAI's built-in image generation tool on 2026-09-02. It is original, project-bound material and was not sourced from an existing game or asset pack.

## Shared direction

Built-in generation mode: **new image generation**, followed by a background-removal edit for transparent gameplay cutouts.

Shared prompt direction:

> Premium 2D vertical bullet-hell key art for an original near-future East Asian neon megacity setting. Polished hand-painted Japanese arcade illustration, crisp readable silhouette, high contrast, dramatic psychic energy, no text, no logo, no watermark, no existing IP.

The three playable characters add these original design directions:

- `characters/kira_voss_keyart.png`: balanced cyan/violet vector psychic, stable mid-range combat silhouette.
- `characters/dae_ryu_keyart.png`: power-focused amber/coral gravity psychic, heavier close formation.
- `characters/mina_zero_keyart.png`: speed-focused emerald/cyan psychic, agile wide-shot silhouette.

Combat animation sheets were derived non-destructively from those three character designs with the same built-in image generation tool on 2026-09-04:

- `characters/kira_voss_combat_sheet.png`
- `characters/dae_ryu_combat_sheet.png`
- `characters/mina_zero_combat_sheet.png`

Each sheet contains a consistent 2×2 set—idle hover, left bank, right bank, and focused attack—followed by a background-extraction pass that preserves genuine RGBA transparency. Runtime code cross-fades these authored poses while retaining a fixed gameplay hitbox.

Boss variants:

- `bosses/arbiter_03_keyart.png`: colossal top-down aerial combat platform with an original segmented military silhouette.
- `bosses/seraph_executor_keyart.png`: original humanoid psychic weapon with a blade-like halo and magenta/cyan energy.

Enemy variants:

- `enemies/neon_drone.png`: compact surveillance/attack drone.
- `enemies/psychic_trooper.png`: airborne armored psychic trooper.
- `enemies/assault_mech.png`: heavy urban assault mech.
- `enemies/vector_gunship.png`: top-down military vector gunship.

Environment:

- `backgrounds/title_megacity.png`: vertical rain-soaked neon megacity matte painting with a distant control spire and layered elevated roads.

Transparency edit direction:

> Remove only the studio-gradient background and replace it with genuine transparency. Preserve identity, pose, clothing, energy, floating devices, colors, and edge quality. Clean alpha, no crop, no additions, no text, no watermark.

The project additionally applies procedural shaders, particles, color grading, parallax, weather, HUD treatment, and gameplay-scale compositing at runtime.
