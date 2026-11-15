// POST /.netlify/functions/ia-image-background { id } — crée une image avec l'IA d'OpenAI (admin uniquement)
// Fonction « background » : elle peut tourner jusqu'à 15 min (une image prend 20 à 60 s).
// Le résultat est écrit dans la table ia_images ; l'app admin attend qu'il passe à « done ».
const { rest, getUser, isAdmin, uploadPublic } = require('./_lib/supa');
const { parseJson, bearer, siteUrl } = require('./_lib/http');

const SIZES = { paysage: '1536x1024', carre: '1024x1024', portrait: '1024x1536' };
const STYLES = {
  smokhouse: 'Premium product photography for "Smok\'House CBD", an upscale CBD coffee-shop brand. Dark moody interior, warm amber lighting, dark walnut wood counter, glass apothecary jars softly blurred in the background, a subtle neon-green glow and golden highlights, shallow depth of field, rich contrast, photorealistic, high detail.',
  studio: 'Clean premium studio product photography on a deep black background, soft golden rim light, subtle reflection, centered subject, photorealistic, high detail.',
  nature: 'Natural premium product photography, soft daylight, natural wood and hemp leaves, earthy tones with golden accents, shallow depth of field, photorealistic, high detail.'
};
const RULES = ' Legal CBD hemp product (THC under 0.3%). No text, no letters, no logos, no watermark, no people, no smoking, no pipes or joints.';

async function setRow(id, patch){
  await rest('ia_images?id=eq.' + encodeURIComponent(id), { method: 'PATCH', body: Object.assign({ updated_at: new Date().toISOString() }, patch), prefer: 'return=minimal' });
}

async function callOpenAI(row, site){
  const key = process.env.OPENAI_API_KEY;
  if(!key) throw new Error('OPENAI_API_KEY manquante dans Netlify');
  const model = process.env.OPENAI_IMAGE_MODEL || 'gpt-image-1.5';
  const prompt = (STYLES[row.style] || STYLES.smokhouse) + ' Subject: ' + row.prompt + '.' + RULES
    + (row.ref_url ? ' Keep the product from the first reference photo exactly as it is (same shape, color and texture); only improve the setting, light and framing.' : '');
  const common = { model, prompt, size: SIZES[row.format] || SIZES.paysage, quality: row.qualite || 'medium', n: 1 };
  let res;
  if(row.ref_url){
    // Retouche à partir de ta photo (+ photo d'ambiance de la marque pour le style)
    const fd = new FormData();
    Object.entries(Object.assign({}, common, { output_format: 'jpeg', output_compression: 88 })).forEach(([k, v]) => fd.append(k, String(v)));
    const refs = [row.ref_url];
    if(row.style === 'smokhouse') refs.push(site + '/premium/hero.jpg');
    for(let i = 0; i < refs.length; i++){
      const r = await fetch(refs[i]); if(!r.ok){ if(i === 0) throw new Error('Photo de départ introuvable'); continue; }
      fd.append('image[]', new Blob([Buffer.from(await r.arrayBuffer())], { type: r.headers.get('content-type') || 'image/jpeg' }), 'ref' + i + '.jpg');
    }
    res = await fetch('https://api.openai.com/v1/images/edits', { method: 'POST', headers: { Authorization: 'Bearer ' + key }, body: fd });
  } else {
    res = await fetch('https://api.openai.com/v1/images/generations', { method: 'POST', headers: { Authorization: 'Bearer ' + key, 'Content-Type': 'application/json' },
      body: JSON.stringify(Object.assign(common, { output_format: 'jpeg', output_compression: 88 })) });
  }
  const data = await res.json().catch(() => ({}));
  if(!res.ok){
    const m = (data.error && data.error.message) || ('HTTP ' + res.status);
    if(/safety|policy|moderation/i.test(m)) throw new Error('Refusé par le filtre de l\'IA : reformule (évite « fumer », « joint »…)');
    if(/verif/i.test(m)) throw new Error('OpenAI demande de vérifier ton organisation (platform.openai.com → Settings → Organization → Verify)');
    if(/billing|quota|credit/i.test(m)) throw new Error('Plus de crédit sur le compte OpenAI (platform.openai.com → Billing)');
    throw new Error('OpenAI : ' + m.slice(0, 200));
  }
  const b64 = data.data && data.data[0] && data.data[0].b64_json;
  if(!b64) throw new Error('Réponse vide de l\'IA');
  return Buffer.from(b64, 'base64');
}

exports.handler = async (event) => {
  let b; try{ b = parseJson(event, 2000); }catch(e){ return { statusCode: 400 }; }
  const user = await getUser(bearer(event));
  if(!user || !(await isAdmin(user.id))) return { statusCode: 403 };
  const id = String(b.id || '');
  const rows = await rest('ia_images?id=eq.' + encodeURIComponent(id) + '&select=*').catch(() => []);
  const row = rows && rows[0];
  if(!row || row.status !== 'pending') return { statusCode: 404 };

  // Garde-fou sur la facture : nombre d'images par jour
  const limit = parseInt(process.env.IA_LIMITE_JOUR || '30', 10);
  const since = new Date(Date.now() - 24 * 3600e3).toISOString();
  const today = await rest('ia_images?status=eq.done&created_at=gte.' + encodeURIComponent(since) + '&select=id').catch(() => []);
  if(today.length >= limit){ await setRow(id, { status: 'error', erreur: 'Limite de ' + limit + ' images par 24 h atteinte (variable IA_LIMITE_JOUR)' }); return { statusCode: 200 }; }

  try{
    const img = await callOpenAI(row, siteUrl(event));
    const isPng = img[0] === 0x89;
    const url = await uploadPublic('produits', 'ia/' + id + (isPng ? '.png' : '.jpg'), img, isPng ? 'image/png' : 'image/jpeg');
    await setRow(id, { status: 'done', url, erreur: null });
  }catch(e){
    console.error('ia-image', e.message);
    await setRow(id, { status: 'error', erreur: String(e.message).slice(0, 300) }).catch(() => {});
  }
  return { statusCode: 200 };
};
