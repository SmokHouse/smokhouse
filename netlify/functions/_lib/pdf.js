// Générateur PDF minimal (A4, Helvetica, WinAnsi), sans dépendance — même rendu que l'app admin
const HELV_W = [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,278,278,355,556,556,889,667,191,333,333,389,584,278,333,278,278,556,556,556,556,556,556,556,556,556,556,278,278,584,584,584,556,1015,667,667,722,722,667,611,778,722,278,500,667,556,833,722,778,667,778,722,667,611,722,667,944,667,667,611,278,278,278,469,556,333,556,556,500,556,556,278,556,556,222,222,500,222,833,556,556,556,556,333,500,278,556,500,722,500,500,500,334,260,334,584,761,556,556,222,556,333,1000,556,556,333,1000,667,333,1000,556,611,556,556,222,222,333,333,350,556,1000,333,1000,500,333,944,556,500,667,278,333,556,556,556,556,260,556,333,737,370,556,584,333,737,333,400,584,333,333,333,556,537,278,333,333,365,556,834,834,834,611,667,667,667,667,667,667,1000,722,667,667,667,667,278,278,278,278,722,722,778,778,778,778,778,584,778,722,722,722,722,667,667,611,556,556,556,556,556,556,889,500,556,556,556,556,278,278,278,278,556,556,556,556,556,556,556,584,611,556,556,556,556,500,556,500];
const HELVB_W = [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,278,333,474,556,556,889,722,238,333,333,389,584,278,333,278,278,556,556,556,556,556,556,556,556,556,556,333,333,584,584,584,611,975,722,722,722,722,667,611,778,722,278,556,722,611,833,722,778,667,778,722,667,611,722,667,944,667,667,611,333,278,333,584,556,333,556,611,556,611,556,333,611,611,278,278,556,278,889,611,611,611,611,389,556,333,611,556,778,556,556,500,389,280,389,584,761,556,556,278,556,500,1000,556,556,333,1000,667,333,1000,556,611,556,556,278,278,500,500,350,556,1000,333,1000,556,333,944,556,500,667,278,333,556,556,556,556,280,556,333,737,370,556,584,333,737,333,400,584,333,333,333,611,556,278,333,333,365,556,834,834,834,611,722,722,722,722,722,722,1000,722,667,667,667,667,278,278,278,278,722,722,778,778,778,778,778,584,778,722,722,722,722,667,667,611,556,556,556,556,556,556,889,556,556,556,556,556,278,278,278,278,611,611,611,611,611,611,611,584,611,611,611,611,611,556,611,556];
const CP1252 = {0x20AC:0x80,0x201A:0x82,0x0192:0x83,0x201E:0x84,0x2026:0x85,0x2020:0x86,0x2021:0x87,0x02C6:0x88,0x2030:0x89,0x0160:0x8A,0x2039:0x8B,0x0152:0x8C,0x017D:0x8E,0x2018:0x91,0x2019:0x92,0x201C:0x93,0x201D:0x94,0x2022:0x95,0x2013:0x96,0x2014:0x97,0x02DC:0x98,0x2122:0x99,0x0161:0x9A,0x203A:0x9B,0x0153:0x9C,0x017E:0x9E,0x0178:0x9F,0x202F:0x20,0x2009:0x20};

function MiniPDF(){
  this.k = 72 / 25.4; this.H = 841.89; this.W = 595.28; this.ops = [];
  this.bold = false; this.size = 10; this.tc = [0, 0, 0]; this.dc = [0, 0, 0]; this.fc = [0, 0, 0];
}
MiniPDF.prototype.bytes = function(s){
  const out = []; for(const ch of String(s)){ const c = ch.codePointAt(0);
    if(c < 128) out.push(c); else if(c >= 160 && c <= 255) out.push(c); else if(CP1252[c] != null) out.push(CP1252[c]); else out.push(63); }
  return out;
};
MiniPDF.prototype.width = function(s, bold, size){
  const w = (bold == null ? this.bold : bold) ? HELVB_W : HELV_W; let t = 0;
  this.bytes(s).forEach(b => { t += w[b] || 0; }); return t / 1000 * (size || this.size) / this.k;
};
MiniPDF.prototype.setFont = function(_f, style){ this.bold = style === 'bold'; };
MiniPDF.prototype.setFontSize = function(s){ this.size = s; };
const col = (a) => a.length === 1 ? [a[0], a[0], a[0]] : a;
MiniPDF.prototype.setTextColor = function(...a){ this.tc = col(a); };
MiniPDF.prototype.setDrawColor = function(...a){ this.dc = col(a); };
MiniPDF.prototype.setFillColor = function(...a){ this.fc = col(a); };
const c3 = (a) => a.map(v => (v / 255).toFixed(3)).join(' ');
MiniPDF.prototype.esc = function(s){
  return this.bytes(s).map(b => b === 40 || b === 41 || b === 92 ? '\\' + String.fromCharCode(b) : b < 32 || b > 126 ? '\\' + b.toString(8).padStart(3, '0') : String.fromCharCode(b)).join('');
};
MiniPDF.prototype.text = function(t, x, y, opt){
  const lines = Array.isArray(t) ? t : [t], lh = this.size * 1.15 / this.k;
  lines.forEach((s, i) => {
    let xx = x; const w = this.width(s);
    if(opt && opt.align === 'right') xx = x - w; else if(opt && opt.align === 'center') xx = x - w / 2;
    this.ops.push(c3(this.tc) + ' rg BT /' + (this.bold ? 'F2' : 'F1') + ' ' + this.size + ' Tf ' + (xx * this.k).toFixed(2) + ' ' + (this.H - (y + i * lh) * this.k).toFixed(2) + ' Td (' + this.esc(s) + ') Tj ET');
  });
};
MiniPDF.prototype.splitTextToSize = function(t, maxW){
  const out = []; String(t).split('\n').forEach(par => {
    let line = ''; par.split(' ').forEach(word => {
      const tryL = line ? line + ' ' + word : word;
      if(this.width(tryL) <= maxW || !line) line = tryL; else { out.push(line); line = word; }
    }); out.push(line);
  }); return out;
};
MiniPDF.prototype.rect = function(x, y, w, h, style){
  const r = (x * this.k).toFixed(2) + ' ' + (this.H - (y + h) * this.k).toFixed(2) + ' ' + (w * this.k).toFixed(2) + ' ' + (h * this.k).toFixed(2) + ' re';
  this.ops.push(style === 'F' ? c3(this.fc) + ' rg ' + r + ' f' : c3(this.dc) + ' RG 0.6 w ' + r + ' S');
};
MiniPDF.prototype.roundedRect = function(x, y, w, h){ this.rect(x, y, w, h); };
MiniPDF.prototype.line = function(x1, y1, x2, y2){
  this.ops.push(c3(this.dc) + ' RG 0.5 w ' + (x1 * this.k).toFixed(2) + ' ' + (this.H - y1 * this.k).toFixed(2) + ' m ' + (x2 * this.k).toFixed(2) + ' ' + (this.H - y2 * this.k).toFixed(2) + ' l S');
};
MiniPDF.prototype.build = function(title){
  const content = this.ops.join('\n');
  const objs = [
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 ' + this.W + ' ' + this.H + '] /Resources << /Font << /F1 4 0 R /F2 5 0 R >> >> /Contents 6 0 R >>',
    '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>',
    '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Bold /Encoding /WinAnsiEncoding >>',
    '<< /Length ' + content.length + ' >>\nstream\n' + content + '\nendstream',
    '<< /Title (' + this.esc(title || '') + ') /Producer (Smok\'house) >>'
  ];
  let pdf = '%PDF-1.4\n'; const offs = [];
  objs.forEach((o, i) => { offs.push(pdf.length); pdf += (i + 1) + ' 0 obj\n' + o + '\nendobj\n'; });
  const x = pdf.length;
  pdf += 'xref\n0 ' + (objs.length + 1) + '\n0000000000 65535 f \n' + offs.map(o => String(o).padStart(10, '0') + ' 00000 n \n').join('');
  pdf += 'trailer\n<< /Size ' + (objs.length + 1) + ' /Root 1 0 R /Info 7 0 R >>\nstartxref\n' + x + '\n%%EOF';
  return Buffer.from(pdf, 'latin1');
};

const PAY_LONG = { especes: 'Espèces', carte: 'Carte bancaire', virement: 'Virement', credit: 'Crédit (à encaisser)', autre: 'Autre' };
const nf = (n, d) => Number(n || 0).toLocaleString('fr-FR', { minimumFractionDigits: d, maximumFractionDigits: d }).replace(/ | /g, ' ');
const frDate = (s) => { if(!s) return ''; const [y, m, d] = String(s).slice(0, 10).split('-'); return d + '/' + m + '/' + y; };

// Facture / avoir au format PDF (Buffer) — mêmes mentions que les factures de l'app admin
function invoicePdf(f){
  const doc = new MiniPDF();
  const E = f.emetteur || {}, C = f.client || {}, W = 210, M = 18;
  const avoir = f.type === 'avoir';
  let y = 20;
  doc.setFont('helvetica', 'bold'); doc.setFontSize(18); doc.text(E.nom_commercial || "Smok'house", M, y);
  doc.setFontSize(9); doc.setFont('helvetica', 'normal'); y += 6;
  [ (E.nom_legal || '') + ' — Entrepreneur individuel (EI)', E.adresse || '', ((E.code_postal || '') + ' ' + (E.ville || '')).trim(),
    'SIRET : ' + (E.siret || ''), [E.telephone, E.email].filter(Boolean).join(' · ') ].filter(Boolean).forEach(t => { doc.text(t, M, y); y += 4.5; });

  doc.setFont('helvetica', 'bold'); doc.setFontSize(16);
  doc.text((avoir ? 'AVOIR' : 'FACTURE') + ' N° ' + f.numero, W - M, 20, { align: 'right' });
  doc.setFont('helvetica', 'normal'); doc.setFontSize(9.5);
  let ry = 27;
  [ 'Date d\'émission : ' + frDate(f.date_emission), 'Date de la vente : ' + frDate(f.date_vente),
    avoir ? 'Annule la facture N° ' + f.facture_origine : null ].filter(Boolean).forEach(t => { doc.text(t, W - M, ry, { align: 'right' }); ry += 5; });

  y = Math.max(y, ry) + 8;
  const bx = W / 2 + 2, bw = W / 2 - M - 2;
  doc.setDrawColor(200); doc.roundedRect(bx, y - 5, bw, C.pro ? 30 : 22, 2, 2);
  doc.setFontSize(8); doc.setTextColor(110); doc.text('CLIENT', bx + 4, y); doc.setTextColor(0);
  doc.setFontSize(10); doc.setFont('helvetica', 'bold'); doc.text(String(C.nom || 'Client particulier'), bx + 4, y + 5.5);
  doc.setFont('helvetica', 'normal'); doc.setFontSize(9);
  let cy = y + 10.5;
  doc.splitTextToSize(String(C.adresse || ''), bw - 8).forEach(t => { doc.text(t, bx + 4, cy); cy += 4.5; });
  if(C.pro && C.siren){ doc.text('SIREN : ' + C.siren, bx + 4, cy); cy += 4.5; }
  if(C.adresse_livraison){ doc.splitTextToSize('Livraison : ' + C.adresse_livraison, bw - 8).forEach(t => { doc.text(t, bx + 4, cy); cy += 4.5; }); }
  y = Math.max(y + (C.pro ? 30 : 22), cy) + 6;

  doc.setFontSize(8.5); doc.setTextColor(90); doc.text('Nature de l\'opération : livraison de biens', M, y); doc.setTextColor(0); y += 6;

  const cols = [M, 118, 145, W - M];
  doc.setFillColor(20, 23, 13); doc.rect(M, y - 4.5, W - 2 * M, 7, 'F');
  doc.setTextColor(255); doc.setFont('helvetica', 'bold'); doc.setFontSize(9);
  doc.text('Désignation', M + 2, y); doc.text('Quantité', cols[1] + 22, y, { align: 'right' }); doc.text('Prix unitaire', cols[2] + 24, y, { align: 'right' }); doc.text('Montant', cols[3] - 2, y, { align: 'right' });
  doc.setTextColor(0); doc.setFont('helvetica', 'normal'); y += 8;
  (f.lignes || []).forEach(l => {
    const d = doc.splitTextToSize(String(l.designation), cols[1] - M - 4);
    doc.text(d, M + 2, y);
    doc.text(nf(Number(l.quantite), 2) + ' ' + (l.unite || 'g'), cols[1] + 22, y, { align: 'right' });
    doc.text(nf(Number(l.prix_unitaire), 2) + ' €/' + (l.unite || 'g'), cols[2] + 24, y, { align: 'right' });
    doc.text(nf(Number(l.total), 2) + ' €', cols[3] - 2, y, { align: 'right' });
    y += 4.5 * d.length + 2.5; doc.setDrawColor(225); doc.line(M, y - 3, W - M, y - 3);
  });
  y += 3;
  doc.setFont('helvetica', 'bold'); doc.setFontSize(11);
  doc.text(avoir ? 'Total de l\'avoir' : 'Total à payer', 128, y); doc.text(nf(Number(f.total), 2) + ' €', W - M - 2, y, { align: 'right' });
  doc.setFont('helvetica', 'normal'); doc.setFontSize(9); y += 5.5;
  doc.text('TVA non applicable, art. 293 B du CGI', W - M - 2, y, { align: 'right' }); y += 10;

  doc.setFontSize(9);
  const lines = [];
  if(avoir && f.motif) lines.push('Motif de l\'avoir : ' + f.motif);
  if(f.mode_paiement && f.mode_paiement !== 'credit') lines.push('Mode de paiement : ' + (PAY_LONG[f.mode_paiement] || f.mode_paiement) + (C.pro ? '' : ' — facture acquittée'));
  if(f.mode_paiement === 'credit' && !C.pro) lines.push('Paiement : à régler.');
  if(C.pro && !avoir){
    lines.push('Date d\'échéance : ' + frDate(f.date_echeance) + ' (paiement à ' + (E.delai_paiement_pro || 30) + ' jours à compter de la date de facture).');
    lines.push('Pas d\'escompte pour paiement anticipé.');
    lines.push('En cas de retard de paiement, des pénalités sont exigibles au taux d\'intérêt appliqué par la Banque centrale européenne à son opération de refinancement la plus récente, majoré de 10 points (art. L441-10 du Code de commerce).');
    lines.push('Indemnité forfaitaire pour frais de recouvrement en cas de retard de paiement : 40 € (art. D441-5 du Code de commerce).');
  }
  lines.forEach(t => { doc.splitTextToSize(t, W - 2 * M).forEach(s => { doc.text(s, M, y); y += 4.5; }); y += 1; });

  doc.setFontSize(7.5); doc.setTextColor(120);
  doc.text((E.nom_legal || '') + ' EI — ' + (E.nom_commercial || '') + ' — SIRET ' + (E.siret || '') + ' — TVA non applicable, art. 293 B du CGI', W / 2, 287, { align: 'center' });
  return doc.build(f.numero);
}

module.exports = { MiniPDF, invoicePdf };
