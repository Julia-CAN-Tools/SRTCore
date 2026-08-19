# SRTCore Agent Instructions

These instructions apply to the entire `SRTCore` repository. Read a package's
own `AGENTS.md` before editing that package.

## Repository contents

| Package | Responsibility | Normal verification |
| --- | --- | --- |
| `IO/CAN/Protocols/CANUtils.jl` | CAN signal and frame encoding | Offline unit tests |
| `IO/CAN/Protocols/J1939Parser.jl` | J1939 identifiers, messages, and catalogs | Offline unit tests |
| `IO/CAN/Drivers/CANInterface.jl` | Linux SocketCAN driver | Offline load; CAN tests only on verified `vcan` |
| `SystemSimulator.jl` | Deterministic threaded control runtime | Offline threaded tests |
| `UI/SRTBonito.jl` | Bonito TCP monitoring and plotting UI | Offline/local-loopback tests |

The dependency direction is:

```text
CANUtils <- J1939Parser
CANInterface + CANUtils + J1939Parser <- SystemSimulator
SRTBonito connects to SystemSimulator monitor sockets over TCP
```

Packages are unregistered. Preserve relative `[sources]` paths and never replace
local packages with registry packages of the same name.

## Change discipline

1. Inspect repository status and relevant entrypoints before editing.
2. Preserve unrelated and pre-existing changes.
3. Update every in-repository consumer when changing a shared interface.
4. Do not edit generated logs, coverage output, Julia caches, or build products.
5. Do not commit, push, configure remotes, or rewrite history unless requested.
6. Keep package boundaries narrow; example-specific models and controllers do
   not belong in SRTCore.

## Verification

Use the smallest relevant offline command:

```bash
julia --project=IO/CAN/Protocols/CANUtils.jl IO/CAN/Protocols/CANUtils.jl/test/runtests.jl
julia --project=IO/CAN/Protocols/J1939Parser.jl IO/CAN/Protocols/J1939Parser.jl/test/runtests.jl
julia --project=SystemSimulator.jl SystemSimulator.jl/test/runtests.jl
julia --project=UI/SRTBonito.jl UI/SRTBonito.jl/test/runtests.jl
julia --project=IO/CAN/Drivers/CANInterface.jl -e 'using CANInterface'
```

Only run CANInterface transport tests after inspecting the exact target with:

```bash
ip -details link show dev vcan0
```

The output must identify a kernel `vcan` device that is UP.

## Real-time requirements

- `SystemSimulator` hot paths must remain allocation-free.
- Cache signal slots and preallocate transport buffers.
- Do not add dictionaries, closures, logging, sleeps, blocking calls, or dynamic
  lookup inside `control_step!` or transport loops.
- Preserve deterministic shutdown and interruptible blocking readers.
- Do not silently change wire formats, protocol ordering, buffer sizes, or
  lifecycle semantics.

## Safety boundary

Offline inspection, unit tests, compilation, and localhost TCP tests are allowed.
Virtual CAN transmission is allowed only after the exact interface is verified
as kernel `vcan`.

Explicit approval is required immediately before any of the following:

- physical CAN transmission or log replay;
- `sudo`, kernel module changes, or interface reconfiguration;
- actuator/controller startup on physical hardware;
- any operation that could energize equipment.

Passing offline or virtual-CAN tests never authorizes a physical-HIL run.

## Completion report

Report changed packages, checks and outcomes, skipped CAN/hardware checks, and
remaining compatibility or safety risks.
