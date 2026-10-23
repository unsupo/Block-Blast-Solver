import os
import sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import pytest
import numpy as np
from env import BlockBlastEnv, _clib
from bitboard_py import SHAPES_DATA, SHAPE_MASKS

def test_initialization():
    env = BlockBlastEnv(use_c_backend=True, seed=123)
    obs, info = env.reset()
    assert obs.shape == (5, 8, 8)
    assert info["action_mask"].shape == (192,)
    assert info["score"] == 0
    assert info["combo"] == 0
    assert info["moves"] == 0
    assert np.sum(info["action_mask"]) > 0
    env.close()

def test_c_and_py_equivalence():
    from bitboard_py import PurePythonBitboardEngine
    import ctypes

    env_c = BlockBlastEnv(use_c_backend=True, seed=42)
    env_c.reset()
    py_eng = PurePythonBitboardEngine(seed=42)

    # Force identical dock shapes in both engines
    dock_shapes = (ctypes.c_int * 3)()
    _clib.bb_get_dock(env_c._c_ptr, dock_shapes)
    py_eng.dock = list(dock_shapes)
    py_eng.board = np.uint64(_clib.bb_get_board(env_c._c_ptr))

    # Verify action mask is 100% bit-for-bit identical
    mask_c = env_c._get_mask_c()
    mask_py = py_eng.get_action_mask()
    np.testing.assert_array_equal(mask_c, mask_py)

    # Perform same valid move
    valid_actions = np.where(mask_c == 1)[0]
    action = valid_actions[0]

    obs_c, rew_c, term_c, trunc_c, info_c = env_c.step(action)
    rew_py = py_eng.step(action)
    obs_py = py_eng.get_observation()
    mask_py = py_eng.get_action_mask()

    assert rew_c == rew_py
    assert info_c["score"] == py_eng.score
    assert info_c["combo"] == py_eng.combo
    assert info_c["lines_cleared"] == py_eng.lines_cleared_total
    np.testing.assert_array_equal(obs_c[0], obs_py[0]) # Board channels match exactly

    env_c.close()

def test_line_clear_and_combo():
    env = BlockBlastEnv(use_c_backend=True, seed=100)
    obs, info = env.reset()

    # Manually simulate line clearing logic using bitboard_py engine
    from bitboard_py import PurePythonBitboardEngine
    eng = PurePythonBitboardEngine(seed=1)
    eng.board = np.uint64(0)
    # Fill row 0 except col 0 (bits 1..7 filled)
    for c in range(1, 8):
        eng.board |= (np.uint64(1) << np.uint64(c))

    # Dock has 1x1 dot at slot 0 (Shape 0)
    eng.dock = [0, -1, -1]
    # Place 1x1 at row 0, col 0 (action = 0 * 64 + 0 = 0)
    points = eng.step(0)

    # 1 cell filled + 1 line cleared with combo 1:
    # points = 1 + 10 * (1^2) * 1 = 11
    assert points == 11
    assert eng.combo == 1
    assert eng.lines_cleared_total == 1
    # Row 0 should now be completely cleared (all 0s)
    assert (eng.board & np.uint64(0xFF)) == np.uint64(0)

def test_render():
    env = BlockBlastEnv(use_c_backend=True, seed=999)
    env.reset()
    txt = env.render(mode="ansi")
    assert "Block Blast" in txt
    assert "Dock:" in txt
    env.close()

if __name__ == "__main__":
    test_initialization()
    test_c_and_py_equivalence()
    test_line_clear_and_combo()
    test_render()
    print("All unit tests passed successfully!")
