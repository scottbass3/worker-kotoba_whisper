"""
Serverless entrypoint.

The Runpod Hub requires a `handler.py` in the repository root (or in
`.runpod/`), while this worker's implementation lives in `src/`. This module is
that entrypoint.

It makes `src/` importable when running from a checkout, and does nothing when
running inside the image, where the Dockerfile has already flattened `src/`
into `/`. Importing `rp_handler` starts the worker.
"""

import os
import sys

SRC_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "src")
if os.path.isdir(SRC_DIR) and SRC_DIR not in sys.path:
    sys.path.insert(0, SRC_DIR)

import rp_handler  # noqa: E402,F401  starts runpod.serverless on import
