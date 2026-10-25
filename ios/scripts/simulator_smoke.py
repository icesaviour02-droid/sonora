#!/usr/bin/env python3
"""Launch the built app on an iPhone 13 simulator and capture review evidence, not mockups."""

import json
from pathlib import Path
import subprocess
import time

IOS = Path(__file__).resolve().parents[1]
OUTPUT = IOS / "build/review"
BUNDLE = "org.sonorahq.iphone.development"


def run(*args):
    print("Running: " + " ".join(args), flush=True)
    # Initial simulator migration can be slow on a fresh hosted Mac. Bound it so failures
    # produce artifacts and diagnostics instead of consuming the entire job allowance.
    limit = 600 if "bootstatus" in args else 120
    return subprocess.check_output(args, text=True, timeout=limit).strip()


def sim(*args):
    return run("xcrun", "simctl", *args)


if __name__ == "__main__":
    OUTPUT.mkdir(parents=True, exist_ok=True)
    runtimes = json.loads(sim("list", "runtimes", "--json"))["runtimes"]
    available = [r for r in runtimes if r.get("isAvailable") and r["identifier"].startswith("com.apple.CoreSimulator.SimRuntime.iOS-") and int(r["version"].split(".")[0]) >= 26]
    if not available:
        raise RuntimeError("No available iOS 26+ simulator runtime on this runner")
    runtime = sorted(available, key=lambda r: tuple(map(int, r["version"].split("."))))[-1]
    (OUTPUT / "selected-runtime.json").write_text(json.dumps(runtime, indent=2))
    udid = sim("create", "Sonora iPhone 13 Review", "com.apple.CoreSimulator.SimDeviceType.iPhone-13", runtime["identifier"])
    try:
        sim("boot", udid)
        sim("bootstatus", udid, "-b")
        sim("status_bar", udid, "override", "--time", "9:41", "--batteryState", "charged", "--batteryLevel", "100")
        sim("install", udid, str(IOS / "build/simulator/Build/Products/Debug-iphonesimulator/Sonora.app"))
        launch = sim("launch", udid, BUNDLE)
        time.sleep(3)
        # Fail if launch succeeded momentarily but the app immediately crashed.
        processes = sim("spawn", udid, "launchctl", "list")
        if BUNDLE not in processes:
            raise RuntimeError("Sonora did not remain running after launch")
        for appearance in ("light", "dark"):
            sim("ui", udid, "appearance", appearance)
            time.sleep(1)
            sim("io", udid, "screenshot", str(OUTPUT / f"iphone13-library-{appearance}.png"))
        sim("ui", udid, "content_size", "accessibility-extra-extra-extra-large")
        time.sleep(1)
        sim("io", udid, "screenshot", str(OUTPUT / "iphone13-library-large-text.png"))
        (OUTPUT / "device.json").write_text(json.dumps({"device": "iPhone 13 simulator", "runtime": runtime, "launch": launch, "limitations": "Launch/empty-state review only; playback, provider and download functionality are not validated."}, indent=2))
    finally:
        try:
            sim("shutdown", udid)
        finally:
            sim("delete", udid)
