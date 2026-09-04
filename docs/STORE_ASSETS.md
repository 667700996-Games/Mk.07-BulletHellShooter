# Steam graphical-asset delivery

The checked-in files under `assets/store/` are platform-neutral source masters. The
upload-ready Steam set is generated under `dist/store/steam/`, so delivery derivatives
never enter the Godot runtime package or Git history.

The production profile follows the current official Steamworks graphical-asset
specification and rules:

- [Graphical Assets overview](https://partner.steamgames.com/doc/store/assets)
- [Store graphical assets](https://partner.steamgames.com/doc/store/assets/standard)
- [Library assets](https://partner.steamgames.com/doc/store/assets/libraryassets)
- [Graphical asset rules](https://partner.steamgames.com/doc/store/assets/rules)

The base capsules contain only the original artwork and the `PSYCHIC VECTOR`
logotype. The library hero and gameplay screenshots contain no logo or marketing
copy. Screenshots preserve the complete 9:16 game render at the center of a 16:9
frame; the side fill is a darkened, blurred duplicate of the same gameplay frame,
not concept art or unrelated imagery.

## Build and verify

Run the capture step with a display-capable Godot process. It renders three route
scenes and all three final bosses with the English in-game UI:

```sh
godot --path . -- --capture-store-sources
godot --headless --path . --script res://tools/store_asset_builder.gd
python3 tools/store_asset_audit.py
```

The audit fails closed on stale candidate identity, missing source captures, source
or output hash drift, wrong file format or dimensions, a non-transparent library
logo, fewer than five gameplay screenshots, duplicate paths, and an incomplete
delivery set. `manifest.json` binds all input and output hashes to the current
release-candidate ID. Re-running the builder from unchanged source pixels produces
the same image bytes and manifest; it contains no wall-clock timestamp.

## Required delivery files

| Role | Output | Size |
|---|---|---:|
| Header capsule | `store/header_capsule.png` | 920×430 |
| Small capsule | `store/small_capsule.png` | 462×174 |
| Main capsule | `store/main_capsule.png` | 1232×706 |
| Vertical capsule | `store/vertical_capsule.png` | 748×896 |
| Page background | `store/page_background.png` | 1438×810 |
| Library capsule | `library/library_capsule.png` | 600×900 |
| Library header | `library/library_header.png` | 920×430 |
| Library hero | `library/library_hero.png` | 3840×1240 |
| Library logo | `logo/library_logo.png` | 1280×400, transparent |
| Shortcut icon | `community/shortcut_icon.png` | 256×256 |
| App icon | `community/app_icon.jpg` | 184×184 |
| Gameplay screenshots | `screenshots/*.png` | 1920×1080 each |

Six localized-English screenshots are produced, exceeding Steam's required minimum
of five. Before portal upload, a human must still preview the set in Steamworks,
choose the library-logo placement, mark at least four eligible screenshots as
suitable for all ages, supply accessible alt text, and approve the artwork against
the live portal templates. Those portal actions require the product App ID and are
not represented by a local audit result.

## Visual review record

The current v1 set was inspected at native and thumbnail size for:

- product-name legibility in the 462×174 small capsule;
- exactly three established heroes and one Aurelion Zero in ensemble capsules;
- unobstructed faces and a readable boss silhouette in landscape and portrait crops;
- the central 860×380 library-hero safe area retaining Kira's face and psychic attack;
- complete, undistorted 9:16 gameplay renders with English HUD text;
- no reviews, awards, pricing, promotion copy, third-party marks, or platform logo.

If the source art, logo construction, crop coordinates, Steam specification, or
release metadata changes, recapture, rebuild, audit, and repeat the visual review.
