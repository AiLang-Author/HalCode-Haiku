#!/usr/bin/env python3
"""Save one provider API key dropped by the desk.

/tmp/halcode_app/keysave.txt format is: hint, newline, key, newline.
Writes ~/.halcode/<hint>_key mode 0600 and upserts key_env (and key_alt)
in ~/.halcode/keys.env. Refuses an unknown hint. Never prints the key.

HALCODE_HOME overrides ~ (tests). HALCODE_KEYSAVE overrides the request path.
"""

import json
import os
import re
import sys
import tempfile

HINT_RE = re.compile(r"^[A-Za-z0-9_-]+$")
ENV_RE = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")


def home_dir():
    override = os.environ.get("HALCODE_HOME")
    if override:
        return override
    return os.path.expanduser("~")


def request_path():
    return os.environ.get("HALCODE_KEYSAVE") or "/tmp/halcode_app/keysave.txt"


def repo_providers():
    here = os.path.dirname(os.path.abspath(__file__))
    return os.path.join(os.path.dirname(here), "providers")


def load_spec(hint):
    paths = [
        os.path.join(home_dir(), ".halcode", "providers", hint + ".json"),
        os.path.join(repo_providers(), hint + ".json"),
    ]
    for path in paths:
        if not os.path.isfile(path):
            continue
        try:
            with open(path, "r", encoding="utf-8") as fh:
                data = json.load(fh)
        except (OSError, ValueError):
            continue
        if isinstance(data, dict):
            return data
    return None


def shell_quote(value):
    return "'" + value.replace("'", "'\\''") + "'"


def env_name(line):
    text = line.strip()
    if not text or text.startswith("#"):
        return None
    if text.startswith("export "):
        text = text[7:].strip()
    if "=" not in text:
        return None
    return text.split("=", 1)[0].strip()


def write_private(path, data):
    directory = os.path.dirname(path)
    os.makedirs(directory, mode=0o700, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=directory, prefix=".keytmp.")
    try:
        os.fchmod(fd, 0o600)
        os.write(fd, data)
        os.close(fd)
        fd = -1
        os.replace(tmp, path)
        os.chmod(path, 0o600)
    except Exception:
        if fd >= 0:
            try:
                os.close(fd)
            except OSError:
                pass
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise


def upsert_env(path, names, value):
    lines = []
    if os.path.isfile(path):
        with open(path, "r", encoding="utf-8") as fh:
            lines = fh.read().splitlines()
    wanted = set(names)
    seen = set()
    out = []
    for line in lines:
        name = env_name(line)
        if name in wanted:
            if name not in seen:
                out.append("export " + name + "=" + shell_quote(value))
                seen.add(name)
            continue
        out.append(line)
    for name in names:
        if name not in seen:
            out.append("export " + name + "=" + shell_quote(value))
    write_private(path, ("\n".join(out) + "\n").encode("utf-8"))


def write_result(status, hint):
    path = os.path.join(os.path.dirname(request_path()), "keyresult.txt")
    try:
        with open(path, "w", encoding="utf-8") as fh:
            fh.write(status + " " + hint + "\n")
    except OSError:
        print("save_provider_key: could not write result", file=sys.stderr)


def main():
    req = request_path()
    if not os.path.isfile(req):
        return 0
    run = req + ".run"
    try:
        os.replace(req, run)
    except OSError:
        return 0
    try:
        with open(run, "r", encoding="utf-8") as fh:
            raw = fh.read()
    except OSError:
        print("save_provider_key: could not read request", file=sys.stderr)
        return 1
    finally:
        try:
            os.unlink(run)
        except OSError:
            pass

    parts = raw.split("\n")
    hint = parts[0].strip() if parts else ""
    key = parts[1].strip() if len(parts) > 1 else ""
    if not HINT_RE.match(hint):
        print("save_provider_key: bad hint", file=sys.stderr)
        write_result("fail", "hint")
        return 1
    spec = load_spec(hint)
    if not spec or spec.get("key_hint") != hint:
        print("save_provider_key: unknown provider", file=sys.stderr)
        write_result("fail", hint)
        return 1
    if spec.get("auth") == "none":
        print("save_provider_key: provider needs no key", file=sys.stderr)
        write_result("fail", hint)
        return 1
    if not key or len(key) > 240:
        print("save_provider_key: empty or oversized key", file=sys.stderr)
        write_result("fail", hint)
        return 1
    names = []
    for field in ("key_env", "key_alt"):
        name = spec.get(field) or ""
        if not name:
            continue
        if not ENV_RE.match(name):
            print("save_provider_key: bad key name", file=sys.stderr)
            write_result("fail", hint)
            return 1
        if name not in names:
            names.append(name)
    if not names:
        print("save_provider_key: provider has no key_env", file=sys.stderr)
        write_result("fail", hint)
        return 1

    hal = os.path.join(home_dir(), ".halcode")
    write_private(os.path.join(hal, hint + "_key"), (key + "\n").encode("utf-8"))
    upsert_env(os.path.join(hal, "keys.env"), names, key)
    write_result("ok", hint)
    print("save_provider_key: saved " + hint, file=sys.stderr)
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception:
        print("save_provider_key: error", file=sys.stderr)
        sys.exit(1)
