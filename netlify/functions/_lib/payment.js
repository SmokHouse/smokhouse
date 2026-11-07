/* =====================================================================
   Module de paiement GÉNÉRIQUE
   Tu choisis le prestataire avec la variable PAYMENT_PROVIDER :
     • « aucun »   (défaut) : pas de paiement en ligne. Tu marques la commande payée à la main dans l'admin (virement…).
     • « test »    : page de paiement SIMULÉE pour tester tout le parcours. ⚠️ Jamais en production.
     • « generique » : API d'un prestataire qui accepte ton activité. Il faut :
          PAYMENT_API_URL     → adresse de création d'un paiement chez lui
          PAYMENT_API_KEY     → sa clé secrète
          PAYMENT_WEBHOOK_SECRET → secret de signature des notifications (HMAC-SHA256)
       La plupart des prestataires suivent ce schéma ; il suffira d'adapter les deux fonctions
       createGeneric() et verifyGeneric() à leur documentation.
   ===================================================================== */
const crypto = require('crypto');

const provider = () => (process.env.PAYMENT_PROVIDER || 'aucun').toLowerCase();
const cents = (n) => Math.round(Number(n) * 100);
function hmac(secret, data){ return crypto.createHmac('sha256', secret).update(data).digest('hex'); }
function safeEq(a, b){
  const x = Buffer.from(String(a || ''), 'utf8'), y = Buffer.from(String(b || ''), 'utf8');
  return x.length === y.length && crypto.timingSafeEqual(x, y);
}
function secret(){
  const s = process.env.PAYMENT_WEBHOOK_SECRET;
  if(!s || s.length < 16) throw new Error('CONFIG_MANQUANTE: PAYMENT_WEBHOOK_SECRET (16 caractères minimum)');
  return s;
}

// Crée un paiement → { url, ref } ou null si pas de paiement en ligne
async function createPayment(order, site){
  const p = provider();
  if(p === 'aucun' || p === 'none' || p === '') return null;
  if(p === 'test'){
    const ref = 'test_' + order.id + '_' + Date.now();
    const token = hmac(secret(), ['test', order.id, cents(order.total), ref].join('|'));
    const q = new URLSearchParams({ o: String(order.id), a: String(cents(order.total)), r: ref, t: token });
    return { url: site + '/paiement-test.html?' + q.toString(), ref };
  }
  if(p === 'generique') return createGeneric(order, site);
  throw new Error('PAYMENT_PROVIDER inconnu : ' + p);
}

async function createGeneric(order, site){
  const res = await fetch(process.env.PAYMENT_API_URL, {
    method: 'POST',
    headers: { Authorization: 'Bearer ' + process.env.PAYMENT_API_KEY, 'Content-Type': 'application/json' },
    body: JSON.stringify({
      amount: cents(order.total), currency: 'EUR', reference: String(order.id),
      description: "Commande Smok'house n° " + order.id,
      customer_email: order.customer_email || undefined,
      return_url: site + '/?paiement=ok&commande=' + order.id + '#compte',
      cancel_url: site + '/?paiement=annule&commande=' + order.id + '#compte',
      webhook_url: site + '/.netlify/functions/payment-webhook'
    })
  });
  const data = await res.json().catch(() => ({}));
  if(!res.ok || !data.url) throw new Error('PAIEMENT_CREATION_ECHEC ' + res.status);
  return { url: data.url, ref: data.id || data.payment_id || null };
}

// Vérifie une notification (webhook) → { ok, event: { id, order_id, ref, amount (€), status } }
function verifyWebhook(headers, raw){
  const p = provider();
  const h = {}; Object.keys(headers || {}).forEach(k => { h[k.toLowerCase()] = headers[k]; });
  if(p === 'test'){
    let b; try{ b = JSON.parse(raw); }catch(e){ return { ok: false, error: 'JSON' }; }
    const expected = hmac(secret(), ['test', b.order_id, b.amount_cents, b.ref].join('|'));
    if(!safeEq(expected, b.token)) return { ok: false, error: 'SIGNATURE' };
    return { ok: true, event: { id: 'evt_' + b.ref, order_id: String(b.order_id), ref: b.ref, amount: Number(b.amount_cents) / 100, status: b.status === 'failed' ? 'failed' : 'paid' } };
  }
  if(p === 'generique') return verifyGeneric(h, raw);
  return { ok: false, error: 'AUCUN_PRESTATAIRE' };
}

// Format générique : en-tête « x-signature: sha256=<hex> » = HMAC-SHA256(corps brut, PAYMENT_WEBHOOK_SECRET)
// Corps : { id, type: "payment.succeeded" | "payment.failed", data: { id, reference, amount (centimes), currency, status } }
function verifyGeneric(h, raw){
  const sig = String(h['x-signature'] || h['x-webhook-signature'] || '').replace(/^sha256=/, '');
  if(!sig || !safeEq(hmac(secret(), raw), sig)) return { ok: false, error: 'SIGNATURE' };
  let b; try{ b = JSON.parse(raw); }catch(e){ return { ok: false, error: 'JSON' }; }
  const d = b.data || {};
  if(d.currency && String(d.currency).toUpperCase() !== 'EUR') return { ok: false, error: 'DEVISE' };
  const paid = /succeeded|paid|captured/i.test(String(b.type || '') + ' ' + String(d.status || ''));
  return { ok: true, event: { id: String(b.id || ''), order_id: String(d.reference || ''), ref: d.id || null, amount: Number(d.amount) / 100, status: paid ? 'paid' : 'failed' } };
}

module.exports = { provider, createPayment, verifyWebhook, hmac, cents };
