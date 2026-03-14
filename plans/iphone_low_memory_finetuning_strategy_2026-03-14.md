# iPhone Low-Memory Fine-Tuning Strategy

Date: March 14, 2026

## Decision

For this app, the production path should be:

1. `QLoRA` as the default iPhone fine-tuning mode.
2. `DoRA` as the quality-focused adapter option.
3. `APOLLO` only as an experimental full-model research path on tiny models.
4. `GaLore` kept out of the normal UI until there is a paper-faithful full-parameter implementation.

## Why

- The current app fine-tunes through `LoRAContainer` and `LoRATrain.train(...)`, so any optimizer only ever sees adapter gradients. That is not full-parameter GaLore.
- MLX on Apple silicon uses CPU/GPU with unified memory, which is a strong fit for quantized adapter training but a poor fit for repeated CPU SVD during training.
- MLX currently exposes `LoRA` and `DoRA` directly through `LoRAConfiguration.FineTuneType`, making them low-risk product paths in this repo.

## Apple Silicon / iPhone constraints

- iPhone training lives inside a unified memory budget; app guardrails in this repo cap resident memory at 2.2 GB.
- Apple’s A18 and A18 Pro chips emphasize GPU + Neural Engine throughput, but the MLX stack used here targets CPU/GPU execution rather than ANE-specific training.
- In practice, the iPhone constraint is not just raw compute. It is unified-memory pressure, thermal throttling, and the cost of moving large activations and gradients through the training loop.

## Shipping path

### QLoRA

- Quantized MLX base model, typically `4-bit`.
- Train only adapter weights.
- Use `Adam` on trainable adapter parameters.
- Keep micro-batch at `1`, adapter rank at `4-8`, and sequence length at `<= 128`.
- This is the safest path for models around `0.5B` to `1.5B`.

### DoRA

- Same deployment model as LoRA, but with `fineTuneType: .dora`.
- Better quality upside than plain LoRA at similar adapter memory cost.
- Prefer quantized bases on iPhone even though DoRA itself does not require quantization.

## Research path

### APOLLO

- Better fit than GaLore for iPhone because it avoids repeated SVD refreshes.
- Can be prototyped with MLX `valueAndGrad(model: ...)` and a custom optimizer.
- In this repo, APOLLO should be treated as a tiny-model experimental path first, not an end-user training option.

### GaLore

- Only worth reviving here if it becomes a separate full-model training loop.
- Must not reuse the LoRA adapter training path and still be described as GaLore.

## Source notes

- GaLore paper: https://arxiv.org/abs/2403.03507
- QLoRA paper: https://arxiv.org/abs/2305.14314
- DoRA paper: https://arxiv.org/abs/2402.09353
- APOLLO paper: https://arxiv.org/abs/2412.05270
- Apple Foundation Models adapter training requirements: https://developer.apple.com/apple-intelligence/foundation-models-adapter/
- MLX project: https://github.com/ml-explore/mlx
- MLX Swift LM project: https://github.com/ml-explore/mlx-swift-lm
