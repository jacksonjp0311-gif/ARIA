# ARIA

> **A graph-native, glyph-capable local execution language for humans and AI.**

```text
◉ operator ──authorizes──▶ ⟁ agent ──transforms──▶ ▧ repository
     │                                                     │
     └────────────── observes Traceflow ────────────────────┘
```

ARIA is an experimental local language with deterministic compilation, typed semantic validation, capability-gated effects, compressed `.ariac` executables, persistent governed memory, graph metadata, and an operator-first CLI. AI may write or propose ARIA, but the compiler and virtual machine—not the model—decide what is valid and executable.

## Status

| Component | Current release |
|---|---|
| Compiler | `0.1.0-alpha.4` PowerShell bootstrap |
| Language specification | `0.3.0` |
| Container | `.ariac` version `1`, bounded gzip + SHA-256 |
| Hosts | Windows PowerShell 5.1 and PowerShell 7 |
| Default authority | Deny by default |
| Production sandbox | No—experimental alpha |

## Alpha.4: Coreflow

ARIA now supports:

- typed values: `Text`, `Number`, `Bool`, `Null`, and `Any`;
- expression precedence, arithmetic, comparisons, and Boolean operators;
- typed `let` bindings and `set` mutation;
- functions with typed parameters and return contracts;
- `if` / `else` lexical blocks;
- bounded `repeat` loops with an iterator;
- module identity metadata;
- typed persistent memory fields;
- deterministic `dispatch Agent <- "task"` events;
- Traceflow rendering driven by VM events;
- independent structured-bytecode verification.

ARIA does **not** yet contact an AI provider. Agent dispatch is a deterministic local event that a future provider-neutral bridge can consume after policy and operator approval.

## Quick start

Open PowerShell in this repository:

```powershell
.\aria.cmd doctor -Strict
.\aria.cmd test
.\aria.cmd trace .\examples\coreflow.aria -Strict
```

Normal output uses ARIA's operator stream: `◈` active, `◆` pass, `⬖` warning, `⬗` failure, and `∿` program transmission. Add `-VerboseOutput` or set `ARIA_VERBOSE=1` for raw diagnostics.

## Coreflow example

```aria
aria 0.3.0
module Arithmetic version 0.1.0
program FunctionDemo version 0.1.0
entry Main

function Add(left: Number, right: Number) -> Number {
  return left + right
}

flow Main {
  let total: Number = Add(2, 3)
  if total == 5 {
    signal pass "typed function online"
  } else {
    signal fail "unexpected result"
  }
  repeat 3 as index {
    emit index
  }
  halt
}
```

Compile and execute:

```powershell
.\aria.cmd gate .\examples\functions.aria -Strict
.\aria.cmd build .\examples\functions.aria -Strict
.\aria.cmd trace .\examples\functions.aria -Strict
```

Artifacts are written to `.aria/build/<Program>-<Version>.ariac` with a provenance record.

## Language pipeline

```text
UTF-8 ARIA source
      ↓
expression lexer + structural parser
      ↓
typed semantic graph and capability analysis
      ↓
structured stack bytecode
      ↓
independent verifier
      ↓
canonical JSON → SHA-256 → bounded gzip
      ↓
.ariac executable container
      ↓
policy-gated local ARIA VM + Traceflow
```

## Command reference

| Command | Purpose |
|---|---|
| `aria doctor [-Strict]` | Verify host, policy, codec, verifier, and optionally the repository manifest. |
| `aria test` | Run the conformance lattice. |
| `aria gate|check <file.aria>` | Parse, type-check, policy-check, compile twice, and verify reproducibility. |
| `aria compile|build <file.aria>` | Produce a compressed `.ariac` artifact and provenance. |
| `aria run|start|trace <file.aria>` | Gate, compile, verify, and execute locally. |
| `aria exec <file.ariac>` | Verify and execute an existing artifact. |
| `aria inspect <file.ariac>` | Verify and disassemble structured bytecode. |
| `aria graph <file.aria|file.ariac>` | Render declared glyphic topology. |
| `aria manifest` | Seal intentional repository changes. |
| `aria verify` | Verify the sealed repository tree. |
| `aria init <Name>` | Create a typed ARIA starter program. |

Use `aria.cmd` on Windows so the process-level execution-policy bypass remains scoped to ARIA.

## Security model

Host effects require all of the following:

1. a declared capability;
2. an allowing entry in `aria.policy.json`;
3. an active `require CapabilityName` instruction;
4. a concrete target confined to the selected workspace and capability scope;
5. execution-time policy revalidation.

The default policy permits console output, ARIA memory, graph inspection, repository-scoped reads, and local agent-dispatch events. It denies filesystem writes, subprocess execution, and network access.

## Repository map

- `grammar/` — normative grammar, glyph registry, opcode registry;
- `src/` — parser, semantics, compiler, verifier, container codec, VM, renderer;
- `examples/` — executable ARIA programs;
- `tests/` — dependency-free conformance suite;
- `docs/` — specification, math, algorithms, research, ADRs, and roadmap;
- `schemas/` — machine-readable interchange and policy schemas.

## Project discipline

Every release must preserve deterministic output, strict version locks, deny-by-default policy, bytecode verification, container integrity, Windows PowerShell 5.1 compatibility, and an auditable manifest. Read [`CONTRIBUTING.md`](CONTRIBUTING.md), [`SECURITY.md`](SECURITY.md), and [`docs/README.md`](docs/README.md) before changing the language core.

ARIA is licensed under Apache-2.0. See [`LICENSE`](LICENSE) and [`NOTICE`](NOTICE).
