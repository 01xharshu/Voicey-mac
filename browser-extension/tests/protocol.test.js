import test from 'node:test';
import assert from 'node:assert/strict';
import {validate} from '../protocol.js';
const base = () => ({version:1,id:'00000000-0000-0000-0000-000000000001',operation:'inspect',url:'https://chatgpt.com/',text:'',recipient:'',subject:''});
test('only explicit supported origins',()=>{for(const url of ['https://evil.test/','https://chatgpt.com.evil.test/','http://chatgpt.com/','https://user:pass@chatgpt.com/','https://chatgpt.com:8443/']) assert.throws(()=>validate({...base(),url}));assert.equal(validate(base()).origin,'https://chatgpt.com');});
test('schema rejects unknown operation and code injection interface',()=>{for(const value of [{...base(),operation:'eval'},{...base(),script:'alert(1)'},{...base(),text:123},{...base(),version:2},{...base(),text:'x'.repeat(16001)}])assert.throws(()=>validate(value));});
test('draft requires an explicit valid recipient',()=>{assert.throws(()=>validate({...base(),operation:'gmailDraft',url:'https://mail.google.com/',recipient:'Harsh Mishra',text:'Thank you'}));assert.doesNotThrow(()=>validate({...base(),operation:'gmailDraft',url:'https://mail.google.com/',recipient:'harsh@example.test',text:'Thank you'}));});
test('prompt operations cannot target Gmail',()=>assert.throws(()=>validate({...base(),operation:'submitPrompt',url:'https://mail.google.com/'})));
