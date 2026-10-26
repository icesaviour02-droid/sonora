//! Cancellation releases read/network futures while preserving one owned reply per accepted call.

use std::collections::HashMap;
use std::sync::{Mutex, OnceLock};

use tokio::sync::oneshot;

const MAX_ACTIVE: usize = 256;
type Requests = HashMap<String, Option<oneshot::Sender<()>>>;
static REQUESTS: OnceLock<Mutex<Requests>> = OnceLock::new();

fn requests() -> &'static Mutex<Requests> {
    REQUESTS.get_or_init(|| Mutex::new(HashMap::new()))
}

/// IDs are unique until the reply arrives. The cap bounds memory if a caller stops consuming replies.
pub(crate) fn register(id: &str) -> Option<oneshot::Receiver<()>> {
    if id.is_empty()
        || id.len() > 128
        || !id
            .bytes()
            .all(|b| b.is_ascii_alphanumeric() || b == b'-' || b == b'_')
    {
        return None;
    }
    let mut requests = requests().lock().ok()?;
    if requests.len() >= MAX_ACTIVE || requests.contains_key(id) {
        return None;
    }
    let (sender, receiver) = oneshot::channel();
    requests.insert(id.to_owned(), Some(sender));
    Some(receiver)
}

pub(crate) fn cancel(id: &str) -> bool {
    let sender = requests()
        .lock()
        .ok()
        .and_then(|mut requests| requests.get_mut(id).and_then(Option::take));
    sender.is_some_and(|sender| sender.send(()).is_ok())
}

pub(crate) fn finish(id: &str) {
    if let Ok(mut requests) = requests().lock() {
        requests.remove(id);
    }
}

pub(crate) fn pending() -> u32 {
    requests()
        .lock()
        .map(|requests| requests.len() as u32)
        .unwrap_or_default()
}
