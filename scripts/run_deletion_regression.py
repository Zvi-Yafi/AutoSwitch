#!/usr/bin/env python3
"""Run production deletion/state control flow with isolated, scheduled services.

Compiles the real state machine, word buffer, history, models and event callback.
Only service implementations and DispatchQueue are replaced. Queues are drained
explicitly to exercise late evaluation/main-queue results without timing races.
No real keyboard events, input-source changes, permissions or preferences.
--source-root permits running the same expectations against an earlier version.
"""
from pathlib import Path
import argparse
import hashlib
import os
import re
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--source-root", type=Path, default=root)
args = parser.parse_args()
fixture = root / "Tests/AutoSwitchTests/Fixtures/Deletion"
relative_paths = [
    "Sources/Core/Models.swift",
    "Sources/Engine/WordBufferManager.swift",
    "Sources/Engine/CorrectionHistory.swift",
    "Sources/Engine/AutoSwitchStateMachine.swift",
    "Sources/System/GlobalKeyboardMonitor.swift",
]
parts = [(fixture / "Services.swift").read_text()]
for relative in relative_paths:
    source = (args.source_root / relative).read_text()
    print(f"{relative} SHA256: {hashlib.sha256(source.encode()).hexdigest()}", flush=True)
    if relative.endswith("GlobalKeyboardMonitor.swift"):
        source = source[source.index("private func customEventTapCallback"):]
    parts.append("\n".join(line for line in source.splitlines() if not line.startswith("import ")))
parts.append((fixture / "Cases.swift").read_text())
combined = "\n".join(parts)
# Explicit names prevent overload resolution from using a real OS event API.
for symbol in ["DispatchQueue", "CGEvent", "CGEventTapProxy"]:
    combined = re.sub(r"\b" + symbol + r"\b", "QA" + symbol, combined)
work = Path(tempfile.mkdtemp(prefix="autoswitch-deletion-regression-", dir="/private/tmp"))
(work / "main.swift").write_text(combined)
print(f"Artifacts: {work}", flush=True)
env = os.environ.copy()
env.setdefault("DEVELOPER_DIR", "/Applications/Xcode.app/Contents/Developer")
subprocess.run([
    "xcrun", "swiftc", "-DDEBUG", "-module-cache-path", str(work / "module-cache"),
    str(work / "main.swift"), "-o", str(work / "deletion-regression"),
], check=True, env=env)
raise SystemExit(subprocess.run([str(work / "deletion-regression")], env=env).returncode)
