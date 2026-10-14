export const origins = new Set(['https://chatgpt.com', 'https://mail.google.com']);
export function validate(command) {
 if (!command || command.version !== 1 || typeof command.id !== 'string' || !/^[0-9a-f-]{36}$/i.test(command.id) || !['inspect','navigate','fillPrompt','submitPrompt','gmailDraft','cancel'].includes(command.operation)) throw Error('Invalid command schema');
 const keys = ['version','id','operation','url','text','recipient','subject'];
 if (Object.keys(command).some(k => !keys.includes(k))) throw Error('Unexpected command field');
 const url = new URL(command.url);
 if (!origins.has(url.origin) || url.username || url.password) throw Error('Unauthorized origin');
 for (const k of ['text','recipient','subject']) if (typeof command[k] !== 'string' || command[k].includes('\0')) throw Error('Invalid field');
 if (command.text.length > 16000 || command.subject.length > 500 || command.recipient.length > 254) throw Error('Oversized content');
 if (['fillPrompt','submitPrompt'].includes(command.operation) && url.hostname !== 'chatgpt.com') throw Error('Wrong prompt origin');
 if (command.operation === 'gmailDraft' && (url.hostname !== 'mail.google.com' || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(command.recipient) || !command.text)) throw Error('Invalid draft');
 return url;
}
