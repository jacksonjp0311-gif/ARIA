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
| Compiler | `0.1.0-alpha.5` PowerShell bootstrap |
| Language specification | `0.4.0` |
| Container | `.ariac` version `1`, bounded gzip + SHA-256 |
| Hosts | Windows PowerShell 5.1 and PowerShell 7 |
| Default authority | Deny by default |
| Production sandbox | No—experimental alpha |

## Alpha.5: Connectflow

ARIA now adds a verified connection ontology on top of Coreflow:

- declared `connection` contracts linking an operator identity, an agent identity, and a protocol;
- deterministic `connect`, `intent`, `propose`, `consent`, and `disconnect` statements;
- explicit human consent as a typed `Bool`, including safe refusal;
- lifecycle enforcement in the local VM before any future provider bridge;
- structured connection events and a dedicated `aria connect` operator experience;
- a `REJECT` renderer state for expected denial or withheld authority;
- quiet compiler probes so conformance output reserves red `FAIL` for unexpected breakage;
- 42 deterministic conformance gates.

ARIA still does **not** contact an AI provider. Connectflow establishes the shared protocol first: human intent, agent proposal, explicit consent, and deterministic closure. A future provider-neutral bridge can attach only after this contract remains intact.

## Quick start

Open PowerShell in this repository:

```powershell
.\aria.cmd doctor -Strict
.\aria.cmd test
.\aria.cmd connect .\examples\connection.aria -Strict
```

Normal output uses ARIA's operator stream: `◈` active, `◆` pass or expected rejection, `⬖` warning, `⬗` unexpected failure, and `∿` program transmission. Add `-VerboseOutput` or set `ARIA_VERBOSE=1` for raw diagnostics.

## Connectflow example

```aria
aria 0.4.0
module Connection version 0.1.0
program ConnectionDemo version 0.1.0
entry Main

agent Architect {
}

connection HumanAI {
  operator = "human"
  agent = "Architect"
  protocol = "intent-proposal-consent"
}

flow Main {
  connect HumanAI
  intent HumanAI <- "Evolve ARIA and its CLI together."
  propose HumanAI <- "Compile a verified local change."
  consent HumanAI <- true
  disconnect HumanAI
}
```

Compile and execute:

```powershell
.\aria.cmd gate .\examples\connection.aria -Strict
.\aria.cmd build .\examples\connection.aria -Strict
.\aria.cmd connect .\examples\connection.aria -Strict
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
| `aria connect [file.aria]` | Run a verified human-agent intent/proposal/consent session. |
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


## Alpha.7: Etherflow

ARIA now adds an Etherflow surface on top of Operatorflow:

- a triadic CLI renderer aligned to three lanes: 🜂 energy, ∿ information, and 🜄 coherence;
- adaptive rendering across `operator`, `compact`, `ci`, and `ether` profiles;
- event-to-surface wiring for typed provider transmissions so visuals reflect real runtime data;
- a future-facing preview bridge that renders transmission events as a compressed, high-signal field instead of plain logs.

Etherflow is a display membrane only. It does not change compiler semantics, bytecode verification, policy enforcement, or the underlying transmission schema.