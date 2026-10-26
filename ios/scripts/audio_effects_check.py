#!/usr/bin/env python3
"""Check the real native DSP boundary with generated PCM, never provider audio or credentials."""

import ctypes
import json
import math
from pathlib import Path
import sys
import threading

IOS = Path(__file__).resolve().parents[1]
DEFAULT = IOS / "Core/target/debug/libsonora_mobile_core.so"
CALLBACKS = []


class NativeDSP:
    def __init__(self, path):
        self.lib = ctypes.CDLL(str(path))
        self.callback_type = ctypes.CFUNCTYPE(None, ctypes.c_void_p, ctypes.c_void_p)
        self.lib.sonora_mobile_request.argtypes = [ctypes.c_char_p, ctypes.c_void_p, self.callback_type]
        self.lib.sonora_mobile_string_free.argtypes = [ctypes.c_void_p]
        self.lib.sonora_audio_stage_create.restype = ctypes.c_void_p
        self.lib.sonora_audio_stage_destroy.argtypes = [ctypes.c_void_p]
        self.lib.sonora_audio_stage_format.argtypes = [ctypes.c_void_p, ctypes.c_uint32, ctypes.c_uint32]
        self.lib.sonora_audio_stage_process.argtypes = [ctypes.c_void_p, ctypes.POINTER(ctypes.POINTER(ctypes.c_float)), ctypes.c_size_t, ctypes.c_bool]
        self.lib.sonora_audio_stage_counter.argtypes = [ctypes.c_void_p]
        self.lib.sonora_audio_stage_counter.restype = ctypes.c_void_p
        self.lib.sonora_audio_counter_frames.argtypes = [ctypes.c_void_p]
        self.lib.sonora_audio_counter_frames.restype = ctypes.c_uint64
        self.revision = 0

    def configure(self, **changes):
        self.revision += 1
        payload = dict(operation="equalizer_configure", revision=self.revision, enabled=False,
                       preset="flat", auto_preamp=False, preamp_db=0, bass_db=0, treble_db=0,
                       normalization_db=0)
        payload.update(changes)
        done = threading.Event()
        result = []

        @self.callback_type
        def callback(context, pointer):
            try:
                result.append(json.loads(ctypes.string_at(pointer)))
            finally:
                self.lib.sonora_mobile_string_free(pointer)
                done.set()

        CALLBACKS.append(callback)
        assert self.lib.sonora_mobile_request(json.dumps(payload).encode(), None, callback) == 0
        assert done.wait(10), "audio configuration did not complete"
        assert result[0]["ok"], result[0].get("error")
        return result[0]["data"]

    def process(self, signals, interleaved=False):
        frames = len(signals[0])
        channels = len(signals)
        if interleaved:
            packed = [signals[c][f] for f in range(frames) for c in range(channels)]
            arrays = [(ctypes.c_float * len(packed))(*packed)]
        else:
            arrays = [(ctypes.c_float * frames)(*s) for s in signals]
        planes = (ctypes.POINTER(ctypes.c_float) * len(arrays))(*arrays)
        stage = self.lib.sonora_audio_stage_create()
        assert stage
        try:
            counter = self.lib.sonora_audio_stage_counter(stage)
            assert self.lib.sonora_audio_stage_format(stage, 48_000, channels) == 0
            assert self.lib.sonora_audio_stage_process(stage, planes, frames, interleaved) == 0
            assert self.lib.sonora_audio_counter_frames(counter) == frames
            if interleaved:
                return [[arrays[0][f * channels + c] for f in range(frames)] for c in range(channels)]
            return [list(a) for a in arrays]
        finally:
            self.lib.sonora_audio_stage_destroy(stage)


def tone(frequency):
    return [ctypes.c_float(0.05 * math.sin(2 * math.pi * frequency * i / 48_000)).value for i in range(48_000)]


def gain_db(before, after):
    # Exclude startup filter history, and measure a frequency-selective response rather than volume.
    a = sum(x*x for x in before[9_600:])
    b = sum(x*x for x in after[9_600:])
    return 10 * math.log10(b / a)


def check(path):
    dsp = NativeDSP(path)
    low, high = tone(60), tone(4_000)
    dsp.configure()
    bypass = dsp.process([low, high])
    assert bypass == [low, high], "disabled equalizer changed finite PCM samples"
    response = dsp.configure(enabled=True, bass_db=6)
    planar = dsp.process([low, high])
    low_db, high_db = gain_db(low, planar[0]), gain_db(high, planar[1])
    assert low_db - high_db > 4 and abs(high_db - response["preamp_db"]) < 0.2, (low_db, high_db)
    assert dsp.process([low, high], interleaved=True) == planar, "planar/interleaved channel mapping differs"
    preset = dsp.configure(enabled=True, preset="bass-boost", auto_preamp=True)
    colored = dsp.process([low, high])
    contrast = gain_db(low, colored[0]) - gain_db(high, colored[1])
    assert contrast > 4 and preset["preamp_db"] < 0 and preset["filter_count"] == 10
    imported = dsp.configure(enabled=True, preamp_db=-3,
        profile="Preamp: -3 dB\nFilter 1: ON PK Fc 1000 Hz Gain 6 dB Q 2\n")
    assert imported["filter_count"] == 1 and not imported["skipped_lines"]
    stale = dsp.configure(revision=0, preamp_db=12)
    assert not stale["applied"] and stale["preamp_db"] == imported["preamp_db"]
    dsp.configure(normalization_db=6)
    normalized = dsp.process([low])[0]
    assert abs(gain_db(low, normalized) - 6) < 0.01
    result = dict(passed=True, bypass_exact=True, channel_layouts_match=True,
                  bass_gain_db=low_db, upper_gain_db=high_db, preset_contrast_db=contrast,
                  preset_headroom_db=preset["preamp_db"], profile_import=True,
                  stale_configuration_ignored=True, normalization_gain_db=gain_db(low, normalized))
    output = IOS / "build/audio-effects-check.json"
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(result, indent=2))
    print(json.dumps(result))


if __name__ == "__main__":
    check(Path(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT)
