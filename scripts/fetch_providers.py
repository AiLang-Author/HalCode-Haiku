#!/usr/bin/env python3
"""
scripts/fetch_providers.py — build a model picker.

Anyone can run this. A key is optional. OpenRouter's catalog is public, so
the picker still has a current cross-lab list with no keys at all. A key in
the environment, ~/.halcode/keys.env, or ~/.halcode/<name>_key adds that
provider's own catalog.

What gets written is not the raw catalog. For each provider the script:

  1. Fetches the live model list.
  2. Keeps models that can answer a chat turn. Embeddings, audio, images,
     moderation, fine-tunes, expired rows, and :free / :batch aliases go.
  3. Drops a dated snapshot (name-YYYYMMDD) when the stable id is also listed.
  4. Keeps at most 40, newest first. Anthropic keeps eight per family
     (opus, sonnet, haiku, fable). OpenRouter keeps four current models
     from each major lab. A provider with no key still gets a list from
     the public models.dev catalog (https://models.dev/api.json).
  5. Picks a default that is not a mini / flash / haiku / lite model when
     a larger one is in the list.

If a provider cannot be reached, its old baked-in ids are not written back.
A previous live catalog is left alone. Otherwise the file stays as connection
info with an empty model list, and the picker simply omits that provider.

Outputs:
  providers/<key>.json
  ~/.halcode/providers/<key>.json
  providers/picker.txt
  ~/.halcode/providers/picker.txt
  /tmp/halcode_app/picker.txt
  /tmp/halcode_app/picker.stamp

Copyright (c) 2026 Sean Collins, 2 Paws Machine and Engineering. MIT.
"""

import json
import os
import re
import sys
import time
import urllib.error
import urllib.request
from datetime import datetime, timezone

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PROVIDERS_DIR = os.path.join(ROOT, "providers")
HALCODE_DIR = os.path.expanduser("~/.halcode/providers")
KEYS_FILE = os.path.expanduser("~/.halcode/keys.env")
PICKER_NAME = "picker.txt"
PICK_LIMIT = 40
FAMILY_KEEP = 8
OR_PER_LAB = 4
CATALOG_URL = "https://models.dev/api.json"
CATALOG = {}
DATE_SNAPSHOT = re.compile(r"^(.*)-(\d{4}|\d{8})$")
ALIAS_SUFFIXES = {"batch", "free", "nitro", "extended", "floor", "beta", "online"}
WEAK = ("mini", "flash", "haiku", "lite", "nano", "instant", "small")
DROP_BITS = (
    "embed", "embedding", "tts", "whisper", "dall-e", "davinci", "babbage",
    "moderation", "realtime", "transcribe", "imagen", "veo", "lyria", "aqa",
    "guard", "banana", "image", "vision", "audio", "voxtral", "clip",
)
OR_LABS = (
    "anthropic", "openai", "google", "x-ai", "deepseek",
    "qwen", "mistralai", "meta-llama", "cohere",
    "minimax", "moonshotai", "nvidia", "ai21", "amazon", "perplexity",
)
OR_HINTS = {
    "google": "gemini",
    "openai": "gpt-",
    "anthropic": "claude",
    "x-ai": "grok",
    "deepseek": "deepseek",
    "qwen": "qwen",
    "mistralai": "mistral",
    "meta-llama": "llama",
    "cohere": "command",
}
FILE_KEYS = {
    "anthropic_key": "ANTHROPIC_API_KEY",
    "openai_key": "OPENAI_API_KEY",
    "gemini_key": "GEMINI_API_KEY",
    "google_key": "GEMINI_API_KEY",
    "deepseek_key": "DEEPSEEK_API_KEY",
    "groq_key": "GROQ_API_KEY",
    "xai_key": "XAI_API_KEY",
    "openrouter_key": "OPENROUTER_API_KEY",
}

# Connection facts only. Model ids come from the live response.
SPECS = {
    "openrouter": {
        "name": "OpenRouter",
        "backend": "openai",
        "base_url": "https://openrouter.ai/api",
        "api_path": "/v1/chat/completions",
        "models_endpoint": "/v1/models",
        "auth": "bearer",
        "key_env": "OPENROUTER_API_KEY",
        "key_hint": "openrouter",
        "tier": 1,
        "key_optional": True,
        "catalog": "openrouter",
    },
    "anthropic": {
        "name": "Anthropic",
        "backend": "anthropic",
        "base_url": "https://api.anthropic.com",
        "api_path": "/v1/messages",
        "models_endpoint": "/v1/models?limit=100",
        "auth": "x-api-key",
        "key_env": "ANTHROPIC_API_KEY",
        "key_hint": "anthropic",
        "catalog": "anthropic",
        "tier": 1,
    },
    "openai": {
        "name": "OpenAI",
        "backend": "openai",
        "base_url": "https://api.openai.com",
        "api_path": "/v1/chat/completions",
        "models_endpoint": "/v1/models",
        "auth": "bearer",
        "key_env": "OPENAI_API_KEY",
        "key_hint": "openai",
        "catalog": "openai",
        "tier": 1,
    },
    "gemini": {
        "name": "Google",
        "backend": "gemini",
        "base_url": "https://generativelanguage.googleapis.com",
        "api_path": "/v1beta/openai/chat/completions",
        "models_endpoint": "/v1beta/models",
        "auth": "bearer",
        "key_env": "GEMINI_API_KEY",
        "key_alt": "GOOGLE_API_KEY",
        "key_hint": "gemini",
        "tier": 1,
        "catalog": "google",
    },
    "deepseek": {
        "name": "DeepSeek",
        "backend": "openai",
        "base_url": "https://api.deepseek.com",
        "api_path": "/v1/chat/completions",
        "models_endpoint": "/v1/models",
        "auth": "bearer",
        "key_env": "DEEPSEEK_API_KEY",
        "key_hint": "deepseek",
        "catalog": "deepseek",
        "tier": 1,
        "reasoning_effort": "medium",
    },
    "groq": {
        "name": "Groq",
        "backend": "openai",
        "base_url": "https://api.groq.com",
        "api_path": "/openai/v1/chat/completions",
        "models_endpoint": "/openai/v1/models",
        "auth": "bearer",
        "key_env": "GROQ_API_KEY",
        "key_hint": "groq",
        "catalog": "groq",
        "tier": 3,
    },
    "xai": {
        "name": "xAI",
        "backend": "openai",
        "base_url": "https://api.x.ai",
        "api_path": "/v1/chat/completions",
        "models_endpoint": "/v1/models",
        "auth": "bearer",
        "key_env": "XAI_API_KEY",
        "key_hint": "xai",
        "catalog": "xai",
        "tier": 1,
    },
    "ollama": {
        "name": "Ollama (Local)",
        "backend": "openai",
        "base_url": "http://localhost:11434",
        "api_path": "/v1/chat/completions",
        "models_endpoint": "/v1/models",
        "auth": "none",
        "key_env": "OLLAMA_API_KEY",
        "key_hint": "ollama",
        "tier": 1,
    },
}


def add_openai(key, name, api, env, catalog=None):
    """OpenAI-compatible host. `api` is the models.dev base, including /v1."""
    SPECS[key] = {
        "name": name,
        "backend": "openai",
        "base_url": api.rstrip("/"),
        "api_path": "/chat/completions",
        "models_endpoint": "/models",
        "auth": "bearer",
        "key_env": env,
        "key_hint": key,
        "tier": 2,
        "catalog": catalog or key,
    }


add_openai("fireworks", "Fireworks", "https://api.fireworks.ai/inference/v1", "FIREWORKS_API_KEY", "fireworks-ai")
add_openai("huggingface", "Hugging Face", "https://router.huggingface.co/v1", "HF_TOKEN", "huggingface")
add_openai("nvidia", "Nvidia", "https://integrate.api.nvidia.com/v1", "NVIDIA_API_KEY", "nvidia")
add_openai("moonshot", "Moonshot", "https://api.moonshot.ai/v1", "MOONSHOT_API_KEY", "moonshotai")
add_openai("alibaba", "Alibaba", "https://dashscope-intl.aliyuncs.com/compatible-mode/v1", "DASHSCOPE_API_KEY", "alibaba")
add_openai("novita", "Novita", "https://api.novita.ai/openai", "NOVITA_API_KEY", "novita-ai")
add_openai("chutes", "Chutes", "https://llm.chutes.ai/v1", "CHUTES_API_KEY", "chutes")
add_openai("inception", "Inception", "https://api.inceptionlabs.ai/v1", "INCEPTION_API_KEY", "inception")
add_openai("stepfun", "StepFun", "https://api.stepfun.com/v1", "STEPFUN_API_KEY", "stepfun")
add_openai("baseten", "Baseten", "https://inference.baseten.co/v1", "BASETEN_API_KEY", "baseten")
add_openai("zhipu", "Zhipu", "https://open.bigmodel.cn/api/paas/v4", "ZHIPU_API_KEY", "zhipuai")
add_openai("xiaomi", "Xiaomi", "https://api.xiaomimimo.com/v1", "XIAOMI_API_KEY", "xiaomi")
add_openai("siliconflow", "SiliconFlow", "https://api.siliconflow.com/v1", "SILICONFLOW_API_KEY", "siliconflow")
add_openai("ai21", "AI21", "https://api.ai21.com/studio/v1", "AI21_API_KEY", "ai21")
add_openai("meta", "Meta", "https://api.meta.ai/v1", "META_MODEL_API_KEY", "meta")
# SpaceXAI is the xAI API. Keep that row first so "xAI Grok" is visible.
_XAI = SPECS.pop("xai")
SPECS = {"xai": _XAI, **SPECS}

SPECS["minimax"] = {
    "name": "MiniMax",
    "backend": "anthropic",
    "base_url": "https://api.minimax.io/anthropic/v1",
    "api_path": "/messages",
    "models_endpoint": "/models",
    "auth": "x-api-key",
    "key_env": "MINIMAX_API_KEY",
    "key_hint": "minimax",
    "tier": 2,
    "catalog": "minimax",
}


def set_key(name, value):
    if name and value and not os.environ.get(name):
        os.environ[name] = value


def load_keys():
    """Env wins, then keys.env (with or without `export`), then *_key files."""
    if os.path.isfile(KEYS_FILE):
        with open(KEYS_FILE, "r", encoding="utf-8") as fh:
            for line in fh:
                line = line.strip()
                if not line or line.startswith("#") or "=" not in line:
                    continue
                if line.startswith("export "):
                    line = line[7:].strip()
                key, val = line.split("=", 1)
                key = key.strip()
                val = val.strip().strip("'\"")
                if not key or not val:
                    continue
                set_key(key, val)
                if key.startswith("HC_") and key.endswith("_KEY"):
                    set_key(key[3:-4] + "_API_KEY", val)
    hal = os.path.expanduser("~/.halcode")
    for filename, std in FILE_KEYS.items():
        path = os.path.join(hal, filename)
        if os.path.isfile(path):
            with open(path, "r", encoding="utf-8") as fh:
                set_key(std, fh.read().strip())
    for hint, spec in SPECS.items():
        stem = spec.get("key_hint") or hint
        path = os.path.join(hal, stem + "_key")
        if not os.path.isfile(path):
            continue
        try:
            with open(path, "r", encoding="utf-8") as fh:
                val = fh.read().strip()
        except OSError:
            continue
        if not val:
            continue
        set_key(spec.get("key_env") or "", val)
        alt = spec.get("key_alt") or ""
        if alt:
            set_key(alt, val)


def api_key_for(spec):
    if spec["auth"] == "none":
        return ""
    name = spec["key_env"]
    alt = spec.get("key_alt") or ""
    return os.environ.get(name) or os.environ.get("HC_" + name) or (os.environ.get(alt) if alt else "") or ""


def fetch_json(url, headers):
    req = urllib.request.Request(url, headers=headers)
    with urllib.request.urlopen(req, timeout=20) as resp:
        return json.loads(resp.read().decode("utf-8"))


def fetch_pages(spec, key):
    """Return the raw model rows, following one provider's paging style."""
    base = spec["base_url"].rstrip("/")
    endpoint = spec.get("models_endpoint", "/v1/models")
    headers = {"Accept": "application/json"}
    if spec["name"] == "Google" and key:
        headers["x-goog-api-key"] = key
    elif spec["auth"] == "bearer" and key:
        headers["Authorization"] = "Bearer " + key
    elif spec["auth"] == "x-api-key" and key:
        headers["x-api-key"] = key
        headers["anthropic-version"] = "2023-06-01"
    rows = []
    url = base + endpoint
    page = 0
    while url and page < 5:
        data = fetch_json(url, headers)
        chunk = data.get("data") or data.get("models") or []
        if isinstance(chunk, list):
            rows.extend(chunk)
        page += 1
        url = ""
        if data.get("has_more") and data.get("last_id"):
            join = "&" if "?" in endpoint else "?"
            url = base + endpoint + join + "after_id=" + str(data["last_id"])
        elif data.get("nextPageToken"):
            join = "&" if "?" in endpoint else "?"
            url = base + endpoint + join + "pageToken=" + str(data["nextPageToken"])
    return rows


def created_value(row):
    raw = row.get("created")
    if raw is None:
        raw = row.get("created_at") or 0
    if isinstance(raw, (int, float)):
        return float(raw)
    if isinstance(raw, str) and raw:
        try:
            return datetime.fromisoformat(raw.replace("Z", "+00:00")).timestamp()
        except ValueError:
            return 0
    return 0


def normalize(row):
    if isinstance(row, str):
        mid = row
        display = row
        created = 0
        src = {}
    else:
        mid = row.get("id") or row.get("name") or ""
        display = row.get("display_name") or row.get("name") or mid
        created = created_value(row)
        src = row
    if mid.startswith("models/"):
        mid = mid[7:]
        if display.startswith("models/"):
            display = display[7:]
    return {"id": mid, "display": display or mid, "_created": created, "_src": src}


def is_chat(item):
    mid = item["id"].lower()
    if not mid:
        return False
    if mid.startswith("ft:") or "~" in mid:
        return False
    if any(bit in mid for bit in DROP_BITS):
        return False
    src = item["_src"]
    life = src.get("lifecycle")
    if isinstance(life, str) and life.lower() in ("deprecated", "retired"):
        return False
    if src.get("deprecated_at") or src.get("expiration_date"):
        return False
    methods = src.get("supportedGenerationMethods") or src.get("supported_generation_methods")
    if methods and "generateContent" not in methods and "generate_content" not in methods:
        return False
    outs = (src.get("architecture") or {}).get("output_modalities")
    if outs is not None and "text" not in outs:
        return False
    own = src.get("output_modalities")
    if isinstance(own, list) and own and "text" not in own:
        return False
    if ":" in item["id"]:
        suffix = item["id"].rsplit(":", 1)[1]
        # Ollama tags look like llama3:latest. OpenRouter aliases are :free, :batch.
        if suffix in ALIAS_SUFFIXES:
            return False
    return True


def collapse_dated(models):
    ids = {m["id"] for m in models}
    kept = []
    for model in models:
        match = DATE_SNAPSHOT.match(model["id"])
        if match and match.group(1) in ids:
            continue
        kept.append(model)
    return kept


def sort_newest(models):
    if any(m["_created"] for m in models):
        return sorted(models, key=lambda m: m["_created"], reverse=True)
    return models


def cap_anthropic(models):
    buckets = {}
    picked = []
    for model in models:
        parts = model["id"].split("-")
        family = parts[1] if len(parts) > 1 else model["id"]
        n = buckets.get(family, 0)
        if n >= FAMILY_KEEP:
            continue
        buckets[family] = n + 1
        picked.append(model)
        if len(picked) >= PICK_LIMIT:
            break
    return picked


def cap_openrouter(models):
    by_lab = {}
    for model in models:
        lab = model["id"].split("/", 1)[0]
        by_lab.setdefault(lab, []).append(model)
    picked = []
    for lab in OR_LABS:
        cands = by_lab.get(lab) or []
        if not cands:
            continue
        hint = OR_HINTS.get(lab)
        hinted = [m for m in cands if hint and hint in m["id"].lower()]
        pool = hinted or cands
        solid = [m for m in pool if "preview" not in m["id"] and "-exp" not in m["id"]]
        pool = solid or pool
        strong = [m for m in pool if not any(bit in m["id"].lower() for bit in WEAK)]
        pool = strong or pool
        pool = sort_newest(pool)
        for model in pool[:OR_PER_LAB]:
            picked.append(model)
            if len(picked) >= PICK_LIMIT:
                return picked
    return picked


def choose_default(models):
    """Newest full chat model, then a preview, then whatever is first."""
    for skip_preview in (True, False):
        for model in models:
            low = model["id"].lower()
            if any(bit in low for bit in WEAK):
                continue
            if skip_preview and ("preview" in low or "-exp" in low or "research" in low):
                continue
            return model["id"]
    return models[0]["id"]


def curate(provider_key, rows):
    models = [normalize(row) for row in rows]
    models = [m for m in models if is_chat(m)]
    models = collapse_dated(models)
    models = sort_newest(models)
    if provider_key == "openrouter":
        models = cap_openrouter(models)
    elif provider_key == "anthropic":
        models = cap_anthropic(models)
    else:
        models = models[:PICK_LIMIT]
    for model in models:
        model.pop("_created", None)
        model.pop("_src", None)
    return models


def read_json(path):
    try:
        with open(path, "r", encoding="utf-8") as fh:
            return json.load(fh)
    except (OSError, json.JSONDecodeError):
        return None


def write_json(path, data):
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as fh:
        json.dump(data, fh, indent=2)
        fh.write("\n")
    os.replace(tmp, path)


def base_record(spec, models, source, note):
    record = {
        "name": spec["name"],
        "backend": spec["backend"],
        "base_url": spec["base_url"],
        "api_path": spec["api_path"],
        "models_endpoint": spec["models_endpoint"].split("?", 1)[0],
        "auth": spec["auth"],
        "key_env": spec["key_env"],
        "key_hint": spec["key_hint"],
        "tier": spec["tier"],
        "models": [{"id": m["id"], "display": m["display"]} for m in models],
        "default_model": choose_default(models) if models else "",
        "source": source,
        "fetched_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    }
    if spec.get("reasoning_effort"):
        record["reasoning_effort"] = spec["reasoning_effort"]
    if note:
        record["note"] = note
    return record


def save_provider(key, record):
    for directory in (PROVIDERS_DIR, HALCODE_DIR):
        try:
            os.makedirs(directory, exist_ok=True)
            write_json(os.path.join(directory, key + ".json"), record)
        except OSError as exc:
            print("  [-] could not write " + os.path.join(directory, key + ".json") + ": " + short_error(exc))


def short_error(exc):
    text = str(exc).replace("\n", " ")
    if len(text) > 180:
        text = text[:180] + "..."
    return text


def load_catalog():
    """Public models.dev snapshot. Used when a provider has no live catalog."""
    global CATALOG
    try:
        req = urllib.request.Request(
            CATALOG_URL,
            headers={"Accept": "application/json", "User-Agent": "halcode-fetch-providers"},
        )
        with urllib.request.urlopen(req, timeout=40) as resp:
            data = json.loads(resp.read().decode("utf-8"))
    except Exception as exc:
        CATALOG = {}
        print("[-] models.dev catalog unavailable: " + short_error(exc))
        return
    if not isinstance(data, dict):
        CATALOG = {}
        print("[-] models.dev catalog was not an object")
        return
    CATALOG = data
    print("[+] models.dev catalog: " + str(len(CATALOG)) + " providers")


def catalog_rows(spec, key):
    rec = CATALOG.get(spec.get("catalog") or key)
    if not isinstance(rec, dict):
        return []
    models = rec.get("models") or {}
    if not isinstance(models, dict):
        return []
    rows = []
    for mid, model in models.items():
        if not isinstance(model, dict):
            continue
        if str(model.get("status") or "").lower() == "deprecated":
            continue
        outs = (model.get("modalities") or {}).get("output") or ["text"]
        rows.append({
            "id": model.get("id") or mid,
            "name": model.get("name") or mid,
            "created_at": model.get("release_date") or model.get("last_updated") or "",
            "architecture": {"output_modalities": outs},
        })
    return rows


def catalog_models(key, spec, note, picker):
    rows = catalog_rows(spec, key)
    models = curate(key, rows) if rows else []
    if not models:
        return False
    save_provider(key, base_record(spec, models, "catalog", note))
    print("  [+] catalog " + str(len(models)) + " models, default " + choose_default(models))
    for model in models:
        picker.append(key + ":" + model["id"])
    return True


def main():
    load_keys()
    load_catalog()
    os.makedirs(PROVIDERS_DIR, exist_ok=True)
    os.makedirs(HALCODE_DIR, exist_ok=True)
    print("[+] Building the model picker")
    picker = []
    for key, spec in SPECS.items():
        print("[*] " + spec["name"])
        key_val = api_key_for(spec)
        if spec["auth"] != "none" and not key_val and not spec.get("key_optional"):
            note = "no " + spec["key_env"] + " set — models.dev catalog"
            previous = read_json(os.path.join(HALCODE_DIR, key + ".json"))
            if previous and previous.get("source") == "live" and previous.get("models"):
                print("  [.] kept the previous live catalog")
                for model in previous["models"]:
                    picker.append(key + ":" + model["id"])
                continue
            if catalog_models(key, spec, note, picker):
                continue
            print("  [-] " + note + " — left out of the picker")
            save_provider(key, base_record(spec, [], "unavailable", "no " + spec["key_env"] + " set"))
            continue
        if spec.get("key_optional") and not key_val:
            print("  [.] no key, using the public catalog")
        try:
            rows = fetch_pages(spec, key_val)
        except Exception as exc:
            note = short_error(exc)
            print("  [-] " + note)
            previous = read_json(os.path.join(HALCODE_DIR, key + ".json"))
            if previous and previous.get("source") == "live" and previous.get("models"):
                print("  [.] kept the previous live catalog")
                for model in previous["models"]:
                    picker.append(key + ":" + model["id"])
            elif catalog_models(key, spec, note, picker):
                pass
            else:
                save_provider(key, base_record(spec, [], "unavailable", note))
                print("  [.] not listing unverified models")
            continue
        models = curate(key, rows)
        if not models:
            print("  [-] live list had no chat models")
            save_provider(key, base_record(spec, [], "empty", "live list had no chat models"))
            continue
        save_provider(key, base_record(spec, models, "live", ""))
        print("  [+] " + str(len(models)) + " models, default " + choose_default(models))
        for model in models:
            picker.append(key + ":" + model["id"])

    body = "# generated by scripts/fetch_providers.py\n"
    current = ""
    for line in picker:
        provider = line.split(":", 1)[0]
        if provider != current:
            body += "# " + provider + "\n"
            current = provider
        body += line + "\n"
    targets = [
        os.path.join(PROVIDERS_DIR, PICKER_NAME),
        os.path.join(HALCODE_DIR, PICKER_NAME),
        os.path.join("/tmp/halcode_app", PICKER_NAME),
    ]
    try:
        os.makedirs("/tmp/halcode_app", exist_ok=True)
    except OSError as exc:
        print("[-] could not create /tmp/halcode_app: " + short_error(exc))
    for path in targets:
        try:
            tmp = path + ".tmp"
            with open(tmp, "w", encoding="utf-8") as fh:
                fh.write(body)
            os.replace(tmp, path)
        except OSError as exc:
            print("[-] could not write " + path + ": " + short_error(exc))
    stamp = str(int(time.time())) + "\n"
    stamp_path = "/tmp/halcode_app/picker.stamp"
    try:
        with open(stamp_path + ".tmp", "w", encoding="utf-8") as fh:
            fh.write(stamp)
        os.replace(stamp_path + ".tmp", stamp_path)
    except OSError as exc:
        print("[-] could not write " + stamp_path + ": " + short_error(exc))
    print("[+] Picker has " + str(len(picker)) + " models")
    for line in picker:
        print("    " + line)


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        sys.exit(130)
