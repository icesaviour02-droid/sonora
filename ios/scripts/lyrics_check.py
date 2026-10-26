#!/usr/bin/env python3
"""Exercise the shared parser/ranking boundary; live mode reports counts, never lyric text."""

import json
from pathlib import Path
import sys

from audio_effects_check import DEFAULT, NativeDSP

IOS = Path(__file__).resolve().parents[1]
LRC = "[00:01.00]<00:01.00>Sonora <00:02.00>shines<00:03.00>\n[00:04.00][00:06.00]Keep the music moving\n"
TTML = '''<tt xmlns="http://www.w3.org/ns/ttml" xmlns:ttm="http://www.w3.org/ns/ttml#metadata"><body><div><p begin="1s" end="5s"><span begin="1s" end="2s">Sonora </span><span begin="2s" end="4s">shines</span><span ttm:role="x-bg" begin="2s" end="4s"><span begin="2s" end="3s">echo</span></span></p></div></body></tt>'''


def check(path, live=False):
    core = NativeDSP(path)
    parsed = core.request(dict(operation="parse_lyrics", text=LRC, format="lrc"))
    assert parsed["ok"]
    sheet = parsed["data"]
    assert sheet["synced"] and sheet["worded"] and len(sheet["lines"]) == 3
    assert len(sheet["lines"][0]["words"]) == 2
    assert sheet["lines"][0]["words"][-1]["end_seconds"] == 3
    assert [line["start_seconds"] for line in sheet["lines"]] == [1, 4, 6]
    ttml = core.request(dict(operation="parse_lyrics", text=TTML, format="ttml"))
    assert ttml["ok"] and ttml["data"]["worded"]
    assert sum(len(line["secondary"]) for line in ttml["data"]["lines"]) > 0
    result = dict(passed=True, enhanced_lrc_words=True, repeated_stamps=True, ttml_backing_vocals=True)
    if live:
        response = core.request(dict(operation="lyrics", title="Yellow", artist="Coldplay", sources=["LrcLib"]), timeout=35)
        assert response["ok"] and len(response["data"].get("lines", [])) > 0
        result["live"] = dict(source=response["data"]["source"], line_count=len(response["data"]["lines"]),
                              choices=len(response["data"].get("choices", [])), providers=response["data"].get("provider_status", []))
    destination = IOS / "build/lyrics-check.json"
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text(json.dumps(result, indent=2))
    print(json.dumps(result))


if __name__ == "__main__":
    args = [arg for arg in sys.argv[1:] if arg != "--live"]
    check(Path(args[0]) if args else DEFAULT, live="--live" in sys.argv)
