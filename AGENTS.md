# ARIA Agent Bootstrap

ARIA is a repository-native language, compiler, verifier, bytecode container, and local virtual machine.

## Start here

From the repository root, run:

```powershell
.\aria.cmd begin --json
.\aria.cmd doctor -Strict
.\aria.cmd test
```

A healthy baseline must report:

- repository manifest integrity
- `SYSTEM READY`
- full conformance with zero failures

## Authoritative entrypoints

- `aria.cmd` — canonical Windows command
- `aria.ps1` — command dispatcher
- `ARIA-RUNTIME.json` — machine-readable repository map
- `src/Aria.Gate.psm1` — compiler gate
- `src/Aria.Parser.psm1` — parser
- `src/Aria.Semantics.psm1` — semantic analysis
- `src/Aria.Bytecode.psm1` — bytecode and container
- `src/Aria.VM.psm1` — local virtual machine
- `src/Aria.SourceCore.psm1` — source-language core
- `grammar/alchemy.json` — executable triadic glyph syntax
- `tests/Run-Tests.ps1` — conformance lattice

## Evolution rule

Do not replace working repository behavior with standalone demonstrations.

Every evolution must:

1. begin from a clean Git tree;
2. preserve the preceding stable tag;
3. update repository-native implementation, documentation, tests, and manifest;
4. run `.\aria.cmd doctor -Strict`;
5. run `.\aria.cmd test`;
6. require zero failed gates before commit or push.

The protected baseline is `aria-alpha21-stable`.
## Alchemical glyph syntax

The first executable triad lowers into existing verified operations:

```aria
🜁 value: Number = 40 + 2
🜂 value
🜄 Project.status = "active"
🜁 Project.status -> state: Text
```

- `🜁` binds or recalls.
- `🜂` emits.
- `🜄` remembers.

Glyph syntax does not bypass semantics, bytecode verification, policy, or the virtual machine.
## Governed application and Git transaction

Authorized evolution is completed through:

```powershell
.\aria.cmd evolve apply <proposal-id> -Message "Commit message"
```

Use `-Push` only for an explicitly requested remote update. The application
module binds candidate bytes to the authorized base commit, seals the manifest,
executes strict doctor and conformance gates, commits only approved paths, and
writes an application receipt beneath `.aria/evolution/`.
## Signal-subset evidence

Use `src/Aria.SignalSubset.psm1` for bounded operational evidence. Declare a
field allowlist, purpose, source, consent scope, retention and finite limit.
Exclude raw stdout, stderr, secrets, credentials and unrelated user data by
default. A subset digest is evidence, not execution authority.