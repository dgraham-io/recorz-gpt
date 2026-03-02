# recorz Remaining Work

This document captures the work still required to move from the current bootstrap VM to the intended Smalltalk-like, prototype-based platform.

It is intentionally specific so it can be used to drive AI-agent tasks and milestone planning.

## 1. Current Baseline

The system currently provides:
- parser + hosted bytecode tooling
- RCBC VM bytecode format with executable block payloads (`RBLK`)
- RISC-V assembly VM running under QEMU with serial diagnostics
- prototype slot model with dynamic method blocks
- closures, local/captured mutation, and non-local return recovery
- `doesNotUnderstand:argc:` fallback diagnostics
- image save/load plus host serial bridge

This is enough to prototype language/runtime behavior, but not yet enough for semantic parity with Smalltalk/Self-class systems.

## 2. Highest-Priority Gaps

### A. Language/Runtime Semantic Coverage

Gaps:
- many selectors and protocols expected by sample-style code are not present
- numeric/library protocols are minimal (`sqrt` and broader math/message protocols missing)
- method lookup/behavior remains bootstrap-level (not yet a complete image-level object universe)

Implications:
- user code can compile and run, but often falls back to DNU diagnostics
- sample code is useful for parser/compiler validation, less so for behavior parity

Acceptance criteria:
- representative sample programs execute without DNU for planned core protocol set
- protocol coverage document lists implemented selectors/prototypes and test status

### B. Reflection and Debugging Model

Gaps:
- no structured debugger objects (stack frames, resumable contexts, breakpoints)
- serial text diagnostics exist, but no interactive Smalltalk-like debugger workflow
- `thisContext` remains intentionally absent; protocol-level reflection not yet complete

Implications:
- debugging is currently VM/serial-centric
- cannot yet perform in-language inspector/browser/debugger workflows

Acceptance criteria:
- in-language context mirror protocol for stack/frame inspection
- breakpoint/step/inspect support through object protocol
- debugger smoke tests proving non-local return and DNU inspection paths

### C. Persistence and Durability

Gaps:
- image persistence is currently in-memory + UART bridge workflow
- no durable block device/file-backed persistence path in VM runtime
- operational tooling around image migration/version checks is still minimal

Implications:
- good for bootstrap iteration, weak for robust repeatable sessions
- serial pipeline is slower and fragile for large images

Acceptance criteria:
- one durable backend (file or virtual block device) with deterministic load/save flow
- compatibility/version policy tests for image migration behavior

### D. Graphics-First Environment

Gaps:
- no framebuffer UI/workspace in current VM runtime
- device-driver-in-language objective not started for graphics/input stack

Implications:
- architecture goal (Smalltalk-like live graphical system) is not yet represented in runtime
- serial remains the only practical interface

Acceptance criteria:
- boot to a minimal framebuffer-backed graphical shell
- language-level driver objects handling input/output paths

### E. FPGA Path Preparation

Gaps:
- no profile-driven hotspot data for HW acceleration planning yet
- no candidate VM-assist ISA contract defined

Implications:
- hardware planning is premature without runtime profiling baselines

Acceptance criteria:
- benchmark/profile suite with hotspot ranking
- first FPGA-assist proposal tied directly to measured bottlenecks

## 3. Recommended Execution Order

1. Core protocol completion for write-run-debug loops.
2. Structured reflection/debugger protocol.
3. Durable image backend and migration tooling.
4. Graphics/input boot path in VM + language-level drivers.
5. Performance profiling and FPGA-assist design.

Rationale:
- this order maximizes immediate developer productivity before investing in UI and hardware.

## 4. Detailed Task Backlog

## 4.1 Core Protocol Completion (Near Term)

Tasks:
- define minimum bootstrap protocol surface by prototype (`Object`, `Integer`, collections, blocks)
- implement missing selectors required by `docs/code_example.md` and smoke-like user programs
- add protocol-conformance tests by selector family
- reduce DNU-only fallback usage in expected paths

Deliverables:
- expanded `docs/protocol_matrix.md` (prototype + selector + status + test, beyond bootstrap core)
- expanded runtime tests proving protocol coverage

Definition of done:
- curated sample set runs with zero unexpected DNU output

## 4.2 Debugging/Reflection (Near-Mid Term)

Tasks:
- define context mirror object model (activation, sender, receiver, selector, pc)
- expose frame traversal and local/capture inspection via protocol
- add breakpoint/step primitives and language wrappers
- create serial and in-language debugger workflows

Deliverables:
- `docs/debug_protocol.md`
- debugger runtime tests and scripted scenarios

Definition of done:
- failing send or non-local return can be inspected and resumed through protocol

## 4.3 Persistence Hardening (Mid Term)

Tasks:
- choose durable persistence backend (host file path in QEMU, virtio block, or both)
- implement VM backend abstraction under image primitives
- add checksums/version guards and failure recovery semantics
- add image migration tests across bytecode/runtime versions

Deliverables:
- durable save/load command path independent of UART bridge
- migration test matrix and compatibility docs

Definition of done:
- repeatable save/restart/load sessions without bridge tooling

## 4.4 Graphics and Drivers (Mid-Late Term)

Tasks:
- add framebuffer memory model and primitive bridge
- implement minimal compositor/workspace objects in language
- define and implement keyboard/mouse event pipeline
- move driver policy logic to language where practical

Deliverables:
- graphical boot demo with input and basic interaction
- driver-object docs and example sources

Definition of done:
- VM boots to a live graphical environment with in-language event handling

## 4.5 Performance and FPGA Planning (Late Term)

Tasks:
- create repeatable benchmark workloads (message send, closure activation, image save/load, UI events)
- profile QEMU/hosted behavior to identify VM hotspots
- draft VM-assist ISA proposals with complexity/cost estimates
- prototype accelerated paths in simulation before RTL commitment

Deliverables:
- `docs/perf_baseline.md`
- `docs/fpga_assist_plan.md`

Definition of done:
- first FPGA implementation target selected from measured data

## 5. Risks and Mitigations

Risk:
- semantic drift between parser/compiler/VM and intended language model.
Mitigation:
- keep executable protocol matrix + sample suite as compatibility gate.

Risk:
- overgrowth of VM primitives instead of language-level behavior.
Mitigation:
- require justification for each new primitive ID; prefer object-level implementation.

Risk:
- persistence incompatibilities during rapid iteration.
Mitigation:
- strict versioning + migration tests + compatibility docs per format change.

Risk:
- graphics scope explosion before runtime stabilizes.
Mitigation:
- lock milestone to minimal shell first, defer tooling polish.

## 6. When You Can Reliably Write and Run New Code

You can write and run `.rcz` code now.

Current practical expectation:
- parser/compiler path is stable for core syntax
- runtime supports meaningful prototype/block experiments
- advanced library-like behavior may hit missing selectors and DNU output

For productive experimentation today:
- keep programs close to currently implemented protocol set
- use smoke-style patterns as templates
- treat DNU output as roadmap signal for next protocol additions

## 7. Suggested Agent Workstream Split

Agent 1 (Runtime Protocols):
- selector coverage and protocol matrix.

Agent 2 (Debug/Reflection):
- context mirror + debugger primitives + tests.

Agent 3 (Persistence):
- durable backend + compatibility test harness.

Agent 4 (Graphics/Drivers):
- framebuffer pipeline + language driver objects.

Agent 5 (Docs/Release Discipline):
- status, compatibility notes, milestone acceptance checklists.
