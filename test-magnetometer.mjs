import assert from 'node:assert/strict';import vm from 'node:vm';import {readFileSync} from 'node:fs';import {MagneticBaseline,observedMagneticHz} from './dist/core.mjs';
const js=readFileSync('dist/app.mjs','utf8'),code=js.slice(js.indexOf('const magnetic='),js.indexOf('const magCapability='));
const els=new Map(),$=id=>{if(!els.has(id))els.set(id,{textContent:'',disabled:false,value:'15'});return els.get(id)};
let now=100,sensor,timers=[],intervals=[],policy=false;
class Magnetometer{constructor(){sensor=this;this.handlers={}}addEventListener(n,f){this.handlers[n]=f}start(){this.started=true}stop(){this.stopped=true}read(x,y,z){Object.assign(this,{x,y,z});this.handlers.reading()}}
const ctx=vm.createContext({$,state:{demo:false},window:{isSecureContext:true,Magnetometer},Magnetometer,MagneticBaseline,observedMagneticHz,performance:{now:()=>now},Number,Math,setTimeout:f=>{timers.push(f);return timers.length},clearTimeout(){},setInterval:f=>intervals.push(f),sensorBlocked:()=>policy,error:e=>e.message,toast(){}});
vm.runInContext(code+'\nthis.mag=magnetic;',ctx);
$('magStart').onclick();assert(sensor.started);assert.equal(ctx.mag.vector,null);sensor.read(null,1,2);assert.equal(ctx.mag.vector,null);
sensor.read(3,4,0);intervals[0]();assert.equal($('magX').textContent,'3.0 µT');assert.equal($('calibrate').disabled,false);
now+=1600;intervals[0]();assert.equal($('magX').textContent,'—');assert.equal($('calibrate').disabled,true);
sensor.handlers.error({error:new Error('denied')});assert.equal(ctx.mag.vector,null);assert.equal(ctx.mag.sensor,null);assert(sensor.stopped);
$('magStart').onclick();const old=sensor;timers.at(-1)();assert.equal(ctx.mag.sensor,null);assert($('magStatus').textContent.includes('5 секунд'));
$('magStart').onclick();const current=sensor;old.handlers.error({error:new Error('late')});assert.equal(ctx.mag.sensor,current);ctx.stopMagnetic();
delete ctx.window.Magnetometer;assert(ctx.magneticUnavailable().includes('API дэмжихгүй'));ctx.window.Magnetometer=Magnetometer;policy=true;assert(ctx.magneticUnavailable().includes('policy'));policy=false;ctx.window.isSecureContext=false;assert(ctx.magneticUnavailable().includes('HTTPS'));
console.log('PASS: magnetic supported/unsupported API, null values, true vector, stale data, error cleanup, timeout and obsolete callbacks. Mocked API; hardware NOT tested.');
