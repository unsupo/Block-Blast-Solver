"""
High-performance local AI Inference Server for Block Blast Flutter App.
Automatically tracks and hot-reloads the latest best trained PyTorch model.
"""

import os
import json
import time
import ctypes
import numpy as np
import torch
import torch.nn as nn
from http.server import HTTPServer, BaseHTTPRequestHandler
from ppo_agent import ActorCritic
from env import _clib, _HAS_C_LIB
from bitboard_py import PurePythonBitboardEngine, SHAPES_DATA

CHECKPOINT_CANDIDATES = [
    "ppo_block_blast_combo_best.pt",
    "ppo_block_blast_combo_5m.pt",
    "ppo_block_blast_checkpoint.pt",
    "ppo_block_blast_exact_rules.pt",
    "ppo_block_blast_10m.pt",
]

device = torch.device("mps" if torch.backends.mps.is_available() else ("cuda" if torch.cuda.is_available() else "cpu"))


class ModelManager:
    def __init__(self):
        self.current_model_path = None
        self.current_mtime = 0
        self.agent = None
        self.device = device
        self.check_and_reload()

    def check_and_reload(self):
        best_path = None
        for candidate in CHECKPOINT_CANDIDATES:
            full_path = os.path.abspath(candidate)
            if os.path.exists(full_path):
                best_path = full_path
                break

        if not best_path:
            return False

        mtime = os.path.getmtime(best_path)
        if best_path != self.current_model_path or mtime > self.current_mtime:
            print(f"[AI Service] Loading model: {os.path.basename(best_path)} (mtime={mtime})")
            checkpoint = torch.load(best_path, map_location=self.device)
            agent = ActorCritic(in_channels=5).to(self.device)
            model_dict = agent.state_dict()

            first_conv_key = "network.0.weight"
            if first_conv_key in checkpoint:
                loaded_weight = checkpoint[first_conv_key]
                current_weight = model_dict[first_conv_key]
                if loaded_weight.shape != current_weight.shape:
                    current_weight[:, :loaded_weight.shape[1], :, :] = loaded_weight
                    checkpoint[first_conv_key] = current_weight

            agent.load_state_dict(checkpoint, strict=False)
            agent.eval()

            self.agent = agent
            self.current_model_path = best_path
            self.current_mtime = mtime
            print(f"[AI Service] Model loaded successfully on {self.device}!")
            return True
        return False

    def predict(self, board_int, dock, combo):
        self.check_and_reload()
        if self.agent is None:
            return None

        # Build 5-channel observation and action mask
        obs = np.zeros((1, 5, 8, 8), dtype=np.float32)
        mask = np.zeros(192, dtype=np.float32)

        # Channel 0: Board
        for i in range(64):
            if (board_int >> i) & 1:
                obs[0, 0, i // 8, i % 8] = 1.0

        # Channels 1..3: Dock pieces & compute action mask
        for slot in range(3):
            sid = dock[slot]
            if sid < 0 or sid >= len(SHAPES_DATA):
                continue
            shape = SHAPES_DATA[sid]
            sh = shape["h"]
            sw = shape["w"]
            smasks = shape["masks"]
            # Observation channel
            for r in range(sh):
                row_bits = smasks[r]
                for c in range(sw):
                    if (row_bits >> (sw - 1 - c)) & 1:
                        obs[0, slot + 1, r, c] = 1.0

            # Action mask
            for r in range(8 - sh + 1):
                for c in range(8 - sw + 1):
                    can_fit = True
                    for dr in range(sh):
                        row_bits = smasks[dr]
                        for dc in range(sw):
                            if (row_bits >> (sw - 1 - dc)) & 1:
                                cell = (r + dr) * 8 + (c + dc)
                                if (board_int >> cell) & 1:
                                    can_fit = False
                                    break
                        if not can_fit:
                            break
                    if can_fit:
                        mask[slot * 64 + r * 8 + c] = 1.0

        # Channel 4: Combo feature map
        obs[0, 4, :, :] = float(combo) * 0.1

        if mask.sum() == 0:
            return {"valid": False, "reason": "no_valid_moves"}

        action = -1
        model_name = "3-Ply Search (300k+ Engine)"

        if _HAS_C_LIB:
            try:
                p = _clib.bb_create(0)
                d0 = dock[0] if len(dock) > 0 else -1
                d1 = dock[1] if len(dock) > 1 else -1
                d2 = dock[2] if len(dock) > 2 else -1
                _clib.bb_set_state(
                    p,
                    ctypes.c_uint64(board_int),
                    ctypes.c_int(d0),
                    ctypes.c_int(d1),
                    ctypes.c_int(d2),
                    ctypes.c_int(combo),
                    ctypes.c_int(0)
                )
                action = int(_clib.bb_get_best_action(p))
                _clib.bb_destroy(p)
            except Exception:
                action = -1

        if action < 0 and self.agent is not None:
            model_name = os.path.basename(self.current_model_path) if self.current_model_path else "PPO Agent"
            with torch.no_grad():
                x = torch.from_numpy(obs).to(self.device)
                m = torch.from_numpy(mask).to(self.device)
                features = self.agent.network(x)
                logits = self.agent.actor(features).squeeze(0)
                very_negative = -1e8
                masked_logits = torch.where(m.bool(), logits, torch.tensor(very_negative, device=self.device))
                action = int(torch.argmax(masked_logits).item())

        if action < 0:
            # Fallback to first valid action
            valids = np.where(mask == 1.0)[0]
            if len(valids) > 0:
                action = int(valids[0])

        slot = action // 64
        cell = action % 64
        r = cell // 8
        c = cell % 8

        return {
            "valid": True,
            "action": action,
            "slot": slot,
            "row": r,
            "col": c,
            "shape_id": dock[slot] if (slot >= 0 and slot < len(dock)) else -1,
            "model": model_name,
            "device": str(self.device),
        }


manager = ModelManager()


class AIRequestHandler(BaseHTTPRequestHandler):
    def log_message(self, format, *args):
        # Silence default HTTP access logs for high-frequency steps
        pass

    def do_GET(self):
        if self.path == "/status" or self.path == "/":
            manager.check_and_reload()
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Access-Control-Allow-Origin", "*")
            self.end_headers()
            data = {
                "status": "online",
                "model": os.path.basename(manager.current_model_path) if manager.current_model_path else None,
                "device": str(manager.device),
                "mtime": manager.current_mtime,
            }
            self.wfile.write(json.dumps(data).encode("utf-8"))
        else:
            self.send_response(404)
            self.end_headers()

    def do_POST(self):
        if self.path == "/predict":
            content_length = int(self.headers.get("Content-Length", 0))
            body = self.rfile.read(content_length).decode("utf-8")
            try:
                payload = json.loads(body)
                board_raw = payload.get("board", 0)
                if isinstance(board_raw, str):
                    board_int = int(board_raw)
                else:
                    board_int = int(board_raw)
                dock = payload.get("dock", [-1, -1, -1])
                combo = payload.get("combo", 0)

                res = manager.predict(board_int, dock, combo)
                if res is None:
                    res = {"valid": False, "error": "model_unavailable"}

                self.send_response(200)
                self.send_header("Content-Type", "application/json")
                self.send_header("Access-Control-Allow-Origin", "*")
                self.end_headers()
                self.wfile.write(json.dumps(res).encode("utf-8"))
            except Exception as e:
                self.send_response(500)
                self.send_header("Content-Type", "application/json")
                self.send_header("Access-Control-Allow-Origin", "*")
                self.end_headers()
                self.wfile.write(json.dumps({"error": str(e)}).encode("utf-8"))
        else:
            self.send_response(404)
            self.end_headers()

    def do_OPTIONS(self):
        self.send_response(200)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")
        self.end_headers()


def run_server(port=8765):
    server = HTTPServer(("127.0.0.1", port), AIRequestHandler)
    print(f"[AI Service] Block Blast AI inference server listening on http://127.0.0.1:{port}")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    server.server_close()


if __name__ == "__main__":
    run_server()
