// Chromium uses intercepted fixtures only. No real accounts or messages.
const {chromium}=require(process.env.VOICEY_PLAYWRIGHT || 'playwright');
const assert=require('node:assert/strict');
const path=require('node:path');
(async()=>{
 const browser=await chromium.launch({headless:true});
 const context=await browser.newContext();
 const page=await context.newPage();let assertions=0;
 async function fixture(url,html){await page.route('**/*',route=>route.fulfill({contentType:'text/html',body:html}));await page.goto(url);await page.evaluate(()=>{window.chrome={runtime:{id:'test',onMessage:{addListener:fn=>window.dispatchVoicey=fn}}};});await page.addScriptTag({path:path.join(__dirname,'../page.js')});await page.bringToFront();}
 async function call(operation,text='',extras={}){const result=await page.evaluate(({operation,text,extras})=>new Promise(resolve=>window.dispatchVoicey({version:1,id:'00000000-0000-0000-0000-000000000001',operation,url:location.href,text,recipient:'',subject:'',...extras},{id:'test'},resolve)),{operation,text,extras});return result;}
 await fixture('https://chatgpt.com/',`<textarea id="prompt-textarea" placeholder="Message ChatGPT"></textarea><button aria-label="Send message" onclick="let e=document.querySelector('textarea');let m=document.createElement('div');m.dataset.messageAuthorRole='user';m.textContent=e.value;document.body.append(m);e.value='';">Send</button>`);
 assert.equal((await call('inspect')).state,'ready');assertions++;
 assert.equal((await call('fillPrompt','why horses exist')).prompt,'why horses exist');assertions++;
 // Force DOM replacement, proving no stale element references are replayed.
 await page.evaluate(()=>{const old=document.querySelector('textarea');const fresh=old.cloneNode();fresh.value=old.value;old.replaceWith(fresh);});
 assert.equal((await call('submitPrompt','why horses exist')).submitted,true);assertions++;
 assert.equal(await page.locator('[data-message-author-role="user"]').count(),1);assertions++;
 assert.equal((await call('submitPrompt','why horses exist')).ok,false);assertions++;
 await fixture('https://chatgpt.com/',`<button>Log in</button>`);
 assert.equal((await call('inspect')).state,'login');assertions++;
 await fixture('https://chatgpt.com/',`<textarea id="prompt-textarea">Existing private draft</textarea>`);
 assert.equal((await call('fillPrompt','new prompt')).ok,false);assertions++;
 assert.equal(await page.locator('textarea').inputValue(),'Existing private draft');assertions++;
 await fixture('https://mail.google.com/',`<div role="main"><button id="compose">Compose</button></div><script>document.querySelector('#compose').onclick=()=>{let b=document.createElement('div');b.setAttribute('role','dialog');b.innerHTML='<input name="to" aria-label="To recipients"><input name="subjectbox"><div contenteditable="true" role="textbox" aria-label="Message Body"></div><span role="status">Saved to Drafts</span><button id="send">Send</button>';document.body.append(b);window.sent=0;document.querySelector('#send').onclick=()=>window.sent++;};</script>`);
 const draft=await call('gmailDraft','Thank you.',{recipient:'harsh@example.test',subject:'Thank you'});
 assert.equal(draft.draftSaved,true);assertions++;
 assert.equal(draft.body,'Thank you.');assertions++;
 assert.equal(await page.evaluate(()=>window.sent),0);assertions++;
 assert.equal((await call('gmailDraft','Thank you.',{recipient:'harsh@example.test'})).ok,false);assertions++;
 assert.equal(await page.locator('[role="dialog"]').count(),1);assertions++;
 await fixture('https://evil.test/',`<textarea id="prompt-textarea"></textarea>`);
 assert.equal((await call('fillPrompt','data')).ok,false);assertions++;
 console.log(`PASS ${assertions} Chromium DOM fixture assertions; no real external traffic`);
 await browser.close();
})().catch(e=>{console.error(e);process.exit(1)});
