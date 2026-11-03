# Conformité et questions pour professionnels — domaine paiement V1

> **Document de référence :** Point de contrôle 3 du chantier paiement (s'appuie sur `docs/payment/PAYMENT_DECISIONS_V1.md` et `docs/payment/PAYMENT_DESIGN.md`).    
> **Date de rédaction :** 2 novembre 2026.  
> **Branche de travail :** `docs/payment-decisions-v1`.  
> **Statut :** Liste de questions, aucun avis juridique. Ce document recense les interrogations techniques, comptables, fiscales et contractuelles destinées aux conseils qualifiés avant la mise en production du domaine paiement. Il ne formule aucune conclusion de droit.

---

## 1. Objet et limites

### 1.1 Ce que le document est
- Un inventaire exhaustif et structuré des questions à soumettre aux professionnels qualifiés (juriste, expert-comptable, fiscaliste, avocat en droit des affaires et des paiements en Algérie) préalablement à toute mise en production financière.
- Un relevé fidèle des faits techniques et des modèles de données effectivement présents dans le code source de Discover AI.
- Une matrice d'impact technique établissant le lien direct entre chaque question et les composants logiciels des versions V1a, V1b et V1c.
- Une consignation objective des contradictions et divergences d'arbitrage constatées entre les documents directeurs (`docs/payment/PAYMENT_DECISIONS_V1.md` et `docs/payment/PAYMENT_DESIGN.md`).
- Une liste des pièces et données contractuelles que le propriétaire du projet doit préparer pour constituer le dossier des professionnels.

### 1.2 Ce que le document n'est pas
- Aucun avis juridique, fiscal, comptable ou réglementaire.
- Aucune qualification de légalité, de conformité ou d'autorisation concernant un flux financier, un schéma d'intermédiation ou un stockage de données.
- Aucune interprétation doctrinale ou jurisprudentielle d'un texte de loi, d'un code ou d'une directive bancaire.
- Aucune validation formelle d'un choix d'architecture ou de modèle de données.

Chaque point relevant de l'appréciation du droit ou de la fiscalité est explicitement identifié par la mention `[QUESTION POUR PROFESSIONNEL]`.

---

## 2. Faits techniques pertinents

Le tableau ci-dessous récapitule l'ensemble des faits techniques observables dans la base de code et les documents directeurs de la branche, sans interprétation subjective :

| # | Fait technique vérifiable | Source (fichier:ligne ou document) |
|---|---|---|
| F1 | Modèle d'intermédiation pur : le partenaire encaisse directement le voyageur ; Discover AI n'encaisse ni ne détient de fonds de tiers et n'intègre aucun PSP en V1. | `docs/payment/PAYMENT_DECISIONS_V1.md:11-19` ; `docs/payment/PAYMENT_DESIGN.md:12-16` |
| F2 | Discover AI facture sa commission au partenaire après confirmation de la prestation ; la plateforme ne promet ni ne gère de remboursement technique au voyageur. | `docs/payment/PAYMENT_DECISIONS_V1.md:16-17` ; `docs/payment/PAYMENT_DESIGN.md:14-15` |
| F3 | Le montant réel est déclaré par le partenaire après exécution ; `Booking.price` (`backend/app/models.py:344`, Float) est dormant et jamais utilisé pour les calculs financiers. | `docs/payment/PAYMENT_DECISIONS_V1.md:25-27` ; `docs/payment/PAYMENT_DESIGN.md:102` |
| F4 | Tous les montants financiers sont stockés en entiers (`BigInteger`), en unités mineures de la devise (centimes), avec devise explicite (ISO 4217). | `docs/payment/PAYMENT_DECISIONS_V1.md:29` ; `docs/payment/PAYMENT_DESIGN.md:102, 291` |
| F5 | Trois types de déclarations sont prévus : service rendu (`service_rendered`), frais d'annulation tardive (`late_cancellation_fee`), frais de no-show (`no_show_fee`). | `docs/payment/PAYMENT_DECISIONS_V1.md:31` ; `docs/payment/PAYMENT_DESIGN.md:289` |
| F6 | Une déclaration n'engendre jamais de facturation automatique ; le profil contractuel et de facturation est rattaché au partenaire et non au POI. | `docs/payment/PAYMENT_DECISIONS_V1.md:32, 38` ; `docs/payment/PAYMENT_DESIGN.md:107-133` |
| F7 | Dans le code existant, le partenaire n'est pas une entité autonome mais un utilisateur rattaché à un POI via la table `poi_managers`. | `backend/app/models.py:366-389` ; `docs/payment/PAYMENT_DECISIONS_V1.md:40` |
| F8 | Séparation des permissions : gestion opérationnelle du POI, déclaration de service, consultation, modification du profil contractuel et facturation. | `docs/payment/PAYMENT_DECISIONS_V1.md:44` ; `docs/payment/PAYMENT_DESIGN.md:500-523` |
| F9 | Un administrateur du tenant (`is_admin == True`) a accès à toutes les réservations du tenant via `_scope_filter` et peut répondre aux demandes (`Booking.responded_by`). | `backend/app/api/v1/endpoints/partner.py:76-86, 339` ; `docs/payment/PAYMENT_AUDIT.md:690-698` |
| F10 | Délai de confirmation/contestation par le voyageur fixé à 72 h configurable par tenant, calculé depuis l'horodatage UTC de création de la notification. | `docs/payment/PAYMENT_DECISIONS_V1.md:60-64` ; `docs/payment/PAYMENT_DESIGN.md:295, 450` |
| F11 | Taux de commission par défaut fixé à 10 % (1 000 bps), surchargeable par partenaire, stocké en points de base (`Integer`). | `docs/payment/PAYMENT_DECISIONS_V1.md:104-105` ; `docs/payment/PAYMENT_DESIGN.md:267` |
| F12 | Snapshot immuable pris à la déclaration : `legal_entity_id` et `applied_rate_bps` sont figés dans `service_declarations` dès l'insertion. | `docs/payment/PAYMENT_DESIGN.md:278, 283-284` |
| F13 | Base de calcul : montant HT si taxes distinctes et documentées, sinon montant encaissé déclaré TTC. Contrôles de cohérence sur les taxes. | `docs/payment/PAYMENT_DECISIONS_V1.md:109-111` ; `docs/payment/PAYMENT_DESIGN.md:465-471` |
| F14 | Une seule entité juridique Discover AI en V1 (Algérie) ; règle de sécurité pays/entité désactivant la commission si pays partenaire ≠ pays entité. | `docs/payment/PAYMENT_DECISIONS_V1.md:118, 121` ; `docs/payment/PAYMENT_DESIGN.md:374-378` |
| F15 | Le modèle `Tenant` possède une colonne `country_code` (`backend/app/models.py:51`, ISO 3166-1 alpha-2), mais les deux seeds `algeria` et `morocco` la laissent à `NULL`. | `backend/app/models.py:51, 68-76` ; `backend/app/initial_data.py:24-47` |
| F16 | Le seed initialise un tenant `morocco` en devise `MAD` ; la fonction `_create_demo_tenants` retourne immédiatement si `algeria` existe. | `backend/app/initial_data.py:20-22, 36-47` |
| F17 | Aucune conversion de devise en V1 ; chaque opération reste dans sa devise d'origine. | `docs/payment/PAYMENT_DECISIONS_V1.md:129` ; `docs/payment/PAYMENT_DESIGN.md:59` |
| F18 | Aucune coordonnée bancaire partenaire n'est collectée en V1 ; seuls les identifiants fiscaux légaux nécessaires à la facturation sont enregistrés. | `docs/payment/PAYMENT_DECISIONS_V1.md:135` ; `docs/payment/PAYMENT_DESIGN.md:57` |
| F19 | Chiffrement symétrique AES-256-GCM au repos des identifiants sensibles via `CredentialCrypto`. | `backend/app/services/credential_crypto.py:25-112` ; `docs/payment/PAYMENT_DESIGN.md:220` |
| F20 | Les détails transmis au partenaire (`_DETAILS_ALLOWED_KEYS`) excluent téléphone et e-mail mais incluent des champs texte libre (`notes`, `message`, `special_requests`). | `backend/app/api/v1/endpoints/partner.py:45-73` ; `docs/payment/PAYMENT_AUDIT.md:694-697` |
| F21 | En V1, Discover AI émet des relevés de commission internes, jamais présentés comme des factures fiscales officielles ; référence de facture externe facultative. | `docs/payment/PAYMENT_DECISIONS_V1.md:143` ; `docs/payment/PAYMENT_DESIGN.md:58` |
| F22 | Reporting financier V1 via scripts CLI en lecture seule et exports CSV isolés par tenant (`app/reporting_finance.py`). | `docs/payment/PAYMENT_DECISIONS_V1.md:149` ; `docs/payment/PAYMENT_DESIGN.md:621-625` |
| F23 | Journal d'audit financier append-only (`financial_audit_log`) avec traçabilité nominative ou identifiant d'opérateur CLI (`operator_identifier`). | `docs/payment/PAYMENT_DESIGN.md:339-363` |
| F24 | L'index unique partiel `uq_notifications_booking_unique` sur `notifications` empêche deux notifications de même type pour un même `booking_id`. | `backend/app/models.py:460-469` ; `backend/app/services/notification_service.py:68-80` |
| F25 | L'identifiant externe `external_id` (`EXT-{booking_id[:8]}`) est déterministe et ne constitue pas une preuve de réalisation. | `backend/app/api/v1/endpoints/bookings.py:259` ; `docs/payment/PAYMENT_DECISIONS_V1.md:54` |
| F26 | Absence totale de colonne temporelle de date de séjour ou de prestation sur `Booking` ; les dates saisies résident dans le JSON libre `booking_data`. | `backend/app/models.py:332-364` ; `docs/payment/PAYMENT_DESIGN.md:410-422` |

---

## 3. Questions par domaine à soumettre aux professionnels

Chaque question est formulée sans préjuger de la réponse juridique, avec son contexte technique, son impact système et son destinataire.

### 3.1 Qualification de l'activité d'intermédiation et relation contractuelle

| # | Question pour professionnel | Contexte technique et source | Décision système conditionnée | Destinataire | Statut |
|---|---|---|---|---|---|
| Q1.1 | Quelle est la qualification juridique exacte de l'activité de Discover AI : simple intermédiaire technique, courtier en ligne, ou agence de voyage / opérateur touristique ? | Discover AI met en relation des voyageurs et des prestataires touristiques locaux via une plateforme logicielle sans manipuler les fonds (`docs/payment/PAYMENT_DECISIONS_V1.md:11-19`). | Qualification légale du service et mentions obligatoires dans les CGU / contrats partenaires (V1a). | Avocat en droit des affaires / droit numérique (Algérie) | OUVERTE |
| Q1.2 | Le fait de calculer et percevoir une commission d'intermédiation sur des réservations touristiques requiert-il un agrément ministériel spécifique (ex. licence d'agence de voyage, agrément d'intermédiation touristique) ? | Discover AI applique un taux de commission par défaut de 10 % sur les prestations exécutées (`docs/payment/PAYMENT_DECISIONS_V1.md:104-105`). | Condition préalable à la mise en production du calcul de commission (V1a). | Avocat en droit du tourisme / droit commercial (Algérie) | OUVERTE |
| Q1.3 | La relation tripartite (Discover AI, partenaire, voyageur) nécessite-t-elle deux contrats distincts et étanches (CGU voyageur dégageant la plateforme de l'exécution, et convention de partenariat avec le POI) ? | Le modèle prévoit que le partenaire contracte la prestation avec le voyageur, et Discover AI l'intermédiation avec le partenaire (`docs/payment/PAYMENT_DECISIONS_V1.md:13-17`). | Architecture contractuelle et clauses d'exonération de responsabilité de la plateforme (V1a). | Avocat en droit des contrats | OUVERTE |
| Q1.4 | La séparation entre le compte opérationnel du gérant (`POIManager`, `backend/app/models.py:381`) et l'entité juridique débitrice de la commission (`partner_profiles`, `docs/payment/PAYMENT_DESIGN.md:225`) satisfait-elle aux exigences d'identification du débiteur ? | Un POI peut avoir plusieurs gestionnaires physiques, mais les commissions sont adossées au profil d'entreprise (`docs/payment/PAYMENT_DESIGN.md:123-133`). | Modèle de données contractuel partenaire (V1a). | Juriste d'entreprise / Avocat | OUVERTE |
| Q1.5 | Un exploitant de POI agissant en personne physique (artisan, guide individuel sans registre du commerce) peut-il légalement souscrire au contrat de commission ? | Le schéma `partner_profiles` prévoit `trade_register_number` optionnel et `tax_identification_number` (`docs/payment/PAYMENT_DESIGN.md:219-220`). | Validation des statuts juridiques admissibles lors de l'onboarding partenaire (V1a). | Avocat / Expert-comptable | OUVERTE |

### 3.2 Facturation de la commission au partenaire

| # | Question pour professionnel | Contexte technique et source | Décision système conditionnée | Destinataire | Statut |
|---|---|---|---|---|---|
| Q2.1 | Discover AI peut-il se limiter en V1 à l'émission de « relevés de commission » périodiques récapitulatifs, sans délivrer de facture fiscale officielle dématérialisée ? | `docs/payment/PAYMENT_DECISIONS_V1.md:143` stipule que Discover AI n'émet en V1 que des relevés internes, sans numérotation fiscale officielle. | Périmètre du module de facturation V1a/V1b (maintien des relevés ou obligation d'un module de facturation complet). | Expert-comptable / Fiscaliste (Algérie) | OUVERTE |
| Q2.2 | Quelles sont les mentions obligatoires légales devant figurer sur un relevé de commission ou une facture d'intermédiation émise par une société de droit algérien ? | Le modèle `legal_entities` stocke nom, NIF/NIS, registre du commerce et adresse (`docs/payment/PAYMENT_DESIGN.md:204-207`). | Gabarit d'export des relevés et des documents comptables (V1b). | Expert-comptable | OUVERTE |
| Q2.3 | Quel régime de numérotation séquentielle et chronologique doit être appliqué aux relevés ou factures de commission (série unique par société, préfixe par année/tenant, absence de rupture de séquence) ? | La numérotation est actuellement déléguée hors système en V1 (`docs/payment/PAYMENT_DECISIONS_V1.md:143`). | Algorithme de génération des références de facturation dans `commission_receivables` (V1b). | Expert-comptable | OUVERTE |
| Q2.4 | Quel est le délai légal d'émission de la note ou facture de commission suite à l'exécution de la prestation touristique ? | La commission est enregistrée dès confirmation de la prestation par le voyageur (`docs/payment/PAYMENT_DESIGN.md:278, 310`). | Fréquence de génération des relevés et échéances de paiement associées (V1b). | Expert-comptable | OUVERTE |

### 3.3 Fiscalité : assiette, TVA et retenues

| # | Question pour professionnel | Contexte technique et source | Décision système conditionnée | Destinataire | Statut |
|---|---|---|---|---|---|
| Q3.1 | La commission d'intermédiation perçue par Discover AI en Algérie est-elle soumise à la TVA locale ? Si oui, à quel taux (taux normal 19 % ou taux réduit) ? | Le calcul de commission `calculated_commission_minor` est calculé en points de base hors mention explicite de TVA (`docs/payment/PAYMENT_DESIGN.md:289, 472`). | Formule de calcul financier et ajout éventuel d'une colonne de taxe sur la commission (V1a/V1b). | Fiscaliste (Algérie) | OUVERTE |
| Q3.2 | L'assiette de la commission peut-elle être assise sur le montant hors taxes déclaré par le partenaire, et quelles pièces justificatives fiscales Discover AI doit-il archiver pour prouver la déduction de la taxe locale du partenaire ? | La formule retient `amount_minor - tax_amount_minor` si les taxes sont documentées (`docs/payment/PAYMENT_DECISIONS_V1.md:109` ; `docs/payment/PAYMENT_DESIGN.md:467`). | Règles de validation des déclarations dans `service_declarations` et contrôles de cohérence obligatoires (V1a). | Fiscaliste / Expert-comptable | OUVERTE |
| Q3.3 | Existe-t-il une obligation de retenue à la source applicable aux commissions payées par des opérateurs touristiques à une plateforme d'intermédiation en Algérie ? | Le partenaire paiera Discover AI sur présentation du relevé (`docs/payment/PAYMENT_DECISIONS_V1.md:16, 143`). | Gestion des encaissements partiels et des retenues dans `commission_receivables` (V1b). | Fiscaliste | OUVERTE |
| Q3.4 | Quel traitement fiscal et comptable appliquer aux commissions perçues sur des frais d'annulation tardive (`late_cancellation_fee`) ou de no-show (`no_show_fee`) sans exécution physique du service ? | Les amendements A13 incluent ces indemnités dans les types de déclaration éligibles à la commission (`docs/payment/PAYMENT_DECISIONS_V1.md:31`). | Éligibilité fiscale des déclarations d'indemnités dans `service_declarations` (V1c). | Fiscaliste | OUVERTE |

### 3.4 Devise, réglementation des changes et multi-tenant

| # | Question pour professionnel | Contexte technique et source | Décision système conditionnée | Destinataire | Statut |
|---|---|---|---|---|---|
| Q4.1 | Une entité commerciale établie en Algérie peut-elle légalement facturer des commissions d'intermédiation en dinars algériens (DZD) à un partenaire situé à l'étranger, ou la facturation doit-elle obligatoirement s'effectuer en devises étrangères avec rapatriement bancaire ? | Le système interdit toute conversion de devise en V1 (`docs/payment/PAYMENT_DECISIONS_V1.md:129`). | Règle de verrouillage pays/entité interdisant toute facturation transfrontalière en V1a (`docs/payment/PAYMENT_DESIGN.md:374-378`). | Avocat spécialisé en réglementation des changes / Banque d'Algérie | OUVERTE |
| Q4.2 | La règle de sécurité technique désactivant strictement la commission si le pays du partenaire ne correspond pas à l'entité juridique Discover AI (ex. tenant `morocco` en MAD face à l'entité DZ) est-elle suffisante pour prévenir toute infraction à la législation des changes ? | Le tenant `morocco` est présent dans le seed en devise `MAD` sans entité Discover AI au Maroc (`backend/app/initial_data.py:36-47` ; `docs/payment/PAYMENT_DECISIONS_V1.md:121-122`). | Maintien du blocage absolu de la commission sur le tenant Maroc en V1a (`docs/payment/PAYMENT_DESIGN.md:374-378`). | Avocat en droit des changes | OUVERTE |
| Q4.3 | Dans la perspective d'une entité Discover AI internationale (V3), quelles sont les formalités bancaires et déclaratives pour rapatrier légalement des redevances logicielles ou commissions depuis l'étranger vers l'Algérie ? | Cadrage V3 prévu dans [source non versionnée : fournie par le propriétaire] et `docs/payment/PAYMENT_DESIGN.md:46-48`. | Conception de l'architecture multi-entités et passerelles de devises (V3). | Conseil juridique et financier international | OUVERTE |

### 3.5 Protection des données personnelles et conservation

| # | Question pour professionnel | Contexte technique et source | Décision système conditionnée | Destinataire | Statut |
|---|---|---|---|---|---|
| Q5.1 | La transmission au partenaire des données de réservation du voyageur (nom complet `User.full_name`, et champs texte libre de `booking_data` : `notes`, `message`, `special_requests`) est-elle proportionnée au regard de la loi algérienne relative à la protection des données (loi 18-07) et du RGPD européen ? | Ces champs sont transmis dans `PartnerBookingResponse` via `_safe_details` (`backend/app/api/v1/endpoints/partner.py:45-73` ; `docs/payment/PAYMENT_AUDIT.md:694-697`). | Filtrage des champs exposés dans l'API partenaire et recueil de consentement spécifique (V1a). | Délégué à la protection des données (DPO) / Avocat TIC | OUVERTE |
| Q5.2 | Quelle est la durée légale de conservation obligatoire du journal d'audit financier (`financial_audit_log`, `docs/payment/PAYMENT_DESIGN.md:339-363`) pour répondre aux obligations comptables et fiscales ? | Le journal est conçu comme immuable et append-only sans mécanisme de purge automatique (`docs/payment/PAYMENT_DESIGN.md:343-349`). | Politique d'archivage, de purge ou de scellement des logs d'audit financier (V1a). | Expert-comptable / Avocat | OUVERTE |
| Q5.3 | En cas de demande d'effacement ou de suppression de compte par un voyageur (droit à l'oubli), comment concilier l'anonymisation de ses données personnelles avec l'intégrité non altérable du grand livre et du journal d'audit financier ? | `financial_audit_log` conserve `actor_user_id` et les états antérieurs sous forme de snapshots JSON (`docs/payment/PAYMENT_DESIGN.md:353, 359-360`). | Procédure d'anonymisation des identifiants dans les tables financières sans altération des montants (V1a). | DPO / Avocat spécialisé données | OUVERTE |
| Q5.4 | Le chiffrement des identifiants fiscaux au repos via AES-256-GCM (`CredentialCrypto`, `backend/app/services/credential_crypto.py:25-112`) répond-il aux standards réglementaires de sécurité applicables aux données professionnelles sensibles ? | La table `partner_profiles` chiffre `tax_identification_number` au repos (`docs/payment/PAYMENT_DESIGN.md:220`). | Validation de l'architecture de chiffrement et gestion des clés maîtres (V1a). | Expert sécurité / Juriste conformité | OUVERTE |

### 3.6 Conditions générales, politiques d'annulation et consentement

| # | Question pour professionnel | Contexte technique et source | Décision système conditionnée | Destinataire | Statut |
|---|---|---|---|---|---|
| Q6.1 | Quelle est la valeur probante de l'acceptation électronique de la politique d'annulation par le voyageur lors de la réservation (`Booking.consent_given = True`, `consent_timestamp = utcnow()`, `backend/app/models.py:342-343` ; `backend/app/api/v1/endpoints/bookings.py:190-279`) au regard de `docs/payment/PAYMENT_DECISIONS_V1.md:96` en cas de litige civil ? | Le consentement voyageur est horodaté nativement en base lors de l'appel à `give_consent` (`backend/app/models.py:342-343` ; `backend/app/api/v1/endpoints/bookings.py:190-279`) et `docs/payment/PAYMENT_DECISIONS_V1.md:96` prévoit une date d'acceptation conservée. | Exigences techniques de preuve d'acceptation (horodatage simple, signature électronique, journalisation d'IP) (V1a/V1c). | Avocat en droit numérique | OUVERTE |
| Q6.2 | Le fait de présenter les conditions de vente et d'annulation en trois langues (français, arabe, anglais) impose-t-il la primauté légale d'une version linguistique particulière (notamment la version arabe en Algérie) ? | Le modèle `Tenant.supported_languages` (`backend/app/models.py:46` ; `backend/app/initial_data.py:28, 40`) définit `["fr", "ar", "en"]`. | Hiérarchie linguistique des contrats et affichage prioritaire sur mobile et web (V1a/V1c). | Juriste / Avocat en droit commercial | OUVERTE |
| Q6.3 | Quelles conditions juridiques précises doivent définir la « force majeure » permettant l'annulation sans frais ni commission, et cette appréciation peut-elle être réservée exclusivement à l'opérateur Discover AI ? | `docs/payment/PAYMENT_DECISIONS_V1.md:94` (A11) et `docs/payment/PAYMENT_DESIGN.md:42` stipulent que la force majeure est décidée par un opérateur autorisé et jamais par les parties. | Rédaction de la clause de force majeure dans les CGU et écran de validation opérateur (V1c). | Avocat en droit des contrats | OUVERTE |

### 3.7 Preuve de la prestation, contestation et délais de forclusion

| # | Question pour professionnel | Contexte technique et source | Décision système conditionnée | Destinataire | Statut |
|---|---|---|---|---|---|
| Q7.1 | L'approbation in-app de la déclaration par le voyageur (clic de confirmation sur notification push) constitue-t-elle une preuve recevable de l'exécution effective du service ? | L'Option A retenue en V1a repose sur la confirmation in-app du voyageur (`docs/payment/PAYMENT_DESIGN.md:427-440`). | Choix définitif du mécanisme de preuve (Option A in-app vs Option B justificatif papier / Option C QR code) (V1a). | Avocat en droit de la preuve numérique | OUVERTE |
| Q7.2 | Considérer le silence du voyageur après l'expiration du délai de 72 h comme une acceptation tacite ouvrant droit à facturation de la commission (Option A du design) est-il légalement opposable au voyageur et au partenaire ? | `docs/payment/PAYMENT_DESIGN.md:392-395` présente l'Option A (tacite) face à l'Option B (mise en attente `expired_unconfirmed` recommandée par `docs/payment/PAYMENT_DECISIONS_V1.md:62-63`). | Arbitrage impératif entre Option A et Option B pour le traitement de l'expiration des 72 h (V1a). | Avocat / Juriste | OUVERTE |
| Q7.3 | L'envoi d'une notification push ou d'un e-mail dont la lecture effective n'est pas techniquement garantie permet-il de faire courir un délai de forclusion contractuel de 72 heures ? | Les notifications utilisent le worker asynchrone sans accusé de lecture formel garanti (`backend/app/services/notification_worker.py:91-105` ; `docs/payment/PAYMENT_DESIGN.md:450-453`). | Point de départ du délai et canal de délivrance requis (V1a). | Avocat en droit de la consommation | OUVERTE |
| Q7.4 | Quel délai maximal de prescription doit être accordé à un voyageur ou un partenaire pour rouvrir un litige sur une prestation contestée ? | La V1a gèle le dossier sous statut `disputed`, la résolution complète intervenant en V1b (`docs/payment/PAYMENT_DESIGN.md:384-387`). | Règles de clôture définitive des dossiers contestés dans `service_declarations` (V1b). | Avocat | OUVERTE |

### 3.8 Gouvernance interne, habilitations et accès système

| # | Question pour professionnel | Contexte technique et source | Décision système conditionnée | Destinataire | Statut |
|---|---|---|---|---|---|
| Q8.1 | La création du rôle nominatif d'opérateur financier (`finance_operator`, `docs/payment/PAYMENT_DESIGN.md:33, 408`) distinct de l'administrateur informatique répond-elle aux obligations de séparation des fonctions comptables ? | `docs/payment/PAYMENT_DECISIONS_V1.md:70` exige un rôle dédié nominatif sans super-administrateur de plateforme. | Matrice RBAC et gestion des habilitations (V1b). | Auditeur interne / Expert-comptable | OUVERTE |
| Q8.2 | L'exécution de scripts de gestion financière et de reporting directement en ligne de commande (CLI) sur le serveur de production (`app/reporting_finance.py`) est-elle conforme aux règles de contrôle interne et d'auditabilité ? | Le modèle reproduit `create_tenant.py` avec trace de l'`operator_identifier` dans les logs (`docs/payment/PAYMENT_DESIGN.md:342, 621-625`). | Validation de la gouvernance d'exploitation et des procédures de sauvegarde (V1a). | Auditeur informatique / Commissaire aux comptes | OUVERTE |
| Q8.3 | L'administrateur de tenant peut-il déclarer une prestation en lieu et place d'un partenaire défaillant sans engager la responsabilité civile de Discover AI pour immixtion dans la gestion du partenaire ? | L'Option B de `docs/payment/PAYMENT_DESIGN.md:509-511` envisage cette faculté avec enregistrement de `declared_by_admin = True` et motif obligatoire. | Maintien ou retrait de la faculté de déclaration par l'administrateur (V1a). | Avocat en droit des affaires | OUVERTE |

### 3.9 Droit de la consommation, transparence et loyauté des plateformes

| # | Question pour professionnel | Contexte technique et source | Décision système conditionnée | Destinataire | Statut |
|---|---|---|---|---|---|
| Q9.1 | La plateforme est-elle tenue d'informer explicitement le voyageur de l'existence et du montant (ou pourcentage) de la commission perçue auprès du partenaire lors de la réservation ? | Le voyageur ne visualise actuellement que le montant du service sans décomposition de la commission (`mobile/lib/screens/bookings_screen.dart:360-366`). | Écrans d'affichage mobile et mentions précontractuelles de transparence tarifaire (V1a). | Juriste droit de la consommation | OUVERTE |
| Q9.2 | Les critères de classement des POI dans l'application (algorithmes de recommandation IA ou filtres de recherche) doivent-ils faire l'objet d'une mention de transparence indiquant s'ils dépendent ou non du taux de commission consenti par le partenaire ? | `docs/payment/PAYMENT_DECISIONS_V1.md:107` interdit formellement les commissions différenciées par catégorie IA en V1. | Rédaction des mentions d'information algorithmique dans les CGU (V1a). | Juriste droit numérique | OUVERTE |

### 3.10 Prévention du contournement et responsabilité contractuelle

| # | Question pour professionnel | Contexte technique et source | Décision système conditionnée | Destinataire | Statut |
|---|---|---|---|---|---|
| Q10.1 | Une clause de non-contournement interdisant au partenaire et au voyageur d'annuler une réservation sur la plateforme pour exécuter la prestation hors ligne est-elle juridiquement valable et opposable ? | `docs/payment/PAYMENT_DECISIONS_V1.md:155` (A10) identifie ce risque majeur d'éviction de commission en l'absence de PSP. | Rédaction de la clause de non-contournement dans le contrat partenaire (V1b). | Avocat en droit des contrats | OUVERTE |
| Q10.2 | Quelles sanctions civiles ou contractuelles (pénalités forfaitaires, exclusion de la plateforme, déchéance du compte) Discover AI peut-il stipuler en cas de fausse déclaration intentionnelle du montant par un partenaire ? | La plateforme implémente un suivi des ratios annulations/confirmations en V1b (`docs/payment/PAYMENT_DECISIONS_V1.md:155`). | Clauses pénales du contrat d'adhésion partenaire (V1b). | Avocat en droit commercial | OUVERTE |
| Q10.3 | Discover AI peut-il être tenu pour solidairement responsable en cas de défaut de paiement, d'accident corporel ou de défaillance du partenaire sur place lors de l'exécution de l'activité touristique ? | Le modèle pose que le partenaire contracte seul avec le voyageur pour l'activité touristique (`docs/payment/PAYMENT_DECISIONS_V1.md:13-17`). | Clauses de décharge et polices d'assurance responsabilité civile professionnelle (V1a). | Avocat en droit des assurances | OUVERTE |

---

## 4. Contradictions et écarts détectés entre les documents source

Une relecture rigoureuse croisée de `docs/payment/PAYMENT_DECISIONS_V1.md` et `docs/payment/PAYMENT_DESIGN.md` met en évidence quatre écarts substantiels qui ne doivent pas être tranchés techniquement mais soumis à l'arbitrage du propriétaire :

| # | Objet de l'écart | Formulation dans `docs/payment/PAYMENT_DECISIONS_V1.md` | Formulation dans `docs/payment/PAYMENT_DESIGN.md` | Analyse technique de l'écart | Statut |
|---|---|---|---|---|---|
| E1 | Prérogatives d'écriture des scripts CLI en V1a | Ligne 79 : *« En V1a, les scripts CLI sont en lecture seule : aucune décision manuelle, donc pas encore de rôle nominatif. Les actions humaines arrivent en V1b avec le rôle finance_operator. »* | Section 5 (tableau des permissions, ligne 513) : La colonne *« Opérateur CLI direct »* attribue des droits d'écriture en V1a : *« déclarer une prestation (maintenance) »*, *« corriger une déclaration (traçabilité audit) »* sous réserve de renseigner `operator_identifier`. | Contradiction directe entre le principe de lecture seule stricte en V1a et l'ouverture d'actions modificatrices par CLI. | À trancher par le propriétaire |
| E2 | Sort d'une déclaration sans réponse après 72 h | Lignes 62-63 : *« Sans réponse à l'expiration : le dossier est marqué "non confirmé" et soumis à vérification humaine. L'absence de réponse n'est pas une preuve de réalisation et aucune facturation automatique n'est déclenchée. »* | Section 4.2 (lignes 453-461) et Section 11 (décision 5) : Le design maintient l'arbitrage ouvert entre l'Option A (confirmation tacite automatique déclenchant le calcul) et l'Option B (marquage `expired_unconfirmed`). | Le document de décisions tranche pour la non-facturation automatique, tandis que le design conserve l'option tacite à titre d'arbitrage ouvert. | À trancher par le propriétaire |
| E3 | Scoping et multiplicité des entités juridiques en V1 | Ligne 118 : *« V1 : une seule entité juridique Discover AI, établie en Algérie. Chaque enregistrement financier porte un legal_entity_id dès la V1. »* | Section 3.2 (lignes 206-213) et Section 11 (décision 3) : Le design propose et recommande l'Option B (*« une ligne legal_entities par tenant »*) pour respecter `CLAUDE.md:59`, créant une entité par tenant dès la V1. | `docs/payment/PAYMENT_DECISIONS_V1.md` postule une entité unique globale pour la V1, alors que `docs/payment/PAYMENT_DESIGN.md` décline l'entité par tenant pour préserver l'isolation multi-tenant stricte. | À trancher par le propriétaire |
| E4 | Déclaration de prestation par l'administrateur du tenant | Absent du document `docs/payment/PAYMENT_DECISIONS_V1.md` : seules sont mentionnées la déclaration par le partenaire (ligne 50) et la vérification humaine par `finance_operator` (ligne 70). | Section 5 (lignes 505-516) et Section 3.2 (lignes 300-304) : Le design introduit une Option B permettant à l'administrateur du tenant de déclarer une prestation avec `declared_by_admin = True` et `declaration_reason`. | Extension de pouvoir opérationnel accordée à l'administrateur non prévue dans le cadrage initial des décisions. | À trancher par le propriétaire |

---

## 5. Matrice « Décision technique bloquée par question »

Cette matrice formalise la dépendance opérationnelle de chaque bloc technique vis-à-vis des réponses des professionnels qualifiés :

| Question | Fonctionnalité conditionnée | Version | Livrable EN TEST sans réponse ? | Bloqué avant PRODUCTION ? | Motif du blocage ou de la levée |
|---|---|---|---|---|---|
| Q1.1 | `partner_profiles`, `partner_poi_assignments` | V1a | Oui (le schéma SQL et la logique d'affectation peuvent être simulés avec des données de test) | **Oui** | Dépend de la réponse de l'avocat en droit des affaires à la question Q1.1 : on ne peut pas figer la qualification du partenaire comme débiteur direct sans cette réponse. |
| Q1.2 | Rattachement contractuel du partenaire | V1a | Oui (modèle relationnel testable sans convention signée) | **Oui** | Dépend de la réponse du juriste à la question Q1.2 : on ne peut pas figer les clauses du contrat d'adhésion partenaire sans cette réponse. |
| Q1.3 | CGU et modèle d'intermédiation | V1a | Oui (interfaces de consentement testables en local) | **Oui** | Dépend de la réponse de l'avocat en droit des contrats à la question Q1.3 : on ne peut pas figer les conditions d'utilisation opposables au voyageur sans cette réponse. |
| Q1.4 | Séparation `POIManager` / `partner_profiles` | V1a | Oui (isolation des modèles couverte par les tests unitaires) | Non | Dépend de la réponse du juriste à la question Q1.4 : l'architecture technique sépare déjà les rôles opérationnel et contractuel dans le modèle. |
| Q1.5 | Statut des prestataires individuels | V1a | Oui (champs de formulaires mockables) | **Oui** | Dépend de la réponse de l'avocat à la question Q1.5 : on ne peut pas figer les pièces d'identification requises pour les personnes physiques sans cette réponse. |
| Q2.1 | `commission_receivables` et émission des relevés | V1a/V1b | Oui (production de fichiers PDF/CSV de test possible) | **Oui** | Dépend de la réponse de l'expert-comptable à la question Q2.1 : on ne peut pas figer le format du document financier émis (relevé vs facture) sans cette réponse. |
| Q2.2 | Mentions obligatoires des relevés | V1b | Oui (gabarit paramétrable) | **Oui** | Dépend de la réponse de l'expert-comptable à la question Q2.2 : on ne peut pas figer les mentions textuelles du relevé sans cette réponse. |
| Q2.3 | Algorithme de numérotation des créances | V1b | Oui (séquence numérique testable) | **Oui** | Dépend de la réponse de l'expert-comptable à la question Q2.3 : on ne peut pas figer la règle de séquence chronologique sans cette réponse. |
| Q2.4 | Délais d'exigibilité de la commission | V1b | Oui (échéances configurables) | Non | Dépend de la réponse de l'expert-comptable à la question Q2.4 : le délai reste une constante configurable en base sans bloquer le modèle. |
| Q3.1 | Calcul de la taxe sur la commission | V1a | Oui (le calcul brut en points de base est fonctionnel en test) | **Oui** | Dépend de la réponse du fiscaliste à la question Q3.1 : on ne peut pas figer le taux de taxe applicable à la commission sans cette réponse. |
| Q3.2 | Déduction des taxes dans `service_declarations` | V1a | Oui (formule arithmétique validée par les tests) | **Oui** | Dépend de la réponse du fiscaliste à la question Q3.2 : on ne peut pas figer la règle de déduction de taxe sans cette réponse. |
| Q3.3 | Gestion des retenues à la source | V1b | Oui (gestion de montants nets testable) | **Oui** | Dépend de la réponse du fiscaliste à la question Q3.3 : on ne peut pas figer le circuit d'imputation des retenues sans cette réponse. |
| Q3.4 | Indemnités de no-show et annulation tardive | V1c | Oui (machine d'états testable) | **Oui** | Dépend de la réponse du fiscaliste à la question Q3.4 : on ne peut pas figer le traitement de la commission sur les frais d'annulation sans cette réponse. |
| Q4.1 | Facturation des partenaires hors Algérie | V1a | Oui (simulations multi-devises isolées) | **Oui** | Dépend de la réponse du juriste en droit des changes à la question Q4.1 : on ne peut pas figer la règle de facturation d'un partenaire hors du pays de l'entité sans cette réponse. |
| Q4.2 | Blocage de la commission sur le tenant Maroc | V1a | Oui (règle pays/entité vérifiée par test unitaire) | Non | Dépend de la réponse de l'avocat en droit des changes à la question Q4.2 : la commission est désactivée par défaut par la règle technique pays/entité. |
| Q4.3 | Modalités de rapatriement de devises | V3 | Oui (hors périmètre V1) | Non | Dépend de la réponse du conseil financier international à la question Q4.3 : concerne uniquement l'extension multi-entités V3. |
| Q5.1 | Exposition des données dans `_safe_details` | V1a | Oui (défense en profondeur active en test) | **Oui** | Dépend de la réponse du DPO à la question Q5.1 : on ne peut pas figer la liste des champs transmis au partenaire sans cette réponse. |
| Q5.2 | Conservation de `financial_audit_log` | V1a | Oui (table append-only fonctionnelle) | Non | Dépend de la réponse du juriste à la question Q5.2 : la durée de conservation du journal n'est pas fixée mais le stockage technique est prêt. |
| Q5.3 | Procédure d'effacement / droit à l'oubli | V1a | Oui (scripts d'anonymisation de test) | **Oui** | Dépend de la réponse du DPO à la question Q5.3 : on ne peut pas figer la procédure d'anonymisation du journal financier sans cette réponse. |
| Q5.4 | Chiffrement des identifiants fiscaux | V1a | Oui (module cryptographique unitaire testé) | Non | AES-256-GCM, backend/app/services/credential_crypto.py ; aucune validation externe n'a été réalisée. |
| Q6.1 | Horodatage et force probante du consentement | V1a/V1c | Oui (horodatage UTC fonctionnel) | **Oui** | Dépend de la réponse de l'avocat en droit numérique à la question Q6.1 : on ne peut pas figer le niveau de preuve requis pour l'acceptation des CGU sans cette réponse. |
| Q6.2 | Priorité linguistique des CGU (Arabe / FR) | V1a/V1c | Oui (support multilingue natif sur mobile et web) | **Oui** | Dépend de la réponse du juriste à la question Q6.2 : on ne peut pas figer la langue contractuelle prévalente sans cette réponse. |
| Q6.3 | Procédure d'arbitrage de la force majeure | V1c | Oui (workflows d'annulation testables) | Non | Dépend de la réponse de l'avocat à la question Q6.3 : la clause contractuelle sera rédigée avant l'étape V1c. |
| Q7.1 | Valeur probante de la confirmation in-app | V1a | Oui (flux voyageur mobile testable) | **Oui** | Dépend de la réponse de l'avocat en droit de la preuve à la question Q7.1 : on ne peut pas figer le mécanisme de preuve in-app sans cette réponse. |
| Q7.2 | Option A (confirmation tacite après 72 h) | V1a | Oui (compte à rebours du worker testable) | **Oui** | Dépend de la réponse de l'avocat à la question Q7.2 : on ne peut pas figer l'arbitrage entre confirmation tacite et mise en attente sans cette réponse. |
| Q7.3 | Fiabilité de notification et délai de forclusion | V1a | Oui (worker d'e-mails et push testable) | **Oui** | Dépend de la réponse de l'avocat à la question Q7.3 : on ne peut pas figer le point de départ du délai de contestation sans cette réponse. |
| Q7.4 | Forclusion des contestations voyageurs | V1b | Oui (transition vers `disputed` testable) | Non | Dépend de la réponse de l'avocat à la question Q7.4 : les règles de clôture du contentieux seront intégrées en V1b. |
| Q8.1 | Rôle nominatif `finance_operator` | V1b | Oui (modèle de rôles testable) | Non | Dépend de la réponse de l'auditeur interne à la question Q8.1 : la séparation des fonctions sera mise en place en V1b. |
| Q8.2 | Traçabilité des actions CLI | V1a | Oui (`operator_identifier` requis par contrainte SQL) | Non | Dépend de la réponse de l'auditeur informatique à la question Q8.2 : l'identification de l'opérateur CLI est déjà contrainte en base. |
| Q8.3 | Déclaration par l'administrateur de tenant | V1a | Oui (drapeau `declared_by_admin` testable) | **Oui** | Dépend de la réponse de l'avocat à la question Q8.3 : on ne peut pas figer l'autorisation de déclaration par l'administrateur sans cette réponse. |
| Q9.1 | Transparence de la commission au voyageur | V1a | Oui (affichage UI paramétrable) | **Oui** | Dépend de la réponse du juriste en droit de la consommation à la question Q9.1 : on ne peut pas figer l'affichage du prix sans cette réponse. |
| Q9.2 | Loyauté du classement et algorithmes IA | V1a | Oui (moteurs de recherche déterministes) | Non | Dépend de la réponse du juriste à la question Q9.2 : aucune commission différenciée par IA n'est appliquée en V1. |
| Q10.1 | Validité de la clause de non-contournement | V1b | Oui (métriques statistiques testables) | **Oui** | Dépend de la réponse de l'avocat en droit des contrats à la question Q10.1 : on ne peut pas figer le texte de la clause de non-contournement sans cette réponse. |
| Q10.2 | Mesures contractuelles en cas de fausse déclaration | V1b | Oui (blocage logique des comptes de test) | **Oui** | Dépend de la réponse de l'avocat à la question Q10.2 : on ne peut pas figer les mesures de suspension de compte sans cette réponse. |
| Q10.3 | Décharge de responsabilité sur les prestations | V1a | Oui (sans incidence sur le code backend) | **Oui** | Dépend de la réponse de l'avocat à la question Q10.3 : on ne peut pas figer les clauses de responsabilité des CGU sans cette réponse. |

---

## 6. Dossier à remettre aux professionnels qualifiés

Pour permettre aux conseils juridiques et fiscaux de formuler leurs conclusions, le propriétaire du projet devra leur transmettre les pièces suivantes :

### 6.1 Pièces techniques et contractuelles disponibles
1. `docs/payment/PAYMENT_DECISIONS_V1.md` : Décisions d'architecture financière du propriétaire (version du 01/11/2026, intégrant les amendements A1 à A14).
2. `docs/payment/PAYMENT_DESIGN.md` : Spécification technique détaillée du domaine paiement (modèles de données SQL, machine d'états, matrice de permissions et endpoints).
3. `docs/payment/PAYMENT_AUDIT.md` : Addendum d'audit du 01/11/2026 (§18) analysant l'état réel du code de réservation et les dépendances mobiles/web.
4. Schéma technique des flux financiers : Diagramme des interactions entre le partenaire, le voyageur et la plateforme Discover AI (`docs/payment/PAYMENT_DESIGN.md` §3.2 et §4).

### 6.2 Éléments précis à fournir par le propriétaire du projet
1. **Cartographie des partenaires cibles :** Liste prévisionnelle des premiers partenaires pilotes en Algérie, précisant leur statut juridique (société commerciale SARL/EURL, artisan individuel, association) et leur régime fiscal.
2. **Textes contractuels actuels :** Projet des Conditions Générales d'Utilisation (CGU) voyageurs, projet de convention de partenariat et politique d'annulation envisagée.
3. **Modèle de relevé de commission :** Projet de mise en page du relevé de commission (mentions textuelles, en-tête légal, libellés de ventilation de la commission et des taxes).
4. **Attribution des rôles administratifs :** Liste nominative des personnes physiques appelées à exercer les fonctions de `finance_operator` et règles internes de délégation.
5. **Déclaration géographique des tenants :** Confirmation de la liste des pays réels associés à chaque tenant pour le renseignement de `Tenant.country_code` (`DZ` pour Discover Algeria, statut définitif de Discover Morocco).


---

## 7. Questions juridiques encore ouvertes après arbitrage du point de contrôle 2

Les arbitrages D1 à D12 rendus par le propriétaire du projet le 02/11/2026 tranchent l'architecture logicielle V1a mais ne valent pas conclusions de droit. Les questions de conformité suivantes demeurent expressément ouvertes à l'examen des professionnels qualifiés :

1. **Validation comptable de la convention d'arrondi (liée à D6) :**
   - *Renvoi :* Question **Q3.2** (`docs/payment/PAYMENT_COMPLIANCE.md:63`).
   - L'expert-comptable doit valider si la règle d'arrondi à l'unité mineure inférieure (floor) ou demi-pair (half to even) est la convention retenue pour les relevés de commission.
2. **Émission des relevés internes vs obligations fiscales de facturation (liée à F21) :**
   - *Renvoi :* Questions **Q2.1**, **Q2.2**, **Q2.3** (`docs/payment/PAYMENT_COMPLIANCE.md:53-55`).
   - La dispense temporaire de délivrance d'une facture fiscale officielle en V1a doit être confirmée au regard du droit fiscal algérien.
3. **Durée de conservation et opposabilité du journal d'audit financier (liée à F23) :**
   - *Renvoi :* Questions **Q5.2**, **Q5.3** (`docs/payment/PAYMENT_COMPLIANCE.md:80-81`).
   - La durée d'archivage probant du journal append-only `financial_audit_log` face aux règles comptables et au droit des données doit être arrêtée.
4. **Statut des partenaires étrangers et étanchéité de change (liée à D10) :**
   - *Renvoi :* Questions **Q4.1**, **Q4.2** (`docs/payment/PAYMENT_COMPLIANCE.md:71-72`).
   - Le blocage technique de facturation sur le tenant Maroc face à l'entité algérienne doit être validé par un juriste spécialisé en réglementation des changes.
5. **Force probante de la confirmation in-app et valeur du consentement (liée à D9) :**
   - *Renvoi :* Questions **Q6.1**, **Q7.1**, **Q7.2** (`docs/payment/PAYMENT_COMPLIANCE.md:88, 96-97`).
   - L'opposabilité de l'approbation in-app du voyageur comme acte de preuve matérielle de l'exécution du service doit être formellement confirmée.

6. **Modalités d'identification de l'opérateur du script de provisionnement (liée à D13 / P1) :**
   - *Renvoi :* Questions **Q8.1**, **Q8.2** (`docs/payment/PAYMENT_COMPLIANCE.md:105-106`).
   - L'auditeur interne et l'auditeur informatique doivent valider le niveau d'authentification exigé (Option A poste d'administration vs Option B conteneur/OIDC) pour l'exécution d'un script en écriture modifiant les profils partenaires et règles de commission.
7. **Couverture de la date prévue et forclusion de signalement (liée à D15 / P2) :**
   - *Renvoi :* Questions **Q7.2**, **Q7.3** (`docs/payment/PAYMENT_COMPLIANCE.md:97-98`).
   - L'avocat doit valider si l'absence de date structurée dans la réservation justifie le blocage sous statut d'anomalie `needs_review` sans notification voyageur.
