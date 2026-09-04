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

NULL TEMPEST received a separate original boss-art pass with the built-in image generation tool on 2026-09-04:

- `bosses/ion_warden_keyart.png`: a non-humanoid atmospheric containment machine with a hexagonal core, swept armor, and cyan ion coils.
- `bosses/ion_warden_combat_sheet.png`: neutral, telegraph, ion-release, and damaged-overdrive poses in a consistent 2×2 layout.
- `bosses/void_archon_keyart.png`: an original horizon-class anomaly built around a violet event-horizon core, broken obsidian crown, and close-orbiting fragments.
- `bosses/void_archon_combat_sheet.png`: neutral, telegraph, horizon-release, and fractured-overdrive poses in a consistent 2×2 layout.

The combat-sheet prompts required genuine transparent backgrounds, identical identity and scale across all four cells, fully contained silhouettes, no text or logos, and no resemblance to an existing franchise. Key-art prompts placed the same concepts in the shattered high-altitude arcology while preserving gameplay-readable silhouettes.

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

NULL TEMPEST regular enemies received independent 2×2 combat sheets with the built-in image generation tool on 2026-09-04:

- `enemies/tempest_needle_combat_sheet.png`: small dart interceptor with idle, left/right bank, and straight-burst release poses.
- `enemies/tempest_corona_combat_sheet.png`: medium six-vane radial gunship with idle, left/right bank, and open-emitter release poses.
- `enemies/tempest_monolith_combat_sheet.png`: large armored conductor with idle, left/right bank, and triple-ring release poses.

All three prompts required a consistent top-down three-quarter camera, fixed anchor and scale, generous cell gutters, genuine transparency, and silhouettes that remain distinct at their actual gameplay sizes. No existing character, vehicle, logo, or franchise was referenced.

HELIOS FORGE received a complete original combat-art pass with OpenAI's built-in image generation tool on 2026-09-04. The final prompt direction was:

> Premium original 2D vertical bullet-hell production art for a solar orbital foundry. Obsidian black and ivory armor, white-hot gold energy, restrained crimson accents, crisp top-down three-quarter silhouettes, no text, no logo, no watermark, and no resemblance to any existing character, vehicle, game, or franchise.

The following transparent 2×2 combat-sheet prompts added fixed scale, generous gutters, full containment, and four readable states—neutral hover, left bank/telegraph, right bank/attack, and firing or damaged overdrive—as appropriate to each role:

- `enemies/forge_cinder_dart_combat_sheet.png`: a small arrowhead Cinder Dart interceptor designed for a fast straight three-shot burst.
- `enemies/forge_corona_wheel_combat_sheet.png`: a medium broken-ring Corona Wheel with six detached emitter nodes designed for a radial volley.
- `enemies/forge_helios_bastion_combat_sheet.png`: a large concentric-disc Helios Bastion whose three armor rings communicate three consecutive circular volleys.
- `bosses/forge_crown_harvester_combat_sheet.png`: the Crown Harvester midboss, a solar-harvesting machine with crescent reaper blades and a captive miniature sun.
- `bosses/forge_aurelion_zero_combat_sheet.png`: Aurelion Zero, a celestial command machine built around an eclipse core with an ivory/obsidian crown and gold-crimson prominences.

The matching opaque key-art prompts placed each boss in the collapsing orbital foundry while preserving its gameplay silhouette:

- `bosses/forge_crown_harvester_keyart.png`: Crown Harvester locking the approach between solar collector rings and molten conduits.
- `bosses/forge_aurelion_zero_keyart.png`: Aurelion Zero manifesting above the eclipse core as the foundry collapses around a false sun.

All seven generated images were normalized to 1024×1024 before Godot import. The five combat sheets were verified as genuine RGBA; the two environment-backed key-art images intentionally remain opaque RGB.

Environment:

- `backgrounds/title_megacity.png`: vertical rain-soaked neon megacity matte painting with a distant control spire and layered elevated roads.

Transparency edit direction:

> Remove only the studio-gradient background and replace it with genuine transparency. Preserve identity, pose, clothing, energy, floating devices, colors, and edge quality. Clean alpha, no crop, no additions, no text, no watermark.

The project additionally applies procedural shaders, particles, color grading, parallax, weather, HUD treatment, and gameplay-scale compositing at runtime.

The root `icon.svg` is an original, hand-authored project vector mark built from geometric paths and gradients for the desktop application icon. It uses no external logo, font, trademark, or stock asset.
