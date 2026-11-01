# PAYMENT_DECISIONS_V1 — Décisions de la fondation financière V1

**Statut :** décisions du propriétaire du projet (spécification du 01/11/2026), intégrant les amendements A1 à A14 listés en annexe A, issus de la relecture du même jour. Valider ce document = le committer. Aucune modification de code, de migration ni de test avant approbation explicite du propriétaire.

**Périmètre :** fondation financière sans PSP. Modèle d'intermédiation. Ce document ne contient aucun avis juridique : les questions juridiques et fiscales sont traitées dans `PAYMENT_COMPLIANCE.md`, sans conclusion.

---

## 1. Objectif et modèle

Suivre les prestations réalisées par les partenaires, calculer les commissions dues à Discover AI, gérer les créances et effectuer des rapprochements manuels.

- Le partenaire contracte avec le voyageur pour la prestation touristique.
- Discover AI contracte avec le partenaire pour l'intermédiation.
- Le partenaire encaisse directement le voyageur. Discover AI ne collecte pas le prix de la prestation.
- Discover AI facture sa commission au partenaire.
- En V1, Discover AI ne promet ni ne traite les remboursements dus au voyageur.

La V1 ne doit pas devenir prématurément un opérateur de paiement.

---

## 2. Origine et déclaration du montant

**Décision :** le montant réel est déclaré par le partenaire après la prestation. Le prix fixé à la réservation est une évolution ultérieure (circuits packagés, offres tarifées).

- Les POI n'ont aujourd'hui qu'une fourchette qualitative `price_range` ; `Booking.price` est un `Float` jamais alimenté et ne doit pas être réutilisé.
- La déclaration comprend : montant, devise, date, partenaire, POI, référence de réservation, taxes si distinctement identifiées.
- Montants en entiers, en unités mineures de la devise (jamais de float). L'exposant de la devise vient d'une table de métadonnées, il n'est jamais supposé.
- La source et l'historique de chaque déclaration sont conservés. Un enregistrement validé n'est jamais modifié silencieusement (nouvelle version ou correction tracée).
- **Type de déclaration [A13] :** service rendu, frais retenus pour annulation tardive, frais retenus pour no-show. Les trois suivent le même circuit de confirmation et de contestation.
- Une déclaration ne déclenche jamais de facturation automatique.

---

## 3. Partenaire et partie contractante

**Décision :** le profil contractuel et de facturation est rattaché au partenaire, pas systématiquement au POI.

- **[A4]** Le partenaire n'existe pas encore comme entité autonome : le code utilise `POIManager` (utilisateur ↔ POI). L'audit examine la relation réelle avant toute nouvelle table.
- Un profil contractuel distinct est prévu, avec un rattachement daté aux POI. Chaque prestation conserve le partenaire responsable au moment de sa déclaration.
- Un partenaire peut exploiter plusieurs POI. Deux POI d'opérateurs juridiquement différents relèvent de deux partenaires distincts.
- Le modèle peut évoluer vers une entité juridique regroupant plusieurs partenaires, sans l'imposer en V1.
- **Permissions séparées :** gestion opérationnelle du POI ; déclaration de prestation ; consultation des prestations déclarées ; modification du profil contractuel et de facturation. Un gérant de POI n'accède pas aux informations fiscales et de facturation du seul fait qu'il gère ce POI.

---

## 4. Confirmation de prestation

**Décision :** le partenaire déclare la prestation, le voyageur la confirme. C'est un événement financier indépendant, jamais ajouté à `Booking.status`.

**Parcours :** (1) déclaration du partenaire avec montant et devise ; (2) création d'un enregistrement financier distinct ; (3) notification au voyageur ; (4) confirmation ou contestation par le voyageur, avec date et source enregistrées ; (5) calcul de la commission après confirmation (ou après le traitement prévu en cas de non-réponse).

- `external_id` n'est pas une preuve de prestation : il est dérivé de l'identifiant de réservation.
- **[A8]** Le mécanisme de preuve n'est pas imposé ici. `PAYMENT_DESIGN.md` compare, avec un modèle de menace : confirmation authentifiée dans l'app (le voyageur est déjà identifié), lien à usage unique pour un voyageur non connecté, QR/code présenté sur place pour prouver la présence. Toute solution à jeton doit être générée côté serveur, difficile à deviner, à durée limitée, à usage unique, liée à la bonne réservation et au bon partenaire, avec trace des tentatives.
- **[A14]** Le voyageur peut contester dès la V1a (enregistrement du motif). La résolution humaine arrive en V1b. Tant qu'une contestation est ouverte, aucune commission n'est calculée.

### Délai de contestation

72 heures, configurable par tenant (valeur initiale 72 h). Rappels via le worker de notifications. **[A14]** Le délai et les rappels font partie de la V1a.

- **Sans réponse à l'expiration :** le dossier est marqué « non confirmé » et soumis à vérification humaine. L'absence de réponse n'est pas une preuve de réalisation et aucune facturation automatique n'est déclenchée.
- Considérer le silence comme une acceptation contractuelle est une question juridique à valider ; le système ne présume pas cette qualification.
- Le point de départ du délai est défini sans ambiguïté dans `PAYMENT_DESIGN.md` (horodatage de création de la notification in-app, en UTC), pas la livraison d'un e-mail.

---

## 5. Contestation et contrôle humain

**[A1, A2]** L'opérateur financier n'est pas un super-administrateur. Rôle dédié `finance_operator` : identité individuelle, authentification existante, permissions explicitement attribuées, actions enregistrées (date, utilisateur, motif, décision), aucune consultation des finances d'autres tenants sans autorisation spécifique.

**Cycle :** (1) déclaration du partenaire ; (2) confirmation ou contestation du voyageur ; (3) ouverture d'un dossier ; (4) collecte des justificatifs ; (5) décision par un opérateur autorisé ; (6) clôture avec motif et historique.

**Résolutions possibles :** montant confirmé ; montant corrigé avec justification ; prestation non établie ; commission annulée ; dossier transmis pour examen complémentaire.

- Toute décision manuelle est attribuable à un utilisateur identifié.
- Aucune contestation n'est clôturée sans motif et historique.
- Aucun opérateur ne modifie silencieusement une déclaration déjà validée.
- En V1a, les scripts CLI sont en lecture seule : aucune décision manuelle, donc pas encore de rôle nominatif. Les actions humaines arrivent en V1b avec le rôle `finance_operator`.

---

## 6. Annulation après confirmation

| Situation | Commission V1 |
|---|---|
| Annulation par l'une des parties avant la limite gratuite | Aucune |
| Annulation tardive par le voyageur | Sur le montant effectivement retenu et déclaré par le partenaire |
| No-show du voyageur | Sur le montant effectivement retenu et déclaré par le partenaire |
| Annulation par le partenaire | Aucune |
| Force majeure | Aucune (règle commerciale V1, sous réserve de validation contractuelle) |

- Les remboursements restent entre voyageur et partenaire. Aucun moteur de remboursement en V1.
- **[A11]** La force majeure est décidée par un opérateur autorisé, jamais déclarée par les parties.
- La politique d'annulation est versionnée ; la version acceptée est conservée sur la réservation (référence facultative du type `cancellation_policy_version_id`, seul ajout envisagé sur `Booking`, si aucun mécanisme équivalent n'existe).
- **[A11]** La version de la politique est présentée et acceptée explicitement au consentement, avec date d'acceptation conservée. Cela concerne le mobile, l'i18n et les tests. Les réservations antérieures à la date de bascule ne reçoivent pas rétroactivement de politique.
- Le parcours d'annulation après confirmation identifie l'auteur, exige un motif d'une liste fermée, enregistre date/heure, politique applicable, conséquences financières, et préserve l'historique. Aucun nouvel état `Booking` : `cancelled` est utilisé si la transition est autorisée après audit.
- **Rappel :** `/cancel` refuse aujourd'hui tout statut hors `pending`, `requested`, `expired`. Depuis la PR #45, `give_consent` n'accepte plus que `pending` (le contournement par `consent=false` est fermé).

---

## 7. Commission

- Taux initial par défaut : 10 % = 1 000 points de base (1 point de base = 0,01 %).
- Taux par défaut par tenant ; surcharge négociable par partenaire ; date d'effet ; taux stocké en points de base.
- Le taux applicable est déterminé à la date de la déclaration, puis conservé comme snapshot immuable sur la prestation. Une modification ultérieure ne recalcule jamais une commission enregistrée.
- Pas de taux par catégorie générée par l'IA en V1 (catégories propres aux tenants et évolutives).

**Base de calcul :** HT lorsque les taxes sont identifiables et documentées ; sinon montant encaissé déclaré. Le système n'invente ni ne reconstitue un montant HT à partir d'informations fiscales absentes. Il conserve le montant déclaré, les informations fiscales, la base retenue, le taux, le résultat et la règle d'arrondi explicite.

- **[A9]** Contrôles de cohérence obligatoires (HT + taxes = total, taxes ≤ total, taux de taxe plausible selon la configuration du pays) et contrôles par échantillon, car déclarer des taxes réduit la base.
- Le traitement fiscal exact de la commission est à valider par un professionnel.

---

## 8. Entité juridique, géographie et multi-tenant

- **V1 :** une seule entité juridique Discover AI, établie en Algérie. Chaque enregistrement financier porte un `legal_entity_id` dès la V1.
- Distinguer `tenant_id` (destination), `legal_entity_id` (entité responsable de l'opération financière) et le partenaire (opérateur de la prestation).
- Ne jamais déduire l'entité juridique du pays ou de la nationalité du voyageur, ni de la devise.
- **[A3] Règle de sécurité métier :** la commission n'est activable pour un partenaire que si le pays du partenaire correspond au pays de l'entité juridique responsable. Le système vérifie le pays du partenaire et l'entité, pas seulement la devise : une transaction en DZD ne prouve pas qu'elle relève de l'entité algérienne. L'activation est un réglage explicite par tenant, désactivé par défaut.
- Le seed contient un tenant « morocco » (MAD) : l'audit l'analyse explicitement. Aucun transfert transfrontalier ni conversion en V1.
- Aucun historique complexe d'affectation tenant-entité en V1 ; deuxième entité = évolution ultérieure.

---

## 9. Devises

Aucune conversion en V1. Chaque prestation reste dans la devise déclarée. Montant entier, devise explicite, exposant issu des métadonnées de devise, aucune agrégation trompeuse entre devises.

---

## 10. Données sensibles

- **[A6]** Aucune coordonnée bancaire des partenaires n'est collectée en V1 : Discover AI reçoit des commissions, il ne verse rien aux partenaires. Ne collecter que les identifiants légaux nécessaires à l'émission de la facture.
- Tout champ réellement secret est chiffré au repos (étudier la réutilisation du mécanisme AES-GCM existant) ; aucun secret dans le code ; accès limité aux rôles autorisés ; accès et modifications sensibles journalisés ; rien de sensible dans les logs, erreurs ou exports ordinaires.
- Un administrateur de tenant ne voit pas les informations fiscales ou de facturation d'un partenaire sans autorisation spécifique. Le profil partenaire reste distinct des informations publiques du POI.

---

## 11. Facturation

**[A7]** En V1, Discover AI produit des relevés de commission qui ne sont jamais présentés comme des factures fiscales. La référence d'une facture externe peut être enregistrée. La numérotation et l'émission de factures conformes restent hors système jusqu'à validation par un professionnel.

---

## 12. Reporting

Scripts en ligne de commande et export CSV, sur le modèle de `create_tenant`. Pas d'écran financier global, pas d'API de reporting transversal, pas de super-administrateur. Les exports respectent l'isolation des tenants, évitent les données sensibles inutiles et sont tracés.

---

## 13. Risque de contournement

**[A10]** Sans PSP, un partenaire et un voyageur peuvent annuler puis traiter hors plateforme. Suivi par partenaire (taux d'annulation, ratio déclarations/confirmations, délais) à partir de la V1b ; clause de non-contournement à soumettre dans `PAYMENT_COMPLIANCE.md`.

---

## 14. Périmètre et découpage

### V1a — Fondation (autonome)
- Profil partenaire, rattachement daté aux POI, séparation des permissions.
- Règle de sécurité pays/entité et activation par tenant.
- Taux de commission : 10 % par défaut par tenant, surcharge partenaire, date d'effet.
- Déclaration de prestation et montant ; confirmation ou contestation (enregistrement) du voyageur ; délai de 72 h configurable et rappels.
- Calcul et snapshot de la commission ; consultation par script CLI en lecture seule.
- Interfaces minimales nécessaires (action de déclaration côté espace partenaire, action de confirmation ou de contestation côté voyageur, notifications FR/EN) : à cadrer dans `PAYMENT_DESIGN.md`, avec tests.
- La V1a ne dépend ni du moteur de contestation complet, ni du rapprochement, ni des annulations.

### V1b — Contrôle financier (après validation de V1a)
- Contestations et résolution humaine ; rôle `finance_operator` nominatif ; journal d'audit.
- Créances et suivi des commissions ; relevés ; références de factures externes.
- Rapprochement manuel ; suivi des anomalies et contrôles par échantillon.

### V1c — Annulation et politiques (après validation de V1b)
- Politiques d'annulation versionnées ; consentement explicite mobile et i18n.
- Annulation après confirmation avec motifs contrôlés ; force majeure par opérateur.
- Date de bascule : réservations antérieures exclues.

### Exclus de la V1
Intégration d'un PSP (Chargily, SATIM, Stripe, PayPal ou autre) ; paiement en ligne du voyageur ; encaissement ou conservation de fonds ; split payment ; autorisation, capture ou void ; remboursements techniques ; conversion de devises ; deuxième entité juridique ; marketplace de créances ; reporting transversal par API ou interface ; super-administrateur ; commission par catégorie IA ; catalogue tarifaire obligatoire ; prix fixe de réservation pour tous les POI ; circuits packagés et forfaits.

---

## 15. Compatibilité Booking

États existants intouchables : `pending`, `requested`, `confirmed`, `declined`, `expired`, `cancelled`. Aucun nouvel état pour une déclaration, une confirmation, une contestation, une commission, une facture ou un règlement : ces événements appartiennent au domaine financier.

Toute évolution de transition est identifiée, justifiée, couverte par des tests de non-régression et soumise à approbation. Les corrections de consentement et de transitions sont vérifiées contre les tests existants avant toute proposition.

---

## 16. Modes de réservation

**[A12]** L'audit identifie tous les modes de réservation, vérifie lesquels apparaissent dans l'espace partenaire, lesquels permettent une déclaration de prestation, et explique pourquoi certains modes seraient exclus de la commission. Hors `manual_confirm`, la confirmation est immédiate et seul le voyageur est notifié : le partenaire n'est pas dans la boucle.

---

## Annexe A — Amendements intégrés (à valider en committant ce fichier)

| Id | Amendement | Origine |
|---|---|---|
| A1 | Rôle `finance_operator` nominatif, pas de super-administrateur | structure_v2.pdf |
| A2 | Cycle de contestation en six étapes et résolutions | structure_v2.pdf |
| A3 | Restriction pays/entité comme règle de sécurité, seed Maroc analysé | structure_v2.pdf |
| A4 | Partenaire issu de `POIManager`, profil distinct, rattachement daté, permissions séparées | structure_v2.pdf |
| A5 | Découpage V1a / V1b / V1c | structure_v2.pdf |
| A6 | Aucune coordonnée bancaire collectée en V1 | relecture, absent du PDF |
| A7 | Relevé de commission distinct de la facture fiscale | structure_v2.pdf |
| A8 | Mécanisme de preuve choisi selon un modèle de menace | relecture, absent du PDF |
| A9 | Contrôles de cohérence sur la base HT | relecture, absent du PDF |
| A10 | Suivi du contournement et clause de non-contournement | relecture, partiellement dans le PDF |
| A11 | Consentement explicite à la politique, date de bascule, force majeure par opérateur | structure_v2.pdf |
| A12 | Audit des modes de réservation | structure_v2.pdf |
| A13 | Type de déclaration (service, frais retenus tardifs, frais no-show) | relecture, absent du PDF |
| A14 | Délai de 72 h, rappels et enregistrement de la contestation dès V1a ; CLI en lecture seule en V1a | relecture, absent du PDF |

---

## Annexe B — Points laissés à PAYMENT_DESIGN.md

Mécanisme de preuve retenu (A8) ; point de départ exact du délai de 72 h ; règle d'arrondi ; schéma minimal par sous-livraison ; matrice de permissions ; interfaces minimales de la V1a ; stratégie de migration et de retour arrière.
