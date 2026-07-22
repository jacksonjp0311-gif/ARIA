# Signalflow alpha.14

Signalflow turns buffering into a language-level signal contract.

A buffered operation now has two visible stages:

```text
⚙◈ align     github.push ⟦········◈◈········⟧  1.8s
◆ github.push │ 🜂 transport │ ∿ origin/main · 1984001 │ 🜄 remote identity verified
└─ ∿ provider · aligned · 1842ms · 4281B · exit:0
```

The PASS frame states the verified outcome. The subordinate receipt states what happened to the signal:

- authority membrane (`local`, `provider`, `verifier`, or `runtime`);
- coherence (`aligned` or `fractured`);
- elapsed transmission time;
- buffered byte count;
- terminal exit code.

## Per-item activation

`Invoke-AriaBufferedItem` applies Bufferflow to one logical item.

`Invoke-AriaBufferedSequence` applies it independently to every item in a sequence. Each item receives its own animation, completion geometry, and signal receipt. No aggregate operation may hide which child item was buffering.

## Signal theory

ARIA treats a buffered operation as a causal signal:

```text
source → mesh → transmit → align → verify → receipt
```

The receipt is not decorative logging. It is typed feedback describing signal duration, volume, authority boundary, terminal status, and coherence.

CI and redirected output suppress moving animation, but receipts remain deterministic text so automation still receives transmission feedback.