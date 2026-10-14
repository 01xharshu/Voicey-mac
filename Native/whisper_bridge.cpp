#include "whisper.h"
#include <atomic>
#include <string>
#include <cstring>
static std::atomic<bool> cancelled{false};
static bool abort_work(void *) {return cancelled.load();}
static void quiet(enum ggml_log_level,const char *,void *){}
extern "C" void voicey_cancel(int c){cancelled=c;}
extern "C" void *voicey_load(const char *path,int gpu){whisper_log_set(quiet,nullptr);auto p=whisper_context_default_params();p.use_gpu=gpu;return whisper_init_from_file_with_params(path,p);}
extern "C" void voicey_free(void *p){if(p)whisper_free((whisper_context*)p);}
extern "C" char *voicey_transcribe(void *ptr,const float *samples,int n,const char *language,const char *vocab) {
 if(!ptr||cancelled||n<1600)return nullptr;auto ctx=(whisper_context*)ptr;
 auto p=whisper_full_default_params(WHISPER_SAMPLING_GREEDY);p.n_threads=4;p.translate=false;p.language=language;p.initial_prompt=vocab;
 p.print_realtime=false;p.print_progress=false;p.print_timestamps=false;p.print_special=false;p.no_context=true;
 p.abort_callback=abort_work;p.abort_callback_user_data=nullptr;
 if(whisper_full(ctx,p,samples,n)||cancelled)return nullptr;
 std::string result;for(int i=0;i<whisper_full_n_segments(ctx);i++)result+=whisper_full_get_segment_text(ctx,i);
 return strdup(result.c_str());
}
