#!/usr/bin/env python3
"""IPC test harness for HalCode9000 tool workers."""
import socket, struct, json, sys, time

def send_ipc(sock_name, msg, timeout=5):
    """Send a JSON message to an abstract Unix socket, return the response."""
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.settimeout(timeout)
    try:
        s.connect('\0' + sock_name)
        payload = json.dumps(msg).encode('utf-8')
        header = struct.pack('>I', len(payload))
        s.sendall(header + payload)
        # read 4-byte length prefix
        hdr = b''
        while len(hdr) < 4:
            chunk = s.recv(4 - len(hdr))
            if not chunk:
                return {"error": "connection closed before header"}
            hdr += chunk
        resp_len = struct.unpack('>I', hdr)[0]
        # read response body
        body = b''
        while len(body) < resp_len:
            chunk = s.recv(resp_len - len(body))
            if not chunk:
                break
            body += chunk
        return json.loads(body.decode('utf-8'))
    except Exception as e:
        return {"error": str(e)}
    finally:
        s.close()

if __name__ == '__main__':
    if len(sys.argv) < 3:
        print("Usage: test_ipc.py <socket_name> '<json_msg>'")
        sys.exit(1)
    sock = sys.argv[1]
    msg = json.loads(sys.argv[2])
    result = send_ipc(sock, msg)
    print(json.dumps(result, indent=2, ensure_ascii=False))
