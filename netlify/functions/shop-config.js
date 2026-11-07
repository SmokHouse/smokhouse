// GET /.netlify/functions/shop-config — indique au site si le paiement en ligne est ouvert (aucune donnée secrète)
const { json } = require('./_lib/http');
const { provider } = require('./_lib/payment');
exports.handler = async () => json(200, { paiement_en_ligne: provider() !== 'aucun', test: provider() === 'test' }, { 'Cache-Control': 'public, max-age=300' });
