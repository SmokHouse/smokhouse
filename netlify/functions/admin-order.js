// POST /.netlify/functions/admin-order — actions de l'app admin qui envoient un e-mail
// Réservé à un compte admin (jeton Supabase vérifié + profil is_admin).
const { rpc, getUser, isAdmin, getOrder } = require('./_lib/supa');
const { json, parseJson, bearer, siteUrl } = require('./_lib/http');
const { afterPaid, afterShipped, sendInvoice } = require('./_lib/actions');
const { sendEmail, layout } = require('./_lib/email');

exports.handler = async (event) => {
  if(event.httpMethod !== 'POST') return json(405, { error: 'METHODE' });
  const user = await getUser(bearer(event));
  if(!user || !(await isAdmin(user.id))) return json(403, { error: 'NOT_ADMIN' });
  let b; try{ b = parseJson(event, 5000); }catch(e){ return json(400, { error: e.message }); }
  const site = siteUrl(event), id = String(b.id || '');

  try{
    switch(b.action){
      case 'expedier': {
        const o = await rpc('statut_commande_srv', { p_order: id, p_statut: 'expediee', p_info: { tracking_number: String(b.tracking_number || '').trim(), carrier: b.carrier || '', tracking_url: b.tracking_url || '' } });
        const mail = await afterShipped(id, site);
        return json(200, { ok: true, order: o, email: mail.ok, email_error: mail.error || null });
      }
      case 'renvoyer-suivi': {
        const mail = await afterShipped(id, site);
        return json(200, { ok: mail.ok, email: mail.ok, email_error: mail.error || null });
      }
      case 'marquer-payee': {               // paiement reçu hors ligne (virement, espèces…)
        const o = await getOrder(id);
        if(!o) return json(404, { error: 'ORDER_NOT_FOUND' });
        const moyen = ['virement', 'carte', 'especes', 'autre'].includes(b.moyen) ? b.moyen : 'virement';
        const r = await rpc('marquer_payee_srv', { p_order: id, p_provider: moyen, p_ref: 'manuel-' + Date.now(), p_montant: o.total, p_event: null, p_details: { par: user.email } });
        if(r === 'OK') await afterPaid(id, site);
        return json(200, { ok: true, resultat: r, order: await getOrder(id) });
      }
      case 'envoyer-facture': {
        const mail = await sendInvoice(id, site);
        return json(200, { ok: mail.ok, email_error: mail.error || null });
      }
      case 'test-email': {
        const to = b.to || user.email;
        const r = await sendEmail({ to, subject: "Test e-mail Smok'house ✅", html: layout('Ça marche !', '<p>Les e-mails automatiques de la boutique sont bien configurés.</p>', site), type: 'test' });
        return json(200, { ok: r.ok, email_error: r.error || null });
      }
      default: return json(400, { error: 'ACTION_INCONNUE' });
    }
  }catch(e){
    console.error('admin-order', b.action, e.message);
    return json(400, { error: String(e.message || 'ERREUR') });
  }
};
