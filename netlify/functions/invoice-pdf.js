// GET /.netlify/functions/invoice-pdf?order=<id>  (ou ?id=<id facture>)
// Télécharge la facture : seulement pour le client propriétaire de la commande ou l'admin.
const { rest, getUser, isAdmin, getOrder, getInvoiceForOrder } = require('./_lib/supa');
const { json, bearer } = require('./_lib/http');
const { invoicePdf } = require('./_lib/pdf');

exports.handler = async (event) => {
  const q = event.queryStringParameters || {};
  const user = await getUser(bearer(event));
  if(!user) return json(401, { error: 'NON_CONNECTE' });
  const admin = await isAdmin(user.id);
  let f = null;
  if(q.id){
    if(!admin) return json(403, { error: 'NOT_ADMIN' });
    const r = await rest('factures?id=eq.' + encodeURIComponent(q.id) + '&select=*'); f = r && r[0];
  } else if(q.order){
    const o = await getOrder(q.order);
    if(!o || (!admin && o.customer_id !== user.id)) return json(404, { error: 'INTROUVABLE' });
    f = await getInvoiceForOrder(q.order);
  }
  if(!f) return json(404, { error: 'PAS_DE_FACTURE' });
  return {
    statusCode: 200, isBase64Encoded: true,
    headers: { 'Content-Type': 'application/pdf', 'Content-Disposition': 'attachment; filename="' + f.numero + '.pdf"', 'Cache-Control': 'private, no-store' },
    body: invoicePdf(f).toString('base64')
  };
};
