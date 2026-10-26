#!/usr/bin/env python3
"""Verify the reused desktop SQLite store through the native ABI, including failed-write rollback."""
import json
from pathlib import Path
import sqlite3
import sys
import tempfile

from audio_effects_check import DEFAULT, IOS, NativeDSP


def check(path):
    core = NativeDSP(path)
    checks = {}
    with tempfile.TemporaryDirectory(prefix="sonora-local-review-") as folder:
        database = Path(folder) / "local.sqlite"

        def call(kind, **fields):
            return core.request(dict(operation="local_library", database_path=str(database), action=dict(kind=kind, **fields)))

        def data(kind, **fields):
            response = call(kind, **fields)
            assert response["ok"], response.get("error")
            return response["data"]

        assert not data("snapshot")["playlists"]
        created = data("create_playlist", name="  音楽 Review  ", track_ids=["one", "two", "one"])
        identity = created["created_id"]
        assert identity.startswith("local-playlist:")
        playlist = created["playlists"][0]
        checks["create_with_unique_ordered_selection"] = playlist["title"] == "音楽 Review" and playlist["track_ids"] == ["one", "two"]
        renamed = data("rename_playlist", playlist_id=identity, name="Evening Review")
        checks["rename_preserves_selection"] = renamed["playlists"][0]["title"] == "Evening Review" and renamed["playlists"][0]["track_ids"] == ["one", "two"]
        added = data("add_tracks", playlist_id=identity, track_ids=["two", "three"])
        checks["append_without_duplicates"] = added["playlists"][0]["track_ids"] == ["one", "two", "three"]
        order = ["three", "one", "two"]
        checks["reorder_persists"] = data("reorder_playlist", playlist_id=identity, track_ids=order)["playlists"][0]["track_ids"] == order
        for invalid in (["one"], ["one", "one", "three"]):
            assert not call("reorder_playlist", playlist_id=identity, track_ids=invalid)["ok"]
        checks["stale_and_duplicate_reorder_rejected"] = data("snapshot")["playlists"][0]["track_ids"] == order
        for category, identifier in [("tracks", "one"), ("albums", "album\0artist"), ("artists", "アーティスト")]:
            response = data("set_favorite", category=category, id=identifier, saved=True)
            key = dict(tracks="track_ids", albums="album_ids", artists="artist_ids")[category]
            assert identifier in response[key]
        checks["all_favorite_categories"] = True
        data("toggle_favorite", category="tracks", id="one")
        data("toggle_favorite", category="tracks", id="one")
        checks["sequential_toggle_restores_favorite"] = "one" in data("snapshot")["track_ids"]
        assert database.read_bytes().startswith(b"SQLite format 3")
        with sqlite3.connect(database) as connection:
            checks["desktop_database_schema"] = connection.execute("select name from playlists where id=?", (identity,)).fetchone()[0] == "Evening Review"
            connection.execute("CREATE TRIGGER reject_review_song BEFORE INSERT ON playlist_tracks WHEN new.track_id='reject' BEGIN SELECT RAISE(ABORT,'generated failure'); END")
        assert not call("create_playlist", name="Must Roll Back", track_ids=["new", "reject"])["ok"]
        checks["create_failure_rolls_back"] = len(data("snapshot")["playlists"]) == 1
        assert not call("add_tracks", playlist_id=identity, track_ids=["four", "reject"])["ok"]
        checks["batch_failure_rolls_back"] = data("snapshot")["playlists"][0]["track_ids"] == order
        with sqlite3.connect(database) as connection:
            connection.execute("CREATE TRIGGER reject_review_delete BEFORE DELETE ON playlists BEGIN SELECT RAISE(ABORT,'generated failure'); END")
        assert not call("delete_playlist", playlist_id=identity)["ok"]
        checks["delete_failure_preserves_tracks"] = data("snapshot")["playlists"][0]["track_ids"] == order
        with sqlite3.connect(database) as connection:
            connection.execute("DROP TRIGGER reject_review_delete")
        removed = data("remove_tracks", playlist_id=identity, track_ids=["two"])
        checks["remove_selection"] = removed["playlists"][0]["track_ids"] == ["three", "one"]
        forgotten = data("forget_tracks", track_ids=["one"])
        checks["deleted_import_cleanup"] = forgotten["playlists"][0]["track_ids"] == ["three"] and "one" not in forgotten["track_ids"] and forgotten["album_ids"] == ["album\0artist"]
        data("delete_playlist", playlist_id=identity)
        with sqlite3.connect(database) as connection:
            checks["delete_leaves_no_orphans"] = connection.execute("select count(*) from playlist_tracks").fetchone()[0] == 0
        checks["empty_name_rejected"] = not call("create_playlist", name="   ")["ok"]
        corrupt = Path(folder) / "corrupt.sqlite"
        original = b"Sonora corrupt database acceptance fixture"
        corrupt.write_bytes(original)
        response = core.request(dict(operation="local_library", database_path=str(corrupt), action=dict(kind="snapshot")))
        checks["corrupt_database_preserved"] = not response["ok"] and corrupt.read_bytes() == original
    assert len(checks) == 16 and all(checks.values()), checks
    result = dict(passed=True, checks=checks)
    (IOS / "build/local-library-check.json").write_text(json.dumps(result, indent=2))
    print(json.dumps(result))


if __name__ == "__main__":
    check(Path(sys.argv[1]) if len(sys.argv)>1 else DEFAULT)
