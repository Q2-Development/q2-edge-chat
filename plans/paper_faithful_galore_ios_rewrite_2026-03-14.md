# Paper-Faithful GaLore Rewrite Plan

Date: March 14, 2026

## Current mismatch

The current app path is:

1. Load an MLX language model.
2. Apply `LoRAContainer`.
3. Train through `LoRATrain.train(...)`.
4. Swap `Adam` for a projected optimizer when `method == .galore`.

That is not paper-faithful GaLore. It is projected optimization on adapter weights.

## What a real GaLore implementation requires

### 1. Separate full-parameter training path

- No `LoRAContainer`.
- No adapter-only training loop.
- Train the model’s real trainable parameters directly.

### 2. Custom training loop

- Use MLX `valueAndGrad(model: ...)` instead of `LoRATrain.train(...)`.
- Own batching, forward pass, loss computation, gradient update, checkpointing, validation, and saving.
- Make this a distinct orchestrator instead of overloading the existing adapter path.

### 3. Layerwise or post-accumulate updates

- The GaLore paper’s memory story depends on avoiding a giant full-gradient residency window.
- Inference: to make this real on iPhone, we need either:
  - per-layer gradient projection and optimizer update during backward, or
  - an MLX-supported post-accumulate hook that lets us project and discard gradients immediately.

Without that, full-model gradients still spike memory before projection.

### 4. Activation checkpointing

- Needed to lower activation memory for sequence lengths that are otherwise unrealistic on iPhone.
- MLX exposes checkpointing primitives in the core stack, but they are not currently wired into this app’s model path.
- This should be part of the full-model experimental trainer from day one.

### 5. SVD strategy

- Exact CPU SVD on iPhone is not a good production fit.
- If GaLore remains the target, use one of:
  - randomized SVD,
  - power iteration,
  - much less frequent basis refresh,
  - or a Mac-first training path instead of iPhone-first.

## Recommended implementation order

1. Build a tiny-model full-parameter trainer with MLX `valueAndGrad(model: ...)`.
2. Add activation checkpointing and gradient clipping.
3. Add projected optimizer state with low-rank moments.
4. Measure memory on `<= 350M` models first.
5. Only then decide whether exact GaLore is still worth pursuing versus APOLLO.

## Acceptance criteria

- Full-model trainer runs without `LoRAContainer`.
- Memory usage is measured on device, not inferred from adapter state only.
- Peak resident memory stays below the app guardrail on a tiny model.
- Validation loss decreases in repeated runs.
- The UI labels the feature as experimental until those conditions are satisfied.

## Source notes

- GaLore paper: https://arxiv.org/abs/2403.03507
- Q-GaLore paper: https://proceedings.mlr.press/v280/zhang25a.html
- APOLLO paper: https://arxiv.org/abs/2412.05270
- MLX project: https://github.com/ml-explore/mlx
- MLX Swift LM project: https://github.com/ml-explore/mlx-swift-lm
