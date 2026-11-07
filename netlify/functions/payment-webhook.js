// POST /.netlify/functions/payment-webhook — notification du prestataire de paiement
// Signature vérifiée côté serveur (HMAC-SHA256) + montant vérifié au centime en base + anti-doublon.
const { rpc, rest } = require('./_lib/supa');
const { json, rawBody, siteUrl } = require('./_lib/http');
const { verifyWebhook, provider } = require('./_lib/payment');
const { afterPaid } = require('./_lib/actions');
const { notify } = require('./_lib/ntfy');

exports.handler = async (event) => {
  if(event.httpMethod !== 'POST') return json(405, { error: 'METHODE' });
  const raw = rawBody(event);
  if(raw.length > 50000) return json(413, { error: 'TROP_GROS' });
  let v;
  try{ v = verifyWebhook(event.headers, raw); }catch(e){ console.error(e.message); return json(500, { error: 'CONFIG' }); }
  if(!v.ok){ console.warn('webhook refusé', v.error); return json(400, { error: v.error }); }
  const ev = v.event;
  if(!ev.order_id) return json(400, { error: 'REFERENCE' });

  if(ev.status !== 'paid'){
    await rest('paiements', { method: 'POST', body: { order_id: ev.order_id, provider: provider(), provider_ref: ev.ref, event_id: null, montant: ev.amount || 0, statut: 'failed', details: { event: ev.id || null } }, prefer: 'return=minimal' }).catch(() => {});
    await rest('orders?id=eq.' + encodeURIComponent(ev.order_id) + '&payment_status=neq.paid', { method: 'PATCH', body: { payment_status: 'failed' }, prefer: 'return=minimal' }).catch(() => {});
    return json(200, { ok: true, statut: 'echec_enregistre' });
  }

  let r;
  try{
    r = await rpc('marquer_payee_srv', { p_order: ev.order_id, p_provider: provider(), p_ref: ev.ref, p_montant: ev.amount, p_event: ev.id || null, p_details: null });
  }catch(e){
    const code = String(e.message);
    console.error('marquer_payee', code);
    if(code === 'ORDER_NOT_FOUND') return json(200, { ok: false, error: code });
    return json(500, { error: 'ERREUR' });                // le prestataire réessaiera
  }
  if(r === 'MONTANT_DIFFERENT'){
    await notify({ title: '⚠️ Paiement au mauvais montant', message: 'Commande n° ' + ev.order_id + ' : ' + ev.amount + ' € reçus. Vérifie dans l\'admin.', tags: ['warning'] });
    return json(200, { ok: false, error: r });             // 200 : inutile que le prestataire renvoie la même notification
  }
  const site = siteUrl(event);
  if(r === 'OK') await afterPaid(ev.order_id, site);
  if(r === 'ANNULEE_A_REMBOURSER') await notify({ title: '⚠️ Paiement reçu sur une commande annulée', message: 'Commande n° ' + ev.order_id + ' : pense à rembourser le client.', tags: ['warning'] });
  return json(200, { ok: true, resultat: r });
};
