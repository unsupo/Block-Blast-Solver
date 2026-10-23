import os
import ctypes
from typing import Optional, Tuple, Dict, Any
import numpy as np
import gymnasium as gym
from gymnasium import spaces

# Try loading native C++ shared library
_LIB_PATH = os.path.join(os.path.dirname(__file__), "libblockblast.dylib")
if not os.path.exists(_LIB_PATH):
    _LIB_PATH = os.path.join(os.path.dirname(__file__), "libblockblast.so")

_HAS_C_LIB = False
_clib = None

if os.path.exists(_LIB_PATH):
    try:
        _clib = ctypes.CDLL(_LIB_PATH)
        # Function prototypes
        _clib.bb_create.argtypes = [ctypes.c_uint64]
        _clib.bb_create.restype = ctypes.c_void_p

        _clib.bb_destroy.argtypes = [ctypes.c_void_p]
        _clib.bb_destroy.restype = None

        _clib.bb_reset.argtypes = [ctypes.c_void_p, ctypes.c_uint64]
        _clib.bb_reset.restype = None

        _clib.bb_set_state.argtypes = [ctypes.c_void_p, ctypes.c_uint64, ctypes.c_int, ctypes.c_int, ctypes.c_int, ctypes.c_int, ctypes.c_int]
        _clib.bb_set_state.restype = None

        _clib.bb_step.argtypes = [ctypes.c_void_p, ctypes.c_int]
        _clib.bb_step.restype = ctypes.c_int

        _clib.bb_get_action_mask.argtypes = [ctypes.c_void_p, ctypes.c_char_p]
        _clib.bb_get_action_mask.restype = None

        _clib.bb_get_observation.argtypes = [ctypes.c_void_p, ctypes.POINTER(ctypes.c_float)]
        _clib.bb_get_observation.restype = None

        _clib.bb_get_board.argtypes = [ctypes.c_void_p]
        _clib.bb_get_board.restype = ctypes.c_uint64

        _clib.bb_get_dock.argtypes = [ctypes.c_void_p, ctypes.POINTER(ctypes.c_int)]
        _clib.bb_get_dock.restype = None

        _clib.bb_get_score.argtypes = [ctypes.c_void_p]
        _clib.bb_get_score.restype = ctypes.c_int

        _clib.bb_get_combo.argtypes = [ctypes.c_void_p]
        _clib.bb_get_combo.restype = ctypes.c_int

        _clib.bb_get_lines_cleared.argtypes = [ctypes.c_void_p]
        _clib.bb_get_lines_cleared.restype = ctypes.c_int

        _clib.bb_get_moves.argtypes = [ctypes.c_void_p]
        _clib.bb_get_moves.restype = ctypes.c_int

        _clib.bb_is_terminated.argtypes = [ctypes.c_void_p]
        _clib.bb_is_terminated.restype = ctypes.c_int

        _clib.bb_get_best_action.argtypes = [ctypes.c_void_p]
        _clib.bb_get_best_action.restype = ctypes.c_int

        _HAS_C_LIB = True
    except Exception as e:
        _HAS_C_LIB = False


try:
    from .bitboard_py import PurePythonBitboardEngine, SHAPES_DATA
except ImportError:
    from bitboard_py import PurePythonBitboardEngine, SHAPES_DATA


class BlockBlastEnv(gym.Env):
    """
    High-Performance Gymnasium Environment for Block Blast using 64-bit Bitboards.
    
    Reverse engineered from Block Blast (Hungry Studio, com.block.juggle).
    - Grid: 8x8 (single uint64 bitboard)
    - Shapes: 43 unique shapes (AlgorithmCore::g_arrShape)
    - Action Space: Discrete(192) = 3 dock slots * 64 grid positions
    - Observation Space: Box(4, 8, 8)
        Channel 0: 8x8 board bitboard
        Channel 1..3: Dock slot shapes (5x5 padded into 8x8)
    - Action Mask: Returned in info['action_mask'] for Masked PPO / CleanRL / SB3
    - Rewards: Placement score + Line clears (10 * lines^2 * combo)
    """
    metadata = {"render_modes": ["human", "ansi"]}

    def __init__(self, use_c_backend: bool = True, seed: Optional[int] = 42):
        super().__init__()
        self.action_space = spaces.Discrete(192)
        self.observation_space = spaces.Box(
            low=0.0, high=1.0, shape=(5, 8, 8), dtype=np.float32
        )

        self.use_c = use_c_backend and _HAS_C_LIB
        self._c_ptr = None
        self._py_engine = None

        if self.use_c:
            self._c_ptr = _clib.bb_create(seed if seed is not None else 42)
            self._obs_buffer = np.zeros(320, dtype=np.float32)
            self._mask_buffer = np.zeros(192, dtype=np.uint8)
        else:
            self._py_engine = PurePythonBitboardEngine(seed)

    def reset(
        self, *, seed: Optional[int] = None, options: Optional[Dict[str, Any]] = None
    ) -> Tuple[np.ndarray, Dict[str, Any]]:
        super().reset(seed=seed)
        seed_val = seed if seed is not None else np.random.randint(0, 2**31 - 1)

        if self.use_c:
            _clib.bb_reset(self._c_ptr, seed_val)
            obs = self._get_obs_c()
            mask = self._get_mask_c()
            score = _clib.bb_get_score(self._c_ptr)
            combo = _clib.bb_get_combo(self._c_ptr)
            lines = _clib.bb_get_lines_cleared(self._c_ptr)
            moves = _clib.bb_get_moves(self._c_ptr)
        else:
            self._py_engine.reset(seed_val)
            obs = self._py_engine.get_observation()
            mask = self._py_engine.get_action_mask()
            score = self._py_engine.score
            combo = self._py_engine.combo
            lines = self._py_engine.lines_cleared_total
            moves = self._py_engine.moves

        info = {
            "action_mask": mask,
            "score": score,
            "combo": combo,
            "lines_cleared": lines,
            "moves": moves,
        }
        return obs, info

    def step(self, action: int) -> Tuple[np.ndarray, float, bool, bool, Dict[str, Any]]:
        if self.use_c:
            points = _clib.bb_step(self._c_ptr, int(action))
            terminated = bool(_clib.bb_is_terminated(self._c_ptr))
            obs = self._get_obs_c()
            mask = self._get_mask_c()
            score = _clib.bb_get_score(self._c_ptr)
            combo = _clib.bb_get_combo(self._c_ptr)
            lines = _clib.bb_get_lines_cleared(self._c_ptr)
            moves = _clib.bb_get_moves(self._c_ptr)
        else:
            points = self._py_engine.step(int(action))
            terminated = self._py_engine.terminated
            obs = self._py_engine.get_observation()
            mask = self._py_engine.get_action_mask()
            score = self._py_engine.score
            combo = self._py_engine.combo
            lines = self._py_engine.lines_cleared_total
            moves = self._py_engine.moves

        truncated = False
        reward = float(points)

        info = {
            "action_mask": mask,
            "score": score,
            "combo": combo,
            "lines_cleared": lines,
            "moves": moves,
        }
        return obs, reward, terminated, truncated, info

    def _get_obs_c(self) -> np.ndarray:
        _clib.bb_get_observation(
            self._c_ptr, self._obs_buffer.ctypes.data_as(ctypes.POINTER(ctypes.c_float))
        )
        return self._obs_buffer.reshape((5, 8, 8)).copy()

    def _get_mask_c(self) -> np.ndarray:
        _clib.bb_get_action_mask(
            self._c_ptr, self._mask_buffer.ctypes.data_as(ctypes.c_char_p)
        )
        return self._mask_buffer.copy()

    def render(self, mode: str = "ansi") -> Optional[str]:
        if self.use_c:
            board_val = _clib.bb_get_board(self._c_ptr)
            score = _clib.bb_get_score(self._c_ptr)
            combo = _clib.bb_get_combo(self._c_ptr)
            lines = _clib.bb_get_lines_cleared(self._c_ptr)
            dock_arr = (ctypes.c_int * 3)()
            _clib.bb_get_dock(self._c_ptr, dock_arr)
            dock = list(dock_arr)
        else:
            board_val = int(self._py_engine.board)
            score = self._py_engine.score
            combo = self._py_engine.combo
            lines = self._py_engine.lines_cleared_total
            dock = list(self._py_engine.dock)

        lines_str = [f"=== Block Blast | Score: {score} | Combo: {combo} | Cleared: {lines} ==="]
        lines_str.append("  0 1 2 3 4 5 6 7")
        for r in range(8):
            row_chars = []
            for c in range(8):
                bit = (board_val >> (r * 8 + c)) & 1
                row_chars.append("■" if bit else "·")
            lines_str.append(f"{r} " + " ".join(row_chars))

        lines_str.append("Dock:")
        for idx, sid in enumerate(dock):
            if sid < 0:
                lines_str.append(f"  Slot {idx}: [EMPTY]")
            else:
                s = SHAPES_DATA[sid]
                lines_str.append(f"  Slot {idx} (ID={sid}, {s['w']}x{s['h']}, fill={s['fill']}):")
                for dr in range(s["h"]):
                    row_b = s["masks"][dr]
                    row_c = ["■" if (row_b >> (s["w"] - 1 - dc)) & 1 else " " for dc in range(s["w"])]
                    lines_str.append("    " + "".join(row_c))

        output = "\n".join(lines_str)
        if mode == "human":
            print(output)
        return output

    def close(self):
        if self.use_c and self._c_ptr is not None:
            _clib.bb_destroy(self._c_ptr)
            self._c_ptr = None
