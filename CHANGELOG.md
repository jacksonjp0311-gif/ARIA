# Changelog

All notable changes to ARIA are recorded here. The compiler, language specification, and container contract are versioned independently.

## 0.1.0-alpha.5 — Connectflow

- Advanced the language lock to specification `0.4.0`.
- Added first-class connection declarations with operator, agent, and protocol identities.
- Added `connect`, `intent`, `propose`, `consent`, and `disconnect` statements.
- Added five verified connection opcodes and VM lifecycle enforcement.
- Added deterministic connection events and the `aria connect` CLI command.
- Added `REJECT` as a successful operator outcome for withheld consent or expected denial.
- Fixed quiet compiler gates so negative conformance probes do not render as failed tests.
- Expanded conformance to 42 deterministic gates.

## 0.1.0-alpha.4 — Coreflow

- Advanced the language lock to specification `0.3.0`.
- Added scalar types, inferred and explicit bindings, assignment, and typed memory fields.
- Added host-independent expression parsing with arithmetic, comparison, Boolean, unary, and call expressions.
- Added typed functions, local frames, returns, lexical `if/else`, and bounded `repeat`.
- Added module identity metadata and deterministic agent-dispatch events.
- Expanded the opcode registry to 32 instructions and added structured control bytecode.
- Hardened the verifier against arithmetic type confusion, invalid call contracts, non-text agent tasks, and malformed structured sequences.
- Revalidated function returns and persisted memory types in the VM.
- Added Coreflow examples, algorithms, cross-domain discoveries, ADR 0005, and 34 conformance gates.

## 0.1.0-alpha.3 — Traceflow

- Added `signal pulse|pass|warn|fail|info` as a language primitive.
- Added verified `SIGNAL` bytecode and structured VM events.
- Added descending tree rendering, `trace`, `graph`, and related CLI aliases.
- Advanced the language specification to `0.2.0` and expanded conformance to 23 gates.

## 0.1.0-alpha.2 — Operator renderer

- Added the ARIA diamond operator renderer with ANSI-aware colors and pulsing active glyphs.
- Styled doctor, gate, compile, run, test, install, manifest, and verification workflows.
- Added concise normal output and `-VerboseOutput` / `ARIA_VERBOSE=1` diagnostics.
- Suppressed PowerShell unapproved-verb import warnings at the CLI boundary.
- Fixed Windows PowerShell 5.1 UTF-8 glyph parsing, blank-line lexing, scalar array unrolling, and path-comparison compatibility.

## 0.1.0-alpha.1 — Bootstrap

- Added the Windows PowerShell 5.1-compatible compiler and virtual machine.
- Added validated glyph aliases and semantic graph metadata.
- Added deterministic gzip-compressed `.ariac` containers with SHA-256 integrity.
- Added explicit durable memory outside compiled artifacts.
- Added deny-by-default capability policy and repository-confined file access.
- Added compiler/spec/container locks, hostile-bytecode verification, repository manifests, schemas, examples, and research documentation.
