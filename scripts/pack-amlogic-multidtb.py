#!/usr/bin/env python3
import os
import gzip
import struct
import sys


MAGIC = 0x5F4C4D41  # "AML_"
VERSION = 2
TOKEN_COUNT = 3
TOKEN_SIZE = 16
ENTRY_SIZE = TOKEN_COUNT * TOKEN_SIZE + 8


def encode_token(token):
    raw = bytearray(TOKEN_SIZE)
    data = token.encode("ascii")
    if len(data) > TOKEN_SIZE:
        raise SystemExit("token too long: %s" % token)
    raw[:len(data)] = data

    out = bytearray()
    for offset in range(0, TOKEN_SIZE, 4):
        out.extend(reversed(raw[offset:offset + 4]))
    return bytes(0x20 if value == 0 else value for value in out)


def encode_name(name):
    tokens = name.split("_")
    if len(tokens) != TOKEN_COUNT:
        raise SystemExit("multi-DTB name must have 3 underscore tokens: %s" % name)
    return b"".join(encode_token(token) for token in tokens)


def align(value, size):
    return (value + size - 1) & ~(size - 1)


def main(argv):
    if len(argv) < 3:
        raise SystemExit("usage: pack-amlogic-multidtb.py OUT NAME=DTB [NAME=DTB ...]")

    output = argv[1]
    inputs = []
    for item in argv[2:]:
        if "=" not in item:
            raise SystemExit("expected NAME=DTB: %s" % item)
        name, path = item.split("=", 1)
        with open(path, "rb") as handle:
            data = handle.read()
        inputs.append((name, data))

    offset = 12 + len(inputs) * ENTRY_SIZE
    entries = []
    payload = bytearray()
    for name, data in inputs:
        offset = align(offset, 8)
        payload.extend(b"\0" * (offset - (12 + len(inputs) * ENTRY_SIZE + len(payload))))
        entries.append((encode_name(name), offset, len(data)))
        payload.extend(data)
        offset += len(data)

    blob = bytearray(struct.pack("<III", MAGIC, VERSION, len(inputs)))
    for token, dtb_offset, size in entries:
        blob.extend(token)
        blob.extend(struct.pack("<II", dtb_offset, size))
    blob.extend(payload)

    os.makedirs(os.path.dirname(output), exist_ok=True)
    with open(output, "wb") as handle:
        handle.write(gzip.compress(bytes(blob), compresslevel=9, mtime=0))


if __name__ == "__main__":
    main(sys.argv)
