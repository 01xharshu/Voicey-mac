#include "NativeBridge.h"
#include "sherpa_api.h"
#include <dlfcn.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <stdatomic.h>
#include <math.h>
static void *runtime;
static atomic_uint epoch=0;
static const SherpaOnnxOfflineTts *(*create_tts)(const SherpaOnnxOfflineTtsConfig *);
static void (*destroy_tts)(const SherpaOnnxOfflineTts *);
static const SherpaOnnxGeneratedAudio *(*generate)(const SherpaOnnxOfflineTts *,const char *,int32_t,float,SherpaOnnxGeneratedAudioCallbackWithArg,void *);
static void (*destroy_audio)(const SherpaOnnxGeneratedAudio *);
int vy_tts_open(const char *directory) {
 if(runtime) return 1;
 char path[4096];snprintf(path,sizeof(path),"%s/libsherpa-onnx-c-api.dylib",directory);
 runtime=dlopen(path,RTLD_NOW|RTLD_LOCAL);if(!runtime)return 0;
 create_tts=dlsym(runtime,"SherpaOnnxCreateOfflineTts");destroy_tts=dlsym(runtime,"SherpaOnnxDestroyOfflineTts");
 generate=dlsym(runtime,"SherpaOnnxOfflineTtsGenerateWithCallbackWithArg");destroy_audio=dlsym(runtime,"SherpaOnnxDestroyOfflineTtsGeneratedAudio");
 if(!create_tts || !destroy_tts || !generate || !destroy_audio){dlclose(runtime);runtime=NULL;return 0;}return 1;
}
void *vy_tts_load(const char *directory,int british) {
 if(!runtime || strlen(directory)>3000)return NULL;
 char model[4096],voices[4096],tokens[4096],data[4096],lexicon[4096];
 snprintf(model,sizeof(model),"%s/model.onnx",directory);snprintf(voices,sizeof(voices),"%s/voices.bin",directory);
 snprintf(tokens,sizeof(tokens),"%s/tokens.txt",directory);snprintf(data,sizeof(data),"%s/espeak-ng-data",directory);
 snprintf(lexicon,sizeof(lexicon),"%s/lexicon-%s-en.txt",directory,british?"gb":"us");
 SherpaOnnxOfflineTtsConfig config;memset(&config,0,sizeof(config));
 config.model.kokoro.model=model;config.model.kokoro.voices=voices;config.model.kokoro.tokens=tokens;
 config.model.kokoro.data_dir=data;config.model.kokoro.lexicon=lexicon;config.model.kokoro.length_scale=1;
 config.model.kokoro.lang="";config.model.num_threads=2;config.model.provider="cpu";
 config.max_num_sentences=1;config.silence_scale=1;
 return (void *)create_tts(&config);
}
static int32_t progress(const float *samples,int32_t count,void *context){return atomic_load(&epoch)==*(unsigned *)context;}
float *vy_tts_render(void *model,const char *text,int speaker,float speed,int *count,int *sample_rate) {
 *count=0;*sample_rate=0;
 if(!model || !text || strlen(text)>8192 || speaker<0 || speaker>53 || !isfinite(speed) || speed<0.5f || speed>2.0f)return NULL;
 unsigned token=atomic_load(&epoch);
 const SherpaOnnxGeneratedAudio *audio=generate(model,text,speaker,speed,progress,&token);
 if(!audio)return NULL;
 float *output=NULL;
 if(atomic_load(&epoch)==token && audio->samples && audio->n>0 && audio->n<24000*180 && audio->sample_rate==24000){
 output=malloc(sizeof(float)*audio->n);if(output){memcpy(output,audio->samples,sizeof(float)*audio->n);*count=audio->n;*sample_rate=audio->sample_rate;}
 }
 destroy_audio(audio);return output;
}
void vy_tts_cancel(void){atomic_fetch_add(&epoch,1);}
void vy_tts_free(void *model){if(model && destroy_tts)destroy_tts(model);}
void vy_audio_free(float *audio){free(audio);}
