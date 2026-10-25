#!/usr/bin/env python3
"""Launch the built app on an iPhone 13 simulator and capture review evidence, not mockups."""

import json
import os
from pathlib import Path
import subprocess
import time
import urllib.parse

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


def verify_playback(container, video_id, downloaded):
    """Require the native player clock to advance, rather than inferring audio from a screenshot."""
    state_file = container / "Library/Application Support/playback-review.json"
    state_file.unlink(missing_ok=True)
    deadline = time.monotonic() + 45
    state = None
    while time.monotonic() < deadline:
        if state_file.exists():
            state = json.loads(state_file.read_text())
            if state.get("hasError"):
                raise RuntimeError("The native player reported a playback error")
            if (state.get("trackID") == "youtube:" + video_id and state.get("isPlaying")
                    and state.get("elapsed", 0) > 1 and state.get("isDownloaded") == downloaded):
                (OUTPUT / ("downloaded-playback.json" if downloaded else "stream-playback.json")).write_text(json.dumps(state, indent=2))
                return
        time.sleep(1)
    raise RuntimeError("Native playback did not advance: " + json.dumps(state))


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
        sim("ui", udid, "content_size", "large")
        sim("ui", udid, "appearance", "light")
        sim("launch", "--terminate-running-process", udid, BUNDLE, "--sonora-review-url", "sonora://search?q=Beethoven")
        time.sleep(10)
        sim("io", udid, "screenshot", str(OUTPUT / "iphone13-youtube-search.png"))
        video_id = os.environ.get("SONORA_SMOKE_VIDEO_ID", "")
        if len(video_id) == 11 and all(c.isascii() and (c.isalnum() or c in "_-") for c in video_id):
            container = Path(sim("get_app_container", udid, BUNDLE, "data"))
            play_url = "sonora://play?" + urllib.parse.urlencode({"id": video_id, "title": video_id})
            sim("launch", "--terminate-running-process", udid, BUNDLE, "--sonora-review-url", play_url)
            verify_playback(container, video_id, downloaded=False)
            sim("io", udid, "screenshot", str(OUTPUT / "iphone13-stream-player.png"))
            sim("launch", "--terminate-running-process", udid, BUNDLE, "--sonora-review-url", "sonora://download?" + urllib.parse.urlencode({"id": video_id, "title": video_id}))
            index = container / "Library/Application Support/Downloads/downloads.json"
            deadline = time.monotonic() + 180
            complete = None
            while time.monotonic() < deadline:
                if index.exists():
                    entries = json.loads(index.read_text())
                    entry = next((e for e in entries if e["track"].get("youtubeID") == video_id), None)
                    if entry and entry["state"] == "downloaded":
                        complete = entry
                        break
                    if entry and entry["state"] == "failed":
                        (OUTPUT / "download-failure.json").write_text(json.dumps(entry, indent=2))
                        sim("io", udid, "screenshot", str(OUTPUT / "iphone13-download-failed.png"))
                        raise RuntimeError("The optional live download check failed: " + str(entry.get("failureCode", "unspecified")))
                time.sleep(2)
            sim("io", udid, "screenshot", str(OUTPUT / "iphone13-download.png"))
            if complete is None:
                raise RuntimeError("The optional download check did not finish within 180 seconds")
            downloaded = index.parent / complete["filename"]
            if not downloaded.exists() or downloaded.stat().st_size == 0:
                raise RuntimeError("A completed download has no audio file")
            sim("launch", "--terminate-running-process", udid, BUNDLE, "--sonora-review-url", "sonora://play?" + urllib.parse.urlencode({"id": video_id, "title": video_id}))
            verify_playback(container, video_id, downloaded=True)
            sim("io", udid, "screenshot", str(OUTPUT / "iphone13-downloaded-player.png"))
            (OUTPUT / "download-check.json").write_text(json.dumps({
                "state": complete["state"], "bytes": downloaded.stat().st_size,
                "expected_bytes": complete.get("expectedBytes"),
                "limitations": "The file was downloaded and validated by the app. Physical-device airplane mode is not verified."
            }, indent=2))
        (OUTPUT / "device.json").write_text(json.dumps({"device": "iPhone 13 simulator", "runtime": runtime, "launch": launch, "limitations": "Simulator launch and appearance review; see download-check.json when the optional live transfer check runs. Physical-device behavior remains unverified."}, indent=2))
    finally:
        try:
            sim("shutdown", udid)
        finally:
            sim("delete", udid)
