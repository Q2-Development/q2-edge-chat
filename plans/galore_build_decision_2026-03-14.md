# GaLore Build Decision

Date: March 14, 2026

## Current decision

Do not build a paper-faithful GaLore iPhone path yet.

## Why

1. The app now has a durable telemetry path for every fine-tune run, including device metadata, peak memory, optimizer memory, and final status.
2. The codebase now also has an experimental APOLLO-style full-model trainer, which is a better fit for iPhone research because it avoids repeated SVD refreshes.
3. Until APOLLO is measured on device, building full GaLore would add more architectural risk than signal.

## Decision rule

Revisit GaLore only if all of the following are true:

1. APOLLO full-model runs on tiny models complete on iPhone without guardrail failure.
2. Telemetry shows meaningful optimizer-memory reduction versus a full Adam baseline.
3. Thermal behavior is acceptable for repeated short experiments.
4. Validation loss improves enough to justify a more complex full-model path.

If those conditions are not met, GaLore remains a no-go for iPhone in this app.

## Near-term recommendation

1. Keep shipping focus on QLoRA and DoRA.
2. Use telemetry to build a real device envelope.
3. Use APOLLO as the only full-model research track until measurements prove it is insufficient.
