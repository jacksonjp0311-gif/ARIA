# Event Spine alpha.8

Event Spine is ARIA's canonical internal event bus. Compiler, verifier, VM, policy, connection, and provider subsystems can now describe runtime facts with one typed object rather than writing provider-specific terminal text.

Every `aria.event` contains:

- a monotonic sequence;
- domain and phase identities;
- execution state;
- Etherflow's energy, information, and coherence lanes;
- source identity and UTC occurrence time;
- typed data;
- a canonical SHA-256 digest.

The spine supports in-memory subscribers, optional append-only NDJSON persistence under `.aria/events`, replay verification, and direct Etherflow rendering.

## Authority boundary

Events describe what happened. They do not grant authority. Policy and bytecode verification remain independent execution gates.

## CLI

`aria events` reads the verified local event ledger and renders recent events through the active Etherflow profile.

`aria transmit` publishes provider normalization, artifact sealing, and provenance verification into the same spine used by future compiler and VM integrations.