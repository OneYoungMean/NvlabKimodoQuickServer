# SPDX-FileCopyrightText: Copyright (c) 2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
# SPDX-License-Identifier: Apache-2.0
"""LLM2Vec encoder wrapper for Kimodo text conditioning."""

import gc
import platform
import os
import numpy as np
import torch
from torch import nn
from .llm2vec import LLM2Vec

class LLM2VecEncoder(nn.Module):
    """LLM2Vec text embeddings."""

    def __init__(
        self,
        base_model_name_or_path: str,
        peft_model_name_or_path: str,
        dtype: str,
        llm_dim: int,
    ) -> None:
        super().__init__()
        self.torch_dtype = getattr(torch, dtype)
        self.llm_dim = llm_dim

        self.custom_dir = self._resolve_local_text_encoder_dir()

        print(f"[LLM2VecEncoder] Initializing model from {self.custom_dir}...")
        print(f"[LLM2VecEncoder] Initialized (Waiting for first use to load weights)...")
        self.model = None

    def _resolve_local_text_encoder_dir(self) -> str:
        """Resolve local LLM2Vec directory for offline runs."""
        candidates: list[str] = []

        env_override = os.environ.get("KIMODO_LLM2VEC_DIR", "").strip()
        if env_override:
            candidates.append(os.path.abspath(env_override))

        kimodo_root = os.environ.get("KIMODO_ROOT_PATH", "").strip()
        if kimodo_root:
            candidates.append(
                os.path.abspath(os.path.join(kimodo_root, "models", "KIMODO-Meta3_llm2vec_NF4"))
            )

        # Keep compatibility with the original README override placeholder.
        manual_placeholder = r"path_to_your_Llama_text-encoders"
        if manual_placeholder and os.path.isdir(manual_placeholder):
            candidates.append(os.path.abspath(manual_placeholder))

        # Derive from package location.
        this_dir = os.path.dirname(os.path.abspath(__file__))
        candidates.append(
            os.path.abspath(
                os.path.join(this_dir, os.pardir, os.pardir, os.pardir, os.pardir, "models", "KIMODO-Meta3_llm2vec_NF4")
            )
        )
        candidates.append(
            os.path.abspath(
                os.path.join(this_dir, os.pardir, os.pardir, os.pardir, "models", "KIMODO-Meta3_llm2vec_NF4")
            )
        )

        seen = set()
        ordered_candidates = []
        for c in candidates:
            if c and c not in seen:
                seen.add(c)
                ordered_candidates.append(c)

        for c in ordered_candidates:
            if os.path.isdir(c):
                # Accept either complete weights or HF-style config-only dirs.
                if os.path.exists(os.path.join(c, "config.json")) or os.path.exists(os.path.join(c, "model.safetensors")):
                    return c

        raise FileNotFoundError(
            "[LLM2VecEncoder] Missing local text encoder directory. "
            "Set KIMODO_LLM2VEC_DIR or ensure KIMODO_ROOT_PATH/models/KIMODO-Meta3_llm2vec_NF4 exists. "
            f"Checked: {ordered_candidates}"
        )

    def unload(self):
        """Offload the model weights to System RAM (CPU) if currently on GPU."""
        if self.model is not None:
            if self.get_device().type == "cuda":
                print(f"[LLM2VecEncoder] Offloading 5.4GB model to System RAM...")
                self.model.model.to("cpu")
                gc.collect()
                if platform.system() == "Linux":
                    try:
                        import ctypes
                        ctypes.CDLL("libc.so.6").malloc_trim(0)
                    except Exception:
                        pass
                elif platform.system() == "Windows":
                    from kimodo.demo.memory_manager import release_system_memory
                    release_system_memory()

                if torch.cuda.is_available():
                    torch.cuda.empty_cache()
                    torch.cuda.ipc_collect()
                if torch.backends.mps.is_available():
                    torch.mps.empty_cache()

    def reload(self):
        """Move from System RAM to VRAM."""
        if self.model is None:
            print(f"[LLM2VecEncoder] Model was None. Reloading from disk (15s delay)...")
            self.model = LLM2Vec.from_pretrained(
                base_model_name_or_path=self.custom_dir,
                peft_model_name_or_path=None,
                torch_dtype=self.torch_dtype,
                device_map="cpu"
            )

        from kimodo.demo.memory_manager import manager
        manager.ensure_vram_capacity(5400 * 1024 * 1024, device="cuda:0", exclude_name="text_encoder")

        curr_device = self.get_device()
        if curr_device.type != "cuda":
            if torch.backends.mps.is_available():
                print(f"[LLM2VecEncoder] Moving weights to GPU (mps)...")
                self.model.model.to("mps")
            else:
                print(f"[LLM2VecEncoder] Moving weights to GPU (cuda:0)...")
                self.model.model.to("cuda:0")
            
            gc.collect()
            
            if platform.system() == "Linux":
                try:
                    import ctypes
                    ctypes.CDLL("libc.so.6").malloc_trim(0)
                except Exception:
                    pass
            elif platform.system() == "Windows":
                from kimodo.demo.memory_manager import release_system_memory
                release_system_memory()

            if torch.cuda.is_available():
                torch.cuda.empty_cache()
                torch.cuda.ipc_collect()
            if torch.backends.mps.is_available():
                torch.mps.empty_cache()
            
            manager.log_memory_usage("Encoder Transfer Complete (RAM Reclaimed)")
        else:
            print(f"[LLM2VecEncoder] Model already on GPU ({curr_device})")

    def get_device(self):
        if self.model is None:
            return torch.device("cpu")
        for p in self.model.model.parameters():
            if p.device.type != "meta":
                return p.device
        return torch.device("cpu")

    def delete(self):
        """Reclaim RAM without deleting from disk unless absolutely necessary."""
        self.unload()

    def __call__(self, text: list[str] | str):
        self.reload() # Auto-reload if called
        is_string = False
        if isinstance(text, str):
            text = [text]
            is_string = True

        results = []
        for t in text:
            with torch.no_grad():
                emb = self.model.encode([t])
                results.append(emb)

        encoded_text = np.concatenate(results, axis=0)

        assert len(encoded_text.shape)
        assert self.llm_dim == encoded_text.shape[-1]

        encoded_text = encoded_text[:, None]
        lengths = np.ones(len(encoded_text), dtype=int).tolist()

        if is_string:
            encoded_text = encoded_text[0]
            lengths = lengths[0]

        encoded_text = torch.tensor(encoded_text).to(self.get_device())
        return encoded_text, lengths
