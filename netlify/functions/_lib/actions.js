// Actions communes : après paiement, après expédition, envoi de facture
const { rest, getOrder, getInvoiceForOrder } = require('./supa');
const { sendEmail, tplPaiement, tplExpedition, tplFacture } = require('./email');
const { invoicePdf } = require('./pdf');
const { notify } = require('./ntfy');
const { eur } = require('./http');

const stamp = (id, col) => rest('orders?id=eq.' + encodeURIComponent(id), { method: 'PATCH', body: { [col]: new Date().toISOString() }, prefer: 'return=minimal' }).catch(e => console.error(col, e.message));

async function afterPaid(orderId, site){
  const o = await getOrder(orderId);
  if(!o) return;
  const f = await getInvoiceForOrder(orderId).catch(() => null);
  if(o.customer_email){
    const t = tplPaiement(o, site, f);
    const r = await sendEmail({ to: o.customer_email, toName: o.customer_name, subject: t.subject, html: t.html, orderId, type: 'paiement',
      attachments: f ? [{ name: f.numero + '.pdf', content: invoicePdf(f) }] : [] });
    if(r.ok && f) await stamp(orderId, 'invoice_sent_at');
  }
  await notify({ title: '💶 Paiement reçu — Expédition France', message: (o.customer_name || '') + ' — ' + eur(o.total) + '\nCommande n° ' + o.id + ' à préparer', tags: ['package', 'moneybag'], click: site + '/admin/' });
}

async function afterShipped(orderId, site){
  const o = await getOrder(orderId);
  if(!o || !o.customer_email) return { ok: false, error: 'PAS_D_EMAIL' };
  const t = tplExpedition(o, site);
  const r = await sendEmail({ to: o.customer_email, toName: o.customer_name, subject: t.subject, html: t.html, orderId, type: 'expedition' });
  if(r.ok) await stamp(orderId, 'tracking_sent_at');
  return r;
}

async function sendInvoice(orderId, site){
  const o = await getOrder(orderId);
  if(!o) return { ok: false, error: 'ORDER_NOT_FOUND' };
  if(!o.customer_email) return { ok: false, error: 'PAS_D_EMAIL' };
  const f = await getInvoiceForOrder(orderId);
  if(!f) return { ok: false, error: 'PAS_DE_FACTURE' };
  const t = tplFacture(o, site, f);
  const r = await sendEmail({ to: o.customer_email, toName: o.customer_name, subject: t.subject, html: t.html, orderId, type: 'facture', attachments: [{ name: f.numero + '.pdf', content: invoicePdf(f) }] });
  if(r.ok) await stamp(orderId, 'invoice_sent_at');
  return r;
}

module.exports = { afterPaid, afterShipped, sendInvoice, stamp };
