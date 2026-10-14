#include "llama.h"
#include <atomic>
#include <string>
#include <vector>
#include <cstring>
#include <chrono>
static std::atomic<bool> cancelled{false};
static bool abort_work(void *) { return cancelled.load(); }
static void quiet(enum ggml_log_level, const char *, void *) {}
struct Engine { llama_model *model; llama_context *ctx; };
extern "C" void voicey_cancel(int c) { cancelled=c; }
extern "C" void *voicey_load(const char *path,int gpu) {
 llama_log_set(quiet,nullptr); llama_backend_init(); auto p=llama_model_default_params();p.n_gpu_layers=gpu?99:0;
 auto m=llama_model_load_from_file(path,p); if(!m)return nullptr;
 auto c=llama_context_default_params();c.n_ctx=4096;c.n_batch=512;c.n_threads=4;c.n_threads_batch=4;
 auto ctx=llama_init_from_model(m,c);if(!ctx){llama_model_free(m);return nullptr;}
 llama_set_abort_callback(ctx,abort_work,nullptr);return new Engine{m,ctx};
}
extern "C" void voicey_free(void *ptr) {if(!ptr)return;auto e=(Engine*)ptr;llama_free(e->ctx);llama_model_free(e->model);delete e;}
extern "C" char *voicey_infer(void *ptr,const char *system,const char *user) {
 auto e=(Engine*)ptr;if(!e||cancelled)return nullptr;
 const auto vocab=llama_model_get_vocab(e->model);
 llama_chat_message messages[]={{"system",system},{"user",user}};
 std::vector<char> chat(24000);auto n=llama_chat_apply_template(llama_model_chat_template(e->model,nullptr),messages,2,true,chat.data(),chat.size());
 if(n<0 || n>=(int)chat.size())return nullptr;
 std::string prompt(chat.data(),n);prompt+="<think>\n</think>\n";
 std::vector<llama_token> tokens(4096);int count=llama_tokenize(vocab,prompt.data(),prompt.size(),tokens.data(),tokens.size(),true,true);
 if(count<1||count>3000)return nullptr;
 llama_memory_clear(llama_get_memory(e->ctx),true);
 for(int i=0;i<count;i+=512){if(cancelled)return nullptr;auto b=llama_batch_get_one(tokens.data()+i,std::min(512,count-i));if(llama_decode(e->ctx,b))return nullptr;}
 const char *grammar=R"(root ::= "{" ws "\"kind\"" ws ":" ws string ws "," ws "\"query\"" ws ":" ws string ws "," ws "\"destination\"" ws ":" ws string ws "," ws "\"browser\"" ws ":" ws string ws "," ws "\"explanation\"" ws ":" ws string ws "}"
ws ::= [ \t\n\r]*
string ::= "\"" char* "\""
char ::= [^"\\\x00-\x1F] | "\\" (["\\/bfnrt] | "u" [0-9a-fA-F] [0-9a-fA-F] [0-9a-fA-F] [0-9a-fA-F])
)";
 auto sampler=llama_sampler_chain_init(llama_sampler_chain_default_params());
 auto g=llama_sampler_init_grammar(vocab,grammar,"root");if(!g){llama_sampler_free(sampler);return nullptr;}
 llama_sampler_chain_add(sampler,g);llama_sampler_chain_add(sampler,llama_sampler_init_greedy());
 std::string output;auto started=std::chrono::steady_clock::now();bool done=false;
 for(int i=0;i<400&&!cancelled;i++) {
 if(std::chrono::steady_clock::now()-started>std::chrono::seconds(45))break;
 auto t=llama_sampler_sample(sampler,e->ctx,-1);if(llama_vocab_is_eog(vocab,t)){done=true;break;}
 char piece[512];int sz=llama_token_to_piece(vocab,t,piece,sizeof(piece),0,true);if(sz>0)output.append(piece,sz);
 auto b=llama_batch_get_one(&t,1);if(llama_decode(e->ctx,b))break;
 }
 llama_sampler_free(sampler);return done&&!cancelled?strdup(output.c_str()):nullptr;
}
