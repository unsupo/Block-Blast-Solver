# Block Blast Gymnasium Environment & PPO RL Design Specification

This document details the reinforcement learning architecture, observation/action space formulations, action masking theory, and training dynamics for **Block Blast!**.

---

## 1. Action Space Formulation

- **Type**: `gymnasium.spaces.Discrete(192)`
- **Dimension**: 192 total actions.
- **Action Decomposition**:
  $$\text{Action } A \in [0, 191]$$
  $$\text{slot} = \lfloor A / 64 \rfloor \in \{0, 1, 2\}$$
  $$\text{cell} = A \pmod{64} \in [0, 63]$$
  $$\text{row} = \lfloor \text{cell} / 8 \rfloor \in [0, 7]$$
  $$\text{col} = \text{cell} \pmod 8 \in [0, 7]$$

### Action Composition
$$\text{Action}(s, r, c) = s \times 64 + r \times 8 + c$$

---

## 2. Invalid Action Masking (Essential for PPO)

Because the majority of actions at any given step are illegal (piece exceeds boundary, overlaps placed blocks, or references an already-used dock slot), standard unmasked exploration causes agents to waste millions of steps sampling illegal moves.

### Mask Construction
The environment returns an action mask vector $M \in \{0, 1\}^{192}$ in `info["action_mask"]`:
$$M[A] = \begin{cases} 
1, & \text{if } \text{dock}[\text{slot}] \ge 0 \ \land \ (r + H \le 8) \ \land \ (c + W \le 8) \ \land \ (\text{board} \ \& \ \text{mask} == 0) \\ 
0, & \text{otherwise} 
\end{cases}$$

### Categorical Action Masking Formulation
In the policy network:
$$\hat{z}_i = \begin{cases} 
z_i, & \text{if } M[i] == 1 \\ 
-\infty \ (-10^8), & \text{if } M[i] == 0 
\end{cases}$$

$$\pi(a_i | s) = \frac{\exp(\hat{z}_i)}{\sum_j \exp(\hat{z}_j)}$$

- The probability of sampling any illegal action is exactly **zero**.
- The gradient with respect to illegal action logits is zero, stabilizing policy gradients.

---

## 3. Observation Space

- **Type**: `gymnasium.spaces.Box(low=0.0, high=1.0, shape=(4, 8, 8), dtype=np.float32)`
- **Channels**:
  - `Channel 0` ($8 \times 8$): Current board state. Binary float: $1.0$ if cell is occupied, $0.0$ if empty.
  - `Channel 1` ($8 \times 8$): Dock slot 0 piece mask (aligned at top-left, 0.0 if already played).
  - `Channel 2` ($8 \times 8$): Dock slot 1 piece mask (aligned at top-left, 0.0 if already played).
  - `Channel 3` ($8 \times 8$): Dock slot 2 piece mask (aligned at top-left, 0.0 if already played).

---

## 4. Dual Bitboard Engine Architecture

### C++ Native Core (`bitboard.h` / `block_blast_c.cpp`)
- Compiled with `clang++ -O3 -std=c++17 -shared -fPIC`.
- Exposes pure C ABI functions (`bb_create`, `bb_step`, `bb_get_action_mask`, `bb_get_observation`).
- Python binding via `ctypes`.
- Zero-copy mask and observation retrieval directly into NumPy buffers.
- Throughput: **>86,000 steps/sec** via Python `ctypes` (>10,000,000 steps/sec in C++).

### Pure Python Fallback (`bitboard_py.py`)
- Independent, standalone NumPy implementation.
- Employs identical 64-bit bitboard operations and row/col clear logic.
- Requires zero compiler toolchain; runs on any standard Python environment.

---

## 5. PPO Agent Implementation Details (`ppo_agent.py`)

- **Architecture**:
  - Backbone: 3-layer Convolutional Neural Network (Conv2d channels $4 \to 64 \to 128 \to 64$, kernel size 3, padding 1) with ReLU activations.
  - Linear feature trunk ($4096 \to 256$).
  - Policy Head: Linear($256 \to 192$).
  - Value Head: Linear($256 \to 1$).
- **Optimization**:
  - Generalized Advantage Estimation (GAE, $\gamma=0.99, \lambda=0.95$).
  - Clipped surrogate loss ($\epsilon = 0.2$).
  - Value function MSE loss with clipping.
  - Entropy bonus ($\alpha = 0.01$).
  - Adam optimizer ($\text{lr} = 2.5 \times 10^{-4}, \epsilon = 10^{-5}$).
  - Hardware acceleration: Automatic detection of Apple Silicon MPS (`mps`), NVIDIA CUDA (`cuda`), or CPU.
