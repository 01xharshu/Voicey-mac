#!/usr/bin/env python3
"""Exercise the actual Swift helper with a fake browser/extension over local IPC."""
import ctypes, json, os, pathlib, secrets, select, shutil, socket, struct, subprocess, sys, time
source=pathlib.Path(sys.argv[1] if len(sys.argv)>1 else '.build/release/VoiceyBrowserHost').resolve()
root=pathlib.Path.home()/'Library/Application Support/Voicey/BrowserBridge'
root.mkdir(parents=True,exist_ok=True,mode=0o700)
name='voicey-host-selftest-'+secrets.token_hex(4)
host=root/name;config=root/(name+'.json');sock=root/(name+'.sock');token=secrets.token_hex(32)
origin='chrome-extension://'+'a'*32+'/'
def send(f,obj):
    data=json.dumps(obj).encode();f.write(struct.pack('<I',len(data))+data);f.flush()
def read(f):
    assert select.select([f],[],[],5)[0], 'frame timeout'
    header=f.read(4);assert len(header)==4,'missing frame header'
    n=struct.unpack('<I',header)[0];assert n<1048576
    return json.loads(f.read(n))
def connect():
    s=socket.socket(socket.AF_UNIX);s.settimeout(5);s.connect(str(sock));return s
p=None
try:
    shutil.copy2(source,host);host.chmod(0o700)
    libproc=ctypes.CDLL('/usr/lib/libproc.dylib');buf=ctypes.create_string_buffer(4096);libproc.proc_pidpath(os.getpid(),buf,4096);parent_path=buf.value.decode()
    config.write_text(json.dumps({'extensionID':'a'*32,'browserID':name,'browserExecutable':parent_path,'token':token}));config.chmod(0o600)
    bad=subprocess.run([str(host),'chrome-extension://'+'b'*32+'/'],capture_output=True,timeout=5)
    assert bad.returncode!=0;print('PASS native extension identity rejected')
    p=subprocess.Popen([str(host),origin],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE,bufsize=0)
    for _ in range(100):
        if sock.exists():break
        if p.poll() is not None:raise RuntimeError(p.stderr.read().decode())
        time.sleep(.02)
    assert sock.exists();assert (sock.stat().st_mode & 0o777)==0o600;print('PASS private socket and parent identity')
    c={'version':1,'id':'00000000-0000-0000-0000-000000000001','operation':'inspect','url':'https://chatgpt.com/','text':'','recipient':'','subject':''}
    with connect() as s:
        f=s.makefile('rwb',buffering=0);send(f,{'token':'wrong','command':c});assert s.recv(1)==b''
    print('PASS invalid IPC authentication rejected')
    with connect() as s:
        f=s.makefile('rwb',buffering=0);send(f,{'token':token,'command':{**c,'url':'https://evil.test/'}});assert s.recv(1)==b''
    print('PASS unauthorized browser destination rejected by native host')
    with connect() as s:
        f=s.makefile('rwb',buffering=0);send(f,{'token':token,'command':c});received=read(p.stdout);assert received==c
        send(p.stdin,{'version':1,'id':c['id'],'ok':True,'url':c['url'],'state':'ready','detail':'fixture'})
        response=read(f);assert response['ok']
    print('PASS actual native framing and correlated response')
    s=connect();f=s.makefile('rwb',buffering=0);send(f,{'token':token,'command':c});assert read(p.stdout)['operation']=='inspect';f.close();s.close()
    assert read(p.stdout)['operation']=='cancel';p.wait(timeout=5)
    print('PASS disconnected app cancels browser and closes helper')
finally:
    if p and p.poll() is None:p.terminate();p.wait(timeout=5)
    for path in [host,config,sock,root/(name+'.lock')]:path.unlink(missing_ok=True)
