#!/usr/bin/env python3
"""Export ContactSeed URIs for all daemon identities via IPC.

Connects to the daemon's Unix socket, queries get_state for each identity,
and prints ContactSeed URIs suitable for GitHub Actions outputs.

Output format (one per identity, lowercase key):
  alice=cleona://...
  allycat=cleona://...

Usage:
  python3 ci-export-seeds.py [--bootstrap-id HEX --bootstrap-addr IP:PORT]
"""
import socket, json, sys, os, urllib.parse, argparse

SOCKET_PATH = os.path.expanduser('~/.cleona/cleona.sock')

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
    return None

def build_contact_seed_uri(data, bootstrap_id=None, bootstrap_addr=None):
    node_id = data["nodeIdHex"]
    name = data.get("displayName", "Node")
    device_id = data.get("deviceNodeIdHex", "")
    dxk = data.get("deviceX25519PkB64", "")
    dmk = data.get("deviceMlKemPkB64", "")
    port = data.get("port", 0)
    local_ips = data.get("localIps", [])
    public_ip = data.get("publicIp")
    public_port = data.get("publicPort")

    uri = f"cleona://{node_id}?n={urllib.parse.quote(name)}&c=b"
    if device_id:
        uri += f"&did={device_id}"
    if dxk:
        uri += f"&dxk={dxk}"
    if dmk:
        uri += f"&dmk={dmk}"

    addrs = []
    if public_ip and public_port:
        addrs.append(f"{public_ip}:{public_port}")
    for ip in local_ips:
        if ":" in ip:
            addrs.append(f"[{ip}]:{port}")
        else:
            addrs.append(f"{ip}:{port}")
    if addrs:
        uri += "&a=" + "%2B".join(addrs)

    if bootstrap_id and bootstrap_addr:
        uri += f"&s={bootstrap_id}@{bootstrap_addr}"

    return uri

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--bootstrap-id", default="")
    parser.add_argument("--bootstrap-addr", default="")
    args = parser.parse_args()

    sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    sock.settimeout(10)
    sock.connect(SOCKET_PATH)

    resp = ipc_call(sock, "get_state")
    if not resp.get("success"):
        print(f"ERROR: {resp.get('error')}", file=sys.stderr)
        sys.exit(1)

    identities = resp.get("data", {}).get("identities", [])

    for ident in identities:
        iid = ident["identityId"]
        name = ident.get("displayName", "?")

        state_resp = ipc_call(sock, "get_state", identity_id=iid)
        if not state_resp.get("success"):
            print(f"ERROR: get_state for {name}: {state_resp.get('error')}", file=sys.stderr)
            continue

        data = state_resp.get("data", {})
        uri = build_contact_seed_uri(
            data,
            bootstrap_id=args.bootstrap_id or None,
            bootstrap_addr=args.bootstrap_addr or None,
        )

        key = name.lower().replace(" ", "")
        print(f"{key}={uri}")

    sock.close()

if __name__ == "__main__":
    main()
