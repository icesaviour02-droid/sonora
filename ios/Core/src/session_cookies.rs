//! Each sign-in gets a private cookie jar; the host persists its current header in Keychain.

use std::path::{Path, PathBuf};

use anyhow::{Context as _, Result};
use cookie_store::CookieStore;

/// Keeps a jar alive through outstanding requests, then removes that session's temporary files.
pub(crate) struct SessionCookies {
    directory: PathBuf,
    initial: String,
}

impl SessionCookies {
    /// Fresh sign-ins always use the supplied header. Only restoration may migrate a matching jar.
    pub(crate) fn create(root: &Path, supplied: &str, restoring: bool) -> Result<Self> {
        let initial = match restoring {
            true => restored_header(root, supplied),
            false => supplied.to_owned(),
        };
        let directory = root.join(format!("session-{:032x}", rand::random::<u128>()));
        let mut builder = std::fs::DirBuilder::new();
        builder.recursive(true);
        #[cfg(unix)]
        {
            use std::os::unix::fs::DirBuilderExt as _;
            builder.mode(0o700);
        }
        builder
            .create(&directory)
            .context("cannot create private youtube session directory")?;
        Ok(Self { directory, initial })
    }

    pub(crate) fn path(&self) -> PathBuf {
        self.directory.join("cookies.json")
    }

    pub(crate) fn resolutions(&self) -> PathBuf {
        self.directory.join("resolved.json")
    }

    /// Returns only current cookies applicable to the same origin seeded by the provider client.
    pub(crate) fn header(&self) -> Result<String> {
        match std::fs::File::open(self.path()) {
            Ok(file) => read_header(file),
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => Ok(self.initial.clone()),
            Err(error) => Err(error).context("cannot read youtube session cookies"),
        }
    }
}

impl Drop for SessionCookies {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir_all(&self.directory);
    }
}

/// Legacy jars may hold newer timestamp cookies, but must never select another Google identity.
fn restored_header(root: &Path, supplied: &str) -> String {
    let cached = std::fs::File::open(root.join("cookies.json"))
        .ok()
        .and_then(|file| read_header(file).ok());
    match cached {
        Some(header) if identity(&header).is_some() && identity(&header) == identity(supplied) => {
            header
        }
        _ => supplied.to_owned(),
    }
}

/// Filters the provider's persisted store by origin and expiry before creating a Keychain header.
fn read_header(file: std::fs::File) -> Result<String> {
    let store: CookieStore = cookie_store::serde::json::load(std::io::BufReader::new(file))
        .map_err(|_| anyhow::anyhow!("cannot decode youtube session cookies"))?;
    let origin = reqwest::Url::parse("https://music.youtube.com/")?;
    let mut pairs: Vec<_> = store.get_request_values(&origin).collect();
    pairs.sort_unstable_by_key(|(name, _)| *name);
    let header = pairs
        .into_iter()
        .map(|(name, value)| format!("{name}={value}"))
        .collect::<Vec<_>>()
        .join("; ");
    super::normalize_cookies(&header)
}

fn identity(header: &str) -> Option<&str> {
    ["SAPISID", "__Secure-3PAPISID"]
        .into_iter()
        .find_map(|key| {
            header
                .split(';')
                .filter_map(|pair| pair.trim().split_once('='))
                .find_map(|(name, value)| (name == key).then_some(value))
        })
}

#[cfg(test)]
mod tests {
    use super::*;
    use cookie_store::RawCookie;

    fn root() -> PathBuf {
        let path =
            std::env::temp_dir().join(format!("sonora-cookies-{:032x}", rand::random::<u128>()));
        std::fs::create_dir_all(&path).unwrap();
        path
    }

    fn jar(path: &Path, identity: &str, timestamp: &str) {
        let mut store = CookieStore::new();
        let origin = reqwest::Url::parse("https://music.youtube.com/").unwrap();
        for pair in [
            format!("SAPISID={identity}"),
            format!("__Secure-1PSIDTS={timestamp}"),
        ] {
            let cookie = RawCookie::parse(format!(
                "{pair}; Domain=youtube.com; Path=/; Secure; Max-Age=3600"
            ))
            .unwrap();
            store.insert_raw(&cookie, &origin).unwrap();
        }
        let file = std::fs::File::create(path).unwrap();
        cookie_store::serde::json::save(&store, &mut std::io::BufWriter::new(file)).unwrap();
    }

    #[test]
    fn fresh_sign_in_never_loads_an_old_jar() {
        let root = root();
        jar(&root.join("cookies.json"), "old", "old-timestamp");
        let fresh = SessionCookies::create(&root, "SAPISID=fresh", false).unwrap();
        assert_eq!(fresh.header().unwrap(), "SAPISID=fresh");
        assert!(!fresh.path().exists());
        drop(fresh);
        std::fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn restore_migrates_timestamp_only_for_the_same_identity() {
        let root = root();
        jar(&root.join("cookies.json"), "same", "new-timestamp");
        let same =
            SessionCookies::create(&root, "SAPISID=same; __Secure-1PSIDTS=old", true).unwrap();
        assert!(
            same.header()
                .unwrap()
                .contains("__Secure-1PSIDTS=new-timestamp")
        );
        let other = SessionCookies::create(&root, "SAPISID=other", true).unwrap();
        assert_eq!(other.header().unwrap(), "SAPISID=other");
        drop((same, other));
        std::fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn requests_keep_their_own_jar_alive_until_completion() {
        let root = root();
        let first =
            std::sync::Arc::new(SessionCookies::create(&root, "SAPISID=first", false).unwrap());
        let pending = first.clone();
        let second = SessionCookies::create(&root, "SAPISID=second", false).unwrap();
        assert_ne!(first.path(), second.path());
        let directory = first.directory.clone();
        drop(first);
        assert!(directory.exists());
        jar(&pending.path(), "first", "rotated");
        assert!(
            pending
                .header()
                .unwrap()
                .contains("__Secure-1PSIDTS=rotated")
        );
        assert_eq!(second.header().unwrap(), "SAPISID=second");
        drop(pending);
        assert!(!directory.exists());
        drop(second);
        std::fs::remove_dir_all(root).unwrap();
    }
}
