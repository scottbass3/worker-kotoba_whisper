# Kotoba Whisper Worker

[![Runpod](https://api.runpod.io/badge/scottbass3/worker-kotoba_whisper)](https://console.runpod.io/hub/listing/scottbass3/worker-kotoba_whisper)

A RunPod serverless worker that transcribes **Japanese** audio using
[kotoba-whisper-v2.0-faster](https://huggingface.co/kotoba-tech/kotoba-whisper-v2.0-faster),
a [CTranslate2](https://github.com/OpenNMT/CTranslate2) conversion of
[kotoba-tech/kotoba-whisper-v2.0](https://huggingface.co/kotoba-tech/kotoba-whisper-v2.0)
run through [faster-whisper](https://github.com/SYSTRAN/faster-whisper).

This is a fork of
[worker-faster_whisper](https://github.com/runpod-workers/worker-faster_whisper),
narrowed to a single model.

---

## Differences from worker-faster_whisper

| | worker-faster_whisper | this worker |
| --- | --- | --- |
| Models | 10 (tiny … turbo), swapped per request | 1, `kotoba-whisper-v2.0-faster`, loaded at startup |
| Language | auto-detected, or set per request | **always Japanese** (`ja`), not configurable |
| Translation | `translate` / `translation` inputs | removed |
| Image size | all 10 models baked in | one 1.4 GB model baked in |
| Cold start | model loaded on first request | model loaded at container start |

### Why the language is forced

kotoba-whisper-v2.0 is distilled from Whisper large-v3 on Japanese speech only.
Decoding it in any other language produces unreliable output, so `language` is
pinned to `ja` in `model_config.py` and the request cannot override it.

### Why translation was removed

The same distillation covers Japanese transcription only. Whisper's
`task="translate"` would still execute, but its quality is not validated by the
model card, so exposing it would be misleading.

---

## Input

| Input | Type | Description |
| --- | --- | --- |
| `audio` | Path | URL to audio file |
| `audio_base64` | str | Base64-encoded audio file |
| `model` | str | Only `"kotoba-whisper-v2.0-faster"` (or the full repo ID `"kotoba-tech/kotoba-whisper-v2.0-faster"`). Default: `"kotoba-whisper-v2.0-faster"` |
| `transcription` | str | Output format. Choices: `"plain_text"`, `"formatted_text"`, `"srt"`, `"vtt"`. Default: `"plain_text"` |
| `temperature` | float | Temperature to use for sampling. Default: 0 |
| `best_of` | int | Number of candidates when sampling with non-zero temperature. Default: 5 |
| `beam_size` | int | Number of beams in beam search, only applicable when temperature is zero. Default: 5 |
| `patience` | float | Patience value to use in beam decoding. Default: 1.0 |
| `length_penalty` | float | Token length penalty coefficient (alpha). Default: 1.0 |
| `suppress_tokens` | str | Comma-separated list of token ids to suppress during sampling. Default: `"-1"` |
| `initial_prompt` | str | Optional text to provide as a prompt for the first window. Default: None |
| `condition_on_previous_text` | bool | Feed the previous output as a prompt for the next window. Default: **False** (recommended for this model) |
| `temperature_increment_on_fallback` | float | Temperature increase when decoding fails. Default: 0.2 |
| `compression_ratio_threshold` | float | Treat decoding as failed above this gzip compression ratio. Default: 2.4 |
| `logprob_threshold` | float | Treat decoding as failed below this average log probability. Default: -1.0 |
| `no_speech_threshold` | float | Consider the segment silence above this probability. Default: 0.6 |
| `enable_vad` | bool | Use Silero voice activity detection to drop non-speech audio. Default: False |
| `word_timestamps` | bool | Include word-level timestamps in the output. Default: False |
| `chunk_length` | int | Length in seconds of the audio segments fed to the model. Default: **15** (recommended by the model card) |

`language`, `translate` and `translation` are **not** accepted. Sending them
returns a validation error.

### Defaults that differ from upstream

Three defaults were changed to match the kotoba-whisper model card and
faster-whisper's own defaults:

- `condition_on_previous_text`: `True` → `False`
- `length_penalty`: `0` → `1.0` (faster-whisper's default; `0` was never intended)
- `chunk_length`: new input, `15`

### Example

```json
{
  "input": {
    "audio": "https://huggingface.co/kotoba-tech/kotoba-whisper-v1.0-ggml/resolve/main/sample_ja_speech.wav"
  }
}
```

producing output like this:

```json
{
  "segments": [
    {
      "id": 1,
      "seek": 0,
      "start": 0.0,
      "end": 5.2,
      "text": "東京は日本の首都です。",
      "tokens": [50364, 30846, 50624],
      "temperature": 0.0,
      "avg_logprob": -0.21,
      "compression_ratio": 1.1,
      "no_speech_prob": 0.01
    }
  ],
  "detected_language": "ja",
  "transcription": "東京は日本の首都です。",
  "device": "cuda",
  "model": "kotoba-whisper-v2.0-faster"
}
```

`detected_language` is always `"ja"` — it reflects the forced language, not a
detection result. It is kept so existing clients do not break.

---

## Hardware

The weights are 1.41 GB in FP16, so the worker is comfortable on any 16 GB
card. The image itself is far larger than the weights: the CUDA base is around
4 GB unpacked, and the CUDA pip wheels add several more, so
`containerDiskInGb` is 20 rather than sized against the model alone. `.runpod/hub.json` therefore offers the Ampere and Ada pools
(`AMPERE_16`, `AMPERE_24`, `ADA_24`, `AMPERE_48`, `ADA_48_PRO`) rather than
pinning the RTX 4090 that upstream needed for `large-v3` and `turbo`. Wider
pools mean far less chance of hitting a supply constraint at deploy time.

`allowedCudaVersions` starts at 12.3 because the image is built on
`nvidia/cuda:12.3.2-cudnn9-runtime-ubuntu22.04`; the host driver has to be at
least that new. It has no upper bound: a CUDA 12.3 container runs fine on a
newer host driver, and most of Runpod's fleet now reports CUDA 13.0 or 13.2, so
capping the list at 12.8 discarded most available capacity. Check live stock
with the `get-capacity` tool before pinning a GPU; the Ampere workstation cards
swing between HIGH and NONE.

---

## Dependency pins

`builder/requirements.txt` pins two transitive dependencies. Both were breaking
the image independently of this fork, because `faster-whisper==1.1.0` declares
them too loosely:

- **`huggingface_hub>=0.30,<1.0`** — faster-whisper does `import requests`
  without declaring it and relies on huggingface_hub to pull it in.
  huggingface_hub 1.0 switched to httpx, so `import faster_whisper` raised
  `ModuleNotFoundError: No module named 'requests'`. It also removed
  `snapshot_download(local_dir_use_symlinks=...)`, which `download_model()`
  still passes when baking the weights.
- **`av>=11,<19`** — faster-whisper calls
  `av.open(..., metadata_errors="ignore")`. PyAV 19 removed that argument, so
  every request failed in `decode_audio` with
  `TypeError: open() got an unexpected keyword argument 'metadata_errors'`.

Both pins can be dropped once faster-whisper supports the newer releases;
faster-whisper 1.2.1 fixes the `requests` import but still passes
`local_dir_use_symlinks` and `metadata_errors`.

---

## Building

The model weights are downloaded at build time into `/models/kotoba-whisper-v2.0-faster`
(set by the `MODEL_PATH` env var) so the container needs no network access on a
cold start.

```bash
docker build -t kotoba-whisper-worker .
```

To run the handler outside the container, `predict.py` falls back to pulling
the model from the Hugging Face Hub when `MODEL_PATH` does not exist:

```bash
pip install -r builder/requirements.txt
python handler.py --test_input="$(cat test_input.json)"
```

### Entrypoint layout

Every Python module lives in the repository root, next to `handler.py`:

```
handler.py        entrypoint; run_whisper_job + runpod.serverless.start()
predict.py        Predictor, model loading, transcription, output formats
rp_schema.py      input validation schema
model_config.py   the one place the model id and language are defined
```

This deliberately mirrors
[runpod-workers/worker-basic](https://github.com/runpod-workers/worker-basic),
the layout Runpod's docs point to. Two Runpod systems inspect this file and
they check different things: the **Hub** requires `handler.py` to exist in the
root or `.runpod/`, while the **GitHub integration** validates that it contains
a `runpod.serverless.start()` call.

An earlier layout kept the implementation in `src/` with a root `handler.py`
that imported it. The Hub accepted that, but the GitHub integration rejected it
with "missing `runpod.serverless.start()`", so the indirection is gone.
