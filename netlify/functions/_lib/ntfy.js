// Notification sur ton téléphone (app ntfy) — sujet secret dans la variable NTFY_TOPIC
async function notify({ title, message, tags, priority, click }){
  const topic = process.env.NTFY_TOPIC;
  if(!topic) return false;
  const server = (process.env.NTFY_URL || 'https://ntfy.sh').replace(/\/$/, '');
  const headers = { 'Content-Type': 'application/json' };
  if(process.env.NTFY_TOKEN) headers.Authorization = 'Bearer ' + process.env.NTFY_TOKEN;
  try{
    const res = await fetch(server + '/', { method: 'POST', headers, body: JSON.stringify({ topic, title, message, tags: tags || [], priority: priority || 4, click }) });
    return res.ok;
  }catch(e){ console.error('ntfy', e.message); return false; }
}
module.exports = { notify };
