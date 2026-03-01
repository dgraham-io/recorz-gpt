# Image/Bridge Compatibility Policy (Bootstrap)

## Image payload (`RCIM`)

- Image payload magic: `RCIM`
- Current image format version: `2`
- Loader rule:
  - `loadImage:` accepts only exact major version `2`.
  - Any other version is rejected as bad format (`-4`).
- Rationale:
  - Bootstrap VM uses absolute object pointers and internal layout snapshots.
  - Cross-version tolerance is intentionally strict until relocation/schema migration exists.

## Host bridge frame (`RCIMG`)

- Bridge header line format:
  - `RCIMG <len> <sum32hex>`
- Payload line format:
  - `<hex bytes>`
- Validation rules in `importImage`:
  - Exact bridge tag `RCIMG`.
  - Exact checksum width (8 hex chars).
  - Decoded byte count matches `<len>`.
  - `sum32` (u32 additive checksum) matches payload bytes.

## Host tooling expectations

- `scripts/qemu_image_bridge.py` is the canonical host helper.
- It verifies `len` and `sum32` on export before writing image files.
- It emits matching `RCIMG` headers for import.

## Forward-compatibility rules

- Any incompatible bridge framing change must use a new tag (`RCIMG2`, etc.).
- Any incompatible image payload change must bump `RCIM` version.
- Bridge/tooling should reject unknown major versions by default.
