#!/usr/bin/env python3
"""Run the actual TextInjector class against in-memory AX/keyboard services.

Imports are removed and service symbols are rebound to prefixed test doubles.
No production control flow or file is modified. Real AXValue/CFRange bridging
is retained; no global events, app
launches, input-source changes, preferences or TCC calls are made.
This checks control flow, not Spotlight's real Accessibility implementation.
"""
from pathlib import Path
import hashlib
import os
import re
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
source_path = root / "Sources/System/TextInjector.swift"
source = source_path.read_text()
fixture = root / "Tests/AutoSwitchTests/Fixtures/SpotlightInjection"
work = Path(tempfile.mkdtemp(prefix="autoswitch-spotlight-regression-", dir="/private/tmp"))
production = "\n".join(line for line in source.splitlines() if not line.startswith("import "))
combined = (fixture / "Services.swift").read_text() + "\n" + production + "\n" + (fixture / "Cases.swift").read_text()
# Explicit rebinding avoids overload resolution against real system APIs.
services = [
    "AXUIElement", "AXUIElementCreateSystemWide", "AXUIElementGetTypeID",
    "AXUIElementGetPid", "AXUIElementSetMessagingTimeout",
    "AXUIElementCopyAttributeValue", "AXUIElementIsAttributeSettable",
    "AXUIElementSetAttributeValue", "NSRunningApplication", "DispatchQueue",
    "CGEventSource", "CGEvent", "usleep",
]
for symbol in services:
    combined = re.sub(r"\b" + symbol + r"\b", "QA" + symbol, combined)
(work / "main.swift").write_text(combined)
print(f"Source SHA256: {hashlib.sha256(source.encode()).hexdigest()}", flush=True)
print(f"Artifacts: {work}", flush=True)
env = os.environ.copy()
env.setdefault("DEVELOPER_DIR", "/Applications/Xcode.app/Contents/Developer")
subprocess.run([
    "xcrun", "swiftc", "-module-cache-path", str(work / "module-cache"),
    str(work / "main.swift"), "-o", str(work / "spotlight-regression")
], check=True, env=env)
raise SystemExit(subprocess.run([str(work / "spotlight-regression")], env=env).returncode)
