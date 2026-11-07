# Smok'house : app client + app admin

> 🛒 **Nouveau : boutique en ligne (livraison locale + expédition France).** Pour la mise en ligne, suis **`GUIDE-BOUTIQUE.md`** : GitHub + Netlify, variables, Brevo, puis verrouillage.

## Ce que contient ce dossier

| Fichier | Rôle |
|---|---|
| `index.html` | Ton site, transformé en app installable (même contenu et même design) |
| `admin/index.html` | Ton app admin : commandes en direct, livraison, stock, fidélité et chiffres |
| `sw.js`, `manifest.webmanifest`, `offline.html`, `icons/` | Ce qu'il faut pour que les deux apps s'installent sur un téléphone |
| `_headers` | Réglages Netlify (le fichier `sw.js` n'est jamais mis en cache et `/admin` n'apparaît pas sur Google) |
| `supabase-setup.sql` | Crée les tables du stock et active le temps réel |

## Installation (environ 10 minutes)

1. **Supabase** : ouvre SQL Editor, puis New query. Colle tout le contenu de `supabase-setup.sql` et clique sur Run.
2. Dans Table Editor, ouvre `products` et renseigne pour chaque produit ton **stock en grammes** (`stock_grams`) et ton **prix d'achat au gramme** (`cost_per_gram`). Tu pourras ensuite tout faire depuis l'app admin.
3. **Netlify** : glisse le dossier entier dans Deploys, à la place de l'ancien `index.html`. Garde tes vidéos et `og-image.jpg` dans le même dossier.
4. **Sur ton téléphone** : ouvre `smokhousecbd.fr/admin`, connecte-toi avec ton compte admin, puis installe l'app. Sur Android : menu ⋮ puis « Installer l'application ». Sur iPhone : bouton Partager puis « Sur l'écran d'accueil ». Ensuite, touche « 🔔 Activer les alertes ».

## Recevoir les commandes même quand l'app est fermée

L'app admin sonne et vibre quand elle est ouverte ou en arrière-plan. Pour être prévenu même quand l'app est fermée :
installe l'app **ntfy** sur ton téléphone et abonne-toi à un sujet secret (par exemple `smokhouse-cmd-8f3k2`).
Dans `index.html`, cherche `var NTFY_TOPIC = '';` et mets ce même sujet entre les guillemets.

## Côté client, ce qui change

- Un bandeau propose d'installer l'app, avec les explications adaptées pour iPhone.
- L'app ne redemande plus l'âge à chaque ouverture (la confirmation est gardée 30 jours).
- Quand tu valides ou livres une commande, le client voit le changement en direct.
- Un produit à 0 g ou masqué affiche « Rupture » et ne peut plus être ajouté au panier.
- Chaque commande enregistre maintenant le détail en grammes et le total. Le stock baisse automatiquement quand tu la marques « Livrée ».

## Ventes hors site et marge (onglet Chiffres)

1. Lance une fois `ventes-setup.sql` dans Supabase (SQL Editor, puis Run).
2. Dans l'app admin, onglet **Chiffres**, puis **Prix d'achat des produits** : entre ce que tu paies 1 g à ton fournisseur.
3. Le bouton **+ Vente** permet d'ajouter une vente faite en boutique, en main propre, sur Snap, etc. Tu peux choisir n'importe quelle date passée.
4. Touche un jour dans **Jour par jour** pour ajouter, modifier ou supprimer une vente, ou corriger le montant d'une commande du site.

## Factures et livre des recettes (onglet Factures)

1. Lance une fois `factures-setup.sql` dans Supabase (après `ventes-setup.sql`).
2. Dans l'app admin, onglet **Factures**, puis **Infos entreprise** : renseigne ton nom légal et ton adresse.
3. Bouton « Facture » sur chaque commande, ou icône 🧾 sur chaque vente dans Chiffres, puis jour : numéro automatique SH-AAAA-NNNN, PDF téléchargeable, facture définitive (correction par avoir).
4. Pour exporter le livre des recettes, va dans l'onglet **Factures**, choisis le mois, puis **Exporter le mois (CSV)**. Le fichier s'ouvre dans Excel ou LibreOffice.
5. Brouillons : lance aussi `brouillons-setup.sql` (après `factures-setup.sql`). Dans l'éditeur de facture, **Brouillon** enregistre sans numéro (modifiable, supprimable, aperçu PDF). **Valider et émettre** attribue le numéro et rend la facture définitive.
6. Produits offerts : lance `offerts-setup.sql`. Dans une vente, **🎁 Produit offert** ajoute des grammes offerts (comptés dans le stock et le coût, pas dans le prix), avec les points fidélité utilisés.
7. Fidélité automatique : lance `fidelite-commandes-setup.sql`. Les points sont crédités quand une commande d'un client connecté passe « Livrée » (1 pt/€ par défaut, réglable dans Fidélité, puis ⚙️ Règles). Le client choisit sa récompense au moment de commander : les points sont retirés tout de suite, et rendus si la commande est annulée.
8. Surnoms et notes privées : lance `client-notes-setup.sql`. Dans Fidélité, touche **Ouvrir** sur un client pour lui donner un surnom (ex : « Kevin (Brives) ») et une note. Seul toi les vois, sur la fiche et sur ses commandes.
9. Minimum d'achat des récompenses : lance `fidelite-minimum-setup.sql` (100 pts dès 20 €, 150 pts dès 30 €). Modifiable dans Fidélité, puis ⚙️ Règles (colonne « min € »).
10. Clients ajoutés à la main : lance `clients-manuels-setup.sql`. Dans Fidélité, **+ Client** crée une carte SH-… sans compte en ligne. Si le client s'inscrit plus tard sur le site avec le même email, il retrouve sa carte et ses points.
11. Bonus ticket à gratter : lance `bonus-ticket-setup.sql`. Dans une vente manuelle ou au moment de marquer une commande « Livrée », choisis +10/20/30/50 % (ou un autre %) : les grammes offerts sont calculés tout seuls, retirés du stock et comptés dans le coût, sans changer le prix.
12. Menu « coffee shop » (version test) : lance `menu-setup.sql`. La page est sur `smokhousecbd.fr/menu.html` (elle n'est liée nulle part sur le site). Pour modifier le menu du jour, les profils, arômes, badges et photos : app admin, onglet Stock, puis **🗒 Menu**. Photos : dossier `menu/` (voir le fichier à l'intérieur).
