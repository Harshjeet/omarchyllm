#!/usr/bin/env python3
"""
OmarchyLLM Speech-to-Text (STT) Transcriber
"""
# Supports:
# 1. Local Offline Whisper (whisper-cli from whisper-cpp package or python-whisper)
# 2. Groq Free Cloud Whisper (whisper-large-v3-turbo)
# 3. OpenAI Whisper API (/v1/audio/transcriptions)
# 4. OpenRouter Audio API (openai/gpt-transcribe)
#
# Zero external pip dependencies (uses Python standard library).
# ==============================================================================

import sys
import os
import io
import re
import json
import base64
import mimetypes
import argparse
import subprocess
import urllib.request
import urllib.parse
import urllib.error

STATE_DIR = os.path.expanduser("~/.local/state/omarchy/plugins/harsh.llm")
KEYS_FILE = os.path.join(STATE_DIR, "keys.json")
CONFIG_FILE = os.path.join(STATE_DIR, "config.json")

WHISPER_MODEL_DIRS = [
    os.path.expanduser("~/.local/share/whisper-cpp"),
    os.path.expanduser("~/.cache/whisper"),
    os.path.expanduser("~/.cache/whisper-cpp"),
    os.path.expanduser("~/.local/state/omarchy/plugins/harsh.llm/models"),
    "/usr/share/whisper-cpp/models",
    "/usr/share/whisper/models",
]

def load_stored_keys():
    if os.path.exists(KEYS_FILE):
        try:
            with open(KEYS_FILE, "r", encoding="utf-8") as f:
                return json.load(f)
        except Exception:
            pass
    return {}

def load_stored_config():
    if os.path.exists(CONFIG_FILE):
        try:
            with open(CONFIG_FILE, "r", encoding="utf-8") as f:
                return json.load(f)
        except Exception:
            pass
    return {}

# ==============================================================================
# Local Offline Whisper Support (whisper-cpp / whisper-cli)
# ==============================================================================

def find_whisper_cpp_model():
    """Finds an existing GGML whisper model (.bin) on disk."""
    priority_models = [
        "ggml-base.en.bin",
        "ggml-base.bin",
        "ggml-small.en.bin",
        "ggml-small.bin",
        "ggml-tiny.en.bin",
        "ggml-tiny.bin",
        "ggml-medium.en.bin",
        "ggml-medium.bin",
        "ggml-large-v3-turbo.bin",
        "ggml-large-v3.bin",
    ]

    for directory in WHISPER_MODEL_DIRS:
        if not os.path.isdir(directory):
            continue

        # Check preferred models first
        for name in priority_models:
            path = os.path.join(directory, name)
            if os.path.isfile(path) and os.path.getsize(path) > 5_000_000:
                return path

        # Check any ggml-*.bin or *.bin in directory
        try:
            for item in sorted(os.listdir(directory)):
                if item.endswith(".bin") and ("ggml" in item or "whisper" in item):
                    path = os.path.join(directory, item)
                    if os.path.isfile(path) and os.path.getsize(path) > 5_000_000:
                        return path
        except Exception:
            pass

    return None

def download_whisper_cpp_model(model_name="ggml-base.en.bin"):
    """Downloads a GGML model into ~/.local/share/whisper-cpp."""
    target_dir = os.path.expanduser("~/.local/share/whisper-cpp")
    os.makedirs(target_dir, exist_ok=True)
    target_path = os.path.join(target_dir, model_name)

    url = f"https://huggingface.co/ggerganov/whisper.cpp/resolve/main/{model_name}"
    sys.stderr.write(f"Downloading offline Whisper model '{model_name}' to {target_dir}...\n")

    try:
        urllib.request.urlretrieve(url, target_path)
        if os.path.isfile(target_path) and os.path.getsize(target_path) > 5_000_000:
            sys.stderr.write("Model download complete.\n")
            return target_path
    except Exception as e:
        sys.stderr.write(f"Download failed for {model_name}: {e}\n")
        # Try compact tiny model as fallback
        if model_name != "ggml-tiny.en.bin":
            tiny_name = "ggml-tiny.en.bin"
            tiny_path = os.path.join(target_dir, tiny_name)
            tiny_url = f"https://huggingface.co/ggerganov/whisper.cpp/resolve/main/{tiny_name}"
            sys.stderr.write(f"Falling back to compact model '{tiny_name}' (~75MB)...\n")
            try:
                urllib.request.urlretrieve(tiny_url, tiny_path)
                if os.path.isfile(tiny_path) and os.path.getsize(tiny_path) > 5_000_000:
                    sys.stderr.write("Compact model download complete.\n")
                    return tiny_path
            except Exception as e2:
                sys.stderr.write(f"Fallback download also failed: {e2}\n")

    return None

def transcribe_whisper_cpp(audio_path, model_path=None):
    """Transcribes audio using whisper-cli (from Arch whisper-cpp package)."""
    # Look for whisper-cli or whisper-cpp
    whisper_bin = subprocess.run(["which", "whisper-cli"], capture_output=True, text=True).stdout.strip()
    if not whisper_bin:
        whisper_bin = subprocess.run(["which", "whisper-cpp"], capture_output=True, text=True).stdout.strip()

    if not whisper_bin:
        return ""

    if not model_path:
        model_path = find_whisper_cpp_model()

    if not model_path:
        model_path = download_whisper_cpp_model("ggml-base.en.bin")

    if not model_path or not os.path.isfile(model_path):
        sys.stderr.write("No whisper.cpp model found. Please download a GGML model to ~/.local/share/whisper-cpp/\n")
        return ""

    cmd = [
        whisper_bin,
        "-m", model_path,
        "-f", audio_path,
        "-nt",       # no timestamps in stdout
        "-np",       # no print info/banners
        "-t", "4",   # 4 threads
    ]

    try:
        proc = subprocess.run(cmd, capture_output=True, text=True, timeout=60)
        output = proc.stdout.strip()

        # If stdout was empty, check stderr for transcription segments
        if not output and proc.stderr:
            clean_lines = []
            for line in proc.stderr.splitlines():
                if "-->" in line:
                    c = re.sub(r"\[.*?-->.*?\]", "", line).strip()
                    if c:
                        clean_lines.append(c)
            if clean_lines:
                output = " ".join(clean_lines).strip()

        # Strip any lingering timestamp brackets or non-speech tags
        output = re.sub(r"\[\d{2}:\d{2}[\.:]\d{2,3}\s*-->\s*\d{2}:\d{2}[\.:]\d{2,3}\]", "", output).strip()
        # Remove [BLANK_AUDIO] or (music) if it's the only text
        if output.lower() in ["[blank_audio]", "(blank audio)", "[silence]"]:
            return ""

        return output
    except Exception as e:
        sys.stderr.write(f"whisper-cli transcription error: {e}\n")
        return ""

def transcribe_python_whisper(audio_path, model="base"):
    """Transcribes audio using Python openai-whisper CLI if installed."""
    whisper_bin = subprocess.run(["which", "whisper"], capture_output=True, text=True).stdout.strip()
    if not whisper_bin:
        return ""

    # Ensure this is not a symlink to whisper-cli
    if "whisper-cli" in os.path.realpath(whisper_bin):
        return transcribe_whisper_cpp(audio_path)

    import tempfile
    with tempfile.TemporaryDirectory() as tmpdir:
        cmd = [
            whisper_bin,
            audio_path,
            "--model", model or "base",
            "--output_format", "txt",
            "--output_dir", tmpdir,
        ]
        try:
            res = subprocess.run(cmd, capture_output=True, text=True, timeout=90)
            base_name = os.path.splitext(os.path.basename(audio_path))[0]
            txt_path = os.path.join(tmpdir, f"{base_name}.txt")
            if os.path.isfile(txt_path):
                with open(txt_path, "r", encoding="utf-8") as f:
                    return f.read().strip()
        except Exception as e:
            sys.stderr.write(f"Python whisper error: {e}\n")

    return ""

def transcribe_local_cli(audio_path):
    """Executes the best available local offline Whisper implementation."""
    # 1. Try whisper-cli (C++ implementation, fast and lightweight)
    res = transcribe_whisper_cpp(audio_path)
    if res:
        return res

    # 2. Try python whisper
    res = transcribe_python_whisper(audio_path)
    if res:
        return res

    return ""

# ==============================================================================
# Cloud API Transcribers (Groq, OpenAI, OpenRouter)
# ==============================================================================

def create_multipart_body(fields, files):
    boundary = "----OmarchyLLMFormBoundary" + os.urandom(16).hex()
    buf = io.BytesIO()

    for name, value in fields.items():
        buf.write(f"--{boundary}\r\n".encode("utf-8"))
        buf.write(f'Content-Disposition: form-data; name="{name}"\r\n\r\n'.encode("utf-8"))
        buf.write(str(value).encode("utf-8"))
        buf.write(b"\r\n")

    for name, filepath in files.items():
        filename = os.path.basename(filepath)
        mime = mimetypes.guess_type(filename)[0] or "audio/wav"
        buf.write(f"--{boundary}\r\n".encode("utf-8"))
        buf.write(f'Content-Disposition: form-data; name="{name}"; filename="{filename}"\r\n'.encode("utf-8"))
        buf.write(f"Content-Type: {mime}\r\n\r\n".encode("utf-8"))
        with open(filepath, "rb") as f:
            buf.write(f.read())
        buf.write(b"\r\n")

    buf.write(f"--{boundary}--\r\n".encode("utf-8"))
    content_type = f"multipart/form-data; boundary={boundary}"
    return buf.getvalue(), content_type

def transcribe_multipart(audio_path, endpoint, api_key, model="whisper-1"):
    base = endpoint.rstrip("/")
    if "api.groq.com" in base or api_key.startswith("gsk_"):
        url = "https://api.groq.com/openai/v1/audio/transcriptions"
        model = model or "whisper-large-v3-turbo"
    elif not base.endswith("/audio/transcriptions"):
        url = f"{base}/audio/transcriptions"
    else:
        url = base

    fields = {"model": model, "response_format": "json"}
    files = {"file": audio_path}

    body_bytes, content_type = create_multipart_body(fields, files)
    headers = {
        "Content-Type": content_type,
        "Authorization": f"Bearer {api_key}"
    }

    req = urllib.request.Request(url, data=body_bytes, headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=30) as response:
            res_data = json.loads(response.read().decode("utf-8", errors="ignore"))
            return res_data.get("text", "").strip()
    except urllib.error.HTTPError as e:
        err_msg = ""
        try:
            err_data = json.loads(e.read().decode("utf-8", errors="ignore"))
            err_msg = err_data.get("error", {}).get("message", "")
        except Exception:
            pass
        sys.stderr.write(f"Transcription error (HTTP {e.code}): {err_msg or e.reason}\n")
        return ""
    except Exception as e:
        sys.stderr.write(f"Transcription network error: {e}\n")
        return ""

def transcribe_openrouter(audio_path, api_key, model="openai/gpt-transcribe"):
    url = "https://openrouter.ai/api/v1/audio/transcriptions"
    try:
        with open(audio_path, "rb") as f:
            audio_b64 = base64.b64encode(f.read()).decode("utf-8")
    except Exception as e:
        sys.stderr.write(f"Failed to read audio file: {e}\n")
        return ""

    payload = {
        "model": model,
        "input_audio": {
            "data": audio_b64,
            "format": "wav"
        }
    }

    headers = {
        "Content-Type": "application/json",
        "Authorization": f"Bearer {api_key}",
        "HTTP-Referer": "https://github.com/omarchy",
        "X-Title": "Omarchy LLM"
    }

    req = urllib.request.Request(url, data=json.dumps(payload).encode("utf-8"), headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=30) as response:
            res_data = json.loads(response.read().decode("utf-8", errors="ignore"))
            return res_data.get("text", "").strip()
    except urllib.error.HTTPError as e:
        err_msg = ""
        try:
            err_data = json.loads(e.read().decode("utf-8", errors="ignore"))
            err_msg = err_data.get("error", {}).get("message", "")
        except Exception:
            pass

        if e.code == 402:
            sys.stderr.write(
                "OpenRouter requires at least $0.50 credit balance for audio transcription.\n"
                "To transcribe for free: Local Whisper or Groq Free API key is recommended.\n"
            )
        else:
            sys.stderr.write(f"OpenRouter audio error (HTTP {e.code}): {err_msg or e.reason}\n")
        return ""
    except Exception as e:
        sys.stderr.write(f"OpenRouter network error: {e}\n")
        return ""

# ==============================================================================
# Diagnostics Check Command
# ==============================================================================

def check_status():
    """Prints a diagnostics report of available speech recognition backends."""
    whisper_bin = subprocess.run(["which", "whisper-cli"], capture_output=True, text=True).stdout.strip()
    if not whisper_bin:
        whisper_bin = subprocess.run(["which", "whisper-cpp"], capture_output=True, text=True).stdout.strip()

    py_whisper = subprocess.run(["which", "whisper"], capture_output=True, text=True).stdout.strip()
    model_path = find_whisper_cpp_model()

    keys = load_stored_keys()
    cfg = load_stored_config()

    report = {
        "whisper_cpp_binary": whisper_bin or None,
        "whisper_cpp_available": bool(whisper_bin),
        "whisper_cpp_model": model_path,
        "whisper_cpp_model_name": os.path.basename(model_path) if model_path else None,
        "whisper_cpp_model_size_mb": round(os.path.getsize(model_path) / (1024 * 1024), 1) if model_path else 0,
        "python_whisper_available": bool(py_whisper and "whisper-cli" not in os.path.realpath(py_whisper)),
        "offline_whisper_ready": bool(whisper_bin and model_path),
        "configured_backend": cfg.get("sttBackend", "whisper"),
        "groq_key_configured": bool(keys.get("groq")),
        "openai_key_configured": bool(keys.get("openai")),
        "openrouter_key_configured": bool(keys.get("openrouter")),
    }
    print(json.dumps(report, indent=2))

# ==============================================================================
# Main Entry Point
# ==============================================================================

def main():
    parser = argparse.ArgumentParser(description="OmarchyLLM Audio Transcriber")
    parser.add_argument("--file", "-f", help="Path to audio file (.wav)")
    parser.add_argument("--endpoint", "-e", default="", help="API endpoint")
    parser.add_argument("--key", "-k", default="", help="API key")
    parser.add_argument("--model", "-m", default="", help="Model name")
    parser.add_argument("--backend", "-b", default="", help="STT backend (whisper, groq, openai, openrouter, auto)")
    parser.add_argument("--check", action="store_true", help="Print diagnostics JSON and exit")
    parser.add_argument("--download-model", nargs="?", const="ggml-base.en.bin", help="Download a GGML model (default: ggml-base.en.bin)")

    args = parser.parse_args()

    if args.check:
        check_status()
        return

    if args.download_model:
        model_path = download_whisper_cpp_model(args.download_model)
        if model_path:
            print(f"OK: {model_path}")
            return
        sys.exit(1)

    if not args.file:
        parser.print_help()
        sys.exit(1)

    if not os.path.isfile(args.file):
        sys.stderr.write(f"Audio file not found: {args.file}\n")
        sys.exit(1)

    stored_keys = load_stored_keys()
    cfg = load_stored_config()

    key = args.key.strip() if args.key else ""
    endpoint = args.endpoint.strip() if args.endpoint else ""
    model = args.model.strip() if args.model else ""

    backend = (args.backend.strip() or cfg.get("sttBackend", "whisper") or "auto").lower()

    # -------------------------------------------------------------------------
    # Route 1: Explicit Offline Local Whisper
    # -------------------------------------------------------------------------
    if backend in ["whisper", "local", "offline", "whisper-cpp"]:
        text = transcribe_local_cli(args.file)
        if text:
            print(text)
            return

        # Fallback to Groq if local whisper is not ready but user has Groq key
        groq_key = stored_keys.get("groq", "").strip()
        if groq_key:
            sys.stderr.write("Local Whisper produced no text; trying Groq Whisper fallback...\n")
            gtext = transcribe_multipart(args.file, "https://api.groq.com/openai/v1", groq_key, "whisper-large-v3-turbo")
            if gtext:
                print(gtext)
                return

        sys.stderr.write("Offline Whisper failed to transcribe audio. Verify microphone capture and model at ~/.local/share/whisper-cpp/.\n")
        sys.exit(1)

    # -------------------------------------------------------------------------
    # Route 2: Explicit Groq Cloud Whisper
    # -------------------------------------------------------------------------
    if backend == "groq":
        groq_key = stored_keys.get("groq", "").strip()
        if key.startswith("gsk_"):
            groq_key = key
        if groq_key:
            text = transcribe_multipart(args.file, "https://api.groq.com/openai/v1", groq_key, model or "whisper-large-v3-turbo")
            if text:
                print(text)
                return
        # If Groq failed, fallback to local whisper
        text = transcribe_local_cli(args.file)
        if text:
            print(text)
            return
        sys.exit(1)

    # -------------------------------------------------------------------------
    # Route 3: Explicit OpenAI Cloud Whisper
    # -------------------------------------------------------------------------
    if backend == "openai":
        openai_key = stored_keys.get("openai", "").strip()
        if key.startswith("sk-") and not key.startswith("sk-or-"):
            openai_key = key
        if openai_key:
            text = transcribe_multipart(args.file, "https://api.openai.com/v1", openai_key, model or "whisper-1")
            if text:
                print(text)
                return
        # Fallback to local whisper
        text = transcribe_local_cli(args.file)
        if text:
            print(text)
            return
        sys.exit(1)

    # -------------------------------------------------------------------------
    # Route 4: Auto Priority Flow
    # -------------------------------------------------------------------------
    # Priority A: Check if Local Whisper is installed and ready
    whisper_bin = subprocess.run(["which", "whisper-cli"], capture_output=True, text=True).stdout.strip()
    if not whisper_bin:
        whisper_bin = subprocess.run(["which", "whisper-cpp"], capture_output=True, text=True).stdout.strip()

    has_local_model = bool(find_whisper_cpp_model())
    if whisper_bin and has_local_model:
        text = transcribe_local_cli(args.file)
        if text:
            print(text)
            return

    # Priority B: Groq Key (Free cloud Whisper)
    groq_key = stored_keys.get("groq", "").strip()
    if key.startswith("gsk_"):
        groq_key = key
    if groq_key:
        text = transcribe_multipart(args.file, "https://api.groq.com/openai/v1", groq_key, model or "whisper-large-v3-turbo")
        if text:
            print(text)
            return

    # Priority C: OpenAI Key
    openai_key = stored_keys.get("openai", "").strip()
    if key.startswith("sk-") and "openrouter" not in endpoint and not key.startswith("sk-or-"):
        openai_key = key
    if openai_key:
        text = transcribe_multipart(args.file, "https://api.openai.com/v1", openai_key, model or "whisper-1")
        if text:
            print(text)
            return

    # Priority D: OpenRouter (if user explicitly provided openrouter key)
    openrouter_key = stored_keys.get("openrouter", "").strip()
    if key.startswith("sk-or-") or "openrouter.ai" in endpoint:
        openrouter_key = key
    if openrouter_key:
        text = transcribe_openrouter(args.file, openrouter_key, model or "openai/gpt-transcribe")
        if text:
            print(text)
            return

    # Priority E: Final Local Whisper Attempt (auto-downloading model if needed)
    text = transcribe_local_cli(args.file)
    if text:
        print(text)
        return

    # If all failed, provide a helpful message
    sys.stderr.write(
        "Voice transcription requires an audio-enabled backend:\n"
        "• Local Offline: Whisper-cpp is installed. Make sure a model exists at ~/.local/share/whisper-cpp/\n"
        "• Free Cloud: Add a free Groq API key in Settings (Groq provides free Whisper).\n"
    )
    sys.exit(1)

if __name__ == "__main__":
    main()
