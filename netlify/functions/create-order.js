// POST /.netlify/functions/create-order — crée une commande (livraison locale ou expédition France)
// Le navigateur envoie seulement : produits + grammes, coordonnées, mode. TOUT le reste est recalculé en base.
const { rpc, rest, getUser } = require('./_lib/supa');
const { json, parseJson, bearer, siteUrl, eur } = require('./_lib/http');
const { notify } = require('./_lib/ntfy');
const { sendEmail, tplConfirmation } = require('./_lib/email');
const { createPayment } = require('./_lib/payment');
const { stamp } = require('./_lib/actions');

const MESSAGES = {
  MODE_INVALIDE: 'Choisis un mode de livraison.',
  PANIER_VIDE: 'Ton panier est vide.',
  PANIER_TROP_GRAND: 'Trop de produits différents dans le panier.',
  COORDONNEES_MANQUANTES: 'Prénom et téléphone obligatoires.',
  ADRESSE_MANQUANTE: 'Indique ton adresse de livraison.',
  HORS_ZONE: "La livraison locale est réservée à la Haute-Loire (code postal 43…). Pour le reste de la France, choisis l'expédition.",
  EXPEDITION_INACTIVE: "L'expédition partout en France n'est pas encore ouverte.",
  METHODE_INVALIDE: 'Choisis livraison à domicile ou en point relais.',
  EMAIL_MANQUANT: "Une adresse e-mail valide est obligatoire pour l'expédition (paiement et suivi du colis).",
  ADRESSE_INCOMPLETE: 'Adresse incomplète : nom, rue, code postal (5 chiffres) et ville.',
  RELAIS_MANQUANT: 'Choisis ton point relais (nom, adresse et code postal).',
  QUANTITE_INVALIDE: 'Quantité invalide pour {p}.',
  PRODUIT_INDISPONIBLE: "{p} n'est plus disponible.",
  PRODUIT_NON_EXPEDIABLE: "{p} n'est pas disponible à l'expédition, seulement en livraison locale.",
  PRIX_INCONNU: "{p} n'a pas de prix configuré.",
  STOCK_INSUFFISANT: 'Stock insuffisant pour {p} : il reste {n} g.'
};
const REWARD_ERRORS = ['REWARD_NOT_FOUND', 'MIN_ACHAT', 'NOT_ENOUGH_POINTS'];

const str = (v, max) => (v == null ? '' : String(v)).trim().slice(0, max || 200);

function cleanItems(items){
  const out = {};
  if(!items || typeof items !== 'object' || Array.isArray(items)) return out;
  Object.keys(items).slice(0, 25).forEach(k => {
    if(!/^[a-z0-9_-]{1,40}$/i.test(k)) return;
    const g = Number(items[k]);
    if(isFinite(g)) out[k] = Math.round(g * 10) / 10;
  });
  return out;
}

async function friendly(code){
  const [base, pid, n] = String(code).split(':');
  let msg = MESSAGES[base];
  if(!msg) return null;
  let name = pid || '';
  if(pid){ try{ const r = await rest('menu_produits?product_id=eq.' + encodeURIComponent(pid) + '&select=nom'); if(r && r[0]) name = r[0].nom; }catch(e){} }
  return msg.replace('{p}', name).replace('{n}', n || '0');
}

exports.handler = async (event) => {
  if(event.httpMethod !== 'POST') return json(405, { error: 'METHODE' });
  let b;
  try{ b = parseJson(event, 20000); }catch(e){ return json(e.http || 400, { error: e.message }); }

  const user = await getUser(bearer(event));
  const mode = b.mode === 'france' ? 'france' : b.mode === 'local' ? 'local' : '';
  const p = {
    mode,
    items: cleanItems(b.items),
    customer_id: user ? user.id : null,                        // jamais pris dans le corps de la requête
    customer_email: str(b.email, 120) || (user && user.email) || '',
    name: str(b.name, 80), phone: str(b.phone, 30), notes: str(b.notes, 500)
  };
  if(mode === 'local'){
    p.address = str(b.address, 300); p.postal_code = str(b.postal_code, 5);
  } else if(mode === 'france'){
    const a = b.ship_address || {};
    p.shipping_method = b.shipping_method === 'relais' ? 'relais' : b.shipping_method === 'domicile' ? 'domicile' : '';
    p.ship_address = { nom: str(a.nom, 80), ligne1: str(a.ligne1, 150), ligne2: str(a.ligne2, 150), cp: str(a.cp, 5), ville: str(a.ville, 80) };
    if(p.shipping_method === 'relais' && b.relay_point){
      const r = b.relay_point;
      p.relay_point = { id: str(r.id, 40), nom: str(r.nom, 120), adresse: str(r.adresse, 200), cp: str(r.cp, 5), ville: str(r.ville, 80) };
    }
  }
  const reward = parseInt(b.reward_points, 10);
  if(user && reward > 0) p.reward_points = reward;

  let order, rewardWarning = null;
  try{
    order = await rpc('creer_commande_srv', { p });
  }catch(e){
    const code = String(e.message || '');
    if(REWARD_ERRORS.includes(code) && p.reward_points){
      // La commande passe quand même, sans la récompense
      delete p.reward_points;
      rewardWarning = code === 'MIN_ACHAT' ? "Récompense non appliquée : montant minimum d'achat non atteint." : 'Récompense non appliquée (points insuffisants).';
      try{ order = await rpc('creer_commande_srv', { p }); }
      catch(e2){ const m = await friendly(e2.message); return json(m ? 400 : 500, { error: String(e2.message).split(':')[0], message: m || 'Erreur, réessaie.' }); }
    } else {
      const m = await friendly(code);
      if(!m) console.error('create-order', code, e.details || '');
      return json(m ? 400 : 500, { error: code.split(':')[0], message: m || 'Erreur, réessaie dans un instant.' });
    }
  }

  const site = siteUrl(event);
  let paymentUrl = null;
  if(order.mode === 'france'){
    try{
      const pay = await createPayment(order, site);
      if(pay){
        paymentUrl = pay.url;
        await rest('paiements', { method: 'POST', body: { order_id: String(order.id), provider: process.env.PAYMENT_PROVIDER, provider_ref: pay.ref, montant: order.total, statut: 'created' }, prefer: 'return=minimal' });
        await rest('orders?id=eq.' + encodeURIComponent(order.id), { method: 'PATCH', body: { payment_ref: pay.ref, payment_provider: process.env.PAYMENT_PROVIDER }, prefer: 'return=minimal' });
      }
    }catch(e){ console.error('paiement', e.message); }
  }

  // Notification téléphone (type de commande bien visible) + e-mail de confirmation — en parallèle
  const isFr = order.mode === 'france';
  const tasks = [
    notify({
      title: isFr ? '📦 Nouvelle commande — EXPÉDITION FRANCE' : '🚲 Nouvelle commande — LIVRAISON LOCALE',
      message: (order.customer_name || '') + ' — ' + (order.customer_phone || '') + '\n' + (order.address || '') + '\n' + (order.items || '') + (order.reward_label ? '\n🎁 ' + order.reward_label : '') + (isFr ? '\n⏳ En attente de paiement' : ''),
      tags: isFr ? ['package'] : ['herb', 'bike'], priority: isFr ? 3 : 5, click: site + '/admin/'
    })
  ];
  if(order.customer_email){
    const t = tplConfirmation(order, site, paymentUrl);
    tasks.push(sendEmail({ to: order.customer_email, toName: order.customer_name, subject: t.subject, html: t.html, orderId: order.id, type: 'confirmation' })
      .then(r => { if(r.ok) return stamp(order.id, 'confirmation_sent_at'); }));
  }
  await Promise.allSettled(tasks);

  return json(200, {
    ok: true, payment_url: paymentUrl, reward_warning: rewardWarning,
    order: { id: order.id, mode: order.mode, status: order.status, subtotal: order.subtotal, shipping_cost: order.shipping_cost, total: order.total,
             items: order.items, reward_label: order.reward_label, reward_points: order.reward_points, points_restants: order.points_restants,
             total_txt: eur(order.total) }
  });
};
