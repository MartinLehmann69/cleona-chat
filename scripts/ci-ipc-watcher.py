#!/usr/bin/env python3
"""CI IPC Watcher — auto-accepts contact requests and sends test messages back.

Runs on Node 1 as a background process during CI cross-node tests.
Connects to the daemon's Unix socket, polls get_state for all identities,
accepts any pending CRs, and sends a "CI-ACK-<identity>" message.

Usage:
  nohup python3 ci-ipc-watcher.py > /tmp/ci-ipc-watcher.log 2>&1 &
  kill $(cat /tmp/ci-ipc-watcher.pid)
"""
import socket, json, sys, time, signal, os

SOCKET_PATH = os.path.expanduser('~/.cleona/cleona.sock')
PID_FILE = '/tmp/ci-ipc-watcher.pid'
POLL_INTERVAL = 3

req_counter = 0

def next_id():
    global req_counter
    req_counter += 1
    return req_counter

def ipc_call(sock, command, params=None, identity_id=None):
    rid = next_id()
    req = {"type": "request", "id": rid, "command": command}
    if params:
        req["params"] = params
    if identity_id:
        req["identityId"] = identity_id
    sock.sendall((json.dumps(req) + "\n").encode())
    buf = b""
    while True:
        chunk = sock.recv(65536)
        if not chunk:
            raise ConnectionError("Socket closed")
        buf += chunk
        while b"\n" in buf:
            line, buf = buf.split(b"\n", 1)
            msg = json.loads(line)
            if msg.get("type") == "response" and msg.get("id") == rid:
                return msg
            # Skip events
    return None

def main():
    with open(PID_FILE, 'w') as f:
        f.write(str(os.getpid()))

    def cleanup(sig, frame):
        try:
            os.unlink(PID_FILE)
        except OSError:
            pass
        sys.exit(0)
    signal.signal(signal.SIGTERM, cleanup)
    signal.signal(signal.SIGINT, cleanup)

    accepted = set()
    messaged = set()
    sys.stdout.reconfigure(line_buffering=True)
    sys.stderr.reconfigure(line_buffering=True)
    print(f"[WATCHER] Started, PID {os.getpid()}, polling {SOCKET_PATH}")

    while True:
        try:
            sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            sock.settimeout(10)
            sock.connect(SOCKET_PATH)

            # Get state (default identity) to discover identities list
            resp = ipc_call(sock, "get_state")
            if not resp.get("success"):
                print(f"[WATCHER] get_state failed: {resp.get('error')}")
                sock.close()
                time.sleep(POLL_INTERVAL)
                continue

            identities = resp.get("data", {}).get("identities", [])

            for ident in identities:
                iid = ident["identityId"]
                name = ident.get("displayName", "?")

                state_resp = ipc_call(sock, "get_state", identity_id=iid)
                data = state_resp.get("data", {})
                pending = data.get("pendingContacts", [])

                for contact in pending:
                    nid = contact.get("nodeId") or contact.get("nodeIdHex", "")
                    if not nid:
                        continue
                    key = f"{iid}:{nid}"
                    if key in accepted:
                        continue

                    acc_resp = ipc_call(sock, "accept_contact", {"nodeIdHex": nid}, iid)
                    if acc_resp.get("success"):
                        accepted.add(key)
                        print(f"[WATCHER] {name}: accepted {contact.get('displayName','?')} ({nid[:12]}...)")
                    else:
                        print(f"[WATCHER] {name}: accept failed for {nid[:12]}: {acc_resp.get('error')}")

                # Send test message to newly accepted contacts that we haven't messaged yet
                for contact in data.get("acceptedContacts", []):
                    nid = contact.get("nodeId") or contact.get("nodeIdHex", "")
                    if not nid:
                        continue
                    msg_key = f"{iid}:{nid}"
                    if msg_key in messaged:
                        continue
                    if msg_key not in accepted:
                        # Pre-existing contact, skip
                        continue

                    time.sleep(2)
                    msg_text = f"CI-ACK-{name}"
                    send_resp = ipc_call(sock, "send_text", {"recipientId": nid, "text": msg_text}, iid)
                    if send_resp.get("success"):
                        messaged.add(msg_key)
                        print(f"[WATCHER] {name}: sent '{msg_text}' to {nid[:12]}...")
                    else:
                        print(f"[WATCHER] {name}: send_text failed to {nid[:12]}: {send_resp.get('error')}")

            sock.close()
        except (ConnectionRefusedError, FileNotFoundError) as e:
            print(f"[WATCHER] Socket not ready: {e}")
        except Exception as e:
            print(f"[WATCHER] Error: {e}", file=sys.stderr)

        time.sleep(POLL_INTERVAL)

if __name__ == "__main__":
    main()
