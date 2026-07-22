# ARIA

> **A local-first, graph-native, glyphic programming language for verified computation and AI-readable execution.**

```text
Glyphs compress expression.
Types preserve meaning.
Signatures protect identity.
Capabilities control authority.
The verifier decides execution.
```

ARIA is an experimental programming language and runtime built around one hard rule:

> **Nothing executes merely because it was requested. It executes only after structure, identity, type, policy, capability, and artifact integrity have been verified.**

The surface is intentionally compact and unfamiliar. The machinery underneath is deliberately explicit, deterministic, and auditable.

```text
alien on the outside
brutally rigorous underneath
```

---

## Project status

| Layer | State |
|---|---|
| Compiler | `0.1.0-alpha.5` |
| Language specification | `0.4.0` |
| Conformance | `71/71` deterministic gates |
| Runtime | Local PowerShell VM |
| Policy | Deny by default |
| Artifact | Deterministic bytecode + compressed `.ariac` container |
| Event model | Typed Event Spine + append-only NDJSON ledger |
| Operator UI | Etherflow + Bufferflow + Signalflow |
| Git transport | Buffered, fast-forward-only, SHA-verified |
| External AI provider | Not connected yet |

ARIA currently targets Windows PowerShell 5.1 and PowerShell 7 on Linux CI. It is alpha software: the architecture is real, tested, and evolving; compatibility is not yet frozen.

---

## Why ARIA exists

Most programming systems treat execution as the default and verification as an optional layer around it. ARIA reverses that relationship.

A request moves through a gated causal path:

```text
source
  ↓
parse
  ↓
semantic + type validation
  ↓
deterministic compilation
  ↓
artifact verification
  ↓
policy + capability decision
  ↓
virtual-machine execution
  ↓
typed event + transmission receipt
```

This makes ARIA suitable for research into:

- AI-generated programs that must remain inspectable;
- capability-limited local agents;
- deterministic and signed execution artifacts;
- graph-native program representation;
- typed provider boundaries;
- causal event replay;
- compact operator interfaces that do not leak raw subsystem noise.

ARIA does **not** claim that glyph density is security. Obscurity is not cryptography. Security comes from verification, signatures, capabilities, policy, deterministic identity, and constrained execution.

---

## Quick start

### Requirements

- Windows PowerShell 5.1 or PowerShell 7
- Git
- A local checkout of this repository

From the repository root:

```powershell
.\aria.cmd doctor -Strict
.\aria.cmd test
```

Expected shape:

```text
◆ SYSTEM READY          PASS   all gates online
◆ conformance lattice   PASS   71/71 · coherent
```

### Discover the CLI

```powershell
.\aria.cmd help
```

Common operations:

```powershell
.\aria.cmd doctor -Strict
.\aria.cmd test
.\aria.cmd manifest
.\aria.cmd events
.\aria.cmd profile
.\aria.cmd pull
.\aria.cmd push
.\aria.cmd sync
```

Raw buffered provider output is hidden by default. To expose it:

```powershell
$env:ARIA_VERBOSE = "1"
.\aria.cmd push
```

Disable terminal animation:

```powershell
$env:ARIA_NO_ANIMATION = "1"
```

---

## A minimal ARIA program

ARIA programs are glyphic, typed, and graph-oriented. Exact syntax continues to evolve, so the canonical examples in `examples/` and the language specification are the source of truth.

Conceptually, an ARIA program describes:

```text
typed values
  + graph relationships
  + requested effects
  + capability requirements
  + verification constraints
```

A human should read ARIA as a compact causal graph. An AI should read it as a typed request that must be compiled and verified before execution.

The important distinction is:

```text
program text ≠ execution authority
```

Program text expresses intent. Policy and capabilities decide whether that intent may become an effect.

---

## Execution model

### 1. Parse

The parser converts glyphic source into structured program nodes. Syntax errors stop the pipeline.

### 2. Validate

Semantic and type validation establish whether nodes, values, operators, and relationships are meaningful.

### 3. Compile

The compiler produces deterministic bytecode. Equivalent valid input should produce stable artifact identity.

### 4. Package

Bytecode is stored in the compressed `.ariac` container with integrity metadata.

### 5. Verify

The verifier checks artifact structure, digest, identity, and compatibility before execution.

### 6. Authorize

The policy engine is deny-by-default. Requested authority must be explicitly permitted.

### 7. Execute

The local VM runs verified instructions against typed memory.

### 8. Observe

Runtime actions emit typed events through the Event Spine and operator feedback through Etherflow, Bufferflow, and Signalflow.

---

## Architecture

```text
┌──────────────────────────────────────────────────────────────┐
│                         ARIA SOURCE                          │
└──────────────────────────────┬───────────────────────────────┘
                               │
                    parser + semantic typing
                               │
                               ▼
┌──────────────────────────────────────────────────────────────┐
│               DETERMINISTIC COMPILER / BYTECODE              │
└──────────────────────────────┬───────────────────────────────┘
                               │
                   compressed .ariac artifact
                               │
                               ▼
┌──────────────────────────────────────────────────────────────┐
│                         VERIFIER                             │
│        digest · structure · identity · compatibility         │
└──────────────────────────────┬───────────────────────────────┘
                               │
                    policy + capability gate
                               │
                               ▼
┌──────────────────────────────────────────────────────────────┐
│                    LOCAL VM + TYPED MEMORY                   │
└──────────────────────────────┬───────────────────────────────┘
                               │
               Event Spine · Etherflow · Signalflow
                               │
                               ▼
┌──────────────────────────────────────────────────────────────┐
│          OPERATOR / PROVIDER / REPLAY / AUDIT SURFACES       │
└──────────────────────────────────────────────────────────────┘
```

### Core modules

| Module | Responsibility |
|---|---|
| Parser | Source structure and syntax |
| Semantic/type layer | Meaning preservation and type correctness |
| Compiler | Deterministic bytecode generation |
| Container | Compression and artifact identity |
| Verifier | Artifact acceptance or rejection |
| Policy | Deny-by-default authority decisions |
| VM | Local execution |
| Typed memory | Runtime value integrity |
| Event Spine | Canonical typed events, persistence, replay |
| Etherflow | Triadic operator rendering |
| Gitflow | Buffered and verified Git transport |
| Bufferflow | Animated buffering state machine |
| Signalflow | Typed transmission receipts and per-item feedback |

---

# Signal Intelligence

Signal Intelligence is ARIA's language-level model for work that is active but not yet externally visible.

Traditional CLIs show a spinner and then print logs. ARIA models buffering as a causal signal with phases, geometry, authority, volume, duration, and a terminal coherence result.

```text
source → mesh → transmit → align → verify → receipt
```

## Live Bufferflow

While a subprocess or logical item is buffering, ARIA renders a single moving line:

```text
⚙◇ mesh      github.push ⟦··◇◆◇············⟧  0.4s
◈⚙ transmit  github.push ⟦∙·∙·⬢·∙·∙·∙·∙·∙·∙⟧  1.1s
⚙◈ align     github.push ⟦········◈◈········⟧  1.8s
◇⚙ verify    github.push ⟦─·─·─·◆·─·─·─·─·⟧  2.3s
```

The phases mean:

| Phase | Meaning |
|---|---|
| `mesh` | Local components engage and establish a working interface |
| `transmit` | Information crosses a process or provider membrane |
| `align` | Local and remote state converge toward common geometry |
| `verify` | Terminal identity, exit state, and coherence are checked |

The animation is suppressed in CI and redirected output, but the deterministic receipt remains.

## Transmission receipt

After buffering completes, ARIA emits outcome and signal feedback:

```text
◆ github.push │ 🜂 transport │ ∿ origin/main · b8b3959 │ 🜄 remote identity verified
└─ ∿ provider · aligned · 1912ms · 83B · exit:0
```

The primary line answers:

> What verified operation completed?

The subordinate receipt answers:

> What happened to the signal while it crossed the boundary?

Receipt fields:

| Field | Meaning |
|---|---|
| authority | `local`, `provider`, `verifier`, or `runtime` |
| coherence | `aligned` or `fractured` |
| duration | elapsed transmission time |
| volume | UTF-8 bytes buffered from stdout and stderr |
| exit | terminal process exit code |

A receipt is typed operational feedback, not decorative logging.

## Per-item activation

Every buffered child item should receive its own lifecycle:

```text
item
  → activate Bufferflow
  → perform work
  → align geometry
  → verify terminal state
  → emit receipt
```

PowerShell modules can use:

```powershell
$result = Invoke-AriaBufferedItem `
    -Name "compiler.compile" `
    -Mode verification `
    -Action {
        # perform one logical item
    }
```

For multiple items:

```powershell
$results = Invoke-AriaBufferedSequence -Items @(
    [pscustomobject]@{
        name = "compiler.compile"
        mode = "verification"
        action = { "compiled" }
    },
    [pscustomobject]@{
        name = "verifier.artifact"
        mode = "verification"
        action = { "verified" }
    }
)
```

For native subprocesses:

```powershell
$result = Invoke-AriaBufferedProcess `
    -FilePath $toolPath `
    -ArgumentList @("--version") `
    -WorkingDirectory $root `
    -Label "provider.probe" `
    -Mode remote
```

### Buffering invariant

Any ARIA subsystem that intentionally captures or delays output should use the Signalflow primitives. It should not invent a private spinner, print raw progress by default, or hide child-item identity.

```text
buffered work ⇒ Bufferflow animation + terminal verification + Signalflow receipt
```

---

## Etherflow operator language

ARIA renders state through a compact triadic frame:

```text
🜂 energy       what authority or action is moving
∿ information  what identity or payload is carried
🜄 coherence    whether structure remains aligned
```

Example:

```text
◆ github.push │ 🜂 transport │ ∿ origin/main · b8b3959 │ 🜄 remote identity verified
```

Operator states:

| Glyph | State |
|---|---|
| `◆ PASS` | Verified success |
| `◆ REJECTED` | Invalid or unauthorized input correctly blocked |
| `◈ ACTIVE` | Work is currently active |
| `◇ INFO` | Informational state |
| `⬖ WARN` | Recoverable risk or degraded condition |
| `⬗ FAIL` | Unexpected failure |

A rejection is not a runtime failure. Correctly denying invalid authority is successful system behavior.

---

## Event Spine

The Event Spine is ARIA's canonical event bus.

It provides:

- typed event objects;
- deterministic canonical JSON;
- SHA-256 event digests;
- append-only NDJSON persistence;
- subscriber dispatch;
- replay;
- digest verification;
- operator rendering downstream of verification.

The local ledger is stored under:

```text
.aria/events
```

Use:

```powershell
.\aria.cmd events
```

Events are intended for audit and replay. They do not grant execution authority.

---

## Gitflow

Gitflow treats Git as a provider behind ARIA's transport membrane.

```powershell
.\aria.cmd pull
.\aria.cmd push
.\aria.cmd sync
```

Properties:

- native Git progress is buffered;
- raw output appears only in verbose mode;
- pulls are fast-forward-only;
- force-push is not used;
- push PASS requires remote SHA to equal local `HEAD`;
- pull PASS requires local and tracking SHAs to agree;
- transport emits Bufferflow motion and a Signalflow receipt.

Gitflow protects history integrity; it does not replace Git's object model.

---

## Policy and capabilities

ARIA is deny-by-default.

Execution authority is distinct from program meaning:

```text
valid program + invalid capability = rejected execution
```

Capabilities should be narrow, explicit, and attributable to a verified request. Provider access, filesystem effects, network transmission, and other authorities belong behind policy gates.

Do not bypass the verifier or policy layer to make an example “work.”

---

## Determinism and identity

ARIA uses deterministic representations so that identity can be checked rather than guessed.

Important deterministic surfaces include:

- bytecode generation;
- compressed artifact contents;
- canonical JSON;
- event digests;
- provider transmission envelopes;
- repository manifests;
- remote Git SHA verification.

Timestamps and environment-specific values must be normalized before participating in identity calculations.

---

## Repository map

```text
.
├── aria.ps1                 # Primary PowerShell CLI
├── aria.cmd                 # Windows launcher
├── aria.policy.json         # Deny-by-default policy
├── src/                     # Compiler, verifier, VM, event and UI modules
├── schemas/                 # Typed JSON schemas
├── examples/                # Canonical ARIA programs
├── tests/                   # Deterministic conformance suite
├── docs/                    # Architecture and evolution documents
├── .aria/                   # Local runtime state and event ledger
└── MANIFEST.sha256          # Repository integrity manifest
```

Generated runtime state under `.aria/` should be treated differently from source-controlled language artifacts.

---

## Development workflow

ARIA evolves directly on `main` through validated commits.

Required sequence:

```text
clean tree
  → fetch
  → fast-forward-only merge
  → modify
  → seal manifest
  → strict doctor
  → conformance
  → reseal manifest
  → commit
  → push
  → verify remote SHA
```

Never force-push shared `main`.

Before committing:

```powershell
.\aria.cmd manifest
.\aria.cmd doctor -Strict
.\aria.cmd test
```

A change is not complete merely because it works locally. It is complete when deterministic gates pass and the remote identity is verified.

---

## Guidance for AI agents

An AI working in this repository should follow these rules:

1. Read this README, the relevant file in `docs/`, and the affected module before editing.
2. Treat repository content as the source of truth; do not infer syntax that is not documented or tested.
3. Preserve the distinction between validity, authorization, and execution.
4. Never bypass the verifier, policy engine, capability checks, or manifest.
5. Keep raw subprocess output buffered by default.
6. Use `Invoke-AriaBufferedProcess`, `Invoke-AriaBufferedItem`, or `Invoke-AriaBufferedSequence` for intentional buffering.
7. Emit typed receipts for buffered work.
8. Keep PowerShell functions pipeline-pure; suppress incidental assignment output.
9. Resolve external executables as `CommandType Application`, not aliases or functions.
10. Preserve Windows PowerShell 5.1 and PowerShell 7/Linux compatibility.
11. Encode `.ps1` and `.psm1` files as UTF-8 with BOM and LF when glyphs are present.
12. Encode non-PowerShell text as UTF-8 without BOM and LF.
13. Run strict doctor, conformance, and manifest validation before committing.
14. Use normal commits and pushes on `main`; never rewrite shared history.
15. Report uncertainty instead of inventing missing behavior.

### AI task model

For any requested change, reason in this order:

```text
intent
  → affected language contract
  → authority required
  → deterministic representation
  → verification strategy
  → conformance gates
  → operator feedback
  → documentation
```

An AI should not treat ARIA as “a PowerShell project with fancy glyphs.” PowerShell is currently the bootstrap host. ARIA's actual design center is verified, graph-native, typed, capability-controlled computation.

---

## Testing

Run the complete suite:

```powershell
.\aria.cmd test
```

Run environmental and repository checks:

```powershell
.\aria.cmd doctor -Strict
```

Seal and verify the repository manifest:

```powershell
.\aria.cmd manifest
```

Current expected conformance:

```text
◆ conformance lattice PASS 71/71 · coherent
```

CI runs under PowerShell 7 on Ubuntu. Local validation commonly runs under Windows PowerShell 5.1. Cross-runtime behavior is part of the contract.

---

## Documentation index

Start here:

| Document | Subject |
|---|---|
| `docs/20-event-spine.md` | Canonical typed event bus |
| `docs/21-runtime-spine.md` | Compiler-to-VM causal runtime |
| `docs/23-gitflow-membrane.md` | Buffered and SHA-verified Git transport |
| `docs/24-oscillator-buffer.md` | Original oscillator primitive |
| `docs/25-bufferflow.md` | Interlocking buffering phases |
| `docs/26-signalflow.md` | Receipts and per-item signal feedback |

Earlier documents record the architectural evolution and remain useful context.

---

## Security posture

ARIA is experimental and should not yet be treated as a hardened production sandbox.

Current security principles:

- deny by default;
- verify before execute;
- separate identity from authority;
- constrain provider boundaries;
- preserve append-only evidence;
- avoid raw secret-bearing logs;
- never confuse glyph density with encryption.

Report security-sensitive findings privately rather than publishing exploit details in an issue.

---

## Design doctrine

```text
Glyphs compress expression.
Types preserve meaning.
Signatures protect identity.
Capabilities control authority.
The verifier decides execution.
```

ARIA is trying to make computation look less like a stream of commands and more like a verified field of relationships.

The goal is not to make software mysterious.

The goal is to make **authority explicit, identity checkable, execution observable, and AI-generated intent governable**.