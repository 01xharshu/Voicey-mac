#include "NativeBridge.h"
#include <dlfcn.h>
#include <stdlib.h>
#include <stdio.h>
static void *llm, *stt;
int vy_runtime_open(const char *dir) {
 char path[4096]; snprintf(path,sizeof(path),"%s/libvoicey_llama.dylib",dir);
 llm=dlopen(path,RTLD_NOW|RTLD_LOCAL); if(!llm) return 0;
 snprintf(path,sizeof(path),"%s/libvoicey_whisper.dylib",dir);
 stt=dlopen(path,RTLD_NOW|RTLD_LOCAL); return stt != NULL;
}
void *vy_llm_load(const char *p,int gpu) { void *(*f)(const char*,int)=llm?dlsym(llm,"voicey_load"):NULL;return f?f(p,gpu):NULL; }
char *vy_llm_infer(void *m,const char *s,const char *u) { char *(*f)(void*,const char*,const char*)=llm?dlsym(llm,"voicey_infer"):NULL;return f?f(m,s,u):NULL; }
void vy_llm_free(void *m) { void (*f)(void*)=llm?dlsym(llm,"voicey_free"):NULL;if(f)f(m); }
void *vy_stt_load(const char *p,int gpu) { void *(*f)(const char*,int)=stt?dlsym(stt,"voicey_load"):NULL;return f?f(p,gpu):NULL; }
char *vy_stt_transcribe(void *m,const float *s,int n,const char *l,const char *v) { char *(*f)(void*,const float*,int,const char*,const char*)=stt?dlsym(stt,"voicey_transcribe"):NULL;return f?f(m,s,n,l,v):NULL; }
void vy_stt_free(void *m) { void (*f)(void*)=stt?dlsym(stt,"voicey_free"):NULL;if(f)f(m); }
void vy_cancel(int c) { void (*f)(int)=llm?dlsym(llm,"voicey_cancel"):NULL;if(f)f(c); f=stt?dlsym(stt,"voicey_cancel"):NULL;if(f)f(c); }
void vy_string_free(char *t) { free(t); }
