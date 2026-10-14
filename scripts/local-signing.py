#!/usr/bin/env python3
"""Persistent local-only code-signing identity in a dedicated private keychain.
Does not add a trusted root, change user trust settings, or grant TCC access.
"""
import pathlib, subprocess, secrets, os, json, hashlib, sys
base=pathlib.Path.home()/'Library/Application Support/Voicey/DevelopmentSigning'
base.mkdir(parents=True,exist_ok=True);os.chmod(base,0o700)
keychain=base/'Voicey.keychain-db';password_file=base/'keychain-password'
def run(args):
 result=subprocess.run(args,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True)
 if result.returncode:raise RuntimeError('Local signing command failed: '+args[0]+' '+args[1]+' (exit '+str(result.returncode)+')')
 return result.stdout
if not password_file.exists():password_file.write_text(secrets.token_urlsafe(32));os.chmod(password_file,0o600)
password=password_file.read_text()
cert=base/'certificate.pem';key=base/'private-key.pem';archive=base/'identity.p12'
if not cert.exists():
 config=base/'certificate.conf';config.write_text('[req]\ndistinguished_name=dn\nx509_extensions=signing\nprompt=no\n[dn]\nCN=Voicey Local Development\n[signing]\nbasicConstraints=critical,CA:FALSE\nkeyUsage=critical,digitalSignature\nextendedKeyUsage=codeSigning\nsubjectKeyIdentifier=hash\nauthorityKeyIdentifier=keyid\n')
 run(['/usr/bin/openssl','req','-new','-x509','-newkey','rsa:2048','-nodes','-sha256','-days','3650','-config',str(config),'-keyout',str(key),'-out',str(cert)])
 os.chmod(key,0o600)
 run(['/usr/bin/openssl','pkcs12','-export','-inkey',str(key),'-in',str(cert),'-name','Voicey Local Development','-passout','pass:'+password,'-out',str(archive)])
 os.chmod(archive,0o600)
if not keychain.exists():
 run(['/usr/bin/security','create-keychain','-p',password,str(keychain)])
 run(['/usr/bin/security','set-keychain-settings','-lut','3600',str(keychain)])
 run(['/usr/bin/security','import',str(archive),'-k',str(keychain),'-P',password,'-T','/usr/bin/codesign'])
 run(['/usr/bin/security','set-key-partition-list','-S','apple-tool:,apple:','-s','-k',password,str(keychain)])
run(['/usr/bin/security','unlock-keychain','-p',password,str(keychain)])
fingerprint=run(['/usr/bin/openssl','x509','-in',str(cert),'-noout','-fingerprint','-sha1']).strip().split('=',1)[1].replace(':','')
if len(sys.argv)>1:
 target=pathlib.Path(sys.argv[1]);identifier=sys.argv[2] if len(sys.argv)>2 else 'local.voicey.mac'
 requirement='=designated => identifier "'+identifier+'" and certificate leaf = H"'+fingerprint+'"'
 run(['/usr/bin/codesign','--force','--keychain',str(keychain),'--sign',fingerprint,'--identifier',identifier,'--requirements',requirement,str(target)])
 print('Signed with persistent local identity:',target.name)
else:print('Persistent local signing identity ready; no paid developer account or system trust change')
