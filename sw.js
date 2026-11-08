/* Smok'house — service worker (app client + app admin)
   Change CACHE_VERSION à chaque mise en ligne importante pour forcer la mise à jour. */
const CACHE_VERSION = 'smokhouse-v6-panier';
const PRECACHE = [
  '/', '/index.html', '/manifest.webmanifest', '/offline.html',
  '/admin/', '/admin/index.html', '/admin/manifest.webmanifest',
  '/icons/icon-192.png', '/icons/icon-512.png', '/icons/admin-192.png', '/icons/favicon-32.png'
];
const CDN_HOSTS = ['cdn.jsdelivr.net', 'unpkg.com', 'fonts.googleapis.com', 'fonts.gstatic.com'];

self.addEventListener('install', (event) => {
  event.waitUntil(
    caches.open(CACHE_VERSION)
      .then((c) => Promise.all(PRECACHE.map((u) => c.add(u).catch(() => null))))
      .then(() => self.skipWaiting())
  );
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys()
      .then((keys) => Promise.all(keys.filter((k) => k !== CACHE_VERSION).map((k) => caches.delete(k))))
      .then(() => self.clients.claim())
  );
});

self.addEventListener('fetch', (event) => {
  const req = event.request;
  if (req.method !== 'GET') return;
  const url = new URL(req.url);

  // Supabase (données, connexion, temps réel) : jamais de cache
  if (url.hostname.endsWith('supabase.co') || url.hostname === 'ntfy.sh') return;
  // Fonctions serveur (commandes, factures, paiement) : jamais de cache
  if (url.pathname.startsWith('/.netlify/') || url.pathname === '/paiement-test.html') return;

  // Pages : réseau d'abord (toujours à jour), cache si hors ligne
  if (req.mode === 'navigate') {
    event.respondWith(
      fetch(req).then((res) => {
        const copy = res.clone();
        caches.open(CACHE_VERSION).then((c) => c.put(req, copy));
        return res;
      }).catch(async () => (await caches.match(req)) || (await caches.match(url.pathname.startsWith('/admin') ? '/admin/' : '/')) || caches.match('/offline.html'))
    );
    return;
  }

  // Librairies, polices, images : cache d'abord, mise à jour en arrière-plan
  if (url.origin === self.location.origin || CDN_HOSTS.includes(url.hostname)) {
    event.respondWith(
      caches.match(req).then((cached) => {
        const network = fetch(req).then((res) => {
          if (res && (res.ok || res.type === 'opaque')) {
            const copy = res.clone();
            caches.open(CACHE_VERSION).then((c) => c.put(req, copy));
          }
          return res;
        }).catch(() => cached);
        return cached || network;
      })
    );
  }
});

// Clic sur une notification : ouvre (ou ramène au premier plan) la bonne app
self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  const target = (event.notification.data && event.notification.data.url) || '/';
  event.waitUntil(
    self.clients.matchAll({ type: 'window', includeUncontrolled: true }).then((list) => {
      for (const c of list) {
        if (new URL(c.url).pathname.startsWith(target.split('#')[0]) && 'focus' in c) return c.focus();
      }
      return self.clients.openWindow(target);
    })
  );
});
