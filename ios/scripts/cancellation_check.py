#!/usr/bin/env python3
"""Check callback ownership, early cancellation, bounded work and racing completions through C."""
import ctypes
import json
from pathlib import Path
import sys
import threading
import time

from audio_effects_check import DEFAULT, IOS, NativeDSP


def check(path):
    native = NativeDSP(path)
    native.lib.sonora_mobile_cancel.argtypes = [ctypes.c_char_p]
    native.lib.sonora_mobile_cancel.restype = ctypes.c_bool
    native.lib.sonora_mobile_pending_requests.restype = ctypes.c_uint32
    keep = []

    def start(identifier, delay=5_000):
        event, replies = threading.Event(), []

        @native.callback_type
        def callback(context, pointer):
            try:
                replies.append(json.loads(ctypes.string_at(pointer)))
            finally:
                native.lib.sonora_mobile_string_free(pointer)
                event.set()
        keep.append(callback)
        payload = dict(operation="review_wait", milliseconds=delay, request_id=identifier)
        status = native.lib.sonora_mobile_request(json.dumps(payload).encode(), None, callback)
        return status, event, replies

    pending = []
    for index in range(260):
        pending.append((f"cancel-{index}", *start(f"cancel-{index}")))
    assert sum(status == 0 for _, status, _, _ in pending) == 256
    assert native.lib.sonora_mobile_pending_requests() == 256
    assert start("cancel-0")[0] == 1, "duplicate request ID accepted"
    assert start("invalid id")[0] == 1
    before = time.monotonic()
    for identifier, status, _, _ in pending:
        assert native.lib.sonora_mobile_cancel(identifier.encode()) == (status == 0)
    for _, status, event, replies in pending:
        if status == 0:
            assert event.wait(2) and len(replies) == 1 and replies[0].get("error") == "cancelled"
    assert time.monotonic() - before < 2, "cancelled work retained its five-second delay"
    assert native.lib.sonora_mobile_pending_requests() == 0
    assert not native.lib.sonora_mobile_cancel(b"unknown")
    status, event, replies = start("complete", delay=1)
    assert status == 0 and event.wait(2) and replies[0]["ok"]
    assert not native.lib.sonora_mobile_cancel(b"complete")
    races = []
    for index in range(100):
        identifier = f"race-{index}"
        status, event, replies = start(identifier, delay=index % 3)
        assert status == 0
        native.lib.sonora_mobile_cancel(identifier.encode())
        races.append((event, replies))
    for event, replies in races:
        assert event.wait(2)
    time.sleep(0.05)
    assert all(len(replies) == 1 for _, replies in races), "a racing request replied more than once"
    assert native.lib.sonora_mobile_pending_requests() == 0
    result = dict(passed=True, bounded_active_requests=True, duplicate_ids_rejected=True,
                  cancellation_releases_work=True, racing_callbacks_exactly_once=True,
                  normal_completion=True, no_registered_requests_remaining=True)
    (IOS / "build/cancellation-check.json").write_text(json.dumps(result, indent=2))
    print(json.dumps(result))


def check_no_fixture(path):
    native = NativeDSP(path)
    replies = []

    @native.callback_type
    def callback(context, pointer):
        replies.append(True)
        native.lib.sonora_mobile_string_free(pointer)

    payload = json.dumps(dict(operation="review_wait", milliseconds=1, request_id="release-fixture-check")).encode()
    assert native.lib.sonora_mobile_request(payload, None, callback) == 1, "test fixture present in production archive"
    time.sleep(0.05)
    assert not replies
    print(json.dumps(dict(passed=True, production_fixture_absent=True)))


if __name__ == "__main__":
    args = [arg for arg in sys.argv[1:] if arg != "--expect-no-fixture"]
    path = Path(args[0]) if args else DEFAULT
    if "--expect-no-fixture" in sys.argv: check_no_fixture(path)
    else: check(path)
