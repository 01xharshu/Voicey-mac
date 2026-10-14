#pragma once
#ifdef __cplusplus
extern "C" {
#endif
int vy_runtime_open(const char *directory);
void *vy_llm_load(const char *path, int gpu);
char *vy_llm_infer(void *model, const char *system, const char *user);
void vy_llm_free(void *model);
void *vy_stt_load(const char *path, int gpu);
char *vy_stt_transcribe(void *model, const float *samples, int count, const char *language, const char *vocabulary);
void vy_stt_free(void *model);
void vy_cancel(int cancel);
void vy_string_free(char *text);
int vy_tts_open(const char *directory);
void *vy_tts_load(const char *directory, int british);
float *vy_tts_render(void *model, const char *text, int speaker, float speed, int *count, int *sample_rate);
void vy_tts_cancel(void);
void vy_tts_free(void *model);
void vy_audio_free(float *audio);
#ifdef __cplusplus
}
#endif
