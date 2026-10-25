#ifndef SONORA_MOBILE_H
#define SONORA_MOBILE_H

#include <stdint.h>

// The callback runs on a Rust worker thread exactly once for each accepted request.
// Copy the JSON and release it with sonora_mobile_string_free. Never use Swift free().
typedef void (*SonoraMobileCallback)(void *context, char *json);

// Copies request_json before returning. Context must remain valid until the callback runs.
// Returns 0 when accepted, 1 for invalid input, or 2 if the runtime could not start.
int32_t sonora_mobile_request(const char *request_json, void *context, SonoraMobileCallback callback);
void sonora_mobile_string_free(char *json);

#endif
