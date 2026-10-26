use anyhow::Result;
use async_trait::async_trait;

use crate::{LyricsHit, LyricsQuery};

/// A source of candidate sheets; callers rank recordings and timing quality after collection.
#[async_trait]
pub trait LyricsProvider: Send + Sync {
    fn name(&self) -> &'static str;
    async fn search(&self, query: &LyricsQuery) -> Result<Vec<LyricsHit>>;
}
