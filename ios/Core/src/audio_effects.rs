//! Native audio taps drive exactly the desktop's filters. Only configuration takes a lock;
//! processing uses preallocated state and the desktop's atomic curve handoff.

use std::ffi::c_void;
use std::sync::atomic::{AtomicU32, AtomicU64, Ordering};
use std::sync::{Arc, Mutex, OnceLock};

use anyhow::{Context as _, Result, bail};
use serde::Deserialize;
use serde_json::{Value, json};

use crate::equalizer::{
    Curve, Edit, EqualizerWriter, Filter, FilterStage, Kind, MAX_CHANNELS, Preamp, Preset, Tone,
    Width, apo,
};

const MAX_FRAMES: usize = 65_536;
const GAIN_RAMP_SECONDS: f32 = 0.04;
static WRITER: OnceLock<Mutex<EqualizerWriter>> = OnceLock::new();
static NORMALIZATION: AtomicU32 = AtomicU32::new(1.0f32.to_bits());
static REVISION: AtomicU64 = AtomicU64::new(0);

pub(crate) struct Configuration {
    pub revision: u64,
    pub enabled: bool,
    pub preset: String,
    pub auto_preamp: bool,
    pub preamp_db: f64,
    pub bass_db: f64,
    pub treble_db: f64,
    pub normalization_db: f64,
    pub profile: Option<String>,
    pub filters: Option<Vec<FilterSpec>>,
}

/// Plain numbers cross the boundary; the shared desktop constructor validates every filter.
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
pub(crate) struct FilterSpec {
    kind: String,
    frequency: f64,
    gain: f64,
    width_unit: String,
    width: f64,
    enabled: bool,
}

impl FilterSpec {
    fn filter(self) -> Result<Filter> {
        let kind = Kind::from_id(&self.kind).context("unknown filter kind")?;
        let width = match self.width_unit.as_str() {
            "q" => Width::Q(self.width),
            "octaves" => Width::Octaves(self.width),
            _ => bail!("unknown filter width"),
        };
        Ok(Filter::new(
            kind,
            self.frequency,
            self.gain,
            width,
            self.enabled,
        )?)
    }
}

/// Describes presets, imported files or edited filters without changing the active sound.
pub(crate) fn describe(
    preset: &str,
    profile: Option<&str>,
    filters: Option<Vec<FilterSpec>>,
    auto_preamp: Option<bool>,
    preamp_db: Option<f64>,
) -> Result<Value> {
    describe_inner(preset, profile, filters, auto_preamp, preamp_db)
        .map_err(|_| InvalidConfiguration.into())
}

fn describe_inner(
    preset: &str,
    profile: Option<&str>,
    filters: Option<Vec<FilterSpec>>,
    auto_preamp: Option<bool>,
    preamp_db: Option<f64>,
) -> Result<Value> {
    let (base, skipped) = base_curve(preset, profile, filters)?;
    let preamp = match auto_preamp {
        Some(true) => Preamp::Auto,
        Some(false) => Preamp::Manual(preamp_db.unwrap_or_default()),
        None => base.preamp(),
    };
    let curve = Curve::new(preamp, base.filters().to_vec())?;
    let filters: Vec<Value> = curve.filters().iter().map(|filter| {
        let (width_unit, width) = match filter.width() { Width::Q(q) => ("q", q), Width::Octaves(o) => ("octaves", o) };
        json!({ "kind": filter.kind().id(), "frequency": filter.frequency(), "gain": filter.gain(),
            "width_unit": width_unit, "width": width, "enabled": filter.enabled() })
    }).collect();
    Ok(
        json!({ "filters": filters, "auto_preamp": matches!(preamp, Preamp::Auto),
        "preamp_db": curve.preamp_db(), "profile": apo::export(&curve), "skipped_lines": skipped }),
    )
}

fn base_curve(
    preset: &str,
    profile: Option<&str>,
    filters: Option<Vec<FilterSpec>>,
) -> Result<(Curve, Vec<usize>)> {
    if let Some(filters) = filters {
        let filters = filters
            .into_iter()
            .map(FilterSpec::filter)
            .collect::<Result<Vec<_>>>()?;
        return Ok((Curve::new(Preamp::Auto, filters)?, Vec::new()));
    }
    if let Some(text) = profile {
        if text.trim().is_empty() {
            bail!("equalizer profile is empty");
        }
        let parsed =
            apo::parse(text).map_err(|_| anyhow::anyhow!("cannot parse equalizer profile"))?;
        return Ok((
            parsed.curve,
            parsed.skipped.into_iter().map(|line| line.line).collect(),
        ));
    }
    let curve = Preset::ALL
        .into_iter()
        .find(|candidate| candidate.id() == preset)
        .context("unknown equalizer preset")?
        .curve();
    Ok((curve, Vec::new()))
}

/// Stable category for the host's localized validation error, without exporting profile text.
#[derive(Debug)]
pub(crate) struct InvalidConfiguration;
impl std::fmt::Display for InvalidConfiguration {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str("invalid audio configuration")
    }
}
impl std::error::Error for InvalidConfiguration {}

fn writer() -> &'static Mutex<EqualizerWriter> {
    WRITER.get_or_init(|| Mutex::new(EqualizerWriter::new(false, Preset::Flat.curve())))
}

/// Validates on the control thread, then publishes atomically to every active audio tap.
pub(crate) fn configure(config: Configuration) -> Result<Value> {
    configure_inner(config).map_err(|_| InvalidConfiguration.into())
}

fn configure_inner(config: Configuration) -> Result<Value> {
    for (value, range) in [
        (config.preamp_db, -30.0..=12.0),
        (config.bass_db, -12.0..=12.0),
        (config.treble_db, -12.0..=12.0),
        (config.normalization_db, -24.0..=24.0),
    ] {
        if !value.is_finite() || !range.contains(&value) {
            bail!("audio value is out of range");
        }
    }
    let (base, skipped) = base_curve(&config.preset, config.profile.as_deref(), config.filters)?;
    let preamp = match config.auto_preamp {
        true => Preamp::Auto,
        false => Preamp::Manual(config.preamp_db),
    };
    let curve = Curve::new(preamp, base.filters().to_vec())?;
    let mut writer = writer()
        .lock()
        .map_err(|_| anyhow::anyhow!("audio writer lock poisoned"))?;
    if config.revision < REVISION.load(Ordering::Relaxed) {
        return Ok(json!({ "applied": false, "preamp_db": writer.preamp_db(),
            "filter_count": writer.curve().filters().len(), "skipped_lines": [], "profile": apo::export(writer.curve()) }));
    }
    REVISION.store(config.revision, Ordering::Relaxed);
    writer.set_curve(curve, Edit::Glide);
    writer.set_tone(Tone::new(config.bass_db, config.treble_db), Edit::Glide);
    writer.set_enabled(config.enabled);
    NORMALIZATION.store(
        (10.0f64.powf(config.normalization_db / 20.0) as f32).to_bits(),
        Ordering::Release,
    );
    Ok(json!({
        "applied": true,
        "preamp_db": writer.preamp_db(), "filter_count": writer.curve().filters().len(),
        "skipped_lines": skipped, "profile": apo::export(writer.curve()),
    }))
}

struct NativeStage {
    filters: FilterStage,
    channels: usize,
    rate: u32,
    gain: f32,
    target: f32,
    step: f32,
    remaining: u32,
    frames: Arc<AtomicU64>,
}

impl NativeStage {
    fn begin_buffer(&mut self) {
        let target = f32::from_bits(NORMALIZATION.load(Ordering::Acquire));
        if target != self.target {
            self.target = target;
            self.remaining = (self.rate as f32 * GAIN_RAMP_SECONDS).max(1.0) as u32;
            self.step = (target - self.gain) / self.remaining as f32;
        }
    }

    fn begin_frame(&mut self) {
        self.filters.begin();
        if self.remaining > 0 {
            self.remaining -= 1;
            self.gain = match self.remaining {
                0 => self.target,
                _ => self.gain + self.step,
            };
        }
    }
}

/// Allocates a desktop filter reader off the render thread. The host owns the returned stage.
#[unsafe(no_mangle)]
pub extern "C" fn sonora_audio_stage_create() -> *mut c_void {
    let Ok(writer) = writer().lock() else {
        return std::ptr::null_mut();
    };
    let gain = f32::from_bits(NORMALIZATION.load(Ordering::Acquire));
    Box::into_raw(Box::new(NativeStage {
        filters: FilterStage::new(writer.reader()),
        channels: 0,
        rate: 0,
        gain,
        target: gain,
        step: 0.0,
        remaining: 0,
        frames: Arc::new(AtomicU64::new(0)),
    }))
    .cast()
}

/// Releases one stage after all render callbacks have ended.
///
/// # Safety
/// `stage` is null or an unfreed pointer from `sonora_audio_stage_create`, used by no other thread.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn sonora_audio_stage_destroy(stage: *mut c_void) {
    if !stage.is_null() {
        drop(unsafe { Box::from_raw(stage.cast::<NativeStage>()) });
    }
}

/// Sets PCM format during preparation, never concurrently with processing.
///
/// # Safety
/// `stage` is a live, exclusively accessed pointer from `sonora_audio_stage_create`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn sonora_audio_stage_format(
    stage: *mut c_void,
    rate: u32,
    channels: u32,
) -> i32 {
    if stage.is_null()
        || !(8_000..=384_000).contains(&rate)
        || !(1..=MAX_CHANNELS as u32).contains(&channels)
    {
        return 1;
    }
    let stage = unsafe { &mut *stage.cast::<NativeStage>() };
    stage.channels = channels as usize;
    stage.rate = rate;
    stage.filters.set_format(rate, channels as u16);
    0
}

/// Processes native float32 PCM without allocating, locking or calling the async runtime.
///
/// # Safety
/// `stage` is live and exclusively used by one render thread. Interleaved audio supplies one
/// nonnull plane of `frames * channels` floats. Planar audio supplies `channels` nonnull planes
/// of `frames` floats, all disjoint and writable. The pointer array itself is valid for its count.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn sonora_audio_stage_process(
    stage: *mut c_void,
    planes: *const *mut f32,
    frames: usize,
    interleaved: bool,
) -> i32 {
    if stage.is_null() || planes.is_null() || frames > MAX_FRAMES {
        return 1;
    }
    let stage = unsafe { &mut *stage.cast::<NativeStage>() };
    if stage.channels == 0 {
        return 1;
    }
    let count = match interleaved {
        true => 1,
        false => stage.channels,
    };
    let planes = unsafe { std::slice::from_raw_parts(planes, count) };
    if planes.iter().any(|plane| plane.is_null()) {
        return 1;
    }
    stage.begin_buffer();
    for frame in 0..frames {
        stage.begin_frame();
        for channel in 0..stage.channels {
            let sample = match interleaved {
                true => unsafe { planes[0].add(frame * stage.channels + channel) },
                false => unsafe { planes[channel].add(frame) },
            };
            unsafe {
                *sample = stage.filters.process(channel, *sample) * stage.gain;
            }
        }
    }
    stage.frames.fetch_add(frames as u64, Ordering::Relaxed);
    0
}

/// Resets filter history at a discontinuity such as a seek.
///
/// # Safety
/// `stage` is live and used only by its render thread, with no concurrent callback.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn sonora_audio_stage_reset(stage: *mut c_void) {
    if !stage.is_null() {
        unsafe { &mut *stage.cast::<NativeStage>() }.filters.reset();
    }
}

/// Returns the separate atomic counter during preparation, before rendering starts.
///
/// # Safety
/// `stage` is live and not concurrently processed. The returned pointer stays valid until the
/// stage is destroyed; its pointee may be read concurrently with render callbacks.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn sonora_audio_stage_counter(stage: *const c_void) -> *const c_void {
    if stage.is_null() {
        return std::ptr::null();
    }
    Arc::as_ptr(&unsafe { &*stage.cast::<NativeStage>() }.frames).cast()
}

/// Reads only the shared counter allocation, never the exclusively borrowed DSP stage.
///
/// # Safety
/// `counter` is null or the counter of a stage that stays alive for the call.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn sonora_audio_counter_frames(counter: *const c_void) -> u64 {
    if counter.is_null() {
        return 0;
    }
    unsafe { &*counter.cast::<AtomicU64>() }.load(Ordering::Relaxed)
}
