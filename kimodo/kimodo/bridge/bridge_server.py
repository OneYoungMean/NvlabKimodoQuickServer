#!/usr/bin/env python
"""
Kimodo Unity Bridge Server

Persistent process for Unity Editor:
- Loads kimodo model once
- Receives newline-delimited JSON requests on stdin
- Sends newline-delimited JSON responses on stdout
"""

import argparse
import json
import sys
import traceback
from dataclasses import dataclass
from typing import Any

import numpy as np


def _out(obj):
    sys.stdout.write(json.dumps(obj) + "\n")
    sys.stdout.flush()


def _rotation_mats_to_quat_wxyz(rot_mats: np.ndarray) -> np.ndarray:
    m = rot_mats.astype(np.float32, copy=False).reshape(-1, 3, 3)
    q = np.zeros((m.shape[0], 4), dtype=np.float32)

    tr = m[:, 0, 0] + m[:, 1, 1] + m[:, 2, 2]
    mask_t = tr > 0.0
    if np.any(mask_t):
        s = np.sqrt(tr[mask_t] + 1.0) * 2.0
        q[mask_t, 0] = 0.25 * s
        q[mask_t, 1] = (m[mask_t, 2, 1] - m[mask_t, 1, 2]) / s
        q[mask_t, 2] = (m[mask_t, 0, 2] - m[mask_t, 2, 0]) / s
        q[mask_t, 3] = (m[mask_t, 1, 0] - m[mask_t, 0, 1]) / s

    mask_x = (~mask_t) & (m[:, 0, 0] > m[:, 1, 1]) & (m[:, 0, 0] > m[:, 2, 2])
    if np.any(mask_x):
        s = np.sqrt(1.0 + m[mask_x, 0, 0] - m[mask_x, 1, 1] - m[mask_x, 2, 2]) * 2.0
        q[mask_x, 0] = (m[mask_x, 2, 1] - m[mask_x, 1, 2]) / s
        q[mask_x, 1] = 0.25 * s
        q[mask_x, 2] = (m[mask_x, 0, 1] + m[mask_x, 1, 0]) / s
        q[mask_x, 3] = (m[mask_x, 0, 2] + m[mask_x, 2, 0]) / s

    mask_y = (~mask_t) & (~mask_x) & (m[:, 1, 1] > m[:, 2, 2])
    if np.any(mask_y):
        s = np.sqrt(1.0 + m[mask_y, 1, 1] - m[mask_y, 0, 0] - m[mask_y, 2, 2]) * 2.0
        q[mask_y, 0] = (m[mask_y, 0, 2] - m[mask_y, 2, 0]) / s
        q[mask_y, 1] = (m[mask_y, 0, 1] + m[mask_y, 1, 0]) / s
        q[mask_y, 2] = 0.25 * s
        q[mask_y, 3] = (m[mask_y, 1, 2] + m[mask_y, 2, 1]) / s

    mask_z = (~mask_t) & (~mask_x) & (~mask_y)
    if np.any(mask_z):
        s = np.sqrt(1.0 + m[mask_z, 2, 2] - m[mask_z, 0, 0] - m[mask_z, 1, 1]) * 2.0
        q[mask_z, 0] = (m[mask_z, 1, 0] - m[mask_z, 0, 1]) / s
        q[mask_z, 1] = (m[mask_z, 0, 2] + m[mask_z, 2, 0]) / s
        q[mask_z, 2] = (m[mask_z, 1, 2] + m[mask_z, 2, 1]) / s
        q[mask_z, 3] = 0.25 * s

    norm = np.linalg.norm(q, axis=1, keepdims=True)
    norm[norm < 1e-8] = 1.0
    q = q / norm
    return q.reshape(*rot_mats.shape[:-2], 4)


def _resolve_skeleton_for_joint_count(skeleton, num_joints: int):
    if skeleton is None:
        return None
    if hasattr(skeleton, "somaskel77") and int(num_joints) == 77:
        return skeleton.somaskel77
    if hasattr(skeleton, "somaskel30") and int(num_joints) == 30:
        return skeleton.somaskel30
    return skeleton


def _extract_flat_local_rot_quats(model, output, sample_index: int):
    local_rot = None

    if output.get("local_rot_mats") is not None:
        candidate = output["local_rot_mats"][sample_index]
        if candidate is not None:
            local_rot = np.asarray(candidate, dtype=np.float32)

    if local_rot is None and output.get("global_rot_mats") is not None:
        try:
            from kimodo.skeleton import global_rots_to_local_rots
            import torch

            global_rot = np.asarray(output["global_rot_mats"][sample_index], dtype=np.float32)
            num_joints = int(np.asarray(output["posed_joints"]).shape[2])
            skeleton = _resolve_skeleton_for_joint_count(model.skeleton, num_joints)
            if skeleton is not None:
                global_rot_t = torch.from_numpy(global_rot)
                if hasattr(skeleton, "joint_parents") and isinstance(skeleton.joint_parents, torch.Tensor):
                    global_rot_t = global_rot_t.to(skeleton.joint_parents.device)
                local_rot_t = global_rots_to_local_rots(global_rot_t, skeleton)
                local_rot = local_rot_t.detach().cpu().numpy().astype(np.float32, copy=False)
        except Exception as exc:
            _out({"status": "progress", "message": f"rotation fallback failed: {exc}"})

    if local_rot is None:
        return None

    q_wxyz = _rotation_mats_to_quat_wxyz(local_rot)
    return q_wxyz.reshape(-1).tolist()


def _parents_and_names(model, num_joints: int):
    parents = None
    names = None
    skel = _resolve_skeleton_for_joint_count(getattr(model, "skeleton", None), num_joints)
    if skel is not None:
        if hasattr(skel, "joint_parents"):
            try:
                jp = skel.joint_parents
                if hasattr(jp, "detach"):
                    jp = jp.detach().cpu().tolist()
                elif hasattr(jp, "cpu"):
                    jp = jp.cpu().tolist()
                parents = [int(x) for x in jp]
            except Exception:
                parents = None
        if hasattr(skel, "bone_order_names"):
            try:
                names = [str(x) for x in list(skel.bone_order_names)]
            except Exception:
                names = None

    if not parents or len(parents) != num_joints:
        parents = [-1] + [i for i in range(num_joints - 1)]
    if not names or len(names) != num_joints:
        names = [f"joint_{i}" for i in range(num_joints)]
    return parents, names


def _load_constraints(path_or_json: str, model):
    if not path_or_json:
        return []

    from kimodo.constraints import load_constraints_lst

    return load_constraints_lst(path_or_json, model.skeleton)


@dataclass
class UnityMotionJsonResult:
    num_frames: int
    num_joints: int
    fps: int
    joint_names: list[str]
    joint_parents: list[int]
    joints: list[float]
    local_rot_quats: list[float] | None
    texts: list[str]
    skeleton: str

    @classmethod
    def from_model_output(cls, model: Any, output: dict, prompt: str, sample_index: int = 0):
        sample_joints = np.asarray(output["posed_joints"][sample_index], dtype=np.float32)
        flat_joints = sample_joints.reshape(-1).tolist()
        joint_count = int(sample_joints.shape[1])
        parents, joint_names = _parents_and_names(model, joint_count)
        local_rot_quats = _extract_flat_local_rot_quats(model, output, sample_index)
        return cls(
            num_frames=int(sample_joints.shape[0]),
            num_joints=joint_count,
            fps=int(model.fps),
            joint_names=joint_names,
            joint_parents=parents,
            joints=flat_joints,
            local_rot_quats=local_rot_quats,
            texts=[prompt],
            skeleton=getattr(getattr(model, "skeleton", None), "name", "unknown"),
        )

    def to_compact_json(self) -> str:
        payload = {
            "num_frames": self.num_frames,
            "num_joints": self.num_joints,
            "fps": self.fps,
            "joint_names": self.joint_names,
            "joint_parents": self.joint_parents,
            "joints": self.joints,
            "local_rot_quats": self.local_rot_quats,
            "texts": self.texts,
            "skeleton": self.skeleton,
        }
        return json.dumps(payload, separators=(",", ":"))


def _generate(req: dict, model):
    from kimodo.tools import seed_everything

    prompt = str(req.get("prompt", "A person walks forward.")).strip()
    if not prompt.endswith("."):
        prompt += "."

    duration = float(req.get("duration", 5.0))
    seed = req.get("seed", None)
    diffusion_steps = int(req.get("diffusion_steps", 100))
    constraints_path = req.get("constraints_json", "")

    if seed is not None:
        seed_everything(int(seed))

    num_frames = max(1, int(duration * float(model.fps)))
    constraints = _load_constraints(constraints_path, model)

    _out({"status": "progress", "message": f"Running diffusion ({diffusion_steps} steps)..."})
    output = model(
        [prompt],
        [num_frames],
        constraint_lst=constraints,
        num_denoising_steps=diffusion_steps,
        num_samples=1,
        multi_prompt=True,
        num_transition_frames=5,
        post_processing=True,
        return_numpy=True,
    )

    motion_data = UnityMotionJsonResult.from_model_output(model, output, prompt, sample_index=0)
    _out({"status": "done", "motion_json_compact": motion_data.to_compact_json()})


def main():
    parser = argparse.ArgumentParser(description="Kimodo Unity Bridge Server")
    parser.add_argument("--model", default="Kimodo-SOMA-RP-v1")
    parser.add_argument("--device", default=None)
    args = parser.parse_args()

    _out({"status": "loading", "message": "Importing Kimodo..."})
    try:
        import torch
        from kimodo import load_model
    except Exception as exc:
        _out({"status": "error", "message": f"Failed to import kimodo: {exc}"})
        return

    device = args.device or ("cuda:0" if torch.cuda.is_available() else "cpu")
    _out({"status": "loading", "message": f"Loading {args.model} on {device}..."})
    try:
        model = load_model(args.model, device=device)
    except Exception as exc:
        _out({"status": "error", "message": f"Model load failed: {exc}\n{traceback.format_exc()}"})
        return

    _out({"status": "ready", "model": args.model, "device": device, "fps": int(model.fps)})

    for raw in sys.stdin:
        line = raw.strip()
        if not line:
            continue

        try:
            req = json.loads(line)
        except Exception as exc:
            _out({"status": "error", "message": f"Bad JSON: {exc}"})
            continue

        cmd = req.get("cmd", "")
        try:
            if cmd == "ping":
                _out({"status": "pong"})
            elif cmd == "generate":
                _generate(req, model)
            elif cmd == "quit":
                _out({"status": "bye"})
                break
            else:
                _out({"status": "error", "message": f"Unknown cmd: {cmd!r}"})
        except Exception as exc:
            _out({"status": "error", "message": str(exc), "traceback": traceback.format_exc()})


if __name__ == "__main__":
    main()

