// Accès Supabase côté serveur (clé SECRÈTE lue dans les variables d'environnement Netlify, jamais dans le site)
const BASE = (process.env.SUPABASE_URL || 'https://qtagbmjzzmwxiptkgjmn.supabase.co').replace(/\/$/, '');

function key(){
  const k = process.env.SUPABASE_SERVICE_ROLE_KEY || process.env.SUPABASE_SECRET_KEY;
  if(!k) throw new Error('CONFIG_MANQUANTE: SUPABASE_SERVICE_ROLE_KEY');
  return k;
}
function headers(extra){
  const k = key();
  const h = { apikey: k, 'Content-Type': 'application/json' };
  // Nouvelle clé « sb_secret_… » : uniquement dans « apikey ». Ancienne clé JWT : aussi dans Authorization.
  if(!k.startsWith('sb_')) h.Authorization = 'Bearer ' + k;
  return Object.assign(h, extra || {});
}

class DbError extends Error {
  constructor(message, status, details){ super(message); this.status = status; this.details = details; }
}

async function call(path, opts){
  const res = await fetch(BASE + path, opts);
  const text = await res.text();
  let data = null; try{ data = text ? JSON.parse(text) : null; }catch(e){ data = text; }
  if(!res.ok){
    const msg = (data && (data.message || data.msg || data.error_description || data.error)) || ('HTTP_' + res.status);
    throw new DbError(String(msg), res.status, data);
  }
  return data;
}

// Requête REST (PostgREST). ex : rest('orders?id=eq.12&select=*')
function rest(path, { method = 'GET', body, prefer } = {}){
  const h = headers(prefer ? { Prefer: prefer } : null);
  return call('/rest/v1/' + path, { method, headers: h, body: body === undefined ? undefined : JSON.stringify(body) });
}

// Appel d'une fonction SQL. ex : rpc('creer_commande_srv', { p: {...} })
function rpc(fn, args){
  return call('/rest/v1/rpc/' + fn, { method: 'POST', headers: headers(), body: JSON.stringify(args || {}) });
}

// Utilisateur connecté à partir de son jeton (Authorization: Bearer …) — null si invalide
async function getUser(token){
  if(!token) return null;
  try{
    const res = await fetch(BASE + '/auth/v1/user', { headers: { apikey: key(), Authorization: 'Bearer ' + token } });
    if(!res.ok) return null;
    const u = await res.json();
    return u && u.id ? u : null;
  }catch(e){ return null; }
}

async function isAdmin(userId){
  if(!userId) return false;
  const rows = await rest('profiles?id=eq.' + encodeURIComponent(userId) + '&select=is_admin');
  return !!(rows && rows[0] && rows[0].is_admin);
}

async function getOrder(id){
  const rows = await rest('orders?id=eq.' + encodeURIComponent(id) + '&select=*');
  return rows && rows[0] ? rows[0] : null;
}

async function getInvoiceForOrder(id){
  const rows = await rest('factures?source=eq.commande&type=eq.facture&source_ref=eq.' + encodeURIComponent(id) + '&select=*&order=id.desc');
  if(!rows || !rows.length) return null;
  const avoirs = await rest('factures?type=eq.avoir&select=facture_origine');
  const annulees = new Set((avoirs || []).map(a => a.facture_origine));
  return rows.find(f => !annulees.has(f.numero)) || null;
}

module.exports = { rest, rpc, getUser, isAdmin, getOrder, getInvoiceForOrder, DbError, BASE };
