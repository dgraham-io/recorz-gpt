# recorz Primitive ABI (v0)

## Scope

Defines VM <-> language primitive invocation behavior for `<primitive: N>` where `N` is `0..255`.

## Dispatch model

- Each primitive ID maps to one VM handler.
- Dispatch occurs at method activation when primitive declaration is present.
- Primitive runs before language fallback body.

## Stack/register contract (abstract)

- Receiver: activation slot `arg0`.
- Method arguments: activation slots `arg1..argN`.
- Return value: pushed as expression result on success.

Concrete register mapping is VM-implementation specific; language-level contract is stable.

## Success/failure contract

- Success: primitive returns a normal object result.
- Failure: primitive returns failure sentinel `PrimitiveFail`.
- On `PrimitiveFail`, VM continues by executing the Smalltalk-level fallback code in the same method body.

## Error classes

- `PrimitiveNotFound` (ID not implemented)
- `PrimitiveBadArity`
- `PrimitiveBadType`
- `PrimitiveDeviceError`

Initial VM may collapse these to `PrimitiveFail`; richer errors can be added later.

## Determinism and side effects

- Primitive must either:
  - produce a value and commit side effects, or
  - return `PrimitiveFail` with no partial externally visible mutation.
- Device primitives are allowed observable side effects but must document ordering guarantees.

## Suggested initial primitive ranges

- `0..31`: core runtime (object, array, numeric fast paths)
- `32..63`: process/context/debug support
- `64..127`: graphics/input
- `128..191`: storage/image/host bridge
- `192..255`: experimental/private

## Versioning rule

- Primitive IDs are append-only once published.
- Never repurpose an existing ID with different semantics.
