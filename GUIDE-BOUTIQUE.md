# Smok'house — mise en ligne de la boutique

Ce guide sert à mettre en ligne la boutique : livraison locale + expédition France.
Suis les étapes dans l'ordre et coche au fur et à mesure.

---

## Ce qui change

| | 🚲 Livraison locale | 📦 Expédition France |
|---|---|---|
| Zone | Haute-Loire (code postal 43…) | Toute la France |
| Délai | Jour même, vélo / scooter | Selon le transporteur |
| Frais | Aucun ajouté en ligne | Domicile 5,90 € · Relais 4,90 € · offert dès 50 € (modifiable) |
| Paiement | À la livraison | En ligne (ou marqué « payé » à la main) |
| Statuts | En attente → Confirmée → En livraison → Livrée (ou Annulée) | En attente de paiement → Payée → En préparation → Expédiée → Livrée (ou Annulée) |
| Suivi | — | N° de suivi saisi dans l'admin, envoyé automatiquement par e-mail |
| Facture | Émise automatiquement à « Livrée » | Émise automatiquement au paiement |

**Sécurité :**
- Le site n'envoie plus que les produits, les grammes et les coordonnées du client.
- Le prix, les frais de port, le total, le stock et la récompense fidélité sont **recalculés par le serveur**.
- Une commande est refusée si le stock ne suffit pas.
- Aucune clé secrète n'est dans le code du site : elles sont dans les variables Netlify.

**Stock :**
- Le stock est **réservé** dès la commande.
- Il est **retiré** à « Livrée » (local) ou à « Expédiée » (France).
- Une commande France non payée libère sa réservation au bout de 24 h.

---

## Étape 1 — Supabase (5 min)

1. Supabase → **SQL Editor** → **New query**.
2. Colle **`boutique-setup.sql`**, puis **Run**.
   - Résultat attendu : `Boutique prête | f | 7`.
   - Le `f` veut dire que l'expédition France est fermée : c'est normal.
3. Récupère ta **clé secrète** : **Project Settings** → **API Keys** → clé **secret** (`sb_secret_…`).
   - Si tu n'as que les anciennes clés, prends la clé **service_role**.
   - ⚠️ Cette clé donne tous les droits. Ne la colle **jamais** dans un fichier du site, ni dans un message. Elle va uniquement dans Netlify (étape 4).

> ⚠️ Ne lance **pas encore** `verrouillage-commandes.sql`. Il vient à la fin (étape 6).

---

## Étape 2 — GitHub (10 min)

Les fonctions serveur ne marchent pas avec le glisser-déposer sur Netlify. Il faut passer par GitHub.

1. Crée un compte sur **github.com**.
2. Clique **New repository** :
   - nom : `smokhouse` ;
   - coche **Private** ;
   - clique **Create repository**.
3. Clique **uploading an existing file**.
4. Glisse **tout le contenu** du dossier `smokhouse-app` (pas le dossier lui-même), avec les sous-dossiers `admin`, `icons`, `menu`, `premium` et **`netlify`**.
5. Clique **Commit changes**.

Vérifie que tu vois bien `netlify.toml` et le dossier `netlify/functions` dans la liste.

---

## Étape 3 — Netlify (10 min)

**Si ton site actuel a été mis en ligne par glisser-déposer**, tu gardes le même site et la même adresse :
1. Netlify → ton site → **Site configuration** → **Build & deploy** → **Link repository**.
2. Choisis **GitHub**, puis le dépôt `smokhouse`.

**Sinon :** **Add new site** → **Import an existing project** → **GitHub** → `smokhouse`.

Réglages à mettre :
- **Build command** : laisser vide.
- **Publish directory** : `.`
- **Functions directory** : `netlify/functions` (normalement déjà lu dans `netlify.toml`).

Clique **Deploy**.

Ensuite, chaque modification envoyée sur GitHub remet le site à jour tout seul.

---

## Étape 4 — Variables d'environnement Netlify (10 min)

Va dans Netlify → **Site configuration** → **Environment variables** → **Add a variable**. Crée ces variables :

| Nom | Valeur |
|---|---|
| `SUPABASE_URL` | `https://qtagbmjzzmwxiptkgjmn.supabase.co` |
| `SUPABASE_SERVICE_ROLE_KEY` | ta clé secrète Supabase (étape 1) |
| `BREVO_API_KEY` | ta clé API Brevo (étape 5) |
| `BREVO_SENDER_EMAIL` | l'adresse d'envoi validée chez Brevo (ex : `commandes@smokhousecbd.fr`) |
| `BREVO_SENDER_NAME` | `Smok'house` |
| `BREVO_REPLY_TO` | ton adresse pour les réponses des clients (optionnel) |
| `NTFY_TOPIC` | ton sujet ntfy secret (ex : `smokhouse-7f3k9q2x`). Choisis un nom difficile à deviner. |
| `PAYMENT_PROVIDER` | `aucun` pour l'instant |
| `PAYMENT_WEBHOOK_SECRET` | une longue phrase aléatoire de 32 caractères ou plus |
| `SITE_URL` | `https://smokhousecbd.fr` (ton adresse, sans `/` à la fin) |

Ensuite :
1. Netlify → **Deploys** → **Trigger deploy** → **Deploy site**.
2. Les variables ne sont prises en compte qu'après ce redéploiement.

Sur ton téléphone :
1. Ouvre l'app **ntfy**.
2. Abonne-toi au même sujet que `NTFY_TOPIC`.
3. Les notifications indiquent maintenant le type de commande : **🚲 LIVRAISON LOCALE** ou **📦 EXPÉDITION FRANCE**.

---

## Étape 5 — Brevo, les e-mails automatiques (15 min)

1. Crée un compte sur **brevo.com** (offre gratuite : 300 e-mails/jour).
2. Va dans **Expéditeurs, domaines** :
   - ajoute ton domaine `smokhousecbd.fr` ;
   - ajoute chez ton hébergeur de domaine les enregistrements DNS que Brevo te donne (DKIM, DMARC) ;
   - sans ça, tes e-mails risquent d'arriver en spam.
3. Va dans **SMTP & API** → **Clés API** → **Générer une clé**. Colle-la dans `BREVO_API_KEY` (étape 4), puis redéploie.
4. Teste l'envoi :
   - admin → **Commandes** → **📦 Expéditions France** → **⚙️ Réglages** → **✉️ Tester l'e-mail** ;
   - tu dois recevoir « Test e-mail Smok'house ✅ ».

Lis aussi les conditions d'utilisation de Brevo pour vérifier qu'elles acceptent ton activité.

E-mails envoyés automatiquement :
- **confirmation** de commande (les deux modes) ;
- **paiement reçu** + facture PDF (France) ;
- **colis expédié** + numéro et lien de suivi ;
- **facture** à la livraison locale, si le client a donné son e-mail.

---

## Étape 6 — Tester, puis verrouiller

1. **Infos entreprise** : admin → **Factures** → **Infos entreprise**. Mets ton nom légal et ton adresse. Sans ça, les factures automatiques ne peuvent pas être émises : l'admin affiche alors un avertissement avec un bouton **Réessayer**.
2. **Commande locale test** : sur le site, ajoute un produit → panier → **🚲 Livraison locale** → code postal 43… → **Valider**.
   Vérifie :
   - qu'elle apparaît dans l'admin, section **Livraisons locales** ;
   - que tu reçois la notification ntfy ;
   - que le client reçoit l'e-mail de confirmation.
3. Dans l'admin, fais avancer la commande : **Confirmer + heure** → **Je pars 🚲** → **Livrée ✓**. La facture se crée toute seule.
4. Une fois que tout marche, lance **`verrouillage-commandes.sql`** dans Supabase.
   - Plus personne ne peut créer une commande en contournant le serveur.
   - Résultat attendu : aucune ligne `INSERT` dans la liste.

---

## Plus tard — ouvrir l'expédition France

Quand tu as validé un transporteur :

1. Ouvre l'admin → **Commandes** → **📦 Expéditions France** → **⚙️ Réglages**.
2. Renseigne :
   - le **transporteur** ;
   - les tarifs et le seuil de livraison offerte ;
   - le **lien de suivi**, avec `{suivi}` à la place du numéro (ex. Colissimo : `https://www.laposte.fr/outils/suivre-vos-envois?code={suivi}`) ;
   - le lien « trouver un point relais » du transporteur (optionnel) ;
   - puis coche **Ouverte aux clients**.
3. Le site affiche alors le bloc **Expédition France** et l'onglet dans le panier.

**Chaque jour :**
1. Les commandes payées arrivent dans **Payées — à préparer**.
2. Clique **Préparer**, puis **📦 Expédier**.
3. Saisis le numéro de suivi : le client le reçoit par e-mail et le stock est retiré.
4. Clique **Livrée ✓** quand le colis est arrivé.

**Produit non expédiable :**
1. Va dans **Stock** → **📋 Fiches**.
2. Décoche **Expédiable**.
3. Le produit reste disponible en livraison locale.

---

## Plus tard — le paiement en ligne

Le module est **générique** : il n'est lié à aucun prestataire. Tant que tu n'en as pas, deux options.

**`PAYMENT_PROVIDER` = `aucun`** :
- le client passe commande ;
- tu encaisses autrement (virement…) ;
- dans l'admin, tu cliques **Paiement reçu** ;
- la commande passe « Payée », la facture est émise et envoyée.

**`PAYMENT_PROVIDER` = `test`** :
- page de paiement **simulée**, pour essayer tout le parcours (paiement → facture → e-mail) ;
- ⚠️ remets `aucun` après les tests : en mode test, n'importe qui peut « payer » sans payer.

**Le jour où un prestataire accepte explicitement ton activité :**
1. Mets `PAYMENT_PROVIDER` = `generique`.
2. Ajoute `PAYMENT_API_URL` et `PAYMENT_API_KEY`.
3. Mets dans `PAYMENT_WEBHOOK_SECRET` le secret de signature qu'il te donne.
4. Donne-lui l'adresse de notification : `https://smokhousecbd.fr/.netlify/functions/payment-webhook`.

Selon sa documentation, il faudra peut-être adapter deux petites fonctions dans `netlify/functions/_lib/payment.js` : `createGeneric` et `verifyGeneric`. Envoie-moi sa doc, je m'en occupe.

Garanties côté serveur :
- la notification de paiement est **vérifiée** (signature HMAC-SHA256) ;
- le **montant est comparé au centime** près au total de la commande ;
- un même paiement n'est jamais compté deux fois.

---

## Fiches produits et prix

Va dans l'admin → **Stock** → **📋 Fiches**. Pour chaque produit tu peux remplir :
- description ;
- n° de lot ;
- taux CBD / THC / THV / CBG ;
- lien du certificat d'analyse (COA) ;
- poids proposés ;
- expédiable ou non ;
- **grille de prix**, au format `1:9, 3:8.5, 5:8, 50:7`, qui veut dire « dès 1 g : 9 €/g, dès 3 g : 8,50 €/g… ».

La grille est utilisée à la fois :
- par le site (affichage) ;
- par le menu ;
- par le serveur (calcul réel de la commande).

Un changement s'applique tout de suite partout.

---

## Promos et remises

**Promos automatiques** : admin → **Stock** → **🏷 Promos** → **+ Nouvelle promo**. Deux types :
- **« X g pour Y € »** : par exemple 10 g pour 90 €. Le prix au gramme du lot s'applique dès 10 g.
- **« -X % »** : par exemple -10 % sur les fleurs dès 5 g.

Une promo peut viser un produit, toutes les fleurs, toutes les résines ou tout le catalogue. Tu peux lui mettre des dates de début et de fin.

Elle s'affiche toute seule sur les cartes du site et sur le menu. Le **serveur** l'applique au moment de la commande et l'indique sur la facture. Si plusieurs promos s'appliquent, le client a la meilleure.

**Remise à la main sur une commande** :
- Bouton **💸 Faire une remise** sur la commande, avant la livraison (local) ou avant le paiement (France).
- Tu indiques le **nouveau total**, par exemple 90 € au lieu de 100 €, et un motif si tu veux.
- La remise apparaît sur la facture (« Remise commerciale »). Les points fidélité sont calculés sur le montant réellement payé.
- Pour annuler une remise, remets le total d'origine.

---

## Photos des variétés

À faire une seule fois : lance **`photos-setup.sql`** dans Supabase.

Ensuite, pour changer une photo :
1. Admin → **Stock**.
2. Touche la **vignette 📷** à gauche du nom de la variété.
3. **Prendre / choisir une photo**, puis **Enregistrer**.

La photo est réduite automatiquement et s'affiche aussitôt sur le site, la fiche produit et le menu. Le bouton **Retirer** remet la photo par défaut.

---

## À prévoir avant d'ouvrir l'expédition (vente à distance)

Vendre en ligne à toute la France fait de toi un vendeur à distance. Ces points sont à vérifier avec un professionnel (ceci n’est pas un avis juridique) :
- **mentions légales** ;
- **CGV**, avec notamment le droit de rétractation de 14 jours ;
- **politique de confidentialité** (RGPD : les adresses et e-mails des clients sont stockés) ;
- **médiateur de la consommation** ;
- **vérification de l'âge** à la livraison selon ton transporteur.

---

## Fichiers ajoutés

- `boutique-setup.sql` : base de données de la boutique, à lancer à l'étape 1.
- `verrouillage-commandes.sql` : à lancer en dernier (étape 6).
- `netlify.toml`, `package.json`, `.gitignore` : configuration Netlify / GitHub.
- `netlify/functions/` : le serveur.
  - `create-order` : crée une commande.
  - `pay-order` : relance un paiement.
  - `payment-webhook` : reçoit les notifications de paiement.
  - `admin-order` : expédition, paiement manuel, e-mails.
  - `invoice-pdf` : téléchargement des factures.
  - `shop-config` : réglages publics de la boutique.
  - `_lib/` : briques communes (Supabase, e-mails Brevo, ntfy, PDF, paiement).
- `paiement-test.html` : page de paiement simulée (mode test uniquement).
