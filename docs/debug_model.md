# recorz Debug/Reflection Model (v0)

## Goal

Provide Smalltalk-like debugging and reflection without a `thisContext` language keyword.

## Principle

- Contexts exist as first-class runtime objects.
- Access to contexts is via reflective protocol messages.
- Core syntax remains minimal (`self`, `super`, literals, message sends, blocks).

## Initial reflective protocol

- `Process current` -> currently running process.
- `Process>>currentContext` -> top activation context.
- `Context>>sender` -> previous context.
- `Context>>receiver`
- `Context>>selector`
- `Context>>arguments`
- `Context>>temporaries`
- `Context>>restart`
- `Context>>step`
- `Context>>resume`

These may be implemented with primitives first, then moved into language-level support.

## Breakpoints and stepping

- Breakpoint metadata stored in method objects.
- Interpreter checks breakpoint table at send/bytecode boundaries.
- On hit, scheduler suspends target process and opens debugger process/UI.

## Error handling flow

1. Exception/event captures current context.
2. System creates debugger model object with captured context.
3. Debugger UI queries context protocol to render stack/locals/source.

## Security/perf note

Full context access is powerful; production profiles may gate protocol exposure.
