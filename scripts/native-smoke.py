#!/usr/bin/env python3
"""Exercise embedded C ABI directly, never a model executable or server."""
import ctypes, pathlib, hashlib, time, wave, struct, json
root=pathlib.Path(__file__).resolve().parent.parent
models=pathlib.Path.home()/'Library/Application Support/Voicey/Models'
libc=ctypes.CDLL('/usr/lib/libSystem.B.dylib');libc.free.argtypes=[ctypes.c_void_p]
def runtime(name):
 lib=ctypes.CDLL(str(root/f'.build/native-{name}/libvoicey_{name}.dylib'))
 lib.voicey_load.argtypes=[ctypes.c_char_p,ctypes.c_int];lib.voicey_load.restype=ctypes.c_void_p
 lib.voicey_free.argtypes=[ctypes.c_void_p];lib.voicey_cancel.argtypes=[ctypes.c_int]
 return lib
def verify(filename,digest):
 h=hashlib.sha256()
 with open(models/filename,'rb') as f:
  while chunk:=f.read(1024*1024):h.update(chunk)
 assert h.hexdigest()==digest, 'model checksum mismatch'
start=time.monotonic()
verify('speech.bin','60ed5bc3dd14eea856493d334349b405782ddcaf0028d4b5df4088345fba2efe')
stt=runtime('whisper');stt.voicey_transcribe.argtypes=[ctypes.c_void_p,ctypes.POINTER(ctypes.c_float),ctypes.c_int,ctypes.c_char_p,ctypes.c_char_p];stt.voicey_transcribe.restype=ctypes.c_void_p
model=stt.voicey_load(str(models/'speech.bin').encode(),0);assert model,'whisper failed to load'
with wave.open(str(root/'.deps/whisper.cpp/samples/jfk.wav')) as f:
 assert f.getframerate()==16000 and f.getnchannels()==1
 raw=f.readframes(f.getnframes());samples=[v/32768 for v in struct.unpack('<'+'h'*(len(raw)//2),raw)]
audio=(ctypes.c_float*len(samples))(*samples)
text=stt.voicey_transcribe(model,audio,len(samples),b'en',b'');assert text,'speech inference failed'
transcript=ctypes.string_at(text).decode();libc.free(text);stt.voicey_free(model)
assert 'country' in transcript.lower(), transcript
print('PASS embedded Whisper sample transcription',round(time.monotonic()-start,2),'s',flush=True)
if not (models/'assistant.gguf').exists() or (models/'assistant.gguf').stat().st_size!=1282439328:
 print('LLM model download incomplete; rerun after completion',flush=True);raise SystemExit(2)
verify('assistant.gguf','e0801cbda7e2f3fd00bea4d73b53b422b14b13aa130e778f6414b6b641920b7e')
llm=runtime('llama');llm.voicey_infer.argtypes=[ctypes.c_void_p,ctypes.c_char_p,ctypes.c_char_p];llm.voicey_infer.restype=ctypes.c_void_p
start=time.monotonic();model=llm.voicey_load(str(models/'assistant.gguf').encode(),0);assert model,'LLM failed to load'
print('LLM loaded',round(time.monotonic()-start,2),'s',flush=True)
system=b'You are a Mac assistant. Return JSON only with strings kind, query, destination, browser, explanation. kind must be launchApp, search, openItem, reveal, website, clipboard, createFolder, capabilities or unsupported. For launching an app use launchApp and query its name. Empty unused fields. Example: Find the BenQ invoice in my Downloads. -> {"kind":"search","query":"BenQ invoice","destination":"Downloads","browser":"","explanation":"Search for invoice"}. /no_think'
for request in [b'Please launch Figma for me.',b'Find the BenQ invoice in my Downloads.']:
 start=time.monotonic();text=llm.voicey_infer(model,system,request);assert text,'LLM inference failed'
 result=json.loads(ctypes.string_at(text));libc.free(text)
 assert set(result)=={'kind','query','destination','browser','explanation'},result
 if request.startswith(b'Please launch'):
  assert result['kind']=='launchApp' and result['query'].lower()=='figma', result
 else:
  assert result['kind'] in ['search','reveal'] and 'benq' in result['query'].lower() and 'invoice' in result['query'].lower() and result['browser']=='', result
 print('PASS constrained embedded LLM',result['kind'],round(time.monotonic()-start,2),'s',flush=True)
llm.voicey_cancel(1);assert not llm.voicey_infer(model,system,b'Open Safari');llm.voicey_cancel(0);llm.voicey_free(model)
print('PASS native cancellation',flush=True)
