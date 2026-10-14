#!/usr/bin/env python3
"""Register the user-installed extension; never installs a background service."""
import argparse, json, os, pathlib, re, secrets, shutil, plistlib
p=argparse.ArgumentParser()
p.add_argument('--extension-id',required=True)
p.add_argument('--browser',choices=['arc','chrome','brave','edge'],required=True)
p.add_argument('--app',default=str(pathlib.Path(__file__).resolve().parents[2]) if pathlib.Path(__file__).parent.name=='Resources' else 'dist/Voicey.app')
a=p.parse_args()
if not re.fullmatch('[a-p]{32}',a.extension_id):p.error('Expected the exact 32-letter extension ID shown by the browser')
browsers={'arc':('/Applications/Arc.app','company.thebrowser.Browser','Arc/User Data/NativeMessagingHosts'), 'chrome':('/Applications/Google Chrome.app','com.google.Chrome','Google/Chrome/NativeMessagingHosts'), 'brave':('/Applications/Brave Browser.app','com.brave.Browser','BraveSoftware/Brave-Browser/NativeMessagingHosts'), 'edge':('/Applications/Microsoft Edge.app','com.microsoft.edgemac','Microsoft Edge/NativeMessagingHosts')}
app,bundle,registration=browsers[a.browser]
info=pathlib.Path(app)/'Contents/Info.plist'
if not info.exists():p.error('Selected browser is not installed')
with info.open('rb') as f: executable=plistlib.load(f)['CFBundleExecutable']
source=pathlib.Path(a.app).resolve()/'Contents/MacOS/VoiceyBrowserHost'
if not source.exists():p.error('Build Voicey first with scripts/build.sh')
root=pathlib.Path.home()/'Library/Application Support/Voicey/BrowserBridge'
root.mkdir(parents=True,exist_ok=True);root.chmod(0o700)
host=root/('voicey-host-'+bundle)
shutil.copy2(source,host);host.chmod(0o700)
config=host.with_name(host.name+'.json')
def private_json(path,obj):
    fd=os.open(path,os.O_WRONLY|os.O_CREAT|os.O_TRUNC|os.O_NOFOLLOW,0o600)
    with os.fdopen(fd,'w') as f:json.dump(obj,f,indent=2)
    path.chmod(0o600)
private_json(config,{'extensionID':a.extension_id,'browserID':bundle,'browserExecutable':str(pathlib.Path(app)/'Contents/MacOS'/executable),'token':secrets.token_hex(32)})
reg=pathlib.Path.home()/'Library/Application Support'/registration
reg.mkdir(parents=True,exist_ok=True)
manifest={'name':'local.voicey.browser','description':'Voicey authenticated local browser bridge','path':str(host),'type':'stdio','allowed_origins':['chrome-extension://'+a.extension_id+'/']}
private_json(reg/'local.voicey.browser.json',manifest)
# Chromium-derived Arc has changed profile layout across releases. Register only
# beneath an existing Chromium NativeMessagingHosts parent as a compatibility route.
if a.browser=='arc':
    alternate=pathlib.Path.home()/'Library/Application Support/Arc/NativeMessagingHosts'
    alternate.mkdir(parents=True,exist_ok=True)
    private_json(alternate/'local.voicey.browser.json',manifest)
print('Registered',reg/'local.voicey.browser.json')
print('Open the extension popup, grant ChatGPT/Gmail separately, then Connect. Verify connection in Voicey settings. Arc compatibility is not certified until that succeeds.')
