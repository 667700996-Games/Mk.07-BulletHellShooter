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

Boss combat sheets were derived non-destructively from the two boss designs with the built-in image generation tool:

- `bosses/arbiter_03_combat_sheet.png`
- `bosses/seraph_executor_combat_sheet.png`

Each sheet contains neutral hover, telegraph/charge, attack-release, and overdrive/damaged poses at a fixed gameplay anchor. ARBITER communicates state through reactor, armor-ring, and cannon deployment; SERAPH uses her arm posture, chest core, halo, and four-blade formation. Background extraction was verified as genuine RGBA before import.

Enemy variants:

- `enemies/neon_drone.png`: compact surveillance/attack drone.
- `enemies/psychic_trooper.png`: airborne armored psychic trooper.
- `enemies/assault_mech.png`: heavy urban assault mech.
- `enemies/vector_gunship.png`: top-down military vector gunship.

Four-pose regular-enemy combat sheets were derived non-destructively from those enemy designs with the built-in image generation tool:

- `enemies/neon_drone_combat_sheet.png`
- `enemies/psychic_trooper_combat_sheet.png`
- `enemies/assault_mech_combat_sheet.png`
- `enemies/vector_gunship_combat_sheet.png`

Each 2×2 sheet uses a fixed gameplay anchor and contains idle hover, left strafe/bank, right strafe/bank, and firing/recoil poses. The shared prompt required the original silhouette, materials, lighting language, and armament to remain recognizable from a top-down bullet-hell view. Background-extraction edits removed generated checkerboards or solid backdrops and were verified as genuine RGBA before import.

Environment:

- `backgrounds/title_megacity.png`: vertical rain-soaked neon megacity matte painting with a distant control spire and layered elevated roads.

Transparency edit direction:

> Remove only the studio-gradient background and replace it with genuine transparency. Preserve identity, pose, clothing, energy, floating devices, colors, and edge quality. Clean alpha, no crop, no additions, no text, no watermark.

The project additionally applies procedural shaders, particles, color grading, parallax, weather, HUD treatment, and gameplay-scale compositing at runtime.
