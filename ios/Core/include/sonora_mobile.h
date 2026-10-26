#ifndef SONORA_MOBILE_H
#define SONORA_MOBILE_H

#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>

// The callback runs on a Rust worker thread exactly once for each accepted request.
// Copy the JSON and release it with sonora_mobile_string_free. Never use Swift free().
typedef void (*SonoraMobileCallback)(void *context, char *json);

// Copies request_json before returning. Context must remain valid until the callback runs.
// Returns 0 when accepted, 1 for invalid input, or 2 if the runtime could not start.
int32_t sonora_mobile_request(const char *request_json, void *context, SonoraMobileCallback callback);
void sonora_mobile_string_free(char *json);

// Prepare/destroy off the render thread. Process/reset exclusively on its owning render thread.
void *sonora_audio_stage_create(void);
void sonora_audio_stage_destroy(void *stage);
int32_t sonora_audio_stage_format(void *stage, uint32_t rate, uint32_t channels);
int32_t sonora_audio_stage_process(void *stage, float *const *planes, size_t frames, bool interleaved);
void sonora_audio_stage_reset(void *stage);
// Obtain the counter before rendering. Read it concurrently only while its stage remains alive.
const void *sonora_audio_stage_counter(const void *stage);
uint64_t sonora_audio_counter_frames(const void *counter);

#endif
