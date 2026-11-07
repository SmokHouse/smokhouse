// Petites aides HTTP communes aux fonctions
function json(status, obj, extra){
  return { statusCode: status, headers: Object.assign({ 'Content-Type': 'application/json; charset=utf-8', 'Cache-Control': 'no-store' }, extra || {}), body: JSON.stringify(obj) };
}
function rawBody(event){
  if(!event.body) return '';
  return event.isBase64Encoded ? Buffer.from(event.body, 'base64').toString('utf8') : event.body;
}
function parseJson(event, maxBytes){
  const raw = rawBody(event);
  if(raw.length > (maxBytes || 20000)) throw Object.assign(new Error('TROP_GROS'), { http: 413 });
  try{ return raw ? JSON.parse(raw) : {}; }catch(e){ throw Object.assign(new Error('JSON_INVALIDE'), { http: 400 }); }
}
function bearer(event){
  const h = event.headers || {};
  const a = h.authorization || h.Authorization || '';
  const m = /^Bearer\s+(.+)$/i.exec(a);
  return m ? m[1].trim() : null;
}
function siteUrl(event){
  const env = process.env.SITE_URL || process.env.URL;
  if(env) return env.replace(/\/$/, '');
  const h = (event && event.headers) || {};
  return 'https://' + (h.host || 'localhost');
}
const eur = (n) => (Math.round(Number(n || 0) * 100) / 100).toFixed(2).replace('.', ',') + ' €';
const esc = (s) => String(s == null ? '' : s).replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));

module.exports = { json, rawBody, parseJson, bearer, siteUrl, eur, esc };
