# Production content budgets

`resources/content_budgets.json` is the machine-readable source-payload contract.
`tools/content_budget_audit.py` pins that policy to reviewed ceilings and fails CI
when a file bypasses, weakens, or exceeds them.

## Texture envelope

The current build contains 33 referenced PNG textures: one background, 12 boss
images, six character images, and 14 enemy images. The global ceiling is 64 images,
96 MiB of source PNG data, and 288 MiB of worst-case RGBA decode storage. Category
ceilings prevent one content family from consuming all global headroom. A single
texture may not exceed 6 MiB, 2048 pixels on either axis, or 3,145,728 pixels.

The audit parses the PNG container itself and verifies every chunk CRC, mandatory
chunk order, 8-bit RGB/RGBA format, non-interlaced encoding, dimensions, and unique
payload hash. Combat sheets must preserve alpha. Every source PNG must have a real
`res://assets/...` reference in production scripts, scenes, or resources, and every
such reference must resolve to a budgeted image. Snake-case filenames are mandatory.

`decoded_rgba_bytes = width * height * 4` is a conservative comparison metric, not
a claim that every image is simultaneously resident or that every GPU uses that
exact layout. Platform-specific imported texture size, residency, streaming, and
VRAM pressure still require native profiling on the defined minimum hardware.

## Runtime-source envelope

The contract separately budgets scripts, scenes, authored JSON/TRES data, and
shaders by minimum/maximum file count, per-file bytes, and category bytes. The
minimums protect the currently shipped production surface from accidental omission;
the maximums retain expansion headroom while making unexpected payload growth a
reviewed decision. Generated `.uid`/`.import` metadata, tests, developer tools,
documentation, and source-art working files are outside this runtime-payload metric.

Raising a ceiling requires changing both the policy and its audited constants,
documenting the memory/package impact, rerunning the full suite, and recording native
target measurements. Moving files to an unscanned extension or directory is not a
valid optimization; new runtime content categories must be added explicitly.

## Run the gate

```sh
python3 tools/content_budget_audit.py
```

The success line exposes texture counts, source and decoded totals, remaining source
headroom, plus count/byte totals for all runtime-source categories. The complete
`tools/validate.sh` suite runs this gate before engine-level content validation.
