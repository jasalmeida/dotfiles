#!/usr/bin/env python3
# Run one shell command on the VM's serial console (a root shell) and print its
# output. Usage: serial.py SOCKET 'command' [timeout_seconds]
import socket, sys, time, uuid

path, cmd = sys.argv[1], sys.argv[2]
timeout = float(sys.argv[3]) if len(sys.argv) > 3 else 60
marker = "__done_" + uuid.uuid4().hex[:8]

s = socket.socket(socket.AF_UNIX)
s.connect(path)
s.settimeout(0.5)
# Drain whatever is already buffered, then send the command with an end marker.
try:
    while s.recv(65536):
        pass
except socket.timeout:
    pass
s.sendall(f"stty -echo cols 200 2>/dev/null; {cmd}; echo {marker}=$?\n".encode())

buf, end = b"", time.time() + timeout
while time.time() < end:
    try:
        chunk = s.recv(65536)
    except socket.timeout:
        continue
    if not chunk:
        break
    buf += chunk
    text = buf.decode(errors="replace")
    if marker + "=" in text and text.rstrip().split(marker + "=")[-1][:1].isdigit():
        out, status = text.rsplit(marker + "=", 1)
        # Drop the echoed command line if the shell echoed it.
        lines = [l for l in out.replace("\r", "").split("\n") if marker not in l]
        print("\n".join(lines).strip())
        sys.exit(int(status.split()[0]))
print(buf.decode(errors="replace").replace("\r", ""))
print(f"[timed out after {timeout:.0f}s]", file=sys.stderr)
sys.exit(124)
