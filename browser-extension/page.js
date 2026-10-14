(() => {
 if (globalThis.__voiceyBridgeV2) return;
 globalThis.__voiceyBridgeV2 = true;
 let cancelled=false,epoch=0;
 const visible = e => !!e && e.getClientRects().length>0 && getComputedStyle(e).visibility!=='hidden';
 const text = e => (e?.innerText ?? e?.value ?? '').trim();
 const label = e => e.getAttribute('aria-label') || e.getAttribute('placeholder') || e.getAttribute('data-testid') || e.innerText || '';
 const find = (selector,pattern,root=document) => [...root.querySelectorAll(selector)].filter(visible).filter(e=>pattern.test(label(e)));
 const unique = list => list.length===1?list[0]:null;
 const wait = async (fn,token) => {const start=Date.now();while(Date.now()-start<7000){if(cancelled||epoch!==token)throw Error('Task cancelled');const value=fn();if(value)return value;await new Promise(r=>setTimeout(r,150));}return null;};
 const prompt = () => unique([...document.querySelectorAll('#prompt-textarea,textarea[placeholder], [contenteditable="true"][role="textbox"]')].filter(visible).filter(e=>e.id==='prompt-textarea'||/message|ask|prompt/i.test(label(e))));
 const users = () => [...document.querySelectorAll('[data-message-author-role="user"]')].filter(visible).map(text);
 const ready = () => {
 if (find('button,a',/^(log in|sign in|login)$/i).length && !prompt()) return 'login';
 if (find('[role="dialog"]',/consent|accept cookies|privacy choices/i).length) return 'consent';
 if (find('[role="alert"]',/error|something went wrong|try again/i).length) return 'error';
 if(location.hostname==='chatgpt.com') return prompt()?'ready':'missing';
 return find('[role="button"],button',/^compose$/i).length || document.querySelector('div[role="main"]')?'ready':(document.querySelector('input[type="password"],input[type="email"]')?'login':'missing');
 };
 function fill(e,value) {
 if(!visible(e)||e.disabled)throw Error('Field unavailable');
 e.focus();
 if(e instanceof HTMLTextAreaElement || e instanceof HTMLInputElement) {
 const setter=Object.getOwnPropertyDescriptor(e instanceof HTMLTextAreaElement?HTMLTextAreaElement.prototype:HTMLInputElement.prototype,'value').set;setter.call(e,value);
 } else {
 // Input events notify React/Lexical editors. Never inject markup from the user.
 e.replaceChildren(document.createTextNode(value));
 }
 e.dispatchEvent(new InputEvent('input',{bubbles:true,inputType:'insertText',data:value}));
 e.dispatchEvent(new Event('change',{bubbles:true}));
 }
 const exact = (e,value) => (e instanceof HTMLInputElement || e instanceof HTMLTextAreaElement ? e.value : e.innerText)===value;
 chrome.runtime.onMessage.addListener((command,sender,respond) => {
 if(sender.id!==chrome.runtime.id)return;
 (async()=>{
 let r={version:1,id:command.id,ok:false,url:location.href,state:ready(),detail:''};
 try {
 const url=new URL(command.url);
 if(command.version!==1||url.origin!==location.origin||!['https://chatgpt.com','https://mail.google.com'].includes(location.origin)||!['inspect','fillPrompt','submitPrompt','gmailDraft','cancel'].includes(command.operation))throw Error('Unauthorized page operation');
 if(command.operation==='cancel'){epoch++;cancelled=true;r.ok=true;return r;}
 cancelled=false;const taskEpoch=++epoch;
 if(document.visibilityState!=='visible'||!document.hasFocus())throw Error('Target page lost focus; stopped before input');
 if(command.operation==='inspect') {
 r.ok=r.state==='ready';r.prompt=prompt()?.value ?? prompt()?.innerText ?? '';r.submitted=users().at(-1)===command.text;
 r.detail=r.ok?'Semantic interface observed':`Interface state: ${r.state}`;return r;
 }
 if(r.state!=='ready'){r.detail=`Interface state: ${r.state}`;return r;}
 if(command.operation==='fillPrompt') {
 const e=prompt();if(!e)throw Error('A unique prompt field was not found');
 const current=e.value??e.innerText;
 if(current.trim() && current!==command.text)throw Error('Prompt contains different text; clear it yourself before continuing');
 fill(e,command.text);await new Promise(r=>setTimeout(r,100));
 r.ok=exact(prompt(),command.text);r.prompt=prompt()?.value??prompt()?.innerText;r.detail=r.ok?'Exact prompt verified':'Prompt value did not match';
 }
 if(command.operation==='submitPrompt') {
 const e=prompt();if(!e||!exact(e,command.text))throw Error('Exact prompt verification failed; no submission');
 if(users().at(-1)===command.text)throw Error('An identical recent user message exists; submission outcome requires review');
 const button=unique(find('button',/^(send|send message|send prompt|send-button)(?:\s+send-button)?$/i));
 if(!button||button.disabled)throw Error('Unique enabled send control unavailable');
 if(!document.hasFocus())throw Error('Focus changed before submission');
 button.click();
 const acknowledged=await wait(()=>users().at(-1)===command.text && (!prompt() || !(prompt().value??prompt().innerText).trim()),taskEpoch);
 r.ok=!!acknowledged;r.submitted=!!acknowledged;r.detail=acknowledged?'User message appeared and composer cleared':'Submission attempted; acknowledgement unavailable. Do not retry automatically.';
 }
 if(command.operation==='gmailDraft') {
 if(!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(command.recipient))throw Error('Exact recipient address required');
 let boxes=[...document.querySelectorAll('[role="dialog"]')].filter(visible).filter(e=>e.querySelector('[name="subjectbox"]'));
 if(boxes.length)throw Error('A compose draft is already open. Review it before creating another draft.');
 const compose=unique(find('[role="button"],button',/^compose$/i));if(!compose)throw Error('Unique Compose control unavailable');compose.click();
 const box=await wait(()=>unique([...document.querySelectorAll('[role="dialog"]')].filter(visible).filter(e=>e.querySelector('[name="subjectbox"]'))),taskEpoch);
 if(!box)throw Error('Compose dialog unavailable');
 const to=unique([...box.querySelectorAll('input')].filter(visible).filter(e=>e.name==='to'||/to recipients/i.test(label(e))));
 const subject=box.querySelector('[name="subjectbox"]');
 const body=unique(find('[contenteditable="true"][role="textbox"]',/message body/i,box));
 if(cancelled||epoch!==taskEpoch||!document.hasFocus())throw Error('Task cancelled or focus changed');
 if(!to||!subject||!body)throw Error('Compose fields could not be identified');
 fill(to,command.recipient);to.dispatchEvent(new KeyboardEvent('keydown',{key:'Enter',code:'Enter',bubbles:true}));to.blur();
 fill(subject,command.subject);fill(body,command.text);body.blur();
 const saved=await wait(()=>{
 const emails=[...box.querySelectorAll('[email],[data-hovercard-id]')].map(e=>e.getAttribute('email')??e.getAttribute('data-hovercard-id'));
 const actualRecipient=emails.includes(command.recipient) || to.value===command.recipient;
 const saveSignal=find('[role="status"],span,div',/^(saved to drafts|draft saved|all changes saved)$/i,box).length>0;
 return actualRecipient && subject.value===command.subject && exact(body,command.text) && saveSignal;
 },taskEpoch);
 r.ok=!!saved;r.draftSaved=!!saved;r.recipient=command.recipient;r.body=text(body);r.detail=saved?'Recipient, body and saved-draft indicator verified; message remains unsent':'Compose populated; saved-draft evidence unavailable. Inspect the draft yourself. No send action was issued.';
 }
 return r;
 }catch(error){r.detail=String(error.message).slice(0,4096);return r;}
 })().then(respond);return true;
 });
})();
