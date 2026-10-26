use anyhow::{Context as _, Result};
use rusqlite::{Connection, params};
use storage::Database;

use crate::LOCAL_PLAYLIST_PREFIX;

pub struct Stored {
    pub id: String,
    pub name: String,
    pub modified_at: i64,
}

/// Which local favorites table a star lands in.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Starred {
    Tracks,
    Albums,
    Artists,
}

impl Starred {
    fn table(self) -> &'static str {
        match self {
            Self::Tracks => "favorites",
            Self::Albums => "favorite_albums",
            Self::Artists => "favorite_artists",
        }
    }

    fn column(self) -> &'static str {
        match self {
            Self::Tracks => "track_id",
            Self::Albums => "album_id",
            Self::Artists => "artist_id",
        }
    }
}

pub struct Store {
    database: Database,
}

impl Store {
    pub fn new(database: Database) -> Self {
        Self { database }
    }

    fn open(&self) -> Result<rusqlite::Connection> {
        self.database.open().context("cannot open local playlists")
    }

    /// The starred ids of one kind, newest first, with the moment each was starred.
    pub fn starred(&self, kind: Starred) -> Result<Vec<(String, i64)>> {
        let connection = self.open()?;
        let mut query = connection
            .prepare(&format!(
                "SELECT {}, added_at FROM {} ORDER BY added_at DESC",
                kind.column(),
                kind.table()
            ))
            .context("cannot read local favorites")?;
        let rows = query
            .query_map([], |row| Ok((row.get(0)?, row.get(1)?)))
            .context("cannot read local favorites")?;

        rows.collect::<rusqlite::Result<Vec<_>>>()
            .context("cannot read local favorites")
    }

    /// Local track IDs ordered by play count, then most recent play.
    pub fn most_played(&self, limit: usize) -> Result<Vec<String>> {
        let connection = self.open()?;
        let mut query = connection
            .prepare(
                "SELECT track_id, COUNT(*) as count
                 FROM plays
                 WHERE track_id LIKE 'local:%'
                 GROUP BY track_id
                 ORDER BY count DESC, MAX(played_at) DESC
                 LIMIT ?",
            )
            .context("cannot read most played local tracks")?;
        let rows = query
            .query_map(params![limit as i64], |row| row.get::<_, String>(0))
            .context("cannot read most played local tracks")?;

        rows.collect::<rusqlite::Result<Vec<_>>>()
            .context("cannot read most played local tracks")
    }

    pub fn set_starred(&self, kind: Starred, id: &str, saved: bool) -> Result<()> {
        let connection = self.open()?;
        match saved {
            true => connection.execute(
                &format!(
                    "INSERT OR REPLACE INTO {} ({}, added_at) VALUES (?, ?)",
                    kind.table(),
                    kind.column()
                ),
                params![id, stamp()],
            ),
            false => connection.execute(
                &format!("DELETE FROM {} WHERE {} = ?", kind.table(), kind.column()),
                params![id],
            ),
        }
        .context("cannot update a local favorite")?;
        Ok(())
    }

    pub fn list(&self) -> Result<Vec<Stored>> {
        let connection = self.open()?;
        let mut query = connection
            .prepare("SELECT id, name, modified_at FROM playlists ORDER BY modified_at DESC")
            .context("cannot read local playlists")?;
        let rows = query
            .query_map([], |row| {
                Ok(Stored {
                    id: row.get(0)?,
                    name: row.get(1)?,
                    modified_at: row.get(2)?,
                })
            })
            .context("cannot read local playlists")?;

        rows.collect::<rusqlite::Result<Vec<_>>>()
            .context("cannot read local playlists")
    }

    pub fn one(&self, id: &str) -> Result<Stored> {
        self.open()?
            .query_row(
                "SELECT id, name, modified_at FROM playlists WHERE id = ?",
                params![id],
                |row| {
                    Ok(Stored {
                        id: row.get(0)?,
                        name: row.get(1)?,
                        modified_at: row.get(2)?,
                    })
                },
            )
            .with_context(|| format!("cannot find local playlist {id}"))
    }

    pub fn create(&self, name: &str) -> Result<String> {
        self.create_with_tracks(name, &[])
    }

    /// Creates the playlist and its initial selection together, leaving no partial playlist on error.
    pub fn create_with_tracks(&self, name: &str, tracks: &[String]) -> Result<String> {
        let id = format!("{LOCAL_PLAYLIST_PREFIX}{}-{}", stamp(), minted());
        let mut connection = self.open()?;
        let transaction = connection
            .transaction()
            .context("cannot begin local playlist creation")?;
        transaction
            .execute(
                "INSERT INTO playlists (id, name, modified_at) VALUES (?, ?, ?)",
                params![id, name, stamp()],
            )
            .context("cannot create a local playlist")?;
        for (position, track) in tracks.iter().enumerate() {
            transaction.execute("INSERT OR IGNORE INTO playlist_tracks (playlist_id, track_id, position) VALUES (?, ?, ?)", params![id, track, position as i64])?;
        }
        transaction
            .commit()
            .context("cannot commit local playlist creation")?;
        Ok(id)
    }

    pub fn rename(&self, id: &str, name: &str) -> Result<()> {
        self.open()?
            .execute(
                "UPDATE playlists SET name = ?, modified_at = ? WHERE id = ?",
                params![name, stamp(), id],
            )
            .context("cannot rename a local playlist")?;
        Ok(())
    }

    pub fn delete(&self, id: &str) -> Result<()> {
        let mut connection = self.open()?;
        let transaction = connection
            .transaction()
            .context("cannot begin local playlist deletion")?;
        transaction
            .execute(
                "DELETE FROM playlist_tracks WHERE playlist_id = ?",
                params![id],
            )
            .context("cannot empty a local playlist")?;
        transaction
            .execute("DELETE FROM playlists WHERE id = ?", params![id])
            .context("cannot delete a local playlist")?;
        transaction
            .commit()
            .context("cannot commit local playlist deletion")
    }

    pub fn add(&self, id: &str, track_id: &str) -> Result<()> {
        self.add_many(id, &[track_id.to_owned()])
    }

    /// Adds a selection in one transaction, preserving order and ignoring songs already present.
    pub fn add_many(&self, id: &str, tracks: &[String]) -> Result<()> {
        let mut connection = self.open()?;
        let transaction = connection
            .transaction()
            .context("cannot begin local playlist addition")?;
        let mut position: i64 = transaction.query_row(
            "SELECT COALESCE(MAX(position), -1) + 1 FROM playlist_tracks WHERE playlist_id = ?",
            params![id],
            |row| row.get(0),
        )?;
        for track in tracks {
            let inserted = transaction.execute("INSERT OR IGNORE INTO playlist_tracks (playlist_id, track_id, position) VALUES (?, ?, ?)", params![id, track, position])?;
            position += inserted as i64;
        }
        touch(&transaction, id)?;
        transaction
            .commit()
            .context("cannot commit local playlist addition")
    }

    pub fn remove(&self, id: &str, track_id: &str) -> Result<()> {
        self.remove_many(id, &[track_id.to_owned()])
    }

    /// Removes a selection together so a failed save leaves the original playlist intact.
    pub fn remove_many(&self, id: &str, tracks: &[String]) -> Result<()> {
        let mut connection = self.open()?;
        let transaction = connection
            .transaction()
            .context("cannot begin local playlist removal")?;
        for track in tracks {
            transaction.execute(
                "DELETE FROM playlist_tracks WHERE playlist_id = ? AND track_id = ?",
                params![id, track],
            )?;
        }
        touch(&transaction, id)?;
        transaction
            .commit()
            .context("cannot commit local playlist removal")
    }

    /// Removes deleted imports from their playlists and track favorites without touching other media.
    pub fn forget_tracks(&self, tracks: &[String]) -> Result<()> {
        let mut connection = self.open()?;
        let transaction = connection
            .transaction()
            .context("cannot begin local track cleanup")?;
        for track in tracks {
            transaction.execute("UPDATE playlists SET modified_at = ? WHERE id IN (SELECT playlist_id FROM playlist_tracks WHERE track_id = ?)", params![stamp(), track])?;
            transaction.execute(
                "DELETE FROM playlist_tracks WHERE track_id = ?",
                params![track],
            )?;
            transaction.execute("DELETE FROM favorites WHERE track_id = ?", params![track])?;
        }
        transaction
            .commit()
            .context("cannot commit local track cleanup")
    }

    /// Reorders the existing set atomically. A stale or duplicated list cannot discard songs.
    pub fn reorder(&self, id: &str, tracks: &[String]) -> Result<()> {
        let mut connection = self.open()?;
        let transaction = connection
            .transaction()
            .context("cannot begin local playlist reorder")?;
        let exists: bool = transaction.query_row(
            "SELECT EXISTS(SELECT 1 FROM playlists WHERE id = ?)",
            params![id],
            |row| row.get(0),
        )?;
        if !exists {
            anyhow::bail!("cannot find local playlist");
        }
        let current: std::collections::HashSet<String> = {
            let mut query = transaction
                .prepare("SELECT track_id FROM playlist_tracks WHERE playlist_id = ?")?;
            query
                .query_map(params![id], |row| row.get::<_, String>(0))?
                .collect::<rusqlite::Result<_>>()?
        };
        let wanted: std::collections::HashSet<String> = tracks.iter().cloned().collect();
        if wanted.len() != tracks.len() || current != wanted {
            anyhow::bail!("local playlist order is stale or duplicated");
        }
        transaction.execute(
            "DELETE FROM playlist_tracks WHERE playlist_id = ?",
            params![id],
        )?;
        for (position, track) in tracks.iter().enumerate() {
            transaction.execute(
                "INSERT INTO playlist_tracks (playlist_id, track_id, position) VALUES (?, ?, ?)",
                params![id, track, position as i64],
            )?;
        }
        touch(&transaction, id)?;
        transaction
            .commit()
            .context("cannot commit local playlist reorder")
    }

    pub fn tracks(&self, id: &str) -> Result<Vec<String>> {
        let connection = self.open()?;
        let mut query = connection
            .prepare("SELECT track_id FROM playlist_tracks WHERE playlist_id = ? ORDER BY position")
            .context("cannot read a local playlist")?;
        let rows = query
            .query_map(params![id], |row| row.get::<_, String>(0))
            .context("cannot read a local playlist")?;

        rows.collect::<rusqlite::Result<Vec<_>>>()
            .context("cannot read a local playlist")
    }
}

fn touch(connection: &Connection, id: &str) -> Result<()> {
    connection
        .execute(
            "UPDATE playlists SET modified_at = ? WHERE id = ?",
            params![stamp(), id],
        )
        .context("cannot stamp a local playlist")?;
    Ok(())
}

fn minted() -> u64 {
    static NEXT: std::sync::atomic::AtomicU64 = std::sync::atomic::AtomicU64::new(0);
    NEXT.fetch_add(1, std::sync::atomic::Ordering::Relaxed)
}

fn stamp() -> i64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap_or_default()
        .as_millis()
        .min(i64::MAX as u128) as i64
}
