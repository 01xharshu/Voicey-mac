import {validate} from './protocol.js';
let port;
const targetTabs = new Map();
function connect() {
 if (port) return;
 port = chrome.runtime.connectNative('local.voicey.browser');
 port.onDisconnect.addListener(() => { port = null; });
 port.onMessage.addListener(async command => {
 let reply = {version:1,id:command.id,ok:false,url:command.url,state:'error',detail:'Invalid command'};
 try {
 const url=validate(command),pattern=url.origin+'/*';
 if(command.operation==='cancel') {
 const tabId=targetTabs.get(url.origin);
 if(tabId) await chrome.tabs.sendMessage(tabId,command).catch(()=>{});
 return;
 }
 if (!await chrome.permissions.contains({origins:[pattern]})) throw Error('Grant this site in the Voicey extension popup');
 let tab;
 const pinned=targetTabs.get(url.origin);
 if (pinned) { try {tab=await chrome.tabs.get(pinned);} catch {targetTabs.delete(url.origin);} }
 // Reuse a visible existing session. Never create a hidden parallel browser.
 if (!tab) tab=(await chrome.tabs.query({url:pattern})).sort((a,b)=>Number(b.active)-Number(a.active))[0];
 if (command.operation==='navigate') {
 if (!tab) tab=await chrome.tabs.create({url:command.url,active:true});
 else { if (new URL(tab.url).origin!==url.origin) throw Error('Target tab changed origin'); await chrome.tabs.update(tab.id,{active:true}); }
 targetTabs.set(url.origin,tab.id);
 await chrome.windows.update(tab.windowId,{focused:true});
 const current=await chrome.tabs.get(tab.id);
 reply={...reply,ok:new URL(current.url || current.pendingUrl).origin===url.origin,url:current.url || current.pendingUrl,state:current.status==='complete'?'ready':'loading',detail:'Actual browser destination observed'};
 } else {
 if (!tab || new URL(tab.url).origin!==url.origin) throw Error('No authorized target tab; navigate first');
 targetTabs.set(url.origin,tab.id);
 if (!tab.active) throw Error('The target tab is no longer active; return to it to continue');
 const window=await chrome.windows.get(tab.windowId);
 if (!window.focused) throw Error('The target browser window lost focus');
 if (tab.status!=='complete') reply={...reply,url:tab.url,state:'loading',detail:'Page loading'};
 else {
 await chrome.scripting.executeScript({target:{tabId:tab.id},files:['page.js']});
 reply=await chrome.tabs.sendMessage(tab.id,command);
 const current=await chrome.tabs.get(tab.id);
 if (new URL(current.url).origin!==url.origin) throw Error('Page changed origin during operation');
 }
 }
 } catch(error) {reply.detail=String(error.message).slice(0,4096);}
 port?.postMessage(reply);
 });
}
chrome.runtime.onStartup.addListener(connect);
chrome.runtime.onInstalled.addListener(connect);
chrome.runtime.onMessage.addListener((m,s,respond)=>{if(m?.connect){connect();respond({connected:!!port});}});
connect();
