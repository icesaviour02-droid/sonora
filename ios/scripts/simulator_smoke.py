#!/usr/bin/env python3
"""Launch the built app on an iPhone 13 simulator and capture review evidence, not mockups."""

import json
import math
import os
from pathlib import Path
import subprocess
import struct
import time
import urllib.parse
import wave
import zlib

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
    deadline = time.monotonic() + 130
    state = None
    while time.monotonic() < deadline:
        if state_file.exists():
            state = json.loads(state_file.read_text())
            if state.get("hasError"):
                (OUTPUT / ("downloaded-playback-failed.json" if downloaded else "stream-playback-failed.json")).write_text(json.dumps(state, indent=2))
                return False
            if (state.get("trackID") == "youtube:" + video_id and state.get("isPlaying")
                    and state.get("elapsed", 0) > 1 and state.get("isDownloaded") == downloaded):
                (OUTPUT / ("downloaded-playback.json" if downloaded else "stream-playback.json")).write_text(json.dumps(state, indent=2))
                return True
        time.sleep(1)
    (OUTPUT / ("downloaded-playback-failed.json" if downloaded else "stream-playback-failed.json")).write_text(json.dumps(state, indent=2))
    return False


def evidence(container, filename, timeout=45):
    """Read count-only app evidence from actual decoded provider results, never raw music/lyrics."""
    path = container / "Library/Application Support" / filename
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if path.exists():
            value = json.loads(path.read_text())
            (OUTPUT / filename).write_text(json.dumps(value, indent=2))
            return value
        time.sleep(1)
    return None


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
        container = Path(sim("get_app_container", udid, BUNDLE, "data"))
        for typeface in ("rounded", "Inter-Regular"):
            review_file = container / "Library/Application Support/font-review.json"
            review_file.unlink(missing_ok=True)
            sim("launch", "--terminate-running-process", udid, BUNDLE, "--sonora-review-url", "sonora://fonts?font=" + typeface)
            review = evidence(container, "font-review.json")
            (OUTPUT / ("font-" + typeface + ".json")).write_text(json.dumps(review, indent=2))
            if not review or review.get("selected") != typeface or review.get("persisted") != typeface or not review.get("selected_available") or not review.get("rounded_available"):
                raise RuntimeError("The chosen font is not available or persisted")
            sim("io", udid, "screenshot", str(OUTPUT / ("iphone13-font-" + typeface + ".png")))
        review_file.unlink(missing_ok=True)
        sim("launch", "--terminate-running-process", udid, BUNDLE, "--sonora-review-url", "sonora://fonts")
        restored_font = evidence(container, "font-review.json")
        if not restored_font or restored_font.get("selected") != "Inter-Regular":
            raise RuntimeError("The font choice did not survive relaunch")
        review_file.unlink(missing_ok=True)
        sim("launch", "--terminate-running-process", udid, BUNDLE, "--sonora-review-url", "sonora://fonts?font=system")
        reset_font = evidence(container, "font-review.json")
        if not reset_font or reset_font.get("selected") != "system":
            raise RuntimeError("The system font could not be restored")
        sim("launch", "--terminate-running-process", udid, BUNDLE, "--sonora-review-url", "sonora://home")
        home_evidence = evidence(container, "home-review.json")
        sim("io", udid, "screenshot", str(OUTPUT / "iphone13-home.png"))
        sim("launch", "--terminate-running-process", udid, BUNDLE, "--sonora-review-url", "sonora://search?q=Beethoven")
        search_evidence = evidence(container, "search-review.json")
        sim("io", udid, "screenshot", str(OUTPUT / "iphone13-youtube-search.png"))
        sim("launch", "--terminate-running-process", udid, BUNDLE, "--sonora-review-url", "sonora://lyricsstorereview")
        lyrics_store = evidence(container, "lyrics-store-review.json", timeout=90)
        if not lyrics_store or not lyrics_store.get("passed"):
            raise RuntimeError("Lyrics import/timing/source/cache/restoration checks failed")
        sim("launch", "--terminate-running-process", udid, BUNDLE, "--sonora-review-url", "sonora://scrobblereview")
        scrobbling = evidence(container, "scrobble-review.json", timeout=90)
        if not scrobbling or not scrobbling.get("passed"):
            raise RuntimeError("Listening thresholds, durable scrobble retry or account isolation failed")
        sim("launch", "--terminate-running-process", udid, BUNDLE, "--sonora-review-url", "sonora://requestreview")
        requests = evidence(container, "native-requests-review.json")
        if not requests or not requests.get("passed"):
            raise RuntimeError("Swift/native cancellation or callback completion failed")
        sim("launch", "--terminate-running-process", udid, BUNDLE, "--sonora-review-url", "sonora://soundobservationreview")
        sound_observation = evidence(container, "sound-observation-review.json")
        if not sound_observation or not sound_observation.get("passed"):
            raise RuntimeError("Live sound settings/menu observation or latest-configuration handling failed")
        fixture = json.loads((IOS / "scripts/review-track.json").read_text())
        sim("launch", "--terminate-running-process", udid, BUNDLE, "--sonora-review-url", "sonora://soundprofilesreview")
        sound_profiles = evidence(container, "sound-profiles-review.json", timeout=90)
        if not sound_profiles or not sound_profiles.get("passed"):
            raise RuntimeError("Sound profile create/edit/import/export/restore/delete checks failed")
        sim("io", udid, "screenshot", str(OUTPUT / "iphone13-sound-profiles.png"))
        sim("launch", "--terminate-running-process", udid, BUNDLE, "--sonora-review-url", "sonora://soundprofileeditor")
        time.sleep(2)
        sim("io", udid, "screenshot", str(OUTPUT / "iphone13-sound-profile-editor.png"))
        metadata = {"id": fixture["id"], "title": fixture["title"], "artist": fixture["artist"], "artwork": fixture["artwork_url"]}
        sim("launch", "--terminate-running-process", udid, BUNDLE, "--sonora-review-url", "sonora://queuereview?" + urllib.parse.urlencode(metadata))
        queue_review = evidence(container, "queue-review.json")
        if not queue_review or not queue_review.get("passed"):
            raise RuntimeError("Queue occurrence, reorder or restoration checks failed")
        time.sleep(2)
        sim("io", udid, "screenshot", str(OUTPUT / "iphone13-queue-duplicates.png"))
        for mode in ("artwork", "lyrics", "queue"):
            route = "sonora://review?" + urllib.parse.urlencode(dict(metadata, mode=mode))
            sim("launch", "--terminate-running-process", udid, BUNDLE, "--sonora-review-url", route)
            if mode == "lyrics":
                lyrics_evidence = evidence(container, "lyrics-review.json")
            time.sleep(4)
            sim("io", udid, "screenshot", str(OUTPUT / ("iphone13-player-" + mode + ".png")))
            if mode == "artwork":
                sim("ui", udid, "content_size", "accessibility-extra-extra-extra-large")
                time.sleep(1)
                sim("io", udid, "screenshot", str(OUTPUT / "iphone13-player-large-text.png"))
                sim("ui", udid, "content_size", "large")
        if not home_evidence or home_evidence.get("items", 0) == 0:
            raise RuntimeError("Home did not return decoded content; inspect the captured screen")
        if not search_evidence or search_evidence.get("songs", 0) == 0:
            raise RuntimeError("Catalog Search did not return decoded songs; inspect the captured screen")
        if not lyrics_evidence or lyrics_evidence.get("line_count", 0) == 0:
            raise RuntimeError("Lyrics did not return decoded lines; inspect the captured screen")
        # This synthetic file checks native import and audio independently from provider authorization.
        tone = container / "Library/Caches/sonora-review-tone.wav"
        tone.parent.mkdir(parents=True, exist_ok=True)
        rate = 22_050
        with wave.open(str(tone), "wb") as output:
            output.setparams((1, 2, rate, 0, "NONE", "not compressed"))
            output.writeframes(b"".join(struct.pack("<h", int(2_000 * math.sin(2 * math.pi * 220 * i / rate))) for i in range(rate * 16)))
        # A self-generated gradient cover exercises actual artwork metadata, never third-party media.
        def png_chunk(kind, data):
            return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xffffffff)
        rows = b"".join(b"\x00" + bytes(channel for x in range(64) for channel in (x * 4, y * 4, 128)) for y in range(64))
        cover = b"\x89PNG\r\n\x1a\n" + png_chunk(b"IHDR", struct.pack(">IIBBBBB", 64, 64, 8, 2, 0, 0, 0)) + png_chunk(b"IDAT", zlib.compress(rows)) + png_chunk(b"IEND", b"")
        (tone.parent / "sonora-review-cover.png").write_bytes(cover)
        sim("launch", "--terminate-running-process", udid, BUNDLE, "--sonora-review-url", "sonora://localreview")
        local_review = evidence(container, "local-playback-review.json", timeout=60)
        if not local_review or not local_review.get("passed"):
            raise RuntimeError("Local import, playback, pause, seek or removal checks failed")
        sim("launch", "--terminate-running-process", udid, BUNDLE, "--sonora-review-url", "sonora://downloadsreview")
        download_layout = evidence(container, "downloads-layout-review.json")
        if not download_layout or not download_layout.get("passed"):
            raise RuntimeError("Download duration, legacy data or playlist restoration failed")
        sim("io", udid, "screenshot", str(OUTPUT / "iphone13-downloads-populated.png"))
        sim("launch", "--terminate-running-process", udid, BUNDLE, "--sonora-review-url", "sonora://localplaylistreview")
        local_library = evidence(container, "local-library-review.json", timeout=90)
        if not local_library or not local_library.get("passed"):
            raise RuntimeError("Native local playlist/favorite queue, ordering or restoration failed")
        time.sleep(2)
        sim("io", udid, "screenshot", str(OUTPUT / "iphone13-local-playlist.png"))
        sim("launch", "--terminate-running-process", udid, BUNDLE, "--sonora-review-url", "sonora://localplaylistrestore")
        local_relaunch = evidence(container, "local-library-relaunch-review.json")
        if not local_relaunch or not local_relaunch.get("passed"):
            raise RuntimeError("Local playlist/media/favorites did not survive actual app relaunch")
        time.sleep(2)
        sim("io", udid, "screenshot", str(OUTPUT / "iphone13-local-playlist-restored.png"))
        sim("launch", "--terminate-running-process", udid, BUNDLE, "--sonora-review-url", "sonora://locallyrics?" + urllib.parse.urlencode({"title": fixture["title"], "artist": fixture["artist"]}))
        local_lyrics = evidence(container, "local-lyrics-review.json")
        if not local_lyrics or local_lyrics.get("has_video_id") or local_lyrics.get("line_count", 0) == 0:
            raise RuntimeError("Local-file metadata lyrics did not decode without a provider ID")
        # A fork without repository variables must still verify real audio before publishing.
        video_id = os.environ.get("SONORA_SMOKE_VIDEO_ID") or fixture["id"]
        if video_id:
            probe_file = container / "Library/Application Support/guest-probe.json"
            sim("launch", "--terminate-running-process", udid, BUNDLE, "--sonora-review-url", "sonora://guestprobe")
            deadline = time.monotonic() + 390
            probe = None
            while time.monotonic() < deadline:
                if probe_file.exists():
                    probe = json.loads(probe_file.read_text())
                    if probe.get("status") in ("selected", "failed"): break
                time.sleep(1)
            (OUTPUT / "guest-probe.json").write_text(json.dumps(probe, indent=2))
            if not probe or probe.get("status") != "selected":
                sim("io", udid, "screenshot", str(OUTPUT / "iphone13-guest-probe.png"))
                raise RuntimeError("Guest resolution failed for the search candidates; inspect guest-probe.json")
            video_id = probe["selected_id"]
            streamed = verify_playback(container, video_id, downloaded=False)
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
                        raise RuntimeError("The live download check failed: " + str(entry.get("failureCode", "unspecified")))
                time.sleep(2)
            sim("io", udid, "screenshot", str(OUTPUT / "iphone13-download.png"))
            if complete is None:
                raise RuntimeError("The download check did not finish within 180 seconds")
            downloaded = index.parent / complete["filename"]
            if not downloaded.exists() or downloaded.stat().st_size == 0:
                raise RuntimeError("A completed download has no audio file")
            sim("launch", "--terminate-running-process", udid, BUNDLE, "--sonora-review-url", "sonora://play?" + urllib.parse.urlencode({"id": video_id, "title": video_id}))
            played_download = verify_playback(container, video_id, downloaded=True)
            sim("io", udid, "screenshot", str(OUTPUT / "iphone13-downloaded-player.png"))
            (OUTPUT / "download-check.json").write_text(json.dumps({
                "state": complete["state"], "bytes": downloaded.stat().st_size,
                "expected_bytes": complete.get("expectedBytes"),
                "limitations": "The file was downloaded and validated by the app. Physical-device airplane mode is not verified."
            }, indent=2))
            if not streamed or not played_download:
                raise RuntimeError("Native playback did not advance; inspect playback diagnostic artifacts")
        (OUTPUT / "device.json").write_text(json.dumps({"device": "iPhone 13 simulator", "runtime": runtime, "launch": launch, "limitations": "Simulator launch, appearance, streaming and download review. Physical-device behavior remains unverified."}, indent=2))
    finally:
        if "container" in locals():
            for filename in ("potoken-review.json", "provider-failure.json"):
                path = container / "Library/Application Support" / filename
                if path.exists(): (OUTPUT / filename).write_text(path.read_text())
        try:
            sim("shutdown", udid)
        finally:
            sim("delete", udid)
