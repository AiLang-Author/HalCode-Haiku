#!/usr/bin/env python3
"""Standalone stress for HalCode cc_* tools.

Runs on the guest. Starts each tool under sys_compat_run, sends one
schema request and one safe call, then stops only the pid it started.

A tool whose @halcode socket is already present is skipped. That keeps
a live HalCode session's listeners in place.

The host does not exec a tool as `sys_compat_run <elf> <name> <socket>`.
Linux execve builds `sys_compat_run <elf> <argv0> <argv1> ...`, and the
loader keeps every argument after its own name. CC_LaunchTool sets
argv[0] to the elf path, so the tool's /proc/self/cmdline is:

    <elf> \\0 <elf> \\0 <name> \\0 <@halcode/Name>

Tools that read argv[2] as the socket (MCP, Skills) therefore see the
name, not the socket. Pass --host-argv to reproduce that shape.
"""

import json
import os
import signal
import socket
import struct
import subprocess
import sys
import time

ROOT = os.environ.get("HALCODE_ROOT", "/boot/home/HalCode-Haiku")
RUNNER = os.environ.get("SYS_COMPAT_RUN", "/boot/home/sys_compat_run")
MANIFEST = os.path.join(ROOT, "cc_tools.json")
WORK = "/tmp/tool_stress_work"
LOGDIR = "/tmp/tool_stress_logs"
ABS_DIR = "/tmp/.lxabs"
PG_SOCK = "/var/run/postgresql/.s.PGSQL.5432"


def abs_path(sock):
    """Bridge encoding of a Linux abstract name. '@' is the marker."""
    if not sock.startswith("@"):
        return sock
    name = sock[1:].encode("utf-8")
    out = []
    for c in name:
        ch = chr(c)
        if ch.isalnum() or ch in ("_", "-"):
            out.append(ch)
        else:
            out.append("%%%02X" % c)
    return ABS_DIR + "/" + "".join(out)


def ps_lines():
    path = "/tmp/tool_stress_ps.txt"
    subprocess.run(["ps"], stdout=open(path, "wb"), stderr=subprocess.DEVNULL)
    data = open(path, "rb").read().replace(b"\x00", b"")
    return data.decode("latin1", "replace").splitlines()


def live_teams(needle):
    hits = []
    for line in ps_lines():
        if needle not in line:
            continue
        parts = line.split()
        team = None
        for tok in parts:
            if tok.isdigit() and int(tok) > 1:
                team = int(tok)
                break
        hits.append((team, line.strip()[:160]))
    return hits


def proc_alive(pid):
    if pid is None or pid <= 0:
        return False
    for team, _line in live_teams(str(pid)):
        if team == pid:
            return True
    # The team column can be wider than the pid search above. Ask the kernel.
    try:
        os.kill(pid, 0)
        return True
    except OSError:
        return False


def stop_pid(pid):
    if not proc_alive(pid):
        return "gone"
    for sig in (signal.SIGTERM, signal.SIGKILL):
        try:
            os.kill(pid, sig)
        except OSError:
            pass
        # A thread blocked in the bridge can stay listed for
        # several seconds after SIGKILL, then disappear.
        for _ in range(40):
            if not proc_alive(pid):
                return "stopped" if sig == signal.SIGTERM else "killed"
            time.sleep(0.25)
    return "STILL_ALIVE"


def framed(msg):
    payload = json.dumps(msg).encode("utf-8")
    return struct.pack(">I", len(payload)) + payload


def read_exact(sock, n):
    buf = b""
    while len(buf) < n:
        chunk = sock.recv(n - len(buf))
        if not chunk:
            break
        buf += chunk
    return buf


def call_tool(sock_path, msg, timeout):
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.settimeout(timeout)
    try:
        s.connect(sock_path)
        s.sendall(framed(msg))
        hdr = read_exact(s, 4)
        if len(hdr) < 4:
            return {"error": "short header", "raw": hdr.hex()}
        n = struct.unpack(">I", hdr)[0]
        if n > 65536:
            return {"error": "length %d" % n}
        body = read_exact(s, n)
        try:
            return json.loads(body.decode("utf-8", "replace"))
        except ValueError:
            return {"error": "bad json", "raw": body[:200].decode("latin1", "replace")}
    except Exception as exc:
        return {"error": str(exc)}
    finally:
        s.close()


def postgres_report():
    lines = []
    lines.append("pg_sock %s exists %s" % (PG_SOCK, os.path.exists(PG_SOCK)))
    try:
        st = os.stat(PG_SOCK)
        lines.append("pg_sock mode %o size %d" % (st.st_mode, st.st_size))
    except OSError as exc:
        lines.append("pg_sock stat %s" % exc)
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.settimeout(2)
    try:
        s.connect(PG_SOCK)
        lines.append("pg_native_connect ok")
    except Exception as exc:
        lines.append("pg_native_connect %s" % exc)
    finally:
        s.close()
    n = 0
    for _team, line in live_teams("postgres"):
        if "/postgres" in line or "bin/postgres" in line:
            lines.append("pg_team " + line)
            n += 1
    lines.append("pg_teams %d" % n)
    return lines


SAFE = {
    "Read": {"path": WORK + "/a.txt", "limit": 64},
    "Head": {"path": WORK + "/a.txt", "lines": 2},
    "LS": {"path": WORK},
    "Write": {"path": WORK + "/w.txt", "content": "stress\n"},
    "Bash": {"command": "echo tool_stress_ok", "timeout_secs": 5},
    "Relmem": {"op": "status"},
    "Pgmem": {
        "op": "search",
        "query": "session:",
        "kind": "session_meta",
        "scope": "persistent",
    },
    "Edit": {"path": WORK + "/e.txt", "old_string": "OLD", "new_string": "NEW"},
    "Undo": {"op": "status"},
    "Find": {"path": WORK, "name": "*.txt", "maxdepth": 1, "max_results": 20},
    "Grep": {"pattern": "stress", "path": WORK + "/a.txt", "fixed": 1},
    "Git": {"subcommand": "status", "path": ROOT},
    "Stat": {"path": WORK + "/a.txt"},
    "Wc": {"path": WORK + "/a.txt"},
    "Du": {"path": WORK},
    "Diff": {"file1": WORK + "/a.txt", "file2": WORK + "/b.txt"},
    "Olympus": {"op": "info", "path": ROOT},
    "Sleep": {"seconds": 1},
    "Skills": {"op": "list"},
    "Packager": {"op": "info", "dir": ROOT},
    "Vision": {"path": WORK + "/a.txt", "detail": "metadata"},
}


def prepare_work():
    os.makedirs(WORK, exist_ok=True)
    os.makedirs(LOGDIR, exist_ok=True)
    open(WORK + "/a.txt", "w").write("stress line\nsecond\n")
    open(WORK + "/b.txt", "w").write("stress line\nother\n")
    open(WORK + "/e.txt", "w").write("OLD\n")
    src = WORK + "/tiny.ailang"
    open(src, "w").write("Function.Main {\n    ReturnValue(1)\n}\n")
    SAFE["Ailang"] = {"op": "analyze", "source": src}
    SAFE["AilangLSP"] = {"source": src}


def clip(obj, n=360):
    text = json.dumps(obj, ensure_ascii=False) if not isinstance(obj, str) else obj
    text = text.replace("\n", " ")
    if len(text) > n:
        text = text[:n] + "..."
    return text


def start_tool(binary, name, sock, host_argv):
    rel = binary[2:] if binary.startswith("./") else binary
    elf = rel if rel.startswith("/") else os.path.join(ROOT, rel)
    if host_argv:
        # Match sys_compat_execve + loader: linux argv[2] becomes the name.
        argv = [RUNNER, elf, elf, name, sock]
    else:
        argv = [RUNNER, elf, name, sock]
    log_path = os.path.join(LOGDIR, name + (".host" if host_argv else ".direct") + ".log")
    log = open(log_path, "wb")
    proc = subprocess.Popen(
        argv,
        cwd=WORK,
        stdout=log,
        stderr=subprocess.STDOUT,
        stdin=subprocess.DEVNULL,
    )
    return proc, log_path


def wait_socket(path, proc, seconds):
    deadline = time.time() + seconds
    while time.time() < deadline:
        if os.path.exists(path):
            return "up"
        if proc.poll() is not None:
            return "exited %s" % proc.returncode
        time.sleep(0.1)
    if proc.poll() is not None:
        return "exited %s" % proc.returncode
    return "no socket"


def log_tail(path):
    try:
        data = open(path, "rb").read().replace(b"\x00", b"")
    except OSError as exc:
        return "log %s" % exc
    text = data.decode("latin1", "replace")
    interesting = []
    for line in text.splitlines():
        low = line.lower()
        if any(k in low for k in (
            "error", "fail", "postgres", "listen", "bind", "cmdline",
            "linux argv", "fatal", "mmap",
        )):
            interesting.append(line.strip()[:200])
    if not interesting:
        interesting = [ln.strip()[:200] for ln in text.splitlines()[-8:]]
    return " | ".join(interesting[-8:])


def listener_up(path):
    """A leftover abstract file is not a listener. Haiku keeps it after close."""
    if not os.path.exists(path):
        return False
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.settimeout(0.4)
    try:
        s.connect(path)
        return True
    except Exception:
        return False
    finally:
        s.close()


def one(tool, host_argv, timeout):
    name = tool["name"]
    sock = tool["socket"]
    path = abs_path(sock)
    row = {
        "name": name,
        "shape": "host-argv" if host_argv else "direct",
        "socket": path,
    }
    if listener_up(path):
        row["result"] = "SKIP live socket"
        return row
    if os.path.exists(path):
        try:
            os.unlink(path)
            row["unlinked_stale"] = True
        except OSError as exc:
            row["unlink"] = str(exc)
    teams = live_teams(os.path.basename(tool["binary"]))
    # A stuck MCP/Skills team has no socket. A second process is allowed
    # only when the abstract name is free, which the check above passed.
    row["other_teams"] = len(teams)
    proc, log_path = start_tool(tool["binary"], name, sock, host_argv)
    row["pid"] = proc.pid
    row["boot"] = wait_socket(path, proc, 12)
    if row["boot"] == "up":
        row["schema"] = clip(call_tool(path, {"method": "schema"}, timeout))
        args = SAFE.get(name)
        if args is None:
            row["call"] = "schema-only"
        else:
            row["call"] = clip(call_tool(
                path,
                {"method": "call", "id": "stress", "args": args},
                timeout,
            ))
    else:
        row["schema"] = ""
        row["call"] = ""
    row["stop"] = stop_pid(proc.pid)
    row["socket_after"] = os.path.exists(path)
    row["log"] = log_tail(log_path)
    return row


def load_tools():
    manifest = json.load(open(MANIFEST))
    return manifest["tools"]


def main(argv):
    host_argv = False
    names = []
    for a in argv:
        if a == "--host-argv":
            host_argv = True
        else:
            names.append(a)
    prepare_work()
    tools = load_tools()
    print("== postgres ==")
    for line in postgres_report():
        print(line)
    print("== sockets ==")
    present = set(os.listdir(ABS_DIR)) if os.path.isdir(ABS_DIR) else set()
    for tool in tools:
        mapped = os.path.basename(abs_path(tool["socket"]))
        flag = "BOUND" if mapped in present else "absent"
        print("%-12s %s" % (tool["name"], flag))
    selected = tools
    if names:
        want = set(names)
        selected = [t for t in tools if t["name"] in want]
    print("== run shape %s ==" % ("host-argv" if host_argv else "direct"))
    for tool in selected:
        row = one(tool, host_argv, 8)
        print("--- %s %s ---" % (row["name"], row["shape"]))
        for key in ("pid", "boot", "other_teams", "unlinked_stale", "stop",
                    "socket_after", "schema", "call", "log", "result"):
            if key in row and row[key] != "":
                print("%s: %s" % (key, row[key]))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
