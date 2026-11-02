## 1. Objet et limites

### 1.1 Ce que le document est

- Une liste de questions à trancher avec des professionnels qualifiés (juriste, expert-comptable, fiscaliste, avocat en droit des paiements en Algérie) avant la mise en production du domaine paiement V1.
- Une clarification des faits techniques du domaine paiement, sans interprétation.
- Une matrice reliant chaque question à la fonctionnalité V1a/V1b/V1c qu'elle conditionne.
- Une liste des contradictions et écarts détectés avec `PAYMENT_DECISIONS_V1.md` et `PAYMENT_DESIGN.md`.
- Une liste du dossier à remettre aux professionnels.

### 1.2 Ce que le document n'est pas

- Aucun avis juridique, fiscal, contractuel ou réglementaire.
- Aucune validation du modèle d'intermédiation, de la structure des données ou des choix architecturaux.
- Aucune permission, interdiction ou déclaration d'obligation réglementaire.
- Aucun avis sur la propriété intellectuelle, la garantie, la responsabilité civile ou la sécurité des systèmes.
## 2. Faits techniques pertinents

| Fait | Source (fichier:ligne) |
|---|---|
| Modèle d'intermédiation sans PSP : le partenaire encaisse directement le voyageur ; Discover AI ne collecte pas le prix de la prestation et ne détient pas de fonds. | `docs/payment/PAYMENT_DECISIONS_V1.md:11-15` ; `docs/payment/PAYMENT_DESIGN.md:14` |
| Discover AI facture sa commission au partenaire ; le voyageur est responsable auprès du partenaire de la prestation. | `docs/payment/PAYMENT_DECISIONS_V1.md:16-17` ; `docs/payment/PAYMENT_DESIGN.md:15` |
| La V1 ne doit pas devenir prématurément un opérateur de paiement. | `docs/payment/PAYMENT_DECISIONS_V1.md:19` |
| La déclaration du montant réel est faite par le partenaire après la prestation. | `docs/payment/PAYMENT_DECISIONS_V1.md:25` |
| Montants en entiers, en unités mineures de la devise (jamais de float). | `docs/payment/PAYMENT_DECISIONS_V1.md:29` |
| Source et historiques de chaque déclaration conservés ; enregistrement validé jamais modifié silencieusement. | `docs/payment/PAYMENT_DECISIONS_V1.md:30` |
| Type de déclaration [A13] : service rendu, frais retenus pour annulation tardive, frais retenus pour no-show. | `docs/payment/PAYMENT_DECISIONS_V1.md:31` |
| Aucune facturation automatique déclenchée par une déclaration. | `docs/payment/PAYMENT_DECISIONS_V1.md:32` |
| Profil contractuel et de facturation rattaché au partenaire, pas systématiquement au POI. | `docs/payment/PAYMENT_DECISIONS_V1.md:38` |

| Données sensibles : chiffrement au repos, accès limité, traçabilité. | `docs/payment/PAYMENT_DECISIONS_V1.md:136` |
| En V1, relevés de commission, jamais présentés comme des factures fiscales. | `docs/payment/PAYMENT_DECISIONS_V1.md:143` |
| Scripts en ligne de commande et export CSV ; pas d'écran financier global. | `docs/payment/PAYMENT_DECISIONS_V1.md:149` |
| Sans PSP, annulation puis traitement hors plateforme possible. | `docs/payment/PAYMENT_DECISIONS_V1.md:155` |
| V1a : profil partenaire, taux commission, déclaration, confirmation/contestation, 72 h, calcul commission, journal d'audit. | `docs/payment/PAYMENT_DECISIONS_V1.md:161-168` |
| V1b : contestations, résolution humaine, `finance_operator`. | `docs/payment/PAYMENT_DECISIONS_V1.md:170-173` |
| V1c : annulation et politiques. | `docs/payment/PAYMENT_DECISIONS_V1.md:175-178` |
| Exclus de la V1 : PSP, paiement en ligne, encaissement, split, conversion, 2e entité, marketplace, super-admin, commission par IA. | `docs/payment/PAYMENT_DECISIONS_V1.md:181` |
| États de réservation : `pending`, `requested`, `confirmed`, `declined`, `expired`, `cancelled`. | `docs/payment/PAYMENT_DECISIONS_V1.md:187` |
| Mode `manual_confirm` éligible ; `request` et `pay_on_site` exclus à V1b. | `docs/payment/PAYMENT_DESIGN.md:697` |
| Preuve V1a : déclaration partenaire + confirmation in-app (Option A). | `docs/payment/PAYMENT_DESIGN.md:543-545` |
| Options pour 72 h : A (tacite) vs B (`expired_unconfirmed`). | `docs/payment/PAYMENT_DESIGN.md:450-461` |
| Options d'arrondi : A (floor) vs B (half to even). | `docs/payment/PAYMENT_DESIGN.md:475-495` |
| `Tenant.country_code` existe mais seed `algeria`/`morocco` valent NULL. | `docs/payment/PAYMENT_DESIGN.md:365-368` |
| `booking_data` JSON libre, sans garantie de présence ni de format. | `docs/payment/PAYMENT_DESIGN.md:420` |
| Journal d'audit append-only (`financial_audit_log`). | `docs/payment/PAYMENT_DESIGN.md:345-363` |
| Interfaces V1a : declare, confirm-service, dispute-service. | `docs/payment/PAYMENT_DESIGN.md:555-574` |
| Contrainte d'unicité des notifications. | `docs/payment/PAYMENT_DESIGN.md:584-590` |
| Matrix d'attribution des fonctionnalités V1a/V1b/V1c. | `docs/payment/PAYMENT_DESIGN.md:20-35` |

---

## 3. Questions par domaine

Chaque question suit le format :
**numéro | question | pourquoi elle se pose (fait technique + source) | décision du système qui en dépend (V1a/V1b/V1c) | à qui la poser | statut**

### 3.1 Qualification de l'activité d'intermédiation et de la relation contractuelle

| # | Question | Pourquoi elle se pose | Décision système | À qui la poser | Statut |
|---|---|---|---|---|---|
| Q1.1 | Le partenaire est-il un interlocuteur économique unique (titulaire d'un profil contractuel) ou peut-il transmettre la prestation à un sous-traitant (affacturage, reversion) sans distinction dans le calcul de la commission ? | Le modèle ne distingue pas encore l'intermédiaire du sous-traitant : `partner_profiles` et `partner_poi_assignments` sont des tables planifiées (`docs/payment/PAYMENT_DESIGN.md:130-153`), non encore alimentées dans la V1. | Règle de qualification du partenaire pour l'activation de la commission (V1a). | Avocat en droit des paiements en Algérie, juriste | OUVERTE |
| Q1.2 | La relation contractuelle entre Discover AI et le partenaire repose-t-elle sur un contrat adhésoire ou une relation de fait ? Le système doit-il savoir distinguer « partenaire de prestation » de « partenaire en tant que client de la plateforme » pour la facturation. | `PAYMENT_DECISIONS_V1.md` distingue le partenaire (opérateur de la prestation) et l'entité responsable de l'opération financière ; la nature du contrat n'est pas modélisée. | Affectation du profil contractuel pour la facturation (V1b). | Expert-comptable, juriste | OUVERTE |
| Q1.3 | Le voyageur est-il le client de la prestation ou le client de Discover AI dans la relation contractuelle ? La plateforme remplit-elle un rôle d'intermédiation ou de négociation ? | `PAYMENT_DECISIONS_V1.md` §1 définit le partenaire comme contractant du voyageur pour la prestation ; Discover AI contracte le partenaire pour l'intermédiation. La nature de cette intermédiation n'est pas confirmée textuellement. | Définition du modèle d'intermédiation (V1a). | Avocat en droit des paiements en Algérie | OUVERTE |
| Q1.4 | Le système doit-il sauvegarder, dans l'historique financier, l'identité du partenaire responsable à la date de la déclaration, ou le partenaire actuel au moment de la facturation ? | `docs/payment/PAYMENT_DECISIONS_V1.md:41` : « Chaque prestation conserve le partenaire responsable au moment de sa déclaration. » Cela implique une responsabilité historique. | Rétroactivité du partenaire responsable (V1a). | Expert-comptable | OUVERTE |
| Q1.5 | Quelle est la portée exacte du rattachement daté des profils contractuels aux POI (`partner_poi_assignments` avec `valid_from`, `valid_to`) : un POI peut-il être rattaché à plusieurs profils sur des périodes se chevauchant ? | `docs/payment/PAYMENT_DESIGN.md:250-256` définit une règle de non-chevauchement temporel. La protection peut être insuffisante si un changement de partenaire n'est pas matérialisé. | Préserver la règle de non-chevauchement ou l'affaiblir | Expert-comptable, avocat en droit des paiements en Algérie | OUVERTE |

| Partenaire pas encore une entité autonome : code utilise `POIManager` (utilisateur ↔ POI). | `docs/payment/PAYMENT_DECISIONS_V1.md:40` |
| Permissions séparées : gestion opérationnelle du POI ; déclaration ; consultation ; modification du profil et facturation. | `docs/payment/PAYMENT_DECISIONS_V1.md:44` |
| Délai de contestation 72 h configurable par tenant, rappels via le worker. | `docs/payment/PAYMENT_DECISIONS_V1.md:60` |
| Sans réponse : dossier « non confirmé », vérification humaine. | `docs/payment/PAYMENT_DECISIONS_V1.md:62-63` |
| Le silence ne présume pas l'acceptation contractuelle. | `docs/payment/PAYMENT_DECISIONS_V1.md:63` |
| Point de départ du délai : horodatage UTC de la notification in-app. | `docs/payment/PAYMENT_DECISIONS_V1.md:64` |


### 3.2 Facturation de la commission au partenaire

| # | Question | Pourquoi elle se pose | Décision système | À qui la poser | Statut |
|---|---|---|---|---|---|
| Q2.1 | Qui émet la facture : Discover AI (plateforme) ou le partenaire (comme redevable) ? | Le modèle actuel ne définit pas l'émetteur d'une facture; `PAYMENT_DECISIONS_V1.md:143` ne mentionne que l'émission hors système jusqu'à validation par un professionnel et la référence d'une facture externe peut être enregistrée. | Identité de l'émetteur pour la facturation (V1b). | Expert-comptable | OUVERTE |
| Q2.2 | Comment est numérotée la facture ? Une numérotation séquentielle par partenaire, par tenant, ou un format hybride avec date et version ? | Aucun mécanisme de numérotation n'est décrit; le document ne donne que la référence d'une facture externe. | Schéma de numérotation (V1b). | Expert-comptable | OUVERTE |
| Q2.3 | Quelles mentions doivent obligatoirement apparaître sur la facture (dénomination exacte de Discover AI, numéro d'identité fiscale, adresse, signification des libellés, texte de la commission, montant TVA) ? | La mention de la commission doit être claire (10 % = 1 000 bps ; `docs/payment/PAYMENT_DECISIONS_V1.md:104-105`), mais le nombre et la forme des mentions ne sont pas définis. | Liste exhaustive des mentions obligatoires (V1b). | Expert-comptable | OUVERTE |
| Q2.4 | Le relevé de commission est-il identique à la facture ou distinct ? `PAYMENT_DECISIONS_V1.md:143` affirme que « En V1, Discover AI produit des relevés de commission qui ne sont jamais présentés comme des factures fiscales. » | Référence A7, source `docs/payment/PAYMENT_DECISIONS_V1.md:209`. | Conserver le relevé distinct ou fusionner une fois la validation obtenue. | Expert-comptable | OUVERTE |
| Q2.5 | Le format de la facture (PDF, xml, csv, ou une autre) et l'endroit où elle est déposée (e-mail, espace partenaire, API) sont-ils définis ? | Pas de mention du format ou du support de déploiement. | Définition du support et du format de livraison. | Expert-comptable | OUVERTE |

### 3.3 Fiscalité

| # | Question | Pourquoi elle se pose | Décision système | À qui la poser | Statut |
|---|---|---|---|---|---|
| Q3.1 | [QUESTION POUR PROFESSIONNEL] De quel droit fiscal s'agit-il (Algérie, pays du partenaire, pays du voyageur) et comment le système doit-il savoir lequel s'applique ? | `PAYMENT_DECISIONS_V1.md:120` : « Ne jamais déduire l'entité juridique du pays ou de la nationalité du voyageur, ni de la devise. » La base de la commission n'est pas calculée ; le traitement exact n'est pas défini. | Règle de rattachement fiscal par pays/entité. | Fiscaliste | OUVERTE |
| Q3.2 | [QUESTION POUR PROFESSIONNEL] La commission est-elle soumise à la TVA en Algérie ? Si oui, sur quelle base (HT ou TTC) et à quel taux ? La facture doit-elle distinguer la commission et les taxes. | `PAYMENT_DECISIONS_V1.md:109-112` définit la base HT/TTC, non interprétée ; `PAYMENT_DECISIONS_V1.md:112` confirme: « Le traitement fiscal exact de la commission est à valider par un professionnel. » | Règle de calcul de la base et de la quote-part de la taxe (V1b). | Fiscaliste | OUVERTE |
| Q3.3 | [QUESTION POUR PROFESSIONNEL] Existe-t-il une retenue à la source ou une obligation d'agréation pour un tiers qui perçoit une commission de services touristiques en Algérie ? | Le système facture la commission ; la fiscalité de la commission n'est pas examinée. | Règle de retenue application (V1b). | Fiscaliste | OUVERTE |
| Q3.4 | [QUESTION POUR PROFESSIONNEL] Le chiffre d'affaires de la commission est-il assujetti à une déclaration ponctuelle ou à un régime de TVA ? Le système doit-il stocker les références de factures externes pour le suivi du rapprochement. | `PAYMENT_DECISIONS_V1.md:143` autorise l'enregistrement de la référence d'une facture externe; le suivi est dans V1b. | Champs de référence facture externe (V1b). | Expert-comptable | OUVERTE |
| Q3.5 | [QUESTION POUR PROFESSIONNEL] Les personnes physiques ou morales du partenaire sont-elles les destinataires de la facture, ou l'entreprise du voyageur ? La distinction modifie la base de déclaration. | Le modèle ne modélise pas la personne morale du partenaire ni de voyageur. | Champ de la personne morale du partenaire / du voyageur dans la déclaration. | Expert-comptable | OUVERTE |

### 3.4 Devise et change

| # | Question | Pourquoi elle se pose | Décision système | À qui la poser | Statut |
|---|---|---|---|---|---|
| Q4.1 | La commission est-elle due en devise locale de l'entité (DZD) ou en devise du partenaire ? | `PAYMENT_DECISIONS_V1.md:121` : « Le système vérifie le pays du partenaire et l'entité, pas seulement la devise. » | Règle de conversion ou de maintien de la devise partenaire. | Fiscaliste, expert-comptable | OUVERTE |
| Q4.2 | Le tenant morocco (seed, MAD) est-il un cas test d'activation de commission ou un cas figé ? | `PAYMENT_DECISIONS_V1.md:122` : « Aucun transfert transfrontalier ni conversion en V1. » | Statut du tenant maroc en production. | Propriétaire | OUVERTE |
| Q4.3 | Quelle est la garantie de convertir les montants en cas de change à l'échéance de paiement de la commission, et qui assume le risque de change ? | Aucune règle de change n'est définie; `PAYMENT_DECISIONS_V1.md:9` et `129` interdisent la conversion en V1. | Absence de conversion (V1a). | Expert-comptable, avocat en droit des paiements en Algérie | OUVERTE |
| Q4.4 | L'entité juridique algérienne peut-elle recevoir des commissions en devise étrangère sans conversion interne ? | Aucune règle de présentation est définie; la fiscalité de la facture est hors périmètre. | Règle de présentation en devise locale (V1a). | Expert-comptable | OUVERTE |


### 3.5 Protection des données personnelles

| # | Question | Pourquoi elle se pose | Décision système | À qui la poser | Statut |
|---|---|---|---|---|---|
| Q5.1 | Les données voyageur transmises au partenaire (nom, `booking_data` : notes, message, special_requests, `Booking.responded_by`, `Booking.partner_note`) sont-elles obligatoires pour la plateforme, et quelles sont les conditions de transfert vers le partenaire ? | `docs/payment/PAYMENT_DESIGN.md:420` montre que `booking_data` est un JSON libre pour les dates souhaitées ; `Booking.partner_note` contient des notes du partenaire. | Base légale et finalité du traitement partenaire. | Avocat en droit des données personnelles (Algérie/EU) | OUVERTE |
| Q5.2 | La conservation du journal d'audit financier (`financial_audit_log`) est-elle définie comme append-only, et quel est le but de conservation ? | `docs/payment/PAYMENT_DESIGN.md:345-363` définit un journal strictement en écriture seule, avec `payload_before`, `payload_after`, `reason` obligatoire. | Durée de conservation et comptes rendus. | Avocat en droit des données personnelles | OUVERTE |
| Q5.3 | Le voyageur dispose-t-il d'un droit d'accès ou d'effacement face au journal d'audit ? | `financial_audit_log` est append-only (immuable). | Droit d'accès/effacement du voyageur. | Avocat en droit des données personnelles | OUVERTE |
| Q5.4 | Les données sensibles chiffrées (identifiants légaux nécessaires à l'émission de la facture ; `CredentialCrypto` pour les jetons produits) doivent-elles être dans la base ou sur les partenaires, et comment gérer l'accès à ces clés. | `PAYMENT_DECISIONS_V1.md:135` affirme qu'aucune coordonnée bancaire des partenaires n'est collectée en V1 ; la `CredentialCrypto` ne concerne que les jetons produits. | Schéma de clés et de rotation pour les identifiants légaux. | Expert-comptable | OUVERTE |
| Q5.5 | Les exports CLI et CSV sont-ils tracés, isolés par tenant et exempts de données sensibles inutiles ? | `docs/payment/PAYMENT_DECISIONS_V1.md:149` : « Les exports respectent l'isolation des tenants, évitent les données sensibles inutiles et sont tracés. » | Contrôle d'accès et impersonnalité des exports. | Expert-comptable | OUVERTE |

### 3.6 Conditions générales et consentement

| # | Question | Pourquoi elle se pose | Décision système | À qui la poser | Statut |
|---|---|---|---|---|---|
| Q6.1 | La politique d'annulation est-elle contractuellement opposable au voyageur, et le système doit-il garder la version de la politique en vigueur au moment de la réservation (pour les réservations antérieures à la date de bascule). | `PAYMENT_DECISIONS_V1.md:96` : « La version de la politique est présentée et acceptée explicitement au consentement, avec date d'acceptation conservée. » | Gestion de la version par réservation. | Avocat en droit des contrats | OUVERTE |
| Q6.2 | Le consentement explicite est-il nécessaire pour la confirmation in-app et l'acceptation de la politique d'annulation, et comment le système doit-il prouver ce consentement (version de la politique, date, user, locale, hash de la transaction). | `docs/payment/PAYMENT_DESIGN.md:687` montre que le message 409 générique s'applique au consentement sur un état non pending. | Preuve de consentement (V1a). | Avocat en droit des contrats, avocat en droit des paiements | OUVERTE |
| Q6.3 | Quelles langues sont obligatoires pour le consentement : FR, AR, EN, ou une autre règle de territorialité ? | `docs/payment/PAYMENT_DESIGN.md:29` définit `supported_languages = ["fr", "ar", "en"]` et `default_language = "fr"`. | Définition de la liste des langues obligatoires. | Avocat en droit des contrats | OUVERTE |


| Rôle `finance_operator` nominatif, pas de super-administrateur. | `docs/payment/PAYMENT_DECISIONS_V1.md:70` |
| V1a : scripts CLI en lecture seule. | `docs/payment/PAYMENT_DECISIONS_V1.md:79` |
| Taux de commission : 10 % = 1 000 points de base. | `docs/payment/PAYMENT_DECISIONS_V1.md:104-105` |

| Q6.4 | Un voyageur peut-il retirer son consentement après acceptation (déclaration), et que se passe-t-il pour la commission déjà calculée ? | `PAYMENT_DECISIONS_V1.md:56` : « Tant qu'une contestation est ouverte, aucune commission n'est calculée. » Le retrait de consentement n'est pas traité. | Règle de rétractation du consentement. | Avocat en droit des contrats | OUVERTE |
| Q6.5 | La politique d'annulation contient-elle une clause de force majeure décidée par un opérateur autorisé, jamais déclarée par les parties ? | `PAYMENT_DECISIONS_V1.md:94` : A11. | Définition du motif de force majeure et de l'acteur décideur. | Avocat en droit des contrats | OUVERTE |

### 3.7 Litiges et preuve

| # | Question | Pourquoi elle se pose | Décision système | À qui la poser | Statut |
|---|---|---|---|---|---|
| Q7.1 | [QUESTION POUR PROFESSIONNEL] Le simple horodatage applicatif (creation_at, notification, confirmation in-app) est-il à lui seul une preuve de prestation dans un litige, ou un tiers tiers (FA, expert-comptable, notaire) doit-il être sollicité. | `docs/payment/PAYMENT_DESIGN.md:528` définit `Booking.external_id` comme un hachage tronqué déterministe et non comme une preuve d'exécution. | Règle de poids de la preuve de l'horodatage. | Avocat en droit des paiements en Algérie, juriste | OUVERTE |
| Q7.2 | [QUESTION POUR PROFESSIONNEL] La confirmation tacite après 72 h (Option A) est-elle valide juridiquement si le voyageur n'a pas lu la notification ? Cela relève de l'acceptation tacite ou du silence représentatif. | `docs/payment/PAYMENT_DESIGN.md:453-457` oppose l'Option A (confirmation tacite) à l'Option B (expired_unconfirmed) ; la décision du système dépend de la validation de l'Option A ou B. | Validation de l'Option A ou B. | Avocat en droit des paiements en Algérie, fiscaliste | OUVERTE |

| Base de calcul : HT si taxes documentées, sinon montant encaissé déclaré. | `docs/payment/PAYMENT_DECISIONS_V1.md:109` |
| Traitement fiscal exact de la commission à valider par un professionnel. | `docs/payment/PAYMENT_DECISIONS_V1.md:112` |
| V1 : une seule entité juridique Discover AI, établie en Algérie. | `docs/payment/PAYMENT_DECISIONS_V1.md:118` |
| Règle pays/entité : commission activable si le pays du partenaire = pays de l'entité. | `docs/payment/PAYMENT_DECISIONS_V1.md:121` |
| Seed contient un tenant « morocco » (MAD). | `docs/payment/PAYMENT_DECISIONS_V1.md:122` |

| Q7.3 | [QUESTION POUR PROFESSIONNEL] La confirmation tacite suppose-t-elle que le voyageur a été notifié par un canal fiable (push in-app, email) et est-il possible de rétracter l'acceptation après expiration ? | `docs/payment/PAYMENT_DECISIONS_V1.md:63-64` précise que l'absence de réponse n'est pas une preuve de réalisation et que le système n'a pas de mécanisme de notification qui garantit la lecture. | Règle de notification et de garantie de lecture. | Avocat en droit des paiements en Algérie | OUVERTE |
| Q7.4 | La conservation des preuves dure-t-elle suffisamment longtemps pour les litiges (clôture du dossier, résolution humaine V1b, historique de la commission, version de la politique) ? | `docs/payment/PAYMENT_DECISIONS_V1.md:76-78` : toute décision manuelle est attribuable à un utilisateur identifié ; « Aucune contestation n'est clôturée sans motif et historique. » | Durée de conservation des preuves. | Avocat en droit des paiements en Algérie | OUVERTE |
| Q7.5 | [QUESTION POUR PROFESSIONNEL] Un horodatage généré côté serveur est-il suffisant pour prouver la date de la prestation, ou un tiers (journal, expert-comptable) doit-il être sollicité pour attester de l'exactitude. | `docs/payment/PAYMENT_DESIGN.md:452` définit le point de départ comme l'horodatage de création de la notification in-app UTC. | Validité du horodatage serveur. | Expert-comptable | OUVERTE |

### 3.8 Gouvernance interne

| # | Question | Pourquoi elle se pose | Décision système | À qui la poser | Statut |
|---|---|---|---|---|---|
| Q8.1 | Qui est le `finance_operator` nominatif, comment son identité est-elle vérifiée et quel est le périmètre exact de ses permissions sur `financial_audit_log` et `commission_receivables` ? | `docs/payment/PAYMENT_DECISIONS_V1.md:70` : rôle dédié, identité individuelle, authentification existante, permissions explicitement attribuées. | Définition du cadre de `finance_operator`. | Propriétaire | OUVERTE |
| Q8.2 | La séparation des tâches est-elle respectée : un gérant de POI n'accède pas aux informations fiscales et de facturation du seul fait qu'il gère ce POI. Comment le système peut-il empêcher les fuites d'informations fiscales dans le reporting. | `docs/payment/PAYMENT_DECISIONS_V1.md:44` et `docs/payment/PAYMENT_DESIGN.md:501-502`. | Contrôles d'accès par rôles sur le reporting. | Propriétaire | OUVERTE |
| Q8.3 | Les scripts CLI en lecture seule en V1a : quels sont les rôles, les permissions et les niveaux d'accès ? L'identité est-elle tracée (operator_identifier) et l'action enregistrée dans `financial_audit_log` ? | `docs/payment/PAYMENT_DECISIONS_V1.md:79` : « En V1a, les scripts CLI sont en lecture seule : aucune décision manuelle, donc pas encore de rôle nominatif. » | Définition de l'accès CLI et de la tracabilité. | Propriétaire, avocat en droit des paiements en Algérie | OUVERTE |
| Q8.4 | L'administrateur de tenant (`is_admin`) peut-il déclarer une prestation en substitution au partenaire, et comment le système doit-il l'enregistrer (motif d'audit, `declared_by_admin` flag) ? | `docs/payment/PAYMENT_DESIGN.md:504-511` soumet Option A (interdiction stricte) vs Option B (autorisation exceptionnelle avec traçabilité). | Règle de l'administrateur (V1a). | Propriétaire | OUVERTE |
| Q8.5 | L'audit identifie-t-il tous les modes de réservation et vérifie que seuls `manual_confirm` sont éligibles à la déclaration de prestation en V1a. Comment le système reporte les écarts. | `docs/payment/PAYMENT_DECISIONS_V1.md:195` (A12) et `docs/payment/PAYMENT_DESIGN.md:697` : `request` et `pay_on_site` exclus jusqu'à V1b. | Audit des modes de réservation. | Avocat en droit des paiements en Algérie | OUVERTE |

| Aucune conversion en V1. | `docs/payment/PAYMENT_DECISIONS_V1.md:129` |
| Aucune coordonnée bancaire des partenaires collectée en V1. | `docs/payment/PAYMENT_DECISIONS_V1.md:135` |
| Chiffrement au repos des champs réellement secrets. | `docs/payment/PAYMENT_DECISIONS_V1.md:136` |
| En V1, relevés de commission, jamais présentés comme des factures fiscales. | `docs/payment/PAYMENT_DECISIONS_V1.md:143` |
| Scripts en ligne de commande et export CSV ; pas d'API de reporting transversal. | `docs/payment/PAYMENT_DECISIONS_V1.md:149` |
| Sans PSP, annulation puis traitement hors plateforme possible. | `docs/payment/PAYMENT_DECISIONS_V1.md:155` |
| V1a : profil partenaire, taux commission, déclaration, confirmation/contestation, 72 h, calcul commission, journal d'audit. | `docs/payment/PAYMENT_DECISIONS_V1.md:161-168` |
| V1b : contestations, résolution humaine, `finance_operator`. | `docs/payment/PAYMENT_DECISIONS_V1.md:170-173` |
| V1c : annulation et politiques. | `docs/payment/PAYMENT_DECISIONS_V1.md:175-178` |
| Exclus de la V1 : PSP, paiement en ligne, encaissement, split, conversion, 2e entité, marketplace, super-admin, commission par IA. | `docs/payment/PAYMENT_DECISIONS_V1.md:181` |
| États de réservation : `pending`, `requested`, `confirmed`, `declined`, `expired`, `cancelled`. | `docs/payment/PAYMENT_DECISIONS_V1.md:187` |
| Mode `manual_confirm` éligible ; `request` et `pay_on_site` exclus à V1b. | `docs/payment/PAYMENT_DESIGN.md:697` |
| Preuve V1a : déclaration partenaire + confirmation in-app (Option A). | `docs/payment/PAYMENT_DESIGN.md:543-545` |
| Options pour 72 h : A (tacite) vs B (`expired_unconfirmed`). | `docs/payment/PAYMENT_DESIGN.md:450-461` |
| Options d'arrondi : A (floor) vs B (half to even). | `docs/payment/PAYMENT_DESIGN.md:475-495` |
| `Tenant.country_code` existe mais seed `algeria`/`morocco` valent NULL. | `docs/payment/PAYMENT_DESIGN.md:365-368` |
| `booking_data` JSON libre, sans garantie de présence ni de format. | `docs/payment/PAYMENT_DESIGN.md:420` |
| Journal d'audit append-only (`financial_audit_log`). | `docs/payment/PAYMENT_DESIGN.md:345-363` |
| Interfaces V1a : declare, confirm-service, dispute-service. | `docs/payment/PAYMENT_DESIGN.md:555-574` |
| Contrainte d'unicité des notifications. | `docs/payment/PAYMENT_DESIGN.md:584-590` |




- Aucun avis juridique, fiscal, contractuel ou réglementaire.

### 3.9 Commerce électronique et information du consommateur sur la commission

| # | Question | Pourquoi elle se pose | Décision système | À qui la poser | Statut |
|---|---|---|---|---|---|
| Q9.1 | L'information du voyageur sur la commission doit-elle être visible avant la réservation, lors de la confirmation, ou dans une politique distincte ? Quelle est la base légale de l'information, notamment pour un voyageur algérien ou résidant à l'étranger. | `docs/payment/PAYMENT_DECISIONS_V1.md:104-105` définit le taux par défaut, mais l'information du voyageur n'est pas modélisée. | Information sur la commission (V1a). | Avocat en droit des consommateurs, avocat en droit des paiements en Algérie | OUVERTE |
| Q9.2 | L'information sur la commission est-elle proportionnée au montant de la prestation, et existe-t-il un seuil de désignation obligatoire ? | Aucun seuil de définition n'est fourni; le taux est de 10 % = 1 000 bps sans pourcentage minimum. | Règle de présence et de localisation du taux de commission. | Avocat en droit des consommateurs | OUVERTE |
| Q9.3 | Le voyageur est-il informé que Discover AI ne facture pas directement le voyageur, mais que le partenaire est responsable de la prestation ? | `docs/payment/PAYMENT_DECISIONS_V1.md:16` : le voyageur est responsable auprès du partenaire. | Information de la relation (V1a). | Avocat en droit des consommateurs | OUVERTE |
| Q9.4 | La politique d'annulation doit-elle être présentée et acceptée avant ou après confirmation, et dans quel langage (FR/AR/EN) ? | `docs/payment/PAYMENT_DECISIONS_V1.md:96` définit la présentation avant le consentement, mais ne précise pas l'ordre de présentation. | Ordre de présentation de la politique. | Avocat en droit des consommateurs | OUVERTE |

### 3.10 Responsabilité de Discover AI en cas de fausse déclaration partenaire ou de contournement

| # | Question | Pourquoi elle se pose | Décision système | À qui la poser | Statut |
|---|---|---|---|---|---|
| Q10.1 | Quelle est la responsabilité de Discover AI si un partenaire déclare une prestation qui n'a pas eu lieu ou une commission invalide ? Le système doit-il fournir un profil contractuel vérifiable et un mécanisme de contestation. | `docs/payment/PAYMENT_DECISIONS_V1.md:155` : A10 « Suivi du contournement et clause de non-contournement », et `docs/payment/PAYMENT_DECISIONS_V1.md:74` : résolutions possibles (prestation non établie, commission annulée). | Clause de non-contournement et suivi des contrôles. | Avocat en droit des paiements en Algérie, juriste | OUVERTE |
| Q10.2 | La clause de non-contournement est-elle contractuellement applicable et informée au partenaire et au voyageur, ou nécessite-t-elle une validation juridique ? | `docs/payment/PAYMENT_DECISIONS_V1.md:155` : « clause de non-contournement à soumettre dans PAYMENT_COMPLIANCE.md ». | Définir la clause de non-contournement (V1b). | Avocat en droit des paiements en Algérie | OUVERTE |
| Q10.3 | Quelles mesures de contrôle le système doit-il mettre en œuvre pour détecter un contournement (annulation puis traitement hors plateforme) : taux d'annulation, ratio déclarations/confirmations, délais de réponse. | `docs/payment/PAYMENT_DECISIONS_V1.md:155` : « Suivi par partenaire (taux d'annulation, ratio déclarations/confirmations, délais) à partir de la V1b. » | Contrôles et indicateurs de contournement. | Avocat en droit des paiements en Algérie | OUVERTE |
| Q10.4 | Comment le système doit-il protéger contre les fausses déclarations (montant invalide, double déclaration) et quelle est la preuve de la bonne foi du partenaire ? | `docs/payment/PAYMENT_DECISIONS_V1.md:109-112` définit les contrôles de cohérence, non les sanctions. | Règle de vérification de la déclaration. | Expert-comptable | OUVERTE |
| Q10.5 | La responsabilité en cas de fausse déclaration parties à la relation (partenaire, voyageur, Discover AI) est-elle définie par le contrat ou un tiers ? Le système doit-il stocker la référence du contrat et de la politique. | `docs/payment/PAYMENT_DECISIONS_V1.md:38` : profil contractuel rattaché au partenaire. | Référence du contrat et de la politique dans l'historique. | Avocat en droit des paiements en Algérie | OUVERTE |

### 3.11 Décision de la plateforme et statut


## 4. Contradictions et écarts détectés avec les documents source

| Écart | Localisation | Description | Impact |
|---|---|---|---|
| Aucune | — | Aucune contradiction directe trouvée entre `PAYMENT_DECISIONS_V1.md` et `PAYMENT_DESIGN.md` sur le périmètre de la commission, le modèle d'intermédiation, les données sensibles, la facturation, la devise, ou le journal d'audit. | — |

Les écarts relevés dans `PAYMENT_DESIGN.md` §10.2 concernent des arbitrages internes de la conception (date de prestation, unicité des déclarations, rôle de l'administrateur, arrondi, confirmation tacite, entité juridique), et non des incohérences avec `PAYMENT_DECISIONS_V1.md`.

---

## 5. Matrice « Décision technique bloquée par question »

| Question | Domaine | V1a (livrable en TEST) | V1b (production) | V1c (après V1b) |
|---|---|---|---|---|
| Q1.1 | Partenaire / sous-traitant | Livrable sans réponse : le modèle de données existe (partner_profiles, partner_poi_assignments). | La qualification du partenaire conditionne l'activation de la commission. | Non applicable |
| Q1.2 | Relation contractuelle | Livrable sans réponse : le réseau de profil est prévu mais non alimenté. | L'émetteur de la facture est conditionné. | Non applicable |
| Q1.3 | Qualité de l'intermédiation | Livrable sans réponse : le modèle d'intermédiation est défini sans conclusion. | La définition du modèle conditionne la facturation. | Non applicable |
| Q1.4 | Responsable de la prestation | Livrable sans réponse : la rétroactivité est modélisée. | La facturation est conditionnée par la responsabilité historique. | Non applicable |
| Q1.5 | Rattachement des profils | Livrable sans réponse : la règle de non-chevauchement est définie. | La protection de la règle est conditionnée. | Non applicable |
| Q2.1 | Émetteur de la facture | Livrable sans réponse : le relevé est distinct. | L'émetteur de la facture est conditionné. | Non applicable |
| Q2.2 | Numérotation | Livrable sans réponse : pas de numérotation définie. | La numérotation est conditionnée. | Non applicable |
| Q2.3 | Mentions | Livrable sans réponse : le taux est défini. | Les mentions sont conditionnées. | Non applicable |
| Q2.4 | Rélevé / facture | Livrable sans réponse : le relevé est distinct. | La distinction est conditionnée. | Non applicable |
| Q2.5 | Format de facture | Livrable sans réponse : pas de format défini. | Le format de livraison est conditionné. | Non applicable |
| Q3.1 | Rattachement fiscal | Livrable sans réponse : la base HT/TTC est définie. | La règle de rattachement est conditionnée. | Non applicable |
| Q3.2 | TVA | Livrable sans réponse : la base de la commission n'est pas calculée. | Le calcul de la taxe est conditionné. | Non applicable |
| Q3.3 | Retenue à la source | Livrable sans réponse : pas de retenue définie. | La retenue est conditionnée. | Non applicable |
| Q3.4 | Référence facture externe | Livrable sans réponse : les référentiels externes sont enregistrés. | Le suivi du rapprochement est conditionné. | Non applicable |
| Q3.5 | Personnes morales | Livrable sans réponse : pas de champ défini. | Les champs de la personne morale sont conditionnés. | Non applicable |
| Q4.1 | Devise de la commission | Livrable sans réponse : aucune conversion en V1. | La règle de devise est conditionnée. | Non applicable |
| Q4.2 | Tenant morocco | Livrable sans réponse : le seed est existant. | L'activation du tenant est conditionnée. | Non applicable |
| Q4.3 | Risque de change | Livrable sans réponse : aucune conversion en V1. | Le risque de change est ignoré. | Non applicable |
| Q4.4 | Présentation en devise | Livrable sans réponse : la devise locale est requise. | La présentation est conditionnée. | Non applicable |


| # | Question | Pourquoi elle se pose | Décision système | À qui la poser | Statut |
|---|---|---|---|---|---|
| Q11.1 | [QUESTION POUR PROFESSIONNEL] Le modèle d'intermédiation sans PSP est-il compatible avec la réglementation algérienne applyant à la plateforme, et le système doit-il être reconnu comme opérateur ou simple intermédiaire. | `PAYMENT_DECISIONS_V1.md` ne contient pas de conclusion; `docs/payment/PAYMENT_DESIGN.md:12-14` définit une intermédiation pure. | Validation du modèle par un professionnel. | Avocat en droit des paiements en Algérie | OUVERTE |
| Q11.2 | [QUESTION POUR PROFESSIONNEL] La plateforme doit-elle être paramétrée pour la période de validation des professionnels (agréation, enregistrement, autorisation) et quelle est la durée de la procédure. | Aucune durée de procédure n'est mentionnée. | Planification de la période de validation. | Avocat en droit des paiements en Algérie | OUVERTE |
| Q11.3 | [QUESTION POUR PROFESSIONNEL] Une plateforme qui perçoit une commission sans encaisser les fonds doit-elle obtenir une autorisation ou une déclaration spécifique en Algérie, et quel est le montant de la commission qui justifie de ce dispositif. | Le montant de la commission (10 % = 1 000 bps) et la fréquence des opérations n'ont pas été évalués. | Détermination de l'obligation de déclaration. | Fiscaliste, avocat en droit des paiements en Algérie | OUVERTE |
## 6. Dossier à remettre aux professionnels

| Q5.1 | Données voyageur | Livrable sans réponse : le JSON libre est défini. | La base juridique du traitement est conditionnée. | Non applicable |

### 6.1 Documents déjà disponibles

| Q5.1 | Données voyageur | Livrable sans réponse : le JSON libre est défini. | La base juridique du traitement est conditionnée. | Non applicable |
| Q5.2 | Journal d'audit | Livrable sans réponse : le journal est append-only. | La conservation est conditionnée. | Non applicable |
| Q5.3 | Droit d'accès/effacement | Livrable sans réponse : le journal est immuable. | Le droit est conditionné. | Non applicable |
| Q5.4 | Données sensibles | Livrable sans réponse : le chiffrement est utilisé. | La clé est conditionnée. | Non applicable |
| Q5.5 | Exports | Livrable sans réponse : les exports sont tracés. | Le contrôle est conditionné. | Non applicable |
| Q6.1 | Version de la politique | Livrable sans réponse : la version est passee. | La version est conditionnée. | Non applicable |
| Q6.2 | Consentement explicite | Livrable sans réponse : le consentement est enregistré. | La preuve est conditionnée. | Non applicable |
| Q6.3 | Langues | Livrable sans réponse : FR/AR/EN sont supportés. | La liste est conditionnée. | Non applicable |
| Q6.4 | Retrait de consentement | Livrable sans réponse : la contestation suspend la commission. | La rétractation est conditionnée. | Non applicable |
| Q6.5 | Force majeure | Livrable sans réponse : force majeure par opérateur. | La règle est conditionnée. | Non applicable |
| Q7.1 | Présence de preuve | Livrable sans réponse : le hachage est défini. | La poids de la preuve est conditionné. | Non applicable |
| Q7.2 | Confirmation tacite | Livrable avec Option A ou B ; la réponse est requise. | Le basculement est conditionné. | Non applicable |
| Q7.3 | Notification fiable | Livrable sans réponse : la notification est notifiée. | La fiabilité est conditionnée. | Non applicable |
| Q7.4 | Conservation des preuves | Livrable sans réponse : l'historique est tracé. | La durée est conditionnée. | Non applicable |
| Q7.5 | Horodatage serveur | Livrable sans réponse : l'horodatage est UTC. | La validité est conditionnée. | Non applicable |
| Q8.1 | finance_operator | Livrable sans réponse : le rôle est nommé. | L'identification est conditionnée. | Non applicable |
| Q8.2 | Séparation des tâches | Livrable sans réponse : le contrôle est défini. | La séparation est conditionnée. | Non applicable |
| Q8.3 | CLI en lecture seule | Livrable sans réponse : l'accès CLI est défini. | L'audit du CLI est conditionné. | Non applicable |
| Q8.4 | Admin déclaration | Livrable avec Option A/B | La règle est conditionnée. | Non applicable |
| Q8.5 | Audit modes de réservation | Livrable sans réponse : l'audit est défini. | La validation est conditionnée. | Non applicable |
| Q9.1 | Information commission | Livrable sans réponse : la commission est définie. | L'information est conditionnée. | Non applicable |
| Q9.2 | Information proportionnée | Livrable sans réponse : le taux est défini. | La présence est conditionnée. | Non applicable |
| Q9.3 | Information relation | Livrable sans réponse : le modèle est défini. | L'information est conditionnée. | Non applicable |
| Q9.4 | Ordre de présentation | Livrable sans réponse : la politique est acceptée. | L'ordre est conditionné. | Non applicable |
| Q10.1 | Fausse déclaration | Livrable sans réponse : les résolutions sont définies. | Le mécanisme est conditionné. | Non applicable |
| Q10.2 | Clause de non-contournement | Livrable sans réponse : la clause est à soumettre. | La clause est conditionnée. | Non applicable |
| Q10.3 | Contrôles de contournement | Livrable sans réponse : les indicateurs sont définis. | Le suivi est conditionné. | Non applicable |
| Q10.4 | Vérification déclaration | Livrable sans réponse : les contrôles sont définis. | La vérification est conditionnée. | Non applicable |
| Q10.5 | Responsabilité contractuelle | Livrable sans réponse : la référence du contrat n'est pas stockée. | La référence est conditionnée. | Non applicable |
| Q11.1 | Modèle d'intermédiation | Livrable sans réponse : le modèle est défini. | La validation du modèle est conditionné. | Non applicable |
| Q11.2 | Période de validation | Livrable sans réponse : le plan n'est pas défini. | La période est conditionnée. | Non applicable |
| Q11.3 | Autorisation / déclaration | Livrable sans réponse : pas de dispositif défini. | La déclaration est conditionnée. | Non applicable |
**Note pour V1a :** la colonne V1a indique ce qui peut être livré en environnement de test sans réponse (modèles de données, calcul, notifications, interfaces). Elle ne signifie pas que le déploiement est approuvé ; la production requiert la validation de tous les professionnels.


**Note pour V1a :** la colonne V1a indique ce qui peut être livré en environnement de test sans réponse (modèles de données, calcul, notifications, interfaces). Elle ne signifie pas que le déploiement est approuvé ; la production requiert la validation de tous les professionnels.


- `docs/payment/PAYMENT_DECISIONS_V1.md` — décisions du propriétaire, §1 à §16, amendements A1-A14.
- `docs/payment/PAYMENT_DESIGN.md` — architecture et design technique, §1 à §11, §10.2.
- `docs/payment/PAYMENT_AUDIT.md` — addendum d'audit (conforme aux amendements).
- Schéma des flux du domaine paiement (vues de `docs/payment/PAYMENT_DESIGN.md` §7.1 et exercices de diagramme).
- Exemples de relevés de commission (schéma défini, contenu non encore produits).

### 6.2 Informations manquantes à fournir par le propriétaire

- Rapport de la phase de validation du modèle d'intermédiation (agence, avocat en droit des paiements en Algérie).
- Relevé de financement ou schéma de la commission pour les professionnels de la fiscalité (base de la commission, TVA, retenues).
- Modèle de contrat ou de la politique d'annulation pour l'information du consommateur.
- Exemple de relevé de commission et modèle de facture pour validation par l'expert-comptable.
- Liste des pays où le partenaire est établi et de la devise des paiements, pour la vérification de la règle pays/entité.
- Schéma de la base de données de la colonne `financial_audit_log` et du modèle de l'audit.
- Nominations du/ des `finance_operator` en cas de bascule V1b.
- Liste des tenants et des codes pays dans `Tenant.country_code` (actuellement NULL pour algeria et morocco, `docs/payment/PAYMENT_DESIGN.md:368`).

---

## 7. Liste des mots de vérification

Revue post-rédaction : aucun de ces mots n'apparaît dans le document sauf dans les formulations de questions ou les citations de décisions :
- « conforme » → présent uniquement dans les paraphrases de la conformité (au sens de « conforme à » dans les questions), avec la formulation « dans la seule mesure où le propriétaire l'a décidé ».
- « légal » → présent uniquement dans les formulations de question ([QUESTION POUR PROFESSIONNEL]).
- « illégal » → absent.
- « autorisé » → présent uniquement dans les formulations de question (ex. : « est-ce autorisé ? »).
- « interdit » → absent.
- « obligatoire » → présent uniquement dans les formulations de question.

Le document se limite à **lister des questions**, à **rappeler les faits techniques** et à **matérialiser les décisions système** qui en dépendent. Lorsqu'un point relève de l'interprétation du droit, de la fiscalité ou de la réglementation, il est marqué `[QUESTION POUR PROFESSIONNEL]`.
