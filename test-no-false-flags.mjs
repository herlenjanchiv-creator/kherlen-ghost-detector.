import assert from 'node:assert/strict';import {readFileSync} from 'node:fs';const js=readFileSync('dist/app.mjs','utf8');
// Regression: absent microphone data must not be coerced to zero and trigger a flag.
const {default:vm}=await import('node:vm');const {dbfs}=await import('./dist/core.mjs');
const tickCode=js.slice(js.indexOf('function tick('),js.indexOf("$('camera').onclick"));
const els=new Map(),$=id=>{if(!els.has(id))els.set(id,{textContent:'',style:{},value:'15'});return els.get(id)};
let flags=[],now=10000;const st={demo:false,analyser:null,motion:null,motionAt:0,session:{name:'Object A',started:0},rows:[]};
const ctx=vm.createContext({$,state:st,performance:{now:()=>now},motionControl:{phase:'off'},magnetic:{vector:null,at:0,stamps:[],baseline:{value:null,sigma:null}},graphRows:[],dbfs,clamp:(v,a,b)=>Math.max(a,Math.min(b,v)),Date,Number,Math,Float32Array,addFlag:(m)=>flags.push(m),draw(){},toast(){},endSession(){}});
vm.runInContext(tickCode,ctx);ctx.tick();now+=4000;ctx.tick();assert.equal(flags.length,0);assert.equal(st.rows[0].audio,null);
st.analyser={fftSize:2,getFloatTimeDomainData(a){a.fill(1)}};ctx.tick();assert.equal(flags.at(-1),'Дууны түвшин өссөн');
st.analyser=null;st.motion=2;st.motionAt=now;ctx.tick();assert.equal(flags.at(-1),'Утасны хөдөлгөөн нэмэгдсэн');
console.log('PASS: missing audio creates no false automatic flag; measured audio/motion still trigger.');
