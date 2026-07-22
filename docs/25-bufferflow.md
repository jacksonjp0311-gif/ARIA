# Bufferflow alpha.13

Bufferflow is ARIA's universal visual contract for intentional buffering.

```text
⚙◇ mesh      github.push ⟦··◇◆◇············⟧  0.4s
◈⚙ transmit  github.push ⟦∙·∙·⬢·∙·∙·∙·∙·∙·∙⟧  1.1s
⚙◈ align     github.push ⟦········◈◈········⟧  1.8s
◇⚙ verify    github.push ⟦─·─·─·─·◆·─·─·─·─·⟧  2.3s
```

The motion communicates four causal phases:

1. **mesh** — local components engage.
2. **transmit** — information crosses the provider membrane.
3. **align** — remote and local geometry converge.
4. **verify** — identity and coherence lock.

Completion briefly resolves into aligned geometry before the verified PASS frame replaces it.

## Universal process membrane

`Invoke-AriaBufferedProcess` is the required primitive for any subprocess whose native output is buffered. It owns stdout/stderr capture, animation, terminal-state verification, verbose replay, and one typed process result.

Animation is automatically suppressed in CI, redirected output, or when `ARIA_NO_ANIMATION=1`.

Raw provider output remains available with `ARIA_VERBOSE=1`.