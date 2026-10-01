export const clamp=(v,a,b)=>Math.max(a,Math.min(b,v));
export function dbfs(samples){if(!samples.length)return -96;let s=0;for(const v of samples)s+=v*v;return clamp(20*Math.log10(Math.max(Math.sqrt(s/samples.length),1e-8)),-96,0)}
export function acceleration(a){if(!a||![a.x,a.y,a.z].every(Number.isFinite))return null;return Math.hypot(a.x,a.y,a.z)}
export function csv(rows){const cell=v=>{const s=v==null?'':String(v);return '"'+s.replaceAll('"','""')+'"'};return '\uFEFF'+[['utc','elapsed_s','mode','audio_dbfs','motion_ms2','magnetic_ut','mag_x_ut','mag_y_ut','mag_z_ut','baseline_ut','baseline_sigma_ut','observed_hz','delta_ut','magnetic_source','event'],...rows.map(r=>[r.utc,r.elapsed,r.mode,r.audio,r.motion,r.mag,r.magX,r.magY,r.magZ,r.magBaseline,r.magSigma,r.magHz,r.magDelta,r.magSource,r.event])].map(r=>r.map(cell).join(',')).join('\r\n')}
export class MagneticBaseline {
 constructor(){this.sigma=null;this.count=0;this.value=null;this.samples=[];this.calibrating=false;this.armed=true}
 start(now){this.sigma=null;this.count=0;this.value=null;this.samples=[];this.started=now;this.calibrating=true;this.armed=true}
 add(value,now){if(!Number.isFinite(value))return false;if(!this.calibrating)return false;this.samples.push(value);if(now-this.started>=3000&&this.samples.length>=20){const sorted=[...this.samples].sort((a,b)=>a-b),n=sorted.length;this.value=n%2?sorted[(n-1)/2]:(sorted[n/2-1]+sorted[n/2])/2;const mean=this.samples.reduce((a,b)=>a+b,0)/n;this.sigma=Math.sqrt(this.samples.reduce((a,b)=>a+(b-mean)**2,0)/n);this.count=n;this.calibrating=false;return true}return false}
 check(value,threshold){if(this.value==null||!Number.isFinite(value))return false;const delta=Math.abs(value-this.value);if(delta<threshold*.8)this.armed=true;if(delta>=threshold&&this.armed){this.armed=false;return true}return false}
}
export function observedMagneticHz(stamps){if(stamps.length<3)return null;const elapsed=(stamps.at(-1)-stamps[0])/1000;return elapsed>=.5?(stamps.length-1)/elapsed:null}
