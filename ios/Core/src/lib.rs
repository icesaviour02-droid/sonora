//! A narrow native boundary around the same YouTube client used by desktop Sonora.
//! Network operations stay on Tokio, with no GPUI, desktop audio output or UI dependencies.

// Reuse the desktop's allocation-free DSP and preset curves, without its rodio output plumbing.
mod audio_effects;
mod lyric_bridge;
#[path = "../../../crates/music/src/models.rs"]
pub mod models;
pub use models::*;
#[path = "../../../crates/music/src/lyrics/mod.rs"]
pub mod lyrics;
pub use lyrics::provider::LyricsProvider;
#[path = "../../../crates/music/src/binimum/mod.rs"]
pub mod binimum;
pub mod desktop_youtube;
#[path = "../../../crates/music/src/equalizer/mod.rs"]
pub mod equalizer;
#[path = "../../../crates/music/src/escape.rs"]
pub mod escape;
#[path = "../../../crates/music/src/kugou/mod.rs"]
pub mod kugou;
#[path = "../../../crates/music/src/lrclib/mod.rs"]
pub mod lrclib;
#[path = "../../../crates/music/src/musixmatch/mod.rs"]
pub mod musixmatch;
#[path = "../../../crates/music/src/netease/mod.rs"]
pub mod netease;

use std::collections::{HashMap, HashSet};
use std::ffi::{CStr, CString, c_char, c_void};
use std::path::PathBuf;
use std::sync::{Arc, Mutex, OnceLock, RwLock, Weak};
use std::time::{Duration, Instant, SystemTime};

use anyhow::{Context as _, Result, bail};
use async_trait::async_trait;
use serde::Deserialize;
use serde_json::{Value, json};
use tokio::runtime::{Builder, Runtime};
use ytmusic::{Client, Minter, YtMusic, nav::Nav as _, parse::find_renderers};

const DEADLINE: Duration = Duration::from_secs(30);
const MAX_QUERY: usize = 512;
const ACCOUNT_LIMIT: usize = 8;
const ROTATION: Duration = Duration::from_secs(10 * 60);
const ROTATION_CHECK: Duration = Duration::from_secs(60);
const POTOKEN_KEEP: Duration = Duration::from_secs(6 * 60 * 60);
const POTOKEN_SOONEST: Duration = Duration::from_secs(5);
const POTOKEN_SLOWEST: Duration = Duration::from_secs(5 * 60);
const POTOKEN_WARM_WAIT: Duration = Duration::from_secs(35);
const POTOKEN_WARM_POLL: Duration = Duration::from_millis(50);
const HOME_BROWSE_ID: &str = "FEmusic_home";
const GENRES_BROWSE_ID: &str = "FEmusic_moods_and_genres";
const GENRE_CATEGORY_ID: &str = "FEmusic_moods_and_genres_category";
const SUBSCRIPTIONS_BROWSE_ID: &str = "FEmusic_library_corpus_artists";
const ARTISTS_SEARCH_PARAMS: &str = "EgWKAQIgAQ%3D%3D";

type Callback = extern "C" fn(*mut c_void, *mut c_char);

static RUNTIME: OnceLock<Result<Runtime, String>> = OnceLock::new();
static SESSION: OnceLock<RwLock<Session>> = OnceLock::new();
static POTOKENS: OnceLock<Mutex<PoTokenStore>> = OnceLock::new();

/// The generation prevents an old sign-in from replacing a later sign-out or account choice.
struct Session {
    api: Arc<YtMusic>,
    generation: u64,
    cache_dir: Option<PathBuf>,
}

/// Shared proof-of-origin token hand-off between `YtMusic` and the iOS `WKWebView` minter.
#[derive(Default)]
struct PoTokenStore {
    wanted: Option<String>,
    minted: HashMap<String, MintedToken>,
    failures: u32,
    failed_at: Option<Instant>,
    warm: bool,
}

struct MintedToken {
    token: String,
    at: Instant,
}

struct MobileMinter;

#[async_trait]
impl Minter for MobileMinter {
    async fn mint(&self, binding: &str) -> Option<String> {
        if let Some(token) = potoken_token(binding) {
            return Some(token);
        }
        let deadline = Instant::now() + POTOKEN_WARM_WAIT;
        while Instant::now() < deadline {
            tokio::time::sleep(POTOKEN_WARM_POLL).await;
            if let Some(token) = potoken_minted(binding) {
                return Some(token);
            }
        }
        None
    }
}

fn potokens() -> &'static Mutex<PoTokenStore> {
    POTOKENS.get_or_init(Mutex::default)
}

fn potoken_token(binding: &str) -> Option<String> {
    let mut store = potokens().lock().ok()?;
    if let Some(token) = store.fresh(binding) {
        return Some(token);
    }
    if !store.held() {
        store.wanted = Some(binding.to_string());
    }
    None
}

fn potoken_minted(binding: &str) -> Option<String> {
    potokens().lock().ok()?.fresh(binding)
}

impl PoTokenStore {
    fn fresh(&self, binding: &str) -> Option<String> {
        self.minted
            .get(binding)
            .filter(|entry| entry.at.elapsed() < POTOKEN_KEEP)
            .map(|entry| entry.token.clone())
    }

    fn held(&self) -> bool {
        let doublings = self.failures.saturating_sub(1).min(16);
        let hold = POTOKEN_SOONEST
            .saturating_mul(1u32 << doublings)
            .min(POTOKEN_SLOWEST);
        self.failed_at.is_some_and(|at| at.elapsed() < hold)
    }

    fn clear(&mut self) {
        self.wanted = None;
        self.minted.clear();
        self.failures = 0;
        self.failed_at = None;
        self.warm = false;
    }
}

fn build_anonymous(cache_dir: Option<&PathBuf>) -> Arc<YtMusic> {
    let mut api = YtMusic::anonymous().mint_po_tokens(Arc::new(MobileMinter));
    if let Some(dir) = cache_dir {
        api = api.cache_player(dir.join("player.json"));
    }
    Arc::new(api)
}

fn build_authenticated(
    cookies: &str,
    authuser: usize,
    page_id: Option<&str>,
    cache_dir: Option<&PathBuf>,
) -> Arc<YtMusic> {
    let mut api = YtMusic::with_cookies(cookies).as_user(authuser);
    if let Some(page) = page_id.filter(|page| !page.is_empty()) {
        api = api.as_page(page);
    }
    if let Some(dir) = cache_dir {
        api = api
            .persist_cookies(dir.join("cookies.json"))
            .cache_resolutions(dir.join("resolved.json"))
            .cache_player(dir.join("player.json"));
    }
    Arc::new(api.mint_po_tokens(Arc::new(MobileMinter)))
}

fn session() -> &'static RwLock<Session> {
    SESSION.get_or_init(|| {
        RwLock::new(Session {
            api: build_anonymous(None),
            generation: 0,
            cache_dir: None,
        })
    })
}

#[derive(Deserialize)]
#[serde(tag = "operation", rename_all = "snake_case", deny_unknown_fields)]
enum Request {
    EqualizerConfigure {
        revision: u64,
        enabled: bool,
        preset: String,
        auto_preamp: bool,
        preamp_db: f64,
        bass_db: f64,
        treble_db: f64,
        normalization_db: f64,
        profile: Option<String>,
        filters: Option<Vec<audio_effects::FilterSpec>>,
    },
    EqualizerDescribe {
        preset: String,
        profile: Option<String>,
        filters: Option<Vec<audio_effects::FilterSpec>>,
        auto_preamp: Option<bool>,
        preamp_db: Option<f64>,
    },
    Configure {
        cache_dir: String,
    },
    PoTokenWanted {},
    PoTokenGive {
        binding: String,
        token: String,
    },
    PoTokenFailed {},
    ListAccounts {
        cookies: String,
    },
    Authenticate {
        cookies: String,
        authuser: Option<usize>,
        page_id: Option<String>,
    },
    RotateCookies {},
    SignOut {},
    Search {
        query: String,
    },
    SearchCatalog {
        query: String,
    },
    SearchSuggestions {
        input: String,
    },
    Resolve {
        video_id: String,
        quality: Option<String>,
    },
    Lyrics {
        video_id: Option<String>,
        title: Option<String>,
        artist: Option<String>,
        album: Option<String>,
        duration_seconds: Option<f64>,
        sources: Option<Vec<String>>,
        local_text: Option<String>,
    },
    ParseLyrics {
        text: String,
        format: Option<String>,
    },
    Home {},
    Genre {
        params: String,
    },
    Album {
        browse_id: String,
    },
    Artist {
        browse_id: String,
    },
    Playlist {
        playlist_id: String,
    },
    Radio {
        video_id: String,
    },
    LibraryContent {},
    RateTrack {
        video_id: String,
        liked: bool,
    },
    RatePlaylist {
        playlist_id: String,
        saved: bool,
    },
    SetArtistSaved {
        artist_id: String,
        saved: bool,
    },
    CreatePlaylist {
        title: String,
    },
    RenamePlaylist {
        playlist_id: String,
        title: String,
    },
    DeletePlaylist {
        playlist_id: String,
    },
    SetPlaylistPrivacy {
        playlist_id: String,
        public: bool,
    },
    AddPlaylistTrack {
        playlist_id: String,
        video_id: String,
    },
    RemovePlaylistTrack {
        playlist_id: String,
        video_id: String,
        set_video_id: String,
    },
}

/// Accepts owned JSON work and delivers an owned JSON response on a background worker.
///
/// # Safety
/// `request_json` must point to a valid NUL-terminated UTF-8 string for this call. The context
/// must be safe to return to the callback's thread and remain alive until that callback runs.
/// The callback must not unwind into Rust. It owns and must eventually release the response.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn sonora_mobile_request(
    request_json: *const c_char,
    context: *mut c_void,
    callback: Option<Callback>,
) -> i32 {
    let Some(callback) = callback else { return 1 };
    if request_json.is_null() {
        return 1;
    }
    let request = match unsafe { CStr::from_ptr(request_json) }.to_str() {
        Ok(value) => match serde_json::from_str::<Request>(value) {
            Ok(request) => request,
            Err(_) => return 1,
        },
        Err(_) => return 1,
    };
    let runtime = RUNTIME.get_or_init(|| {
        Builder::new_multi_thread()
            .worker_threads(2)
            .enable_all()
            .build()
            .map_err(|error| error.to_string())
    });
    let Ok(runtime) = runtime else { return 2 };
    // Rust does not dereference the host context. Only the host callback interprets it.
    let context = context as usize;
    runtime.spawn(async move {
        let deadline = match request {
            Request::Resolve { .. } => Duration::from_secs(90),
            _ => DEADLINE,
        };
        let outcome = tokio::time::timeout(deadline, execute(request)).await;
        let response = match outcome {
            Ok(Ok(data)) => json!({ "ok": true, "data": data }),
            Ok(Err(error)) => {
                let message = format!("{error:#}").to_lowercase();
                let verification = message.contains("not a bot");
                let code = if verification { "verification_required" }
                    else if error.downcast_ref::<audio_effects::InvalidConfiguration>().is_some() { "equalizer_invalid" }
                    else if error.downcast_ref::<ytmusic::SignInRequired>().is_some() { "sign_in_required" }
                    else { "provider_unavailable" };
                json!({ "ok": false, "error": code, "diagnostics": {
                    "network_verification": verification,
                    "decipher_problem": message.contains("solver") || message.contains("decipher") || message.contains("quickjs"),
                    "audio_host_refused": message.contains("is not being served") || message.contains("stream host refused"),
                    "api_login_required": message.contains("login_required"),
                }})
            }
            Err(_) => json!({ "ok": false, "error": "timeout" }),
        };
        // JSON serialization escapes interior NULs, so a CString is always representable.
        if let Ok(encoded) = CString::new(response.to_string()) {
            callback(context as *mut c_void, encoded.into_raw());
        }
    });
    0
}

/// Releases exactly one response returned by `sonora_mobile_request`.
///
/// # Safety
/// The pointer must be null or an unfreed string returned to this library's callback.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn sonora_mobile_string_free(json: *mut c_char) {
    if !json.is_null() {
        drop(unsafe { CString::from_raw(json) });
    }
}

async fn execute(request: Request) -> Result<Value> {
    match request {
        Request::Configure { cache_dir } => {
            let dir = PathBuf::from(cache_dir.trim());
            if dir.as_os_str().is_empty() {
                bail!("empty cache directory");
            }
            std::fs::create_dir_all(&dir).context("cannot create provider cache dir")?;
            let mut state = session()
                .write()
                .map_err(|_| anyhow::anyhow!("session lock poisoned"))?;
            state.cache_dir = Some(dir.clone());
            if !state.api.is_cookie_auth() {
                state.api = build_anonymous(Some(&dir));
            }
            return Ok(json!({ "configured": true }));
        }
        Request::PoTokenWanted {} => {
            let wanted = potokens().lock().ok().and_then(|mut s| s.wanted.take());
            return Ok(json!({ "binding": wanted }));
        }
        Request::PoTokenGive { binding, token } => {
            if let Ok(mut store) = potokens().lock() {
                store
                    .minted
                    .retain(|_, entry| entry.at.elapsed() < POTOKEN_KEEP);
                store.minted.insert(
                    binding,
                    MintedToken {
                        token,
                        at: Instant::now(),
                    },
                );
                store.failures = 0;
                store.failed_at = None;
                store.warm = true;
            }
            return Ok(json!({ "stored": true }));
        }
        Request::PoTokenFailed {} => {
            if let Ok(mut store) = potokens().lock() {
                store.failures = store.failures.saturating_add(1);
                store.failed_at = Some(Instant::now());
                store.warm = false;
            }
            return Ok(json!({ "recorded": true }));
        }
        Request::ListAccounts { cookies } => return list_accounts(&cookies).await,
        Request::Authenticate {
            cookies,
            authuser,
            page_id,
        } => {
            return authenticate(&cookies, authuser.unwrap_or(0), page_id.as_deref()).await;
        }
        Request::SignOut {} => {
            if let Ok(mut store) = potokens().lock() {
                store.clear();
            }
            let mut state = session()
                .write()
                .map_err(|_| anyhow::anyhow!("session lock poisoned"))?;
            state.generation += 1;
            if let Some(dir) = &state.cache_dir {
                let _ = std::fs::remove_file(dir.join("cookies.json"));
                let _ = std::fs::remove_file(dir.join("resolved.json"));
            }
            state.api = build_anonymous(state.cache_dir.as_ref());
            return Ok(json!({ "signed_out": true }));
        }
        _ => {}
    }

    let api = session()
        .read()
        .map_err(|_| anyhow::anyhow!("session lock poisoned"))?
        .api
        .clone();

    match request {
        Request::EqualizerConfigure {
            revision,
            enabled,
            preset,
            auto_preamp,
            preamp_db,
            bass_db,
            treble_db,
            normalization_db,
            profile,
            filters,
        } => audio_effects::configure(audio_effects::Configuration {
            revision,
            enabled,
            preset,
            auto_preamp,
            preamp_db,
            bass_db,
            treble_db,
            normalization_db,
            profile,
            filters,
        }),
        Request::EqualizerDescribe {
            preset,
            profile,
            filters,
            auto_preamp,
            preamp_db,
        } => audio_effects::describe(&preset, profile.as_deref(), filters, auto_preamp, preamp_db),
        Request::RotateCookies {} => {
            if api.is_cookie_auth() {
                let _ = api.rotate_cookies().await;
            }
            Ok(json!({ "rotated": api.is_cookie_auth() }))
        }
        Request::Search { query } => {
            let query = validate_query(&query)?;
            let tracks = api
                .search_songs(query)
                .await
                .context("cannot search youtube")?;
            Ok(Value::Array(
                tracks.into_iter().filter_map(serialize_track).collect(),
            ))
        }
        Request::SearchCatalog { query } => {
            let query = validate_query(&query)?;
            let (songs, albums, playlists, artists) = tokio::join!(
                api.search_songs(query),
                api.search_albums(query),
                api.search_playlists(query),
                search_artists(&api, query),
            );
            Ok(json!({
                "songs": songs?.into_iter().filter_map(serialize_track).collect::<Vec<_>>(),
                "albums": albums.unwrap_or_default().into_iter().map(serialize_album).collect::<Vec<_>>(),
                "playlists": playlists.unwrap_or_default().into_iter().map(serialize_playlist).collect::<Vec<_>>(),
                "artists": artists.unwrap_or_default(),
            }))
        }
        Request::SearchSuggestions { input } => {
            let input = input.trim();
            if input.is_empty() || input.len() > MAX_QUERY {
                return Ok(Value::Array(Vec::new()));
            }
            let suggestions = api.search_suggestions(input).await.unwrap_or_default();
            Ok(json!(suggestions))
        }
        Request::Resolve { video_id, quality } => {
            validate_video_id(&video_id)?;
            let ceiling = match quality.as_deref() {
                Some("low") => Some(64_000),
                Some("normal") => Some(160_000),
                _ => None,
            };
            // Match desktop playback: validate by opening the first real body range. A separate
            // one-byte URL probe can be rejected even when the normal stream request is served.
            let (format, body) = api
                .open_audio_within(&video_id, ceiling)
                .await
                .context("cannot open youtube audio")?;
            drop(body);
            if !format.mime.starts_with("audio/mp4") {
                bail!("the provider did not offer a native audio format");
            }
            Ok(json!({
                "url": format.url,
                "mime": format.mime,
                "codec": format.codec,
                "bitrate_kbps": format.bitrate / 1000,
                "loudness_db": format.loudness_db,
                "user_agent": format.user_agent,
                "duration_seconds": format.duration.map(|duration| duration.as_secs()),
                "content_length": format.content_length,
            }))
        }
        Request::Lyrics {
            video_id,
            title,
            artist,
            album,
            duration_seconds,
            sources,
            local_text,
        } => {
            if let Some(id) = video_id.as_deref() {
                validate_video_id(id)?;
            }
            for value in [title.as_deref(), artist.as_deref(), album.as_deref()]
                .into_iter()
                .flatten()
            {
                if value.len() > MAX_QUERY {
                    bail!("lyrics metadata is too long");
                }
            }
            lyric_bridge::resolve(lyric_bridge::Lookup {
                video_id,
                title,
                artist,
                album,
                duration_seconds,
                sources,
                local_text,
            })
            .await
        }
        Request::ParseLyrics { text, format } => lyric_bridge::parse(&text, format.as_deref()),
        Request::Home {} => fetch_home(&api).await,
        Request::Genre { params } => fetch_genre(&api, &params).await,
        Request::Album { browse_id } => fetch_album(&api, &browse_id).await,
        Request::Artist { browse_id } => fetch_artist(&api, &browse_id).await,
        Request::Playlist { playlist_id } => fetch_playlist(&api, &playlist_id).await,
        Request::Radio { video_id } => {
            validate_video_id(&video_id)?;
            fetch_radio(&api, &video_id).await
        }
        Request::LibraryContent {} => fetch_library_content(&api).await,
        Request::RateTrack { video_id, liked } => {
            validate_video_id(&video_id)?;
            api.rate_track(&video_id, liked).await?;
            Ok(json!({ "liked": liked }))
        }
        Request::RatePlaylist { playlist_id, saved } => {
            api.rate_playlist(&playlist_id, saved).await?;
            Ok(json!({ "saved": saved }))
        }
        Request::SetArtistSaved { artist_id, saved } => {
            set_artist_saved(&api, &artist_id, saved).await?;
            Ok(json!({ "saved": saved }))
        }
        Request::CreatePlaylist { title } => {
            let title = validate_query(&title)?;
            let id = api.create_playlist(title).await?;
            Ok(json!({ "playlist_id": id }))
        }
        Request::RenamePlaylist { playlist_id, title } => {
            let title = validate_query(&title)?;
            api.rename_playlist(&playlist_id, title).await?;
            Ok(json!({ "renamed": true }))
        }
        Request::DeletePlaylist { playlist_id } => {
            api.delete_playlist(&playlist_id).await?;
            Ok(json!({ "deleted": true }))
        }
        Request::SetPlaylistPrivacy {
            playlist_id,
            public,
        } => {
            api.set_playlist_privacy(&playlist_id, public).await?;
            Ok(json!({ "public": public }))
        }
        Request::AddPlaylistTrack {
            playlist_id,
            video_id,
        } => {
            validate_video_id(&video_id)?;
            api.add_playlist_track(&playlist_id, &video_id).await?;
            Ok(json!({ "added": true }))
        }
        Request::RemovePlaylistTrack {
            playlist_id,
            video_id,
            set_video_id,
        } => {
            validate_video_id(&video_id)?;
            api.remove_playlist_track(&playlist_id, &video_id, &set_video_id)
                .await?;
            Ok(json!({ "removed": true }))
        }
        Request::Configure { .. }
        | Request::PoTokenWanted {}
        | Request::PoTokenGive { .. }
        | Request::PoTokenFailed {}
        | Request::ListAccounts { .. }
        | Request::Authenticate { .. }
        | Request::SignOut {} => unreachable!("handled before session read"),
    }
}

fn validate_query(query: &str) -> Result<&str> {
    let trimmed = query.trim();
    if trimmed.is_empty() || trimmed.len() > MAX_QUERY {
        bail!("query must contain 1 to 512 bytes");
    }
    Ok(trimmed)
}

fn normalize_cookies(cookies: &str) -> Result<String> {
    if cookies.len() > 32_768 || cookies.contains(['\r', '\n', '\0']) {
        bail!("invalid cookie header");
    }
    let pairs: Vec<_> = cookies
        .split(';')
        .map(str::trim)
        .filter(|pair| !pair.is_empty())
        .collect();
    if !pairs.iter().all(|pair| {
        pair.split_once('=').is_some_and(|(name, value)| {
            !name.is_empty()
                && name
                    .bytes()
                    .all(|byte| byte.is_ascii_alphanumeric() || byte == b'_' || byte == b'-')
                && !value.is_empty()
                && !value.chars().any(char::is_whitespace)
        })
    }) || !pairs.iter().any(|pair| {
        pair.split_once('=')
            .is_some_and(|(name, _)| matches!(name, "SAPISID" | "__Secure-3PAPISID"))
    }) {
        bail!("cookies carry no signed-in account");
    }
    Ok(pairs.join("; "))
}

async fn list_accounts(cookies: &str) -> Result<Value> {
    let normalized = normalize_cookies(cookies)?;
    let mut accounts = Vec::new();
    let mut seen = HashSet::new();
    for index in 0..ACCOUNT_LIMIT {
        let Ok(identities) = YtMusic::with_cookies(&normalized)
            .as_user(index)
            .identities()
            .await
        else {
            break;
        };
        let before = accounts.len();
        for identity in identities {
            if seen.insert(identity.key()) {
                let id = match &identity.page_id {
                    Some(page) => format!("{index}:{page}"),
                    None => index.to_string(),
                };
                let avatar = ytmusic::best_thumbnail(&identity.profile.thumbnails)
                    .map(|thumb| thumb.url.clone());
                accounts.push(json!({
                    "id": id,
                    "authuser": index,
                    "page_id": identity.page_id,
                    "name": identity.profile.name,
                    "email": identity.profile.email,
                    "avatar_url": avatar,
                }));
            }
        }
        if accounts.len() == before {
            break;
        }
    }
    if accounts.is_empty() {
        bail!("cookies were not accepted");
    }
    Ok(Value::Array(accounts))
}

/// Validates the desktop cookie-header format and checks the account before publishing a session.
/// Credentials are supplied from the host Keychain and are never saved or logged by the core.
async fn authenticate(cookies: &str, authuser: usize, page_id: Option<&str>) -> Result<Value> {
    let normalized = normalize_cookies(cookies)?;
    let (generation, cache_dir) = {
        let mut state = session()
            .write()
            .map_err(|_| anyhow::anyhow!("session lock poisoned"))?;
        state.generation += 1;
        (state.generation, state.cache_dir.clone())
    };
    let api = build_authenticated(&normalized, authuser, page_id, cache_dir.as_ref());
    let fresh = cache_dir
        .as_ref()
        .and_then(|dir| std::fs::metadata(dir.join("cookies.json")).ok())
        .and_then(|meta| meta.modified().ok())
        .is_some_and(|at| at.elapsed().is_ok_and(|elapsed| elapsed < ROTATION));
    if !fresh {
        let _ = api.rotate_cookies().await;
    }
    let profile = api
        .profile()
        .await
        .context("cannot verify youtube account")?;
    let avatar = ytmusic::best_thumbnail(&profile.thumbnails).map(|thumb| thumb.url.clone());
    let mut state = session()
        .write()
        .map_err(|_| anyhow::anyhow!("session lock poisoned"))?;
    if state.generation != generation {
        bail!("superseded account request");
    }
    keep_fresh(Arc::downgrade(&api), SystemTime::now());
    state.api = api;
    Ok(json!({
        "name": profile.name,
        "email": profile.email,
        "avatar_url": avatar,
        "authuser": authuser,
        "page_id": page_id,
    }))
}

fn keep_fresh(api: Weak<YtMusic>, since: SystemTime) {
    tokio::spawn(async move {
        let mut rotated = since;
        loop {
            tokio::time::sleep(ROTATION_CHECK).await;
            let Some(api) = api.upgrade() else {
                return;
            };
            if rotated.elapsed().is_ok_and(|elapsed| elapsed < ROTATION) {
                continue;
            }
            let _ = api.rotate_cookies().await;
            rotated = SystemTime::now();
        }
    });
}

fn validate_video_id(id: &str) -> Result<()> {
    if id.len() != 11
        || !id
            .bytes()
            .all(|byte| byte.is_ascii_alphanumeric() || byte == b'_' || byte == b'-')
    {
        bail!("invalid youtube video id");
    }
    Ok(())
}

fn serialize_track(track: ytmusic::Track) -> Option<Value> {
    let id = track.video_id?;
    let thumbnail = ytmusic::best_thumbnail(&track.thumbnails).map(|image| image.url.clone());
    let artist = track
        .artists
        .iter()
        .map(|artist| artist.name.as_str())
        .collect::<Vec<_>>()
        .join(", ");
    let artist_id = track.artists.iter().find_map(|artist| artist.id.clone());
    let album_title = track.album.as_ref().map(|album| album.name.clone());
    let album_id = track.album.and_then(|album| album.id);
    Some(json!({
        "id": id,
        "title": track.title,
        "artist": artist,
        "artist_id": artist_id,
        "album_title": album_title,
        "album_id": album_id,
        "artwork_url": thumbnail,
        "duration_seconds": track.duration.map(|duration| duration.as_secs()),
        "available": track.available,
        "explicit": track.explicit,
        "liked": track.liked,
        "set_video_id": track.set_video_id,
    }))
}

fn serialize_album(album: ytmusic::Album) -> Value {
    let artist = album
        .artists
        .iter()
        .map(|artist| artist.name.as_str())
        .collect::<Vec<_>>()
        .join(", ");
    let artist_id = album.artists.iter().find_map(|artist| artist.id.clone());
    let artwork = ytmusic::best_thumbnail(&album.thumbnails).map(|image| image.url.clone());
    let kind = match album.kind {
        ytmusic::AlbumKind::Album => "Album",
        ytmusic::AlbumKind::Single => "Single",
        ytmusic::AlbumKind::Ep => "EP",
        ytmusic::AlbumKind::Compilation => "Compilation",
    };
    json!({
        "id": album.browse_id,
        "playlist_id": album.playlist_id,
        "title": album.title,
        "artist": artist,
        "artist_id": artist_id,
        "year": album.year,
        "kind": kind,
        "track_count": album.track_count,
        "artwork_url": artwork,
    })
}

fn serialize_playlist(playlist: ytmusic::Playlist) -> Value {
    let artwork = ytmusic::best_thumbnail(&playlist.thumbnails).map(|image| image.url.clone());
    json!({
        "id": playlist.id,
        "title": playlist.title,
        "author": playlist.author.unwrap_or_default(),
        "editable": playlist.owned,
        "owned": playlist.owned,
        "public": playlist.public.unwrap_or(false),
        "track_count": playlist.track_count,
        "artwork_url": artwork,
    })
}

async fn search_artists(api: &YtMusic, query: &str) -> Result<Vec<Value>> {
    let response = api
        .execute_with(
            "search",
            Client::Music,
            json!({ "query": query, "params": ARTISTS_SEARCH_PARAMS }),
            true,
        )
        .await?;
    let mut artists = Vec::new();
    for shelf in find_renderers(&response, "musicShelfRenderer") {
        for item in shelf.items(&["contents"]) {
            let Some(renderer) = item.at(&["musicResponsiveListItemRenderer"]) else {
                continue;
            };
            let Some(id) = renderer.str_at(&["navigationEndpoint", "browseEndpoint", "browseId"])
            else {
                continue;
            };
            if !id.starts_with("UC") {
                continue;
            }
            let Some(name) = renderer.run_text(&[
                "flexColumns",
                "0",
                "musicResponsiveListItemFlexColumnRenderer",
                "text",
            ]) else {
                continue;
            };
            let subtitle = renderer.run_text(&[
                "flexColumns",
                "1",
                "musicResponsiveListItemFlexColumnRenderer",
                "text",
            ]);
            let artwork = ytmusic::best_thumbnail(&ytmusic::parse::thumbnails(renderer))
                .map(|thumb| thumb.url.clone());
            artists.push(json!({
                "id": id,
                "name": name,
                "subtitle": subtitle,
                "artwork_url": artwork,
            }));
        }
    }
    Ok(artists)
}

async fn fetch_album(api: &Arc<YtMusic>, browse_id: &str) -> Result<Value> {
    let mut detail = api.album(browse_id).await?;
    detail.tracks = api.swap_playable(detail.tracks).await;
    let album_meta = serialize_album(detail.album);
    let tracks: Vec<Value> = detail
        .tracks
        .into_iter()
        .filter_map(serialize_track)
        .collect();
    let mut response = album_meta;
    response["description"] = json!(detail.description);
    response["tracks"] = json!(tracks);
    Ok(response)
}

async fn fetch_artist(api: &Arc<YtMusic>, browse_id: &str) -> Result<Value> {
    let mut artist = api.artist(browse_id).await?;
    artist.top_tracks = api.swap_playable(artist.top_tracks).await;
    let artwork = ytmusic::best_thumbnail(&artist.thumbnails).map(|thumb| thumb.url.clone());
    let top_tracks: Vec<Value> = artist
        .top_tracks
        .into_iter()
        .filter_map(serialize_track)
        .collect();
    let albums: Vec<Value> = artist.albums.into_iter().map(serialize_album).collect();
    let singles: Vec<Value> = artist.singles.into_iter().map(serialize_album).collect();
    Ok(json!({
        "id": artist.browse_id,
        "name": artist.name,
        "description": artist.description,
        "subscribers": artist.subscribers,
        "artwork_url": artwork,
        "top_songs": top_tracks,
        "albums": albums,
        "singles": singles,
        "related": [],
    }))
}

async fn fetch_playlist(api: &Arc<YtMusic>, playlist_id: &str) -> Result<Value> {
    let mut detail = api.playlist(playlist_id).await?;
    detail.tracks = api.swap_playable(detail.tracks).await;
    let playlist_meta = serialize_playlist(detail.playlist);
    let tracks: Vec<Value> = detail
        .tracks
        .into_iter()
        .filter_map(serialize_track)
        .collect();
    let mut response = playlist_meta;
    response["public"] = json!(detail.public);
    response["privacy"] = json!(if detail.public { "PUBLIC" } else { "PRIVATE" });
    response["tracks"] = json!(tracks);
    Ok(response)
}

async fn fetch_radio(api: &YtMusic, video_id: &str) -> Result<Value> {
    let response = api
        .execute(
            "next",
            Client::Music,
            json!({
                "videoId": video_id,
                "playlistId": format!("RDAMVM{video_id}"),
                "enablePersistentPlaylistPanel": true,
                "tunerSettingValue": "AUTOMIX_SETTING_NORMAL",
            }),
        )
        .await?;
    let tracks: Vec<Value> = find_renderers(&response, "playlistPanelRenderer")
        .into_iter()
        .next()
        .map(|panel| {
            panel
                .items(&["contents"])
                .iter()
                .filter_map(ytmusic::parse::panel_track)
                .filter_map(serialize_track)
                .collect()
        })
        .unwrap_or_default();
    Ok(Value::Array(tracks))
}

async fn fetch_library_content(api: &Arc<YtMusic>) -> Result<Value> {
    if !api.is_cookie_auth() {
        return Ok(json!({
            "liked_songs": [],
            "albums": [],
            "playlists": [],
            "artists": [],
        }));
    }
    let (songs, albums, playlists, artists) = tokio::join!(
        api.liked_songs_resolved(),
        api.library_albums(),
        api.library_playlists(),
        fetch_saved_artists(api),
    );
    Ok(json!({
        "liked_songs": songs?.into_iter().filter_map(serialize_track).collect::<Vec<_>>(),
        "albums": albums.unwrap_or_default().into_iter().map(serialize_album).collect::<Vec<_>>(),
        "playlists": playlists.unwrap_or_default().into_iter().filter(|p| p.id != "SE").map(serialize_playlist).collect::<Vec<_>>(),
        "artists": artists.unwrap_or_default(),
    }))
}

async fn fetch_saved_artists(api: &YtMusic) -> Result<Vec<Value>> {
    let response = api
        .execute(
            "browse",
            Client::Music,
            json!({ "browseId": SUBSCRIPTIONS_BROWSE_ID }),
        )
        .await?;
    let renderers = ["musicTwoRowItemRenderer", "musicResponsiveListItemRenderer"]
        .into_iter()
        .flat_map(|kind| find_renderers(&response, kind));
    let mut artists = Vec::new();
    for renderer in renderers {
        let Some(id) = renderer
            .str_at(&["navigationEndpoint", "browseEndpoint", "browseId"])
            .or_else(|| {
                renderer.str_at(&[
                    "flexColumns",
                    "0",
                    "musicResponsiveListItemFlexColumnRenderer",
                    "text",
                    "runs",
                    "0",
                    "navigationEndpoint",
                    "browseEndpoint",
                    "browseId",
                ])
            })
        else {
            continue;
        };
        if !id.starts_with("UC") {
            continue;
        }
        let Some(name) = renderer.run_text(&["title"]).or_else(|| {
            renderer.run_text(&[
                "flexColumns",
                "0",
                "musicResponsiveListItemFlexColumnRenderer",
                "text",
            ])
        }) else {
            continue;
        };
        let artwork = ytmusic::best_thumbnail(&ytmusic::parse::thumbnails(renderer))
            .map(|thumb| thumb.url.clone());
        artists.push(json!({
            "id": id,
            "name": name,
            "artwork_url": artwork,
        }));
    }
    Ok(artists)
}

async fn set_artist_saved(api: &YtMusic, artist_id: &str, saved: bool) -> Result<()> {
    let artist = api
        .execute("browse", Client::Music, json!({ "browseId": artist_id }))
        .await?;
    let channel_id = ytmusic::parse::find_renderer(&artist, "subscribeButtonRenderer")
        .and_then(|button| button.get("channelId"))
        .and_then(Value::as_str)
        .context("artist response has no subscription channel")?;
    let endpoint = match saved {
        true => "subscription/subscribe",
        false => "subscription/unsubscribe",
    };
    api.execute(
        endpoint,
        Client::Music,
        json!({ "channelIds": [channel_id] }),
    )
    .await?;
    Ok(())
}

async fn fetch_home(api: &YtMusic) -> Result<Value> {
    let (home_res, genres_res) = tokio::join!(
        api.execute(
            "browse",
            Client::Music,
            json!({ "browseId": HOME_BROWSE_ID })
        ),
        api.execute(
            "browse",
            Client::Music,
            json!({ "browseId": GENRES_BROWSE_ID })
        ),
    );
    let mut answer = home_res?;
    let mut sections = Vec::new();
    collect_home_sections(&answer, &mut sections);
    for _ in 0..2 {
        let Some(token) = find_renderers(&answer, "nextContinuationData")
            .into_iter()
            .find_map(|next| next.str_at(&["continuation"]))
            .map(str::to_owned)
        else {
            break;
        };
        let Ok(next) = api
            .execute("browse", Client::Music, json!({ "continuation": token }))
            .await
        else {
            break;
        };
        answer = next;
        collect_home_sections(&answer, &mut sections);
    }
    let genres: Vec<Value> = genres_res
        .ok()
        .map(|res| {
            find_renderers(&res, "gridRenderer")
                .into_iter()
                .flat_map(|grid| grid.items(&["items"]))
                .filter_map(|item| {
                    let button = item.get("musicNavigationButtonRenderer")?;
                    let params = button.str_at(&["clickCommand", "browseEndpoint", "params"])?;
                    let title = button.run_text(&["buttonText"])?;
                    Some(json!({ "params": params, "title": title, "color": button.get("solidColor").and_then(Value::as_u64).unwrap_or(0) }))
                })
                .collect()
        })
        .unwrap_or_default();
    Ok(json!({
        "sections": sections,
        "genres": genres,
    }))
}

async fn fetch_genre(api: &YtMusic, params: &str) -> Result<Value> {
    let answer = api
        .execute(
            "browse",
            Client::Music,
            json!({ "browseId": GENRE_CATEGORY_ID, "params": params }),
        )
        .await?;
    let mut sections = Vec::new();
    collect_home_sections(&answer, &mut sections);
    Ok(Value::Array(sections))
}

fn collect_home_sections(answer: &Value, sections: &mut Vec<Value>) {
    for shelf in find_renderers(answer, "musicCarouselShelfRenderer") {
        let Some(title) =
            shelf.run_text(&["header", "musicCarouselShelfBasicHeaderRenderer", "title"])
        else {
            continue;
        };
        if title == "Music videos for you" {
            continue;
        }
        let items: Vec<Value> = shelf
            .items(&["contents"])
            .iter()
            .filter_map(parse_shelf_item)
            .collect();
        if !items.is_empty()
            && !sections
                .iter()
                .any(|existing| existing.get("title").and_then(Value::as_str) == Some(&title))
        {
            sections.push(json!({
                "title": title,
                "items": items,
            }));
        }
    }
}

fn parse_shelf_item(node: &Value) -> Option<Value> {
    if let Some(playlist) = ytmusic::parse::two_row_playlist(node) {
        return Some(shelf_item("playlist", serialize_playlist(playlist)));
    }
    if let Some(album) = ytmusic::parse::two_row_album(node) {
        return Some(shelf_item("album", serialize_album(album)));
    }
    if let Some(renderer) = node.at(&["musicTwoRowItemRenderer"]) {
        let page_type = renderer.str_at(&[
            "navigationEndpoint",
            "browseEndpoint",
            "browseEndpointContextSupportedConfigs",
            "browseEndpointContextMusicConfig",
            "pageType",
        ]);
        if page_type == Some("MUSIC_PAGE_TYPE_ARTIST")
            && let Some(id) = renderer.str_at(&["navigationEndpoint", "browseEndpoint", "browseId"])
            && id.starts_with("UC")
            && let Some(name) = renderer.run_text(&["title"])
        {
            let artwork = ytmusic::best_thumbnail(&ytmusic::parse::thumbnails(renderer))
                .map(|thumb| thumb.url.clone());
            return Some(shelf_item(
                "artist",
                json!({"id": id, "name": name, "artwork_url": artwork}),
            ));
        }
    }
    if let Some(track) = ytmusic::parse::list_item_track(node).or_else(|| two_row_track(node))
        && let Some(serialized) = serialize_track(track)
    {
        return Some(shelf_item("song", serialized));
    }
    None
}

/// Adds the common display fields while preserving typed metadata in the native boundary.
fn shelf_item(kind: &str, data: Value) -> Value {
    let mut item = json!({
        "kind": if kind == "song" { "track" } else { kind },
        "id": data["id"],
        "title": data.get("title").or_else(|| data.get("name")).cloned().unwrap_or(json!("")),
        "subtitle": data.get("artist").or_else(|| data.get("author")).cloned().unwrap_or(json!("")),
        "artwork_url": data["artwork_url"],
    });
    item[kind] = data;
    item
}

fn two_row_track(item: &Value) -> Option<ytmusic::Track> {
    let renderer = item.at(&["musicTwoRowItemRenderer"])?;
    let endpoint = renderer.at(&[
        "thumbnailOverlay",
        "musicItemThumbnailOverlayRenderer",
        "content",
        "musicPlayButtonRenderer",
        "playNavigationEndpoint",
        "watchEndpoint",
    ])?;
    let video_id = endpoint.str_at(&["videoId"])?.to_owned();
    let title = renderer.run_text(&["title"])?;
    let mut artists = ytmusic::parse::artist_runs(renderer.runs(&["subtitle"]));
    if artists.is_empty() {
        artists = renderer
            .runs(&["subtitle"])
            .iter()
            .filter_map(|run| run.str_at(&["text"]))
            .take_while(|text| *text != " • ")
            .filter(|text| {
                !matches!(*text, ", " | " & " | "Song" | "Video") && !text.trim().is_empty()
            })
            .map(|name| ytmusic::ArtistRef {
                name: name.to_owned(),
                id: None,
            })
            .collect();
    }
    Some(ytmusic::Track {
        video_id: Some(video_id),
        title,
        artists,
        album: None,
        duration: None,
        thumbnails: ytmusic::parse::thumbnails(renderer),
        explicit: ytmusic::parse::explicit(renderer),
        available: true,
        kind: ytmusic::TrackKind::Song,
        set_video_id: None,
        liked: None,
        views: None,
    })
}
