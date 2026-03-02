# recorz Protocol Matrix (Bootstrap Core)

This matrix tracks protocol coverage in the current VM bootstrap.

Status legend:
- `implemented`: expected to work in current bootstrap
- `partial`: works in constrained/bootstrap form
- `planned`: not implemented yet

## Global / Runtime

| Protocol | Status | Notes | Coverage |
|---|---|---|---|
| `Object` global binding | implemented | Prebound at VM init | `tests.test_vm_smoke:test_qemu_boot_banner` |
| `doesNotUnderstand:argc:` diagnostics | implemented | Serial diagnostics + receiver return | `tests.test_vm_smoke:test_qemu_dnu_fallback` |
| image `saveImage` / `loadImage:` | implemented | In-memory snapshot | `tests.test_vm_smoke:test_qemu_image_snapshot_restore` |
| image bridge `exportImage:` / `importImage` | implemented | UART `RCIMG` frame + checksum | `tests.test_vm_smoke:test_qemu_image_host_bridge_roundtrip` |

## `Object` / Slot Protocol

| Selector | Status | Notes | Coverage |
|---|---|---|---|
| `clone` | implemented | Proto clone into heap object | `test_qemu_boot_banner`, `test_qemu_protocol_core_matrix` |
| `addSlot:value:` | implemented | add/update slot value | `test_qemu_boot_banner`, `test_qemu_protocol_core_matrix` |
| `slotNamed:` | implemented | value lookup by symbol | `test_qemu_boot_banner` |
| unresolved `x` / `x:` accessor fallback | partial | Applies on unresolved sends for existing slots | `test_qemu_code_example_core_path`, `test_qemu_protocol_core_matrix` |
| `addMethod:do:` | implemented | dynamic block method install | `test_qemu_boot_banner`, `test_qemu_protocol_core_matrix` |
| `primitiveFailed` | implemented | fallback return path | `test_qemu_boot_banner` |

## `Integer` Protocol

| Selector | Status | Notes | Coverage |
|---|---|---|---|
| `print` | implemented | decimal UART print | `test_qemu_boot_banner` |
| `+`, `-`, `*`, `/` | implemented | tagged-int arithmetic; `/` handles div-zero via fallback path | `test_qemu_boot_banner`, `test_qemu_protocol_core_matrix` |
| `sqrt` | implemented | floor integer square root | `test_qemu_code_example_core_path`, `test_qemu_protocol_core_matrix` |

## Collections / Payload-backed Objects

| Prototype | Selector | Status | Notes | Coverage |
|---|---|---|---|---|
| `ByteArray` | `size` | implemented | tagged length | `test_qemu_boot_banner`, `test_qemu_protocol_core_matrix` |
| `ByteArray` | `at:` | implemented | zero-based index | `test_qemu_boot_banner`, `test_qemu_protocol_core_matrix` |
| `ByteArray` | `at:put:` | implemented | in-place update | `test_qemu_boot_banner`, `test_qemu_protocol_core_matrix` |
| `ObjectArray` | `size` | implemented | element count | `test_qemu_boot_banner`, `test_qemu_protocol_core_matrix` |
| `ObjectArray` | `at:` | implemented | zero-based index | `test_qemu_boot_banner`, `test_qemu_protocol_core_matrix` |
| `ObjectArray` | `at:put:` | implemented | in-place update | `test_qemu_boot_banner`, `test_qemu_protocol_core_matrix` |

## Blocks / Control

| Selector / Feature | Status | Notes | Coverage |
|---|---|---|---|
| `value`, `value:` | implemented | executable block payloads | `test_qemu_boot_banner`, `test_qemu_protocol_core_matrix` |
| lexical capture + mutation | implemented | captured refs/locals update | `test_qemu_boot_banner` |
| non-local return (`^`) | implemented | home-frame validity checks + CannotReturn recovery | `test_qemu_cannot_return_escape` |
| declared primitive in block (`<primitive: N>`) | implemented | primitive-first with fallback body | `test_qemu_boot_banner`, `test_qemu_memory_primitives_10_11` |

## Sample Hardware-style Protocol

| Selector | Status | Notes | Coverage |
|---|---|---|---|
| `byteAt:` (primitive `10`) | partial | dual-mode primitive: int receiver -> `print`; object receiver -> memory read | `test_qemu_memory_primitives_10_11` |
| `byteAt:put:` (primitive `11`) | partial | dual-mode primitive: int receiver -> `+`; object receiver -> memory write | `test_qemu_memory_primitives_10_11` |

## Explicitly Out of Scope (Current Bootstrap)

Planned but not yet implemented:
- full Smalltalk class-library parity
- structured debugger object model (frame inspectors, stepping protocol)
- graphical workspace/device protocol stack
- durable non-UART image backend
