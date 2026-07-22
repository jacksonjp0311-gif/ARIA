# Bytecode and `.ariac` Container

ARIA 0.4.0 lowers typed source into structured stack bytecode. The bytecode is independently verified before it can execute.

## Instruction families

| Family | Opcodes | Contract |
|---|---|---|
| Constants and locals | `PUSH_CONST`, `LOAD`, `STORE`, `SET` | Move typed scalar values between the constant pool, operand stack, and lexical bindings. |
| Arithmetic | `ADD`, `SUB`, `MUL`, `DIV`, `NEG` | Typed numeric operations; `ADD` also permits `Text + Text`. |
| Logic and comparison | `EQ`, `NE`, `LT`, `LE`, `GT`, `GE`, `AND`, `OR`, `NOT` | Produce verified `Bool` results. |
| Transmission | `EMIT`, `SIGNAL` | Emit console output or a structured Traceflow event. |
| Memory | `MEM_SET`, `MEM_GET` | Access declared typed persistent memory fields. |
| Authority and assertions | `REQUIRE_CAP`, `ASSERT_TRUE` | Activate declared capability authority or enforce a Boolean invariant. |
| Filesystem | `FS_READ`, `FS_WRITE` | Perform policy-gated, workspace-confined text I/O. |
| Agents | `AGENT_DISPATCH` | Emit a deterministic agent task event. |
| Functions | `CALL`, `RETURN` | Enter a typed local frame and return exactly one scalar result, including `Null`. |
| Structured control | `IF`, `REPEAT` | Execute nested verified instruction sequences without arbitrary jump offsets. |
| Termination | `HALT` | Stop the entry flow. |

The normative machine-readable table is [`grammar/opcodes.json`](../grammar/opcodes.json).

## Why structured control

`IF` contains explicit `then` and `else` instruction arrays. `REPEAT` contains an explicit body, iterator name, and maximum bound. This makes control topology visible to the verifier and disassembler and avoids accepting arbitrary branch offsets in the bootstrap format.

## Verifier contract

The verifier checks:

- compiler and specification locks;
- opcode allowlisting and required fields;
- constant-pool indexes and scalar values;
- operand-stack underflow and terminal stack depth;
- arithmetic, comparison, Boolean, call, return, memory, and dispatch types;
- function argument counts and return contracts;
- lexical variable definitions;
- memory, capability, function, and agent references;
- capability activation before host effects;
- structured branch and loop bodies;
- function `RETURN` and entry-flow `HALT` termination.

The VM repeats runtime type, policy, path, memory, call-depth, and loop-bound checks rather than trusting the compiler.

## Binary envelope

```text
offset  size  field
0       4     ASCII magic: ARIA
4       1     container version: 1
5       1     compression: 1 = gzip
6       2     reserved: zero
8       4     uncompressed payload length, little-endian
12      4     compressed payload length, little-endian
16      32    SHA-256 of canonical uncompressed payload
48      n     gzip-compressed canonical JSON bytecode
```

Both compressed and uncompressed sizes are bounded. Decoding verifies the fixed header, exact encoded length, declared decompressed length, UTF-8 validity, SHA-256 digest, JSON structure, and bytecode model before execution.

The canonical JSON payload keeps the alpha format inspectable. A later container version may introduce a denser binary instruction section without changing ARIA source semantics.

## Connectflow opcodes

`CONNECT_OPEN`, `CONNECT_INTENT`, `CONNECT_PROPOSE`, `CONNECT_CONSENT`, and `CONNECT_CLOSE` encode the local intent/proposal/consent lifecycle. The verifier checks declaration references and operand types; the VM enforces protocol order and deterministic closure.
