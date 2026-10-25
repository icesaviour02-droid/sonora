//! A narrow native boundary around the same YouTube client used by desktop Sonora.
//! Network operations stay on Tokio, with no GPUI, desktop audio output or UI dependencies.

use std::ffi::{CStr, CString, c_char, c_void};
use std::sync::{Arc, OnceLock};
use std::time::Duration;

use anyhow::{Context as _, Result, bail};
use serde::Deserialize;
use serde_json::{Value, json};
use tokio::runtime::{Builder, Runtime};
use ytmusic::YtMusic;

const DEADLINE: Duration = Duration::from_secs(30);
const MAX_QUERY: usize = 512;

type Callback = extern "C" fn(*mut c_void, *mut c_char);

static RUNTIME: OnceLock<Result<Runtime, String>> = OnceLock::new();
static CLIENT: OnceLock<Arc<YtMusic>> = OnceLock::new();

#[derive(Deserialize)]
#[serde(tag = "operation", rename_all = "snake_case", deny_unknown_fields)]
enum Request {
    Search { query: String },
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
        let outcome = tokio::time::timeout(DEADLINE, execute(request)).await;
        let response = match outcome {
            Ok(Ok(data)) => json!({ "ok": true, "data": data }),
            Ok(Err(_)) => json!({ "ok": false, "error": "provider_unavailable" }),
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
    let api = CLIENT.get_or_init(|| Arc::new(YtMusic::anonymous()));
    match request {
        Request::Search { query } => {
            let query = query.trim();
            if query.is_empty() || query.len() > MAX_QUERY {
                bail!("query must contain 1 to 512 bytes");
            }
            let tracks = api
                .search_songs(query)
                .await
                .context("cannot search youtube")?;
            Ok(Value::Array(tracks.into_iter().filter_map(|track| {
                let id = track.video_id?;
                let thumbnail = ytmusic::best_thumbnail(&track.thumbnails).map(|image| image.url.clone());
                Some(json!({
                    "id": id,
                    "title": track.title,
                    "artist": track.artists.iter().map(|artist| artist.name.as_str()).collect::<Vec<_>>().join(", "),
                    "artwork_url": thumbnail,
                    "duration_seconds": track.duration.map(|duration| duration.as_secs()),
                    "available": track.available,
                }))
            }).collect()))
        }
    }
}
