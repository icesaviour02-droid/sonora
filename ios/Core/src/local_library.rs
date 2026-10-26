//! Desktop local playlists and favorites, serialized off the host UI and audio threads.

use std::path::PathBuf;
use std::sync::{Arc, OnceLock};

use anyhow::{Context as _, Result, bail};
use serde::Deserialize;
use serde_json::{Value, json};
use tokio::sync::Semaphore;

use crate::desktop_local_store::{Starred, Store};

#[derive(Deserialize)]
#[serde(tag = "kind", rename_all = "snake_case", deny_unknown_fields)]
pub(crate) enum Action {
    Snapshot,
    CreatePlaylist {
        name: String,
        #[serde(default)]
        track_ids: Vec<String>,
    },
    RenamePlaylist {
        playlist_id: String,
        name: String,
    },
    DeletePlaylist {
        playlist_id: String,
    },
    AddTracks {
        playlist_id: String,
        track_ids: Vec<String>,
    },
    RemoveTracks {
        playlist_id: String,
        track_ids: Vec<String>,
    },
    ReorderPlaylist {
        playlist_id: String,
        track_ids: Vec<String>,
    },
    ForgetTracks {
        track_ids: Vec<String>,
    },
    ToggleFavorite {
        category: Category,
        id: String,
    },
    SetFavorite {
        category: Category,
        id: String,
        saved: bool,
    },
}

#[derive(Clone, Copy, Deserialize)]
#[serde(rename_all = "snake_case")]
pub(crate) enum Category {
    Tracks,
    Albums,
    Artists,
}

impl Category {
    fn starred(self) -> Starred {
        match self {
            Self::Tracks => Starred::Tracks,
            Self::Albums => Starred::Albums,
            Self::Artists => Starred::Artists,
        }
    }
}

/// A cancelled caller cannot detach unbounded SQLite workers or interrupt a durable mutation.
pub(crate) async fn execute(database_path: String, action: Action) -> Result<Value> {
    if database_path.len() > 4_096 || !PathBuf::from(&database_path).is_absolute() {
        bail!("invalid local database path");
    }
    static SERIAL: OnceLock<Arc<Semaphore>> = OnceLock::new();
    let permit = SERIAL
        .get_or_init(|| Arc::new(Semaphore::new(1)))
        .clone()
        .acquire_owned()
        .await?;
    tokio::task::spawn_blocking(move || {
        let _permit = permit;
        let store = Store::new(storage::Database::at(PathBuf::from(database_path)));
        let mut created = None;
        match action {
            Action::Snapshot => {}
            Action::CreatePlaylist { name, track_ids } => {
                tracks_checked(&track_ids)?;
                created = Some(store.create_with_tracks(name_checked(&name)?, &track_ids)?)
            }
            Action::RenamePlaylist { playlist_id, name } => {
                playlist_checked(&store, &playlist_id)?;
                store.rename(&playlist_id, name_checked(&name)?)?;
            }
            Action::DeletePlaylist { playlist_id } => {
                playlist_checked(&store, &playlist_id)?;
                store.delete(&playlist_id)?;
            }
            Action::AddTracks {
                playlist_id,
                track_ids,
            } => {
                playlist_checked(&store, &playlist_id)?;
                tracks_checked(&track_ids)?;
                store.add_many(&playlist_id, &track_ids)?;
            }
            Action::RemoveTracks {
                playlist_id,
                track_ids,
            } => {
                playlist_checked(&store, &playlist_id)?;
                tracks_checked(&track_ids)?;
                store.remove_many(&playlist_id, &track_ids)?;
            }
            Action::ReorderPlaylist {
                playlist_id,
                track_ids,
            } => {
                playlist_checked(&store, &playlist_id)?;
                tracks_checked(&track_ids)?;
                store.reorder(&playlist_id, &track_ids)?;
            }
            Action::ForgetTracks { track_ids } => {
                tracks_checked(&track_ids)?;
                store.forget_tracks(&track_ids)?;
            }
            Action::ToggleFavorite { category, id } => {
                if id.is_empty() || id.len() > 2_048 {
                    bail!("invalid local favorite identity");
                }
                let selected = store
                    .starred(category.starred())?
                    .iter()
                    .any(|(saved, _)| saved == &id);
                store.set_starred(category.starred(), &id, !selected)?;
            }
            Action::SetFavorite {
                category,
                id,
                saved,
            } => {
                if id.is_empty() || id.len() > 2_048 {
                    bail!("invalid local favorite identity");
                }
                store.set_starred(category.starred(), &id, saved)?;
            }
        }
        snapshot(&store, created)
    })
    .await
    .context("cannot finish local library work")?
}

fn name_checked(name: &str) -> Result<&str> {
    let name = name.trim();
    if name.is_empty() || name.chars().count() > 200 {
        bail!("invalid local playlist name");
    }
    Ok(name)
}

fn playlist_checked(store: &Store, id: &str) -> Result<()> {
    if !id.starts_with(crate::LOCAL_PLAYLIST_PREFIX) || id.len() > 128 {
        bail!("invalid local playlist identity");
    }
    store.one(id)?;
    Ok(())
}

fn tracks_checked(tracks: &[String]) -> Result<()> {
    if tracks.len() > 10_000 || tracks.iter().any(|id| id.is_empty() || id.len() > 1_024) {
        bail!("invalid local track identities");
    }
    Ok(())
}

fn snapshot(store: &Store, created: Option<String>) -> Result<Value> {
    let playlists = store.list()?.into_iter().map(|playlist| {
        let tracks = store.tracks(&playlist.id)?;
        Ok(json!({ "id": playlist.id, "title": playlist.name, "modified_at": playlist.modified_at, "track_ids": tracks }))
    }).collect::<Result<Vec<_>>>()?;
    fn ids(store: &Store, category: Starred) -> Result<Vec<String>> {
        Ok(store
            .starred(category)?
            .into_iter()
            .map(|(id, _)| id)
            .collect())
    }
    Ok(
        json!({ "playlists": playlists, "track_ids": ids(store, Starred::Tracks)?,
        "album_ids": ids(store, Starred::Albums)?, "artist_ids": ids(store, Starred::Artists)?, "created_id": created }),
    )
}
