"""
Serverless entrypoint.

Two Runpod systems look at this file:

- The Hub requires a `handler.py` in the repository root (or in `.runpod/`).
- The GitHub integration scans it for a `runpod.serverless.start()` call, so
  that call has to live here rather than behind an import.

The worker's implementation lives in `src/`, so this module bridges the two: it
puts `src/` on `sys.path` when run from a checkout, and does nothing inside the
image, where the Dockerfile has already flattened `src/` into `/`.
"""

import os
import sys

SRC_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "src")
if os.path.isdir(SRC_DIR) and SRC_DIR not in sys.path:
    sys.path.insert(0, SRC_DIR)

import runpod  # noqa: E402
from rp_handler import run_whisper_job  # noqa: E402

runpod.serverless.start({"handler": run_whisper_job})
