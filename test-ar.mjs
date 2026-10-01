// Статик шалгалт: JS-ийн $('id') бүр HTML-д байгаа эсэх (GPT хувилбарын тестээс)
import assert from 'node:assert/strict'; import { readFileSync } from 'node:fs';
const html = readFileSync(new URL('./dist/ar.html', import.meta.url), 'utf8');
const ids = new Set([...html.matchAll(/id="([^"]+)"/g)].map(m => m[1]));
const dynamic = new Set(['measC','exR','exV','torchC','stampC','lensB','sensR','sensV','taC','demoC','csvB','setClose','evShare','evDl','evClose','evPreview','sesName','sesNote','sesFlag','sesAudio','sesSave','sesEvents','sesHistory','sesClose']);
for (const [, id] of html.matchAll(/\$\('([^']+)'\)/g)) assert(ids.has(id) || dynamic.has(id), 'Missing element ' + id);
assert(html.includes('ghost.webp')); console.log('PASS: DOM references, assets');
