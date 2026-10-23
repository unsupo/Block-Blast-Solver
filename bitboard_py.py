import numpy as np
import random
from typing import Tuple, List, Optional

# All 43 exact shapes reverse-engineered from libtask.so
SHAPES_DATA = [
    {"id": 0, "kind": 0, "fill": 1, "w": 1, "h": 1, "masks": [1]},
    {"id": 1, "kind": 0, "fill": 1, "w": 1, "h": 1, "masks": [1]},
    {"id": 2, "kind": 1, "fill": 2, "w": 1, "h": 2, "masks": [1, 1]},
    {"id": 3, "kind": 0, "fill": 2, "w": 2, "h": 1, "masks": [3]},
    {"id": 4, "kind": 1, "fill": 3, "w": 1, "h": 3, "masks": [1, 1, 1]},
    {"id": 5, "kind": 0, "fill": 3, "w": 3, "h": 1, "masks": [7]},
    {"id": 6, "kind": 3, "fill": 3, "w": 2, "h": 2, "masks": [3, 2]},
    {"id": 7, "kind": 1, "fill": 4, "w": 1, "h": 4, "masks": [1, 1, 1, 1]},
    {"id": 8, "kind": 3, "fill": 4, "w": 3, "h": 2, "masks": [4, 7]},
    {"id": 9, "kind": 2, "fill": 4, "w": 2, "h": 2, "masks": [3, 3]},
    {"id": 10, "kind": 3, "fill": 4, "w": 3, "h": 2, "masks": [2, 7]},
    {"id": 11, "kind": 0, "fill": 5, "w": 5, "h": 1, "masks": [31]},
    {"id": 12, "kind": 3, "fill": 5, "w": 3, "h": 3, "masks": [7, 1, 1]},
    {"id": 13, "kind": 2, "fill": 9, "w": 3, "h": 3, "masks": [7, 7, 7]},
    {"id": 14, "kind": 3, "fill": 4, "w": 3, "h": 2, "masks": [3, 6]},
    {"id": 15, "kind": 3, "fill": 3, "w": 2, "h": 2, "masks": [3, 1]},
    {"id": 16, "kind": 3, "fill": 4, "w": 2, "h": 3, "masks": [2, 3, 1]},
    {"id": 17, "kind": 0, "fill": 4, "w": 4, "h": 1, "masks": [15]},
    {"id": 18, "kind": 3, "fill": 4, "w": 3, "h": 2, "masks": [6, 3]},
    {"id": 19, "kind": 3, "fill": 4, "w": 2, "h": 3, "masks": [1, 3, 2]},
    {"id": 20, "kind": 3, "fill": 4, "w": 2, "h": 3, "masks": [2, 3, 2]},
    {"id": 21, "kind": 3, "fill": 5, "w": 3, "h": 3, "masks": [7, 4, 4]},
    {"id": 22, "kind": 1, "fill": 5, "w": 1, "h": 5, "masks": [1, 1, 1, 1, 1]},
    {"id": 23, "kind": 3, "fill": 5, "w": 3, "h": 3, "masks": [4, 4, 7]},
    {"id": 24, "kind": 3, "fill": 5, "w": 3, "h": 3, "masks": [1, 1, 7]},
    {"id": 25, "kind": 3, "fill": 4, "w": 2, "h": 3, "masks": [1, 3, 1]},
    {"id": 26, "kind": 3, "fill": 4, "w": 3, "h": 2, "masks": [7, 2]},
    {"id": 27, "kind": 3, "fill": 3, "w": 2, "h": 2, "masks": [2, 3]},
    {"id": 28, "kind": 3, "fill": 3, "w": 2, "h": 2, "masks": [1, 3]},
    {"id": 29, "kind": 3, "fill": 4, "w": 2, "h": 3, "masks": [1, 1, 3]},
    {"id": 30, "kind": 3, "fill": 4, "w": 3, "h": 2, "masks": [7, 1]},
    {"id": 31, "kind": 3, "fill": 4, "w": 2, "h": 3, "masks": [3, 2, 2]},
    {"id": 32, "kind": 3, "fill": 4, "w": 2, "h": 3, "masks": [3, 1, 1]},
    {"id": 33, "kind": 3, "fill": 4, "w": 3, "h": 2, "masks": [1, 7]},
    {"id": 34, "kind": 3, "fill": 4, "w": 3, "h": 2, "masks": [7, 4]},
    {"id": 35, "kind": 2, "fill": 6, "w": 3, "h": 2, "masks": [7, 7]},
    {"id": 36, "kind": 2, "fill": 6, "w": 2, "h": 3, "masks": [3, 3, 3]},
    {"id": 37, "kind": 3, "fill": 2, "w": 2, "h": 2, "masks": [2, 1]},
    {"id": 38, "kind": 3, "fill": 2, "w": 2, "h": 2, "masks": [1, 2]},
    {"id": 39, "kind": 3, "fill": 3, "w": 3, "h": 3, "masks": [4, 2, 1]},
    {"id": 40, "kind": 3, "fill": 3, "w": 3, "h": 3, "masks": [1, 2, 4]},
    {"id": 41, "kind": 3, "fill": 3, "w": 3, "h": 3, "masks": [1, 2, 4]},
    {"id": 42, "kind": 3, "fill": 4, "w": 2, "h": 3, "masks": [2, 2, 3]},
]

# Precompute 64-bit placement bitmasks for all 43 shapes at each (r, c)
SHAPE_MASKS = np.zeros((43, 8, 8), dtype=np.uint64)
for s in SHAPES_DATA:
    sid = s["id"]
    w, h = s["w"], s["h"]
    masks = s["masks"]
    for r in range(8 - h + 1):
        for c in range(8 - w + 1):
            m = 0
            for dr in range(h):
                row_bits = masks[dr]
                for dc in range(w):
                    if (row_bits >> (w - 1 - dc)) & 1:
                        bit_idx = (r + dr) * 8 + (c + dc)
                        m |= (1 << bit_idx)
            SHAPE_MASKS[sid, r, c] = np.uint64(m)


# Reverse-engineered shape pools from libtask.so
POOL_SAFE = [6, 27, 28, 15, 3, 2, 5, 4, 37, 38, 39, 40, 41]
POOL_HARD = [11, 13, 22, 12, 24, 21, 23, 14, 16, 18, 19]
POOL_STANDARD = [
    7, 8, 9, 10, 11, 12, 13, 14, 16, 17, 18, 19, 20, 21,
    22, 23, 24, 25, 26, 29, 30, 31, 32, 33, 34, 35, 36, 42
]


def simulate_placement(b: int, sid: int, r: int, c: int) -> int:
    m = int(SHAPE_MASKS[sid, r, c])
    if m == 0 or (b & m) != 0:
        return 0
    nb = b | m
    clear_mask = 0
    for row in range(8):
        row_mask = 0xFF << (row * 8)
        if (nb & row_mask) == row_mask:
            clear_mask |= row_mask
    col_base = 0x0101010101010101
    for col in range(8):
        col_mask = col_base << col
        if (nb & col_mask) == col_mask:
            clear_mask |= col_mask
    return nb & ~clear_mask


def _check_live_way_recursive(b: int, candidate: list, used_mask: int, placed_count: int) -> bool:
    if placed_count == 3:
        return True

    for i in range(3):
        if (used_mask & (1 << i)) == 0:
            sid = candidate[i]
            s = SHAPES_DATA[sid]
            w, h = s["w"], s["h"]

            for r in range(8 - h + 1):
                for c in range(8 - w + 1):
                    m = int(SHAPE_MASKS[sid, r, c])
                    if (b & m) == 0:
                        if placed_count == 2:
                            return True
                        nb = simulate_placement(b, sid, r, c)
                        if _check_live_way_recursive(nb, candidate, used_mask | (1 << i), placed_count + 1):
                            return True
    return False


def has_live_way(b: int, candidate: list) -> bool:
    return _check_live_way_recursive(b, candidate, 0, 0)


class PurePythonBitboardEngine:
    def __init__(self, seed: Optional[int] = 42):
        self.rng = random.Random(seed)
        self.reset(seed)

    def reset(self, seed: Optional[int] = None):
        if seed is not None:
            self.rng.seed(seed)
        self.board = np.uint64(0)
        self.combo = 0
        self.score = 0
        self.lines_cleared_total = 0
        self.moves = 0
        self.terminated = False
        self.dock = [0, 0, 0]
        self.refill_dock()

    def refill_dock(self):
        filled_cells = bin(int(self.board)).count("1")
        cover_rate = filled_cells / 64.0

        hard_prob = 0.05
        if self.score >= 8400:
            hard_prob = 0.40
        elif self.score >= 3800:
            hard_prob = 0.30
        elif self.score >= 1400:
            hard_prob = 0.20
        elif self.score >= 500:
            hard_prob = 0.12

        candidate = [0, 0, 0]
        valid = False

        for _ in range(8):
            for i in range(3):
                if cover_rate >= 0.58:
                    if self.rng.random() < 0.75:
                        candidate[i] = self.rng.choice(POOL_SAFE)
                    else:
                        candidate[i] = self.rng.choice(POOL_STANDARD)
                elif cover_rate <= 0.28:
                    if self.rng.random() < 0.35:
                        candidate[i] = self.rng.choice(POOL_HARD)
                    else:
                        candidate[i] = self.rng.choice(POOL_STANDARD)
                else:
                    r = self.rng.random()
                    if r < hard_prob:
                        candidate[i] = self.rng.choice(POOL_HARD)
                    elif r < hard_prob + 0.35:
                        candidate[i] = self.rng.choice(POOL_SAFE)
                    else:
                        candidate[i] = self.rng.randint(0, 42)

            if has_live_way(int(self.board), candidate):
                valid = True
                break

        if not valid:
            candidate = [self.rng.choice(POOL_SAFE) for _ in range(3)]

        self.dock = candidate
        self.check_termination()

    def check_termination(self):
        for slot in range(3):
            sid = self.dock[slot]
            if sid < 0:
                continue
            s = SHAPES_DATA[sid]
            w, h = s["w"], s["h"]
            for r in range(8 - h + 1):
                for c in range(8 - w + 1):
                    m = SHAPE_MASKS[sid, r, c]
                    if (self.board & m) == 0:
                        self.terminated = False
                        return
        self.terminated = True

    def get_action_mask(self) -> np.ndarray:
        mask = np.zeros(192, dtype=np.int8)
        if self.terminated:
            return mask

        for slot in range(3):
            sid = self.dock[slot]
            if sid < 0:
                continue
            s = SHAPES_DATA[sid]
            w, h = s["w"], s["h"]
            slot_offset = slot * 64

            for r in range(8 - h + 1):
                row_offset = slot_offset + r * 8
                for c in range(8 - w + 1):
                    m = SHAPE_MASKS[sid, r, c]
                    if (self.board & m) == 0:
                        mask[row_offset + c] = 1
        return mask

    def step(self, action: int) -> int:
        if self.terminated:
            return 0

        slot = action // 64
        cell = action % 64
        r = cell // 8
        c = cell % 8

        if slot < 0 or slot >= 3:
            return -10
        sid = self.dock[slot]
        if sid < 0:
            return -10

        m = SHAPE_MASKS[sid, r, c]
        if m == 0 or (self.board & m) != 0:
            return -10

        # Place piece
        self.board |= m
        self.dock[slot] = -1
        self.moves += 1

        points = SHAPES_DATA[sid]["fill"]

        # Line clear checking (rows and cols simultaneously)
        clear_mask = np.uint64(0)
        cleared_rows = 0
        cleared_cols = 0

        for row in range(8):
            row_mask = np.uint64(0xFF << (row * 8))
            if (self.board & row_mask) == row_mask:
                clear_mask |= row_mask
                cleared_rows += 1

        col_base = np.uint64(0x0101010101010101)
        for col in range(8):
            col_mask = col_base << np.uint64(col)
            if (self.board & col_mask) == col_mask:
                clear_mask |= col_mask
                cleared_cols += 1

        lines_cleared = cleared_rows + cleared_cols
        if lines_cleared > 0:
            self.board &= ~clear_mask
            self.combo += 1
            self.lines_cleared_total += lines_cleared
            points += 10 * (lines_cleared * lines_cleared) * self.combo
        else:
            self.combo = 0

        self.score += points

        if self.dock[0] < 0 and self.dock[1] < 0 and self.dock[2] < 0:
            self.refill_dock()
        else:
            self.check_termination()

        return points

    def get_observation(self) -> np.ndarray:
        obs = np.zeros((5, 8, 8), dtype=np.float32)

        # Channel 0: Board
        for i in range(64):
            if (self.board >> np.uint64(i)) & np.uint64(1):
                obs[0, i // 8, i % 8] = 1.0

        # Channels 1..3: Dock pieces
        for slot in range(3):
            sid = self.dock[slot]
            if sid < 0:
                continue
            s = SHAPES_DATA[sid]
            w, h = s["w"], s["h"]
            masks = s["masks"]
            for r in range(h):
                row_bits = masks[r]
                for c in range(w):
                    if (row_bits >> (w - 1 - c)) & 1:
                        obs[slot + 1, r, c] = 1.0

        # Channel 4: Combo feature map
        obs[4, :, :] = self.combo * 0.1

        return obs
