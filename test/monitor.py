#!/usr/bin/env python3
# Drive the test VM through its QEMU monitor.
#   monitor.py SOCKET 'command' ...     monitor commands, e.g. 'screendump /work/s.png -f png'
#   monitor.py SOCKET --type 'text'     type text on the VM's keyboard (\n is Enter)
import socket, sys, time

KEYS = {" ": "spc", "\n": "ret", "-": "minus", "=": "equal", ".": "dot", ",": "comma",
        "/": "slash", ";": "semicolon", "'": "apostrophe", "`": "grave_accent",
        "[": "bracket_left", "]": "bracket_right", "\\": "backslash"}
SHIFTED = {"~": "grave_accent", "!": "1", "@": "2", "#": "3", "$": "4", "%": "5", "^": "6",
           "&": "7", "*": "8", "(": "9", ")": "0", "_": "minus", "+": "equal", ":": "semicolon",
           '"': "apostrophe", "<": "comma", ">": "dot", "?": "slash", "|": "backslash",
           "{": "bracket_left", "}": "bracket_right"}

def key(c):
    if c.isalpha() or c.isdigit():
        return f"shift-{c.lower()}" if c.isupper() else c
    if c in KEYS:
        return KEYS[c]
    return f"shift-{SHIFTED[c]}"

s = socket.socket(socket.AF_UNIX)
s.connect(sys.argv[1])
s.settimeout(0.2)
time.sleep(0.3)
try:
    s.recv(65536)
except socket.timeout:
    pass

args = sys.argv[2:]
if args[:1] == ["--type"]:
    commands = [f"sendkey {key(c)}" for c in args[1].replace("\\n", "\n")]
else:
    commands = args
for cmd in commands:
    s.sendall((cmd + "\n").encode())
    time.sleep(0.08)
    try:
        s.recv(65536)
    except socket.timeout:
        pass
