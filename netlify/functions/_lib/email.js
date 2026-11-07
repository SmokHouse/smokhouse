// E-mails automatiques via Brevo (clé API dans la variable BREVO_API_KEY)
const { rest } = require('./supa');
const { eur, esc } = require('./http');

async function logEmail(orderId, type, to, ok, erreur){
  try{ await rest('emails_envoyes', { method: 'POST', body: { order_id: orderId == null ? null : String(orderId), type, destinataire: to, ok, erreur: erreur ? String(erreur).slice(0, 300) : null }, prefer: 'return=minimal' }); }
  catch(e){ console.error('log email', e.message); }
}

// attachments : [{ name: 'SH-2026-0001.pdf', content: Buffer }]
async function sendEmail({ to, toName, subject, html, attachments, orderId, type, replyTo }){
  if(!to){ return { ok: false, error: 'PAS_D_EMAIL' }; }
  const apiKey = process.env.BREVO_API_KEY;
  if(!apiKey){ await logEmail(orderId, type, to, false, 'BREVO_API_KEY manquante'); return { ok: false, error: 'BREVO_NON_CONFIGURE' }; }
  const body = {
    sender: { email: process.env.BREVO_SENDER_EMAIL, name: process.env.BREVO_SENDER_NAME || "Smok'house" },
    to: [{ email: to, name: toName || undefined }],
    subject, htmlContent: html
  };
  if(replyTo || process.env.BREVO_REPLY_TO) body.replyTo = { email: replyTo || process.env.BREVO_REPLY_TO };
  if(attachments && attachments.length) body.attachment = attachments.map(a => ({ name: a.name, content: Buffer.from(a.content).toString('base64') }));
  try{
    const res = await fetch('https://api.brevo.com/v3/smtp/email', { method: 'POST', headers: { 'api-key': apiKey, 'Content-Type': 'application/json', accept: 'application/json' }, body: JSON.stringify(body) });
    if(!res.ok){ const t = await res.text(); await logEmail(orderId, type, to, false, 'Brevo ' + res.status + ' ' + t); return { ok: false, error: 'BREVO_' + res.status }; }
    await logEmail(orderId, type, to, true, null);
    return { ok: true };
  }catch(e){ await logEmail(orderId, type, to, false, e.message); return { ok: false, error: e.message }; }
}

/* ---------- Modèles ---------- */
function layout(title, inner, site){
  return `<!doctype html><html lang="fr"><body style="margin:0;background:#0A0C07;font-family:Arial,Helvetica,sans-serif;color:#F3EFDF;">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#0A0C07;padding:24px 12px;"><tr><td align="center">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="max-width:560px;background:#14170D;border:1px solid #2a3220;border-radius:14px;">
<tr><td style="padding:22px 24px 6px;font-family:Georgia,serif;font-size:22px;color:#8FE24C;">Smok'house</td></tr>
<tr><td style="padding:6px 24px 0;font-family:Georgia,serif;font-size:19px;color:#F3EFDF;">${esc(title)}</td></tr>
<tr><td style="padding:14px 24px 22px;font-size:14px;line-height:1.55;color:#E4DFCB;">${inner}</td></tr>
<tr><td style="padding:14px 24px;border-top:1px solid #2a3220;font-size:11px;color:#A8A38B;">Produits à base de CBD, THC &lt; 0,3 %, réservés aux personnes majeures. Ne pas conduire après consommation.<br><a href="${esc(site)}" style="color:#8FE24C;">${esc(site.replace(/^https?:\/\//, ''))}</a></td></tr>
</table></td></tr></table></body></html>`;
}
function btn(href, label){ return `<p style="margin:18px 0;"><a href="${esc(href)}" style="display:inline-block;background:#8FE24C;color:#0E1207;text-decoration:none;font-weight:bold;padding:12px 20px;border-radius:999px;">${esc(label)}</a></p>`; }
function recap(o){
  const lignes = Array.isArray(o.lignes_json) && o.lignes_json.length ? o.lignes_json
    : Object.entries(o.items_json || {}).map(([k, g]) => ({ designation: k, grammes: g, total: null }));
  const rows = lignes.map(l => `<tr><td style="padding:6px 0;border-bottom:1px solid #2a3220;">${esc(String(l.grammes).replace('.', ','))} g ${esc(l.designation)}</td><td align="right" style="padding:6px 0;border-bottom:1px solid #2a3220;white-space:nowrap;">${l.total != null ? eur(l.total) : ''}</td></tr>`).join('');
  const port = o.mode === 'france' ? `<tr><td style="padding:6px 0;">Livraison ${o.shipping_method === 'relais' ? 'en point relais' : 'à domicile'}</td><td align="right">${Number(o.shipping_cost) > 0 ? eur(o.shipping_cost) : 'Offerte'}</td></tr>` : '';
  const reward = o.reward_label ? `<tr><td style="padding:6px 0;color:#8FE24C;">🎁 ${esc(o.reward_label)} (-${o.reward_points} pts)</td><td align="right">Offert</td></tr>` : '';
  return `<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="font-size:14px;color:#E4DFCB;margin:8px 0;">${rows}${reward}${port}
<tr><td style="padding:10px 0 0;font-weight:bold;">Total</td><td align="right" style="padding:10px 0 0;font-weight:bold;color:#8FE24C;">${eur(o.total)}</td></tr></table>`;
}
const num = (o) => 'n° ' + o.id;

function tplConfirmation(o, site, paymentUrl){
  if(o.mode === 'france'){
    return { subject: `Commande ${num(o)} reçue — Smok'house`, html: layout('Merci pour ta commande !',
      `<p>Salut ${esc(o.customer_name || '')},</p><p>Ta commande <b>${num(o)}</b> (expédition France) est bien enregistrée.</p>${recap(o)}
      <p><b>Adresse :</b> ${esc(o.address || '')}</p>
      ${paymentUrl ? `<p>Il ne reste plus qu'à régler ta commande pour qu'on la prépare :</p>${btn(paymentUrl, 'Payer ma commande')}` : `<p>Elle sera préparée dès réception du paiement. Tu peux suivre son état dans ton espace client.</p>`}
      <p style="color:#A8A38B;font-size:12px;">Sans paiement sous 24 h, la réservation du stock est libérée.</p>`, site) };
  }
  return { subject: `Commande ${num(o)} reçue — livraison locale`, html: layout('Commande bien reçue ✅',
    `<p>Salut ${esc(o.customer_name || '')},</p><p>Ta commande <b>${num(o)}</b> en <b>livraison locale</b> (vélo / scooter, jour même) est bien arrivée. Je te recontacte très vite au <b>${esc(o.customer_phone || '')}</b> pour l'heure de livraison.</p>
    ${recap(o)}<p><b>Adresse :</b> ${esc(o.address || '')}<br><b>Paiement :</b> à la livraison (espèces ou carte).</p>
    <p style="color:#A8A38B;font-size:12px;">Remise en main propre à un majeur, pièce d'identité pouvant être demandée.</p>`, site) };
}
function tplPaiement(o, site, facture){
  return { subject: `Paiement reçu — commande ${num(o)}`, html: layout('Paiement bien reçu 💚',
    `<p>Salut ${esc(o.customer_name || '')},</p><p>Le paiement de ta commande <b>${num(o)}</b> est confirmé. On la prépare ; tu recevras ton numéro de suivi dès l'expédition.</p>
    ${recap(o)}${facture ? `<p>Ta facture <b>${esc(facture.numero)}</b> est en pièce jointe.</p>` : ''}${btn(site + '/#compte', 'Suivre ma commande')}`, site) };
}
function tplExpedition(o, site){
  return { subject: `Ta commande ${num(o)} est expédiée 📦`, html: layout('Ton colis est parti !',
    `<p>Salut ${esc(o.customer_name || '')},</p><p>Ta commande <b>${num(o)}</b> a été expédiée${o.carrier ? ' avec <b>' + esc(o.carrier) + '</b>' : ''}.</p>
    <p>Numéro de suivi : <b style="font-family:monospace;font-size:16px;color:#8FE24C;">${esc(o.tracking_number)}</b></p>
    ${o.tracking_url ? btn(o.tracking_url, 'Suivre mon colis') : ''}<p><b>Livraison :</b> ${esc(o.address || '')}</p>`, site) };
}
function tplFacture(o, site, facture){
  return { subject: `Ta facture ${facture.numero} — Smok'house`, html: layout('Ta facture',
    `<p>Salut ${esc(o.customer_name || '')},</p><p>Merci pour ta commande <b>${num(o)}</b> ! Tu trouveras ta facture <b>${esc(facture.numero)}</b> en pièce jointe.</p>${btn(site + '/#compte', 'Mon espace client')}`, site) };
}

module.exports = { sendEmail, tplConfirmation, tplPaiement, tplExpedition, tplFacture, layout };
