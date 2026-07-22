# AI Bridge Architecture

ARIA's deterministic core and an AI model have different jobs.

## AI responsibilities

- translate human intent into proposed ARIA;
- inspect graph, memory schemas, diagnostics, and repository state;
- explain failed gates;
- propose patches and tests;
- estimate uncertainty and cite evidence.

## Compiler responsibilities

- parse exact syntax;
- resolve names and types;
- enforce authority;
- produce deterministic bytecode;
- verify containers;
- execute defined opcodes only.

## Proposed protocol

A future AI bridge should exchange a signed proposal envelope containing intent, source diff, requested capabilities, evidence, expected tests, and rollback plan. The compiler validates the resulting ARIA exactly as it validates human-authored source.

No model probability, role name, or glyph grants authority. Only a valid capability accepted by policy and activated in deterministic execution can cross a host boundary.
