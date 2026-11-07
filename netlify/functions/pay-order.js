// POST /.netlify/functions/pay-order { order_id, email? } — (re)lance le paiement d'une commande France en attente
const { rest, getUser, getOrder } = require('./_lib/supa');
const { json, parseJson, bearer, siteUrl } = require('./_lib/http');
const { createPayment, provider } = require('./_lib/payment');

exports.handler = async (event) => {
  if(event.httpMethod !== 'POST') return json(405, { error: 'METHODE' });
  let b; try{ b = parseJson(event, 2000); }catch(e){ return json(400, { error: e.message }); }
  const id = String(b.order_id || '').slice(0, 40);
  if(!id) return json(400, { error: 'ORDER_MANQUANT' });
  const user = await getUser(bearer(event));
  const o = await getOrder(id);
  // Le client doit être le propriétaire (compte) ou connaître l'e-mail de la commande (invité)
  const owner = o && (o.customer_id ? user && user.id === o.customer_id : (o.customer_email && String(b.email || '').trim().toLowerCase() === o.customer_email));
  if(!o || !owner) return json(404, { error: 'ORDER_NOT_FOUND', message: 'Commande introuvable.' });
  if(o.mode !== 'france' || o.status !== 'attente_paiement' || o.payment_status === 'paid') return json(400, { error: 'PAS_A_PAYER', message: 'Cette commande ne peut pas être payée en ligne.' });
  if(Date.now() - new Date(o.created_at).getTime() > 24 * 3600e3) return json(400, { error: 'EXPIREE', message: 'Commande expirée (plus de 24 h). Repasse-la depuis le panier.' });
  if(provider() === 'aucun') return json(400, { error: 'PAIEMENT_INDISPONIBLE', message: "Le paiement en ligne n'est pas encore ouvert : je te contacte pour le règlement." });
  try{
    const pay = await createPayment(o, siteUrl(event));
    await rest('paiements', { method: 'POST', body: { order_id: String(o.id), provider: provider(), provider_ref: pay.ref, montant: o.total, statut: 'created' }, prefer: 'return=minimal' });
    await rest('orders?id=eq.' + encodeURIComponent(o.id), { method: 'PATCH', body: { payment_ref: pay.ref, payment_provider: provider() }, prefer: 'return=minimal' });
    return json(200, { ok: true, payment_url: pay.url });
  }catch(e){ console.error(e); return json(500, { error: 'PAIEMENT_ERREUR', message: 'Paiement indisponible, réessaie plus tard.' }); }
};
