document.querySelector('#identity').textContent=chrome.runtime.id;
for(const [id,origin] of [['chatgpt','https://chatgpt.com/*'],['gmail','https://mail.google.com/*']]) document.getElementById(id).onclick=async()=>{const ok=await chrome.permissions.request({origins:[origin]});document.querySelector('#status').textContent=ok?'Site permission granted.':'Permission declined.';};
document.getElementById('connect').onclick=async()=>{await chrome.runtime.sendMessage({connect:true});document.querySelector('#status').textContent='Connection requested. Check Voicey Computer Use settings.';};
