# faster-whisper needs cudnn >= 9
# see https://github.com/runpod-workers/worker-faster_whisper/pull/44
FROM nvidia/cuda:12.3.2-cudnn9-runtime-ubuntu22.04

# Remove any third-party apt sources to avoid issues with expiring keys.
RUN rm -f /etc/apt/sources.list.d/*.list

ENV DEBIAN_FRONTEND=noninteractive \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

WORKDIR /

# Only what the worker needs at runtime. Every image byte is paid on each cold
# start, when a worker pulls the image, so nothing here is "just in case":
# - no compiler or Python headers: every dependency installs from a wheel;
# - no ffmpeg: faster-whisper decodes audio with PyAV, which bundles its own;
# - no `apt-get upgrade`: it adds a large layer and makes the build depend on
#   the day it runs.
# ca-certificates is needed for HTTPS: the weights at build time, `audio` URLs
# at runtime.
RUN apt-get update -y && \
    apt-get install -y --no-install-recommends python3.10 python3-pip ca-certificates && \
    ln -s /usr/bin/python3 /usr/bin/python && \
    rm -rf /var/lib/apt/lists/*

# Install Python dependencies
COPY builder/requirements.txt /requirements.txt
RUN python -m pip install -r /requirements.txt && \
    rm /requirements.txt

# Bake the kotoba-whisper weights into the image so cold starts need no network
ENV MODEL_PATH=/models/kotoba-whisper-v2.0-faster
COPY builder/fetch_models.py /fetch_models.py
COPY model_config.py /model_config.py
RUN python /fetch_models.py && \
    rm /fetch_models.py /model_config.py

# Handler and its modules, all from the repository root
COPY handler.py predict.py rp_schema.py model_config.py ./

# test input that will be used when the container runs outside of runpod
COPY test_input.json .

# Set default command
CMD ["python", "-u", "/handler.py"]
