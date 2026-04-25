#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import os
import socket
import sys
import time
from pathlib import Path
from typing import Any

STATE_DIR = Path(os.environ.get("GEMBOT_STATE_DIR", Path.home() / ".local/share/gembot-yal-lilith/state"))
HEARTBEAT_NAME = os.environ.get("GEMBOT_HEARTBEAT_NAME", "Fractal Node v6")
ALLOWED_LOCAL_CIDRS = os.environ.get(
    "GEMBOT_ALLOWED_LOCAL_CIDRS",
    "127.0.0.1/32,192.168.0.0/16,10.0.0.0/8",
)
HEARTBEAT_FILE = STATE_DIR / "heartbeat.json"
SEQUENCE_FILE = STATE_DIR / "sequence.txt"


def local_ips() -> list[str]:
    values: set[str] = {"127.0.0.1"}
    hostname = socket.gethostname()
    try:
        for info in socket.getaddrinfo(hostname, None, family=socket.AF_INET):
            values.add(info[4][0])
    except socket.gaierror:
        pass
    return sorted(values)


def next_sequence() -> int:
    previous = 0
    if SEQUENCE_FILE.exists():
        previous = int(SEQUENCE_FILE.read_text(encoding="utf-8").strip() or "0")
    current = previous + 1
    SEQUENCE_FILE.write_text(str(current), encoding="utf-8")
    return current


def heartbeat_payload() -> dict[str, Any]:
    return {
        "assistant": "Gembot Yal'Lilith",
        "node": HEARTBEAT_NAME,
        "allowed_local_cidrs": [part.strip() for part in ALLOWED_LOCAL_CIDRS.split(",") if part.strip()],
        "hostname": socket.gethostname(),
        "local_ipv4": local_ips(),
        "sequence": next_sequence(),
        "timestamp": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "status": "ready",
    }


def run_self_test() -> int:
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    payload = heartbeat_payload()
    assert payload["sequence"] >= 1
    assert payload["allowed_local_cidrs"], "at least one local CIDR is required"
    test_file = STATE_DIR / ".write-test"
    test_file.write_text("ok", encoding="utf-8")
    assert test_file.read_text(encoding="utf-8") == "ok"
    test_file.unlink()
    print("self-test: ok")
    return 0


def loop() -> int:
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    while True:
        payload = heartbeat_payload()
        HEARTBEAT_FILE.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")
        time.sleep(30)


def main() -> int:
    parser = argparse.ArgumentParser(description="Local-only assistant heartbeat stub")
    parser.add_argument("--self-test", action="store_true", help="run deterministic self-test")
    args = parser.parse_args()

    if args.self_test:
        return run_self_test()
    return loop()


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except AssertionError as exc:
        print(f"self-test failed: {exc}", file=sys.stderr)
        raise SystemExit(1)
