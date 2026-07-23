# Source Language Core alpha.21

ARIA now has a small ordinary source language above its verification substrate.

## Principle

```text
ordinary code should be ordinary
dangerous effects should be extraordinary
```

Alpha.21 is intentionally pure. Programs cannot access files, processes, repositories, networks, secrets, or deployment systems.

## Commands

```powershell
.\aria-source.cmd check examples\source-core\03-function.aria
.\aria-source.cmd run examples\source-core\03-function.aria
.\aria-source.cmd ir examples\source-core\03-function.aria
```

## Source forms

### Immutable bindings

```aria
let radius: Int = 7;
let diameter: Int = radius * 2;
emit diameter;
```

Bindings cannot be reassigned.

### Pure functions

```aria
fn add(x: Int, y: Int) -> Int {
    x + y
}

emit add(20, 22);
```

Functions have explicit parameter and return types.

### Conditionals

```aria
emit if temperature > 30 { "hot" } else { "mild" };
```

Both branches must have the same type.

### Values

Alpha.21 supports:

```text
Int
Text
Bool
```

### Operators

```text
+ - * /
== !=
< <= > >=
&& || !
```

`+` operates on either two integers or two text values.

Integer division truncates toward zero.

## Compilation path

```text
source text
→ deterministic tokens
→ source AST
→ static type verification
→ pure evaluation
→ aria.source-ir/0.7
→ SHA-256 identity
```

## Current boundaries

Alpha.21 deliberately excludes:

- mutable bindings;
- recursion;
- closures;
- collections;
- records;
- tagged unions;
- pattern matching;
- modules;
- effects;
- implicit type coercion.

Those features should arrive incrementally, with conformance gates and readable diagnostics.

## Success criterion

A programmer can write and run small typed programs without touching:

```text
PowerShell internals
JSON fixtures
capability ledgers
graph transition objects
governance envelopes
```

The governance substrate remains available for later effectful execution, but it is not exposed in ordinary pure programs.