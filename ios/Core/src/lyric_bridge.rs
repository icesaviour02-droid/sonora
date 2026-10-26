//! The desktop's sources, recording matching, ranking, timing and romanization for native UI.

use std::sync::{Arc, OnceLock};
use std::time::Duration;

use anyhow::{Result, bail};
use serde_json::{Value, json};
use tokio::task::JoinSet;

use crate::{
    Lyrics, LyricsHit, LyricsLane, LyricsLine, LyricsProvider, LyricsQuery, LyricsWord,
    RomanizedText, TrackKey,
};

const MAX_TEXT: usize = 1_024 * 1_024;
const SOURCE_PATIENCE: Duration = Duration::from_secs(8);
const DEFAULT_SOURCES: &[&str] = &[
    "Local",
    "YouTube Music",
    "Apple Music",
    "Musixmatch",
    "LrcLib",
];
const ALL_SOURCES: &[&str] = &[
    "Local",
    "YouTube Music",
    "Apple Music",
    "Musixmatch",
    "LrcLib",
    "Kugou",
    "NetEase",
];

struct Providers {
    youtube: Arc<crate::desktop_youtube::lyrics::YouTubeLyrics>,
    sources: Vec<Arc<dyn LyricsProvider>>,
}

fn providers() -> &'static Providers {
    static PROVIDERS: OnceLock<Providers> = OnceLock::new();
    PROVIDERS.get_or_init(|| {
        let youtube = Arc::new(crate::desktop_youtube::lyrics::YouTubeLyrics::new());
        Providers {
            youtube: youtube.clone(),
            sources: vec![
                youtube,
                Arc::new(crate::binimum::Binimum::new()),
                Arc::new(crate::musixmatch::Musixmatch::new()),
                Arc::new(crate::lrclib::LrcLib::new()),
                Arc::new(crate::kugou::Kugou::new()),
                Arc::new(crate::netease::NetEase::new()),
            ],
        }
    })
}

pub(crate) struct Lookup {
    pub video_id: Option<String>,
    pub title: Option<String>,
    pub artist: Option<String>,
    pub album: Option<String>,
    pub duration_seconds: Option<f64>,
    pub sources: Option<Vec<String>>,
    pub local_text: Option<String>,
}

/// Searches enabled sources concurrently on Tokio and applies the desktop's quality-first ranking.
pub(crate) async fn resolve(lookup: Lookup) -> Result<Value> {
    let priority = lookup
        .sources
        .unwrap_or_else(|| DEFAULT_SOURCES.iter().map(|s| (*s).to_owned()).collect());
    if priority.len() > ALL_SOURCES.len()
        || priority.iter().any(|s| !ALL_SOURCES.contains(&s.as_str()))
    {
        bail!("unknown lyrics source");
    }
    if priority.is_empty() {
        return Ok(empty(false));
    }
    let query = LyricsQuery {
        title: lookup.title.unwrap_or_default(),
        artist: lookup.artist.unwrap_or_default(),
        album: lookup.album,
        duration: lookup
            .duration_seconds
            .and_then(|s| Duration::try_from_secs_f64(s).ok())
            .unwrap_or_default(),
        track: lookup.video_id.map(|id| TrackKey {
            provider: "youtube",
            id,
        }),
    };
    if query.title.trim().is_empty() || query.artist.trim().is_empty() {
        if priority.iter().any(|s| s == "YouTube Music")
            && let Some(id) = query.id_for("youtube")
            && let Ok(Ok(Some(sheet))) =
                tokio::time::timeout(SOURCE_PATIENCE, providers().youtube.sheet(id)).await
        {
            return Ok(render(&sheet, "YouTube Music", &[], false));
        }
        return Ok(empty(false));
    }
    let mut hits = Vec::new();
    let mut status = Vec::new();
    if priority.iter().any(|s| s == "Local")
        && let Some(text) = lookup
            .local_text
            .as_deref()
            .filter(|s| !s.trim().is_empty())
    {
        if let Ok((sheet, writers)) = parse_sheet(text, None) {
            hits.push(LyricsHit {
                source: "Local",
                trust: 100,
                lyrics: sheet,
                instrumental: false,
                title: query.title.clone(),
                artist: query.artist.clone(),
                album: query.album.clone(),
                duration: (!query.duration.is_zero()).then_some(query.duration),
                writers,
            });
        } else {
            status.push(json!({ "source": "Local", "status": "invalid" }));
        }
    }
    let mut tasks = JoinSet::new();
    for source in &providers().sources {
        if !priority.iter().any(|name| name == source.name()) {
            continue;
        }
        let source = source.clone();
        let query = query.clone();
        tasks.spawn(async move {
            let result = tokio::time::timeout(SOURCE_PATIENCE, source.search(&query)).await;
            (source.name(), result)
        });
    }
    while let Some(result) = tasks.join_next().await {
        let Ok((source, result)) = result else {
            continue;
        };
        match result {
            Ok(Ok(found)) => {
                status.push(
                    json!({ "source": source, "status": "complete", "matches": found.len() }),
                );
                hits.extend(found);
            }
            Ok(Err(_)) => status.push(json!({ "source": source, "status": "unavailable" })),
            Err(_) => status.push(json!({ "source": source, "status": "timeout" })),
        }
    }
    let instrumental = crate::lyrics::instrumental(&query, &hits);
    crate::lyrics::reshape(&mut hits);
    let ranked = crate::lyrics::rank_with_priority(&query, hits, &priority);
    let choices: Vec<Value> = ranked
        .iter()
        .enumerate()
        .map(|(index, hit)| {
            let mut value = render(&hit.lyrics, hit.source, &hit.writers, hit.instrumental);
            value["id"] = json!(index);
            value
        })
        .collect();
    let mut response = choices
        .first()
        .cloned()
        .unwrap_or_else(|| empty(instrumental));
    response["choices"] = json!(choices);
    response["provider_status"] = json!(status);
    Ok(response)
}

/// Sidecars/tags use the desktop readers, including word timing, backing lanes and romanization.
pub(crate) fn parse(text: &str, format: Option<&str>) -> Result<Value> {
    let (sheet, writers) = parse_sheet(text, format)?;
    Ok(render(&sheet, "Local", &writers, false))
}

fn parse_sheet(text: &str, format: Option<&str>) -> Result<(Lyrics, Vec<String>)> {
    if text.len() > MAX_TEXT {
        bail!("lyrics text is too long");
    }
    let text = text.trim_start_matches('\u{feff}');
    if format == Some("ttml")
        || text.trim_start().starts_with("<?xml")
        || text.trim_start().starts_with("<tt")
    {
        let sheet = crate::lyrics::ttml::parse(text)?;
        return Ok((sheet.lyrics, sheet.writers));
    }
    let lines = crate::lyrics::lrc::parse(text);
    let sheet = match lines.is_empty() {
        true => Lyrics::plain(text),
        false => Lyrics::Synced {
            lines: lines.into(),
        },
    };
    Ok((sheet, Vec::new()))
}

fn empty(instrumental: bool) -> Value {
    json!({ "text": null, "lines": [], "synced": false, "worded": false,
        "instrumental": instrumental, "source": null, "writers": [] })
}

fn render(sheet: &Lyrics, source: &str, writers: &[String], instrumental: bool) -> Value {
    match sheet {
        Lyrics::Plain { text, romanized } => json!({ "text": text, "lines": [], "synced": false,
            "worded": false, "instrumental": instrumental, "source": source, "writers": writers,
            "romanized": romanized.as_ref().map(|r| &r.text), "romanization_script": script(romanized.as_ref()) }),
        Lyrics::Synced { lines } => json!({
            "text": lines.iter().map(|line| line.text.as_str()).collect::<Vec<_>>().join("\n"),
            "lines": lines.iter().enumerate().map(|(id, line)| line_value(id, line)).collect::<Vec<_>>(),
            "synced": true, "worded": sheet.worded(), "instrumental": instrumental, "source": source, "writers": writers,
        }),
    }
}

fn line_value(id: usize, line: &LyricsLine) -> Value {
    json!({ "id": id, "text": line.text, "start_seconds": line.start.as_secs_f64(),
        "end_seconds": line.end.map(|s| s.as_secs_f64()), "romanized": line.romanized.as_ref().map(|r| &r.text),
        "romanization_script": script(line.romanized.as_ref()), "voice": if line.voice.lead() { "lead" } else { "counter" },
        "words": words(line.words.as_deref()),
        "secondary": line.secondary.iter().enumerate().map(|(id, lane)| lane_value(id, lane)).collect::<Vec<_>>() })
}

fn lane_value(id: usize, lane: &LyricsLane) -> Value {
    json!({ "id": id, "text": lane.text, "start_seconds": lane.start.as_secs_f64(),
        "end_seconds": lane.end.map(|s| s.as_secs_f64()), "romanized": lane.romanized.as_ref().map(|r| &r.text),
        "romanization_script": script(lane.romanized.as_ref()), "words": words(lane.words.as_deref()) })
}

fn words(words: Option<&[LyricsWord]>) -> Vec<Value> {
    words.unwrap_or_default().iter().enumerate().map(|(id, word)| json!({ "id": id,
        "text": word.text, "start_seconds": word.start.as_secs_f64(), "end_seconds": word.end.as_secs_f64() })).collect()
}

fn script(romanized: Option<&RomanizedText>) -> Option<String> {
    romanized.map(|r| format!("{:?}", r.writing_system))
}
