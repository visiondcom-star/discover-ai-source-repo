# Architecture & Design Technique — Domaine Paiement & Fondation Financière V1

> **Document de référence :** Point de contrôle 2 du chantier paiement (conforme à `PAYMENT_ARCHITECTURE_V3.md` section 4 et 5, et `PAYMENT_DECISIONS_V1.md` §1 à §16 intégrant les amendements A1 à A14).  
> **Date de rédaction :** 1er novembre 2026.  
> **Branche de travail :** `docs/payment-decisions-v1`.  
> **Statut :** DOCUMENTATION TECHNIQUE DE CONCEPTION (DESIGN). Aucun code applicatif, aucune migration Alembic, aucune dépendance et aucun test n'ont été modifiés sur le dépôt. Aucune conclusion juridique ou fiscale n'est formulée (les aspects réglementaires et légaux sont consignés dans `PAYMENT_COMPLIANCE.md`).

---

## 1. Périmètre et étiquetage par sous-version

Conformément à `PAYMENT_DECISIONS_V1.md` §14, la fondation financière repose sur un modèle d'intermédiation pur :

- Le partenaire encaisse directement le voyageur ; Discover AI ne collecte ni ne détient les fonds du voyageur (`PAYMENT_DECISIONS_V1.md` §1).
- Discover AI facture sa commission au partenaire après confirmation de la prestation (`PAYMENT_DECISIONS_V1.md` §1, §4, §7).
- La V1a constitue une sous-version **strictement autonome** : elle ne dépend ni du moteur de contestation complet, ni de la résolution humaine avancée, ni du rapprochement bancaire, ni des politiques d'annulation.

### 1.1 Matrice d'attribution des fonctionnalités

| Fonctionnalité                                                                                                                | Version | Dépendances & Prérequis                                                                |
| ----------------------------------------------------------------------------------------------------------------------------- | ------- | -------------------------------------------------------------------------------------- |
| Modèle de données : profil contractuel partenaire (`partner_profiles`), rattachement daté aux POI (`partner_poi_assignments`) | **V1a** | Aucune (extension propre à côté de `POIManager`, `backend/app/models.py:366`)          |
| Entité légale Discover AI unique (Algérie) et propagation de `legal_entity_id`                                                | **V1a** | Une seule ligne en base (`PAYMENT_DECISIONS_V1.md` §8)                                 |
| Règle de sécurité pays/entité (activation commission si pays partenaire == pays entité)                                       | **V1a** | `Tenant.country_code` (`backend/app/models.py:51`) et pays du profil partenaire        |
| Configuration du taux de commission (base 1 000 bps = 10 %, surcharges par partenaire)                                        | **V1a** | Stockage en points de base (`Integer`)                                                 |
| Déclaration de prestation par le partenaire (`service_declarations`) avec montant et devise                                   | **V1a** | Réservation au statut `confirmed`                                                      |
| Confirmation de prestation par le voyageur (enregistrement date, source, montant)                                             | **V1a** | Notification voyageur in-app / push                                                    |
| Enregistrement initial de contestation par le voyageur (motif horodaté)                                                       | **V1a** | Suspension du calcul de commission dès l'ouverture (`PAYMENT_DECISIONS_V1.md` §4, A14) |
| Délai de réponse de 72 h configurable par tenant et rappels périodiques                                                       | **V1a** | Worker de notifications (`backend/app/services/notification_service.py`)               |
| Calcul et snapshot immuable de la commission (`service_completions`, `commission_receivables`)                                | **V1a** | Uniquement après confirmation du voyageur                                              |
| Journal d'audit financier append-only (`financial_audit_log`)                                                                 | **V1a** | Immuabilité et traçabilité des opérations                                              |
| Script CLI de consultation financière en lecture seule                                                                        | **V1a** | Modèle `backend/app/create_tenant.py:1-104`                                            |
| Rôle nominatif `finance_operator` et matrice de permissions fines                                                             | **V1b** | V1a validée                                                                            |
| Cycle complet de contestation et résolution humaine (6 étapes, justifications)                                                | **V1b** | Rôle `finance_operator` (`PAYMENT_DECISIONS_V1.md` §5, A2)                             |
| Relevés de commission Discover AI et saisie des références de factures externes                                               | **V1b** | `commission_receivables` V1a (`PAYMENT_DECISIONS_V1.md` §11, A7)                       |
| Grand livre partenaire immuable (`partner_ledger_entries`) et écritures compensatoires                                        | **V1b** | V1a validée                                                                            |
| Outils CLI de rapprochement manuel et détection des anomalies / contournements                                                | **V1b** | Suivi ratios annulations/déclarations (`PAYMENT_DECISIONS_V1.md` §13, A10)             |
| Politiques d'annulation versionnées (`cancellation_policies`)                                                                 | **V1c** | V1b validée                                                                            |
| Consentement explicite à la politique lors de la réservation (mobile, web, i18n)                                              | **V1c** | Clé facultative sur `Booking` (`PAYMENT_DECISIONS_V1.md` §6, A11)                      |
| Parcours d'annulation post-confirmation avec motifs fermés et date de bascule                                                 | **V1c** | Refonte coordonnée de `/cancel` (`backend/app/api/v1/endpoints/bookings.py:309`)       |
| Déclaration des frais de no-show et annulation tardive retenus par le partenaire                                              | **V1c** | Politiques d'annulation V1c (`PAYMENT_DECISIONS_V1.md` §2, §6, A13)                    |
| Force majeure validée exclusivement par un opérateur autorisé                                                                 | **V1c** | Rôle `finance_operator` (`PAYMENT_DECISIONS_V1.md` §6, A11)                            |
| Intégration du premier PSP (ex. Chargily pour l'Algérie)                                                                      | **V2**  | Agrément, KYC/KYB plateforme, validation légale                                        |
| Webhooks publics sécurisés et idempotents                                                                                     | **V2**  | Premier PSP en place                                                                   |
| Autorisation, capture, void, remboursements techniques                                                                        | **V2**  | Capacités du PSP validées                                                              |
| Deuxième entité légale Discover AI (Europe / France)                                                                          | **V3**  | Structure juridique et bancaire européenne établie                                     |
| Gestion multi-devises et conversion de devises                                                                                | **V3**  | Flux transfrontaliers validés                                                          |
| Marketplace et split-payment automatisé                                                                                       | **V3**  | Cadre réglementaire DSP2 / agrément établissement de paiement                          |

### 1.2 Exclusions formelles de la V1 (périmètre négatif strict)

Sont formellement exclus de la version V1 (`PAYMENT_DECISIONS_V1.md` §1, §10, §11, §14) :

- Aucune intégration de passerelle de paiement / PSP (ni Chargily, ni SATIM, ni Stripe, ni PayPal).
- Aucun encaissement ni détention de fonds de tiers par Discover AI.
- Aucun traitement de remboursement technique vers les voyageurs (les remboursements éventuels restent un accord direct entre partenaire et voyageur).
- Aucune collecte ni stockage de coordonnées bancaires partenaires (RIB, IBAN, cartes) : Discover AI n'effectue aucun versement aux partenaires en V1 (`PAYMENT_DECISIONS_V1.md` §10, A6).
- Aucune émission de facture fiscale officielle : seuls des relevés de commission internes sont produits, avec enregistrement facultatif du numéro de facture externe (`PAYMENT_DECISIONS_V1.md` §11, A7).
- Aucune conversion de devises : chaque opération est libellée et conservée dans la devise déclarée (`PAYMENT_DECISIONS_V1.md` §9).
- Aucun rôle de « super-administrateur » global de plateforme : l'isolation multi-tenant demeure absolue (`backend/app/core/tenant.py:1-25`, `backend/app/dependencies.py:144-155`).

---

## 2. Modes de réservation éligibles à la déclaration de prestation (V1a)

Dans le backend actuel, les modes autorisés sont définis dans `backend/app/constants.py:87` : `BOOKING_MODES_SUPPORTED = ("info_only", "request", "manual_confirm", "pay_on_site")`.  
L'analyse de leur cycle de vie (`docs/payment/PAYMENT_AUDIT.md` §18.2) conduit à formuler les options suivantes pour la V1a :

### 2.1 Mode `manual_confirm` (Recommandation V1a)

- **Fonctionnement dans le code :** À la réservation, le voyageur donne son consentement (`POST /bookings/{id}/consent`), la réservation passe à `status="requested"` (`backend/app/api/v1/endpoints/bookings.py:226`) et une notification `booking_request_received` est envoyée à tous les `POIManager` rattachés au POI (`backend/app/api/v1/endpoints/bookings.py:230-253`). Le partenaire accepte ou refuse explicitement dans son espace de gestion (`POST /partner/bookings/{id}/respond`, `backend/app/api/v1/endpoints/partner.py:256-358`), ce qui horodate son identité dans `Booking.responded_by` et `Booking.responded_at` (`backend/app/api/v1/endpoints/partner.py:339-340`).
- **Éligibilité à la prestation :** C'est le mode le plus robuste pour la V1a. Le partenaire a explicitement confirmé la venue du voyageur, connaît la réservation dans sa file d'attente, et dispose de la légitimité pour déclarer le service rendu à l'issue de la date prévue.
- **Recommandation :** Activer la déclaration de prestation en V1a **exclusivement sur les réservations issues du mode `manual_confirm`**.

### 2.2 Mode `pay_on_site`

- **Fonctionnement dans le code :** Bien que son libellé évoque un paiement sur place, son implémentation actuelle est un doublon du mode `request` : lors de `give_consent(consent=True)`, la réservation passe immédiatement à `status="confirmed"` sans notification au partenaire (`backend/app/api/v1/endpoints/bookings.py:255-273`). Le partenaire ne valide jamais la demande au préalable.
- **Chemin d'extension proposé :**
  - Option A : Exclure `pay_on_site` de la déclaration en V1a.
  - Option B : Aligner le mode `pay_on_site` sur le cycle de vie de `manual_confirm` (passage en `requested`, notification du `POIManager`, accord préalable requis).
- **Risques :** L'option B modifie le comportement existant des réservations `pay_on_site`, ce qui contrevient au principe d'immuabilité sans accord préalable.
- **Recommandation :** Exclure en V1a ; étudier l'alignement pour la V1b.

### 2.3 Mode `request`

- **Fonctionnement dans le code :** Mode historique. Confirmation instantanée par le voyageur sans accord du partenaire (`backend/app/api/v1/endpoints/bookings.py:255-273`). Le partenaire n'étant pas prévenu de la réservation, il ne dispose d'aucun moyen fiable pour déclarer la prestation sans recherche manuelle a posteriori.
- **Recommandation :** Exclure formellement de la commission en V1a.

### 2.4 Mode `info_only`

- **Fonctionnement dans le code :** Rejeté dès la création avec HTTP 422 (`backend/app/api/v1/endpoints/bookings.py:108-109`).
- **Recommandation :** Exclusion totale et définitive (aucune réservation n'existe en base).

> **DÉCISION PROPRIÉTAIRE REQUISE :** Confirmer que seule la modalité `manual_confirm` ouvre droit à la déclaration de prestation et au calcul de commission en V1a, les autres modes étant exclus de la commission jusqu'à revue en V1b.

---

## 3. Modèle de données minimal V1a

Toutes les tables financières respectent les principes d'architecture fondamentaux de Discover AI :

1. **Types numériques stricts :** Montants stockés en entiers (`BigInteger` ou `Integer`, unités mineures / centimes) avec colonne `currency` (code ISO 4217 à 3 lettres) et exposant issu d'un dictionnaire immuable de devises. La colonne existante `Booking.price` (`Float`, `backend/app/models.py:344`), jamais alimentée par l'API, est **strictement ignorée**.
2. **Isolation multi-tenant stricte :** Chaque table porte une clé étrangère `tenant_id` non nulle pointant sur `tenants.id` avec index dédié, conformément à l'isolation globale de la plateforme.
3. **Traçabilité juridique :** Chaque ligne financière porte `legal_entity_id`. En V1, une unique ligne d'entité Discover AI existe (Algérie).
4. **Snapshots immuables :** Le taux de commission (en points de base, ex. 1 000 bps pour 10,00 %) et l'entité juridique sont copiés en dur au moment de la déclaration. Une modification ultérieure de la règle de commission ou du statut du partenaire n'altère jamais les enregistrements passés.

### 3.1 Analyse du modèle partenaire : extension de `POIManager` vs table dédiée

#### Constat sur l'existant

Dans le code actuel (`backend/app/models.py:366-389`), la table `poi_managers` est une simple table d'association reliant un `user_id` à un `poi_id` dans un `tenant_id` :

```python
# backend/app/models.py:381-386
id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
tenant_id = Column(UUID(as_uuid=True), ForeignKey("tenants.id", ondelete="CASCADE"), nullable=False, index=True)
poi_id = Column(UUID(as_uuid=True), ForeignKey("pois.id", ondelete="CASCADE"), nullable=False)
user_id = Column(UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
created_at = Column(DateTime, nullable=False, server_default=text("now()"))
```

Cette table ne porte aucune information légale, fiscale, contractuelle ou de facturation.  
Par ailleurs, un POI peut avoir 3 gérants distincts, et un même professionnel peut exploiter 5 POI différents (`docs/payment/PAYMENT_AUDIT.md` §17.4). Si l'on rattachait la commission à `poi_managers`, le débiteur contractuel de Discover AI serait ambigu.

#### Comparatif architectural

- **Option 1 — Surcharger `poi_managers` :** Ajouter des colonnes contractuelles (`tax_id`, `legal_name`, `billing_address`) sur `poi_managers`.  
  _Inconvénients majeurs :_ Dénormalisation massive (redondance dès qu'un gérant a plusieurs POI), impossibilité de gérer un gérant opérationnel (ex. un employé d'accueil) sans lui exposer les données fiscales de l'entreprise, risque de régression sur la gestion des autorisations opérationnelles (`backend/app/dependencies.py:158-175`).
- **Option 2 — Tables dédiées `partner_profiles` et `partner_poi_assignments` (Recommandation) :**  
  Créer une entité contractuelle distincte `partner_profiles` rattachée au tenant, et une table de liaison temporelle `partner_poi_assignments` associant un POI à un profil partenaire sur une période donnée (`valid_from`, `valid_to`).  
  _Avantages :_ Découplage net entre le rôle opérationnel (gérer les demandes de réservation au quotidien via `POIManager`) et le rôle contractuel/financier (partie liée pour les commissions et déclarations), préservation intégrale du fonctionnement existant de `poi_managers`.

> **DÉCISION PROPRIÉTAIRE REQUISE :** Valider la création d'un profil contractuel partenaire autonome (`partner_profiles`) et son rattachement aux POI (`partner_poi_assignments`), sans modifier la table opérationnelle `poi_managers`.

### 3.2 Spécification des tables V1a

```
+----------------------------------------------------------------------------------------------------+
|                                         legal_entities                                             |
| id (UUID, PK) | tenant_id (UUID, FK) | name (String) | country_code (String(2)) | is_active (Bool) |
+----------------------------------------------------------------------------------------------------+
                                                  ▲
                                                  │ 1:N
+-------------------------------------------------+--------------------------------------------------+
|                                      commission_rules                                              |
| id (UUID, PK) | tenant_id (UUID, FK) | partner_profile_id (UUID, FK, opt) | rate_bps (Integer)     |
| valid_from (DateTime) | valid_to (DateTime, opt) | is_active (Boolean)                             |
+----------------------------------------------------------------------------------------------------+
                                                  ▲
                                                  │ 1:N
+-------------------------------------------------+--------------------------------------------------+
|                                      partner_profiles                                              |
| id (UUID, PK) | tenant_id (UUID, FK) | legal_name (String) | trade_register_number (String)        |
| tax_identification_number (String) | country_code (String(2)) | billing_contact_user_id (UUID, FK)  |
| is_commission_enabled (Boolean) | created_at (DateTime) | updated_at (DateTime)                    |
+----------------------------------------------------------------------------------------------------+
         ▲                                                                   ▲
         │ 1:N                                                               │ 1:N
+--------+----------------------------+             +------------------------+-----------------------+
|   partner_poi_assignments           |             |           service_declarations                 |
| id (UUID, PK) | tenant_id (UUID, FK)|             | id (UUID, PK) | tenant_id (UUID, FK)           |
| partner_profile_id (UUID, FK)       |             | booking_id (UUID, FK, unique)                  |
| poi_id (UUID, FK)                   |             | partner_profile_id (UUID, FK)                  |
| valid_from (DateTime)               |             | poi_id (UUID, FK) | declared_by_user_id (UUID) |
| valid_to (DateTime, opt)            |             | declaration_type (String(30))                  |
+-------------------------------------+             | amount_minor (BigInteger) | currency (String)  |
                                                    | tax_amount_minor (BigInteger, opt)             |
                                                    | status (String(30)) | confirmation_deadline    |
                                                    | created_at (DateTime)                          |
                                                    +------------------------------------------------+
                                                                             │
                                                                             │ 1:1
                                                    +------------------------▼-----------------------+
                                                    |           service_completions                  |
                                                    | id (UUID, PK) | tenant_id (UUID, FK)           |
                                                    | declaration_id (UUID, FK, unique)              |
                                                    | legal_entity_id (UUID, FK)                     |
                                                    | confirmed_at (DateTime)                        |
                                                    | confirmation_source (String(50))               |
                                                    | final_amount_minor (BigInteger)                |
                                                    | applied_commission_bps (Integer)               |
                                                    | calculated_commission_minor (BigInteger)       |
                                                    +------------------------------------------------+
                                                                             │
                                                                             │ 1:1
                                                    +------------------------▼-----------------------+
                                                    |         commission_receivables                 |
                                                    | id (UUID, PK) | tenant_id (UUID, FK)           |
                                                    | completion_id (UUID, FK, unique)               |
                                                    | legal_entity_id (UUID, FK)                     |
                                                    | partner_profile_id (UUID, FK)                  |
                                                    | receivable_status (String(30))                 |
                                                    | amount_due_minor (BigInteger) | currency       |
                                                    | created_at (DateTime)                          |
                                                    +------------------------------------------------+
```

#### 1. Table `legal_entities`

- **Rôle :** Représente l'entité juridique Discover AI émettrice et responsable de l'activité financière. En V1, contient exactement une ligne : Discover AI Algérie.
- **Colonnes :**
  - `id` : `UUID`, Clé Primaire (`default=uuid.uuid4`).
  - `tenant_id` : `UUID`, Clé Étrangère vers `tenants.id`, non nulle, indexée.
  - `name` : `String(150)`, nom social légal de l'entité Discover AI.
  - `country_code` : `String(2)`, non nulle, code ISO 3166-1 alpha-2 (`DZ` en V1).
  - `registration_number` : `String(100)`, identifiant légal d'enregistrement (ex. Registre de Commerce algérien).
  - `tax_id` : `String(100)`, identifiant fiscal (ex. NIF / NIS).
  - `is_active` : `Boolean`, défaut `True`.
  - `created_at` : `DateTime`, défaut `utcnow`.
- **Contraintes :** `UniqueConstraint("tenant_id", "country_code", name="uq_legal_entity_tenant_country")`.

#### 2. Table `partner_profiles`

- **Rôle :** Fiche d'identification contractuelle de l'opérateur touristique (personne morale ou entrepreneur individuel).
- **Colonnes :**
  - `id` : `UUID`, Clé Primaire.
  - `tenant_id` : `UUID`, Clé Étrangère vers `tenants.id`, non nulle, indexée.
  - `legal_name` : `String(200)`, raison sociale contractante.
  - `trade_register_number` : `String(100)`, numéro de registre du commerce (chiffré au repos ou texte selon sensibilité).
  - `tax_identification_number` : `String(100)`, numéro d'identification fiscale (chiffré via `CredentialCrypto`, `backend/app/services/credential_crypto.py:25-113`).
  - `country_code` : `String(2)`, code ISO 3166-1 alpha-2 du partenaire (utilisé pour la vérification pays/entité).
  - `billing_address` : `JSON`, coordonnées postales et administratives.
  - `billing_contact_user_id` : `UUID`, Clé Étrangère vers `users.id` (contact principal habilité pour la finance).
  - `is_commission_enabled` : `Boolean`, défaut `False` (activation explicite exigée par `PAYMENT_DECISIONS_V1.md` §8).
  - `created_at` : `DateTime`, défaut `utcnow`.
  - `updated_at` : `DateTime`, défaut `utcnow`, `onupdate=utcnow`.
- **Contraintes :** `Index("ix_partner_profiles_tenant_country", "tenant_id", "country_code")`.

#### 3. Table `partner_poi_assignments`

- **Rôle :** Rattachement temporel d'un POI à une entité partenaire responsable de sa gestion financière.
- **Colonnes :**
  - `id` : `UUID`, Clé Primaire.
  - `tenant_id` : `UUID`, Clé Étrangère vers `tenants.id`, non nulle, indexée.
  - `partner_profile_id` : `UUID`, Clé Étrangère vers `partner_profiles.id`, non nulle.
  - `poi_id` : `UUID`, Clé Étrangère vers `pois.id`, non nulle, indexée.
  - `valid_from` : `DateTime`, date d'effet du rattachement, non nulle.
  - `valid_to` : `DateTime`, date de fin éventuelle (nullable).
  - `created_at` : `DateTime`, défaut `utcnow`.
- **Contraintes :** `Index("ix_partner_poi_validity", "tenant_id", "poi_id", "valid_from")`.

#### 4. Table `commission_rules`

- **Rôle :** Définition des taux de commission applicables (règle par défaut par tenant, ou règle négociée par partenaire).
- **Colonnes :**
  - `id` : `UUID`, Clé Primaire.
  - `tenant_id` : `UUID`, Clé Étrangère vers `tenants.id`, non nulle, indexée.
  - `partner_profile_id` : `UUID`, Clé Étrangère vers `partner_profiles.id`, nullable (si NULL = taux par défaut du tenant).
  - `rate_bps` : `Integer`, taux en points de base (ex. `1000` = 10,00 %, `1 bps = 0.01 %`).
  - `valid_from` : `DateTime`, date d'entrée en vigueur de la règle, non nulle.
  - `valid_to` : `DateTime`, date de fin de validité (nullable).
  - `is_active` : `Boolean`, défaut `True`.
  - `created_at` : `DateTime`, défaut `utcnow`.
- **Contraintes :** `CheckConstraint("rate_bps >= 0 AND rate_bps <= 10000", name="chk_rate_bps_range")`.

#### 5. Table `service_declarations`

- **Rôle :** Déclaration de réalisation de la prestation saisie par le partenaire après exécution.
- **Colonnes :**
  - `id` : `UUID`, Clé Primaire.
  - `tenant_id` : `UUID`, Clé Étrangère vers `tenants.id`, non nulle, indexée.
  - `booking_id` : `UUID`, Clé Étrangère vers `bookings.id`, non nulle, **UNIQUE** (une seule déclaration active par réservation).
  - `partner_profile_id` : `UUID`, Clé Étrangère vers `partner_profiles.id`, non nulle.
  - `poi_id` : `UUID`, Clé Étrangère vers `pois.id`, non nulle.
  - `declared_by_user_id` : `UUID`, Clé Étrangère vers `users.id` (gérant ayant saisi la déclaration).
  - `declaration_type` : `String(30)`, parmi `("service_rendered", "late_cancellation_fee", "no_show_fee")` (`PAYMENT_DECISIONS_V1.md` §2, A13).
  - `amount_minor` : `BigInteger`, montant total encaissé déclaré en unités mineures (centimes), non nul, strictement positif (`> 0`).
  - `currency` : `String(3)`, code devise ISO 4217 identique à `Booking.currency`.
  - `tax_amount_minor` : `BigInteger`, nullable, montant des taxes incluses identifiées et documentées.
  - `status` : `String(30)`, état de la déclaration : `"declared"`, `"confirmed"`, `"disputed"`, `"expired_unconfirmed"`.
  - `confirmation_deadline` : `DateTime`, échéance de 72 heures allouée au voyageur pour confirmer ou contester.
  - `dispute_reason` : `Text`, motif de contestation renseigné par le voyageur en cas de désaccord.
  - `disputed_at` : `DateTime`, horodatage de contestation par le voyageur.
  - `created_at` : `DateTime`, défaut `utcnow`.
- **Contraintes :** `UniqueConstraint("tenant_id", "booking_id", name="uq_declaration_per_booking")`.

#### 6. Table `service_completions`

- **Rôle :** Prestation formellement actée (confirmée par le voyageur ou clôturée). Déclenche le calcul de commission.
- **Colonnes :**
  - `id` : `UUID`, Clé Primaire.
  - `tenant_id` : `UUID`, Clé Étrangère vers `tenants.id`, non nulle, indexée.
  - `declaration_id` : `UUID`, Clé Étrangère vers `service_declarations.id`, non nulle, **UNIQUE**.
  - `legal_entity_id` : `UUID`, Clé Étrangère vers `legal_entities.id`, non nulle (snapshot immuable).
  - `confirmed_at` : `DateTime`, horodatage de validation définitive.
  - `confirmation_source` : `String(50)`, source de confirmation (ex. `"traveller_in_app"`, `"operator_resolution"`, `"tacit_deadline"` si retenu).
  - `final_amount_minor` : `BigInteger`, assiette financière retenue (en centimes).
  - `applied_commission_bps` : `Integer`, snapshot immuable du taux en points de base appliqué.
  - `calculated_commission_minor` : `BigInteger`, montant calculé de la commission due à Discover AI en unités mineures.
  - `created_at` : `DateTime`, défaut `utcnow`.
- **Contraintes :** `UniqueConstraint("tenant_id", "declaration_id", name="uq_completion_per_declaration")`.

#### 7. Table `commission_receivables`

- **Rôle :** Créance financière de commission due par le partenaire à Discover AI.
- **Colonnes :**
  - `id` : `UUID`, Clé Primaire.
  - `tenant_id` : `UUID`, Clé Étrangère vers `tenants.id`, non nulle, indexée.
  - `completion_id` : `UUID`, Clé Étrangère vers `service_completions.id`, non nulle, **UNIQUE**.
  - `legal_entity_id` : `UUID`, Clé Étrangère vers `legal_entities.id`, non nulle.
  - `partner_profile_id` : `UUID`, Clé Étrangère vers `partner_profiles.id`, non nulle, indexée.
  - `amount_due_minor` : `BigInteger`, montant de la commission restant dû.
  - `currency` : `String(3)`, devise de la créance.
  - `receivable_status` : `String(30)`, état de la créance : `"pending"`, `"invoiced"`, `"partially_paid"`, `"paid"`, `"waived"` (`PAYMENT_DECISIONS_V1.md` §14, V1b). En V1a, systématiquement initialisé à `"pending"`.
  - `created_at` : `DateTime`, défaut `utcnow`.

#### 8. Table `financial_audit_log`

- **Rôle :** Journal d'audit append-only immuable consignant chaque événement financier.
- **Colonnes :**
  - `id` : `UUID`, Clé Primaire.
  - `tenant_id` : `UUID`, non nulle, indexée.
  - `actor_user_id` : `UUID`, nullable (NULL si exécuté par un script système / CLI).
  - `actor_role` : `String(50)`, rôle de l'acteur (ex. `"partner"`, `"traveller"`, `"cli_operator"`).
  - `action` : `String(50)`, ex. `"declare_service"`, `"confirm_service"`, `"dispute_service"`, `"expire_declaration"`.
  - `target_table` : `String(50)`, table visée (ex. `"service_declarations"`).
  - `target_id` : `UUID`, identifiant de la ligne ciblée.
  - `payload_before` : `JSON`, état antérieur (sérialisé).
  - `payload_after` : `JSON`, nouvel état.
  - `reason` : `Text`, motif obligatoire pour toute opération de correction ou résolution manuelle.
  - `created_at` : `DateTime`, non nulle, défaut `utcnow`.
- **Contraintes :** Table strictement en écriture seule (aucun `UPDATE` ni `DELETE` permis par politique logicielle).

### 3.3 Source du pays et mise en œuvre de la règle pays/entité

- **Analyse du modèle existant :** La colonne `Tenant.country_code` existe (`backend/app/models.py:51`, `Column(String(2), nullable=True, index=True)`) et valide les 2 lettres ASCII ISO 3166-1 alpha-2 (`backend/app/models.py:68-76`).  
  Cependant, dans `backend/app/initial_data.py:24-47`, ni le seed `algeria` ni le seed `morocco` ne renseignent cette colonne (valeur `NULL`).
- **Proposition d'alimentation pérenne :**
  1. Le pays de l'entité juridique Discover AI est fourni par la table `legal_entities.country_code` (`DZ` pour la première entité en V1).
  2. Le pays du partenaire est fourni explicitement dans `partner_profiles.country_code` lors de la création du dossier partenaire.
  3. Le tenant conserve `Tenant.country_code` comme filtre territorial géographique.
- **Règle de sécurité métier à l'évaluation de la commission :**
  ```python
  if partner_profile.country_code != legal_entity.country_code:
      # Règle PAYMENT_DECISIONS_V1 §8 : pays différent => commission désactivée
      raise CommissionNotEligibleError("Partner country does not match legal entity country")
  ```

---

## 4. Machine d'états financière (strictement séparée de Booking)

Le cycle de vie de `Booking.status` (`backend/app/constants.py:92` : `pending`, `requested`, `confirmed`, `declined`, `expired`, `cancelled`) **demeure strictement intact**. Aucun nouvel état n'est injecté dans `Booking`.  
La déclaration financière dispose de sa propre machine d'états sur la table `service_declarations.status`.

```
                  [Réservation au statut 'confirmed']
                                  │
                                  │ (1) Partenaire : déclare la prestation
                                  ▼
                     +--------------------------+
                     |         declared         |
                     +--------------------------+
                                  │
             +--------------------+--------------------+
             │                                         │
             │ (2a) Voyageur : confirme                 │ (2b) Voyageur : conteste
             ▼                                         ▼
+--------------------------+              +--------------------------+
|        confirmed         |              |         disputed         |
|  (Calcul commission V1a) |              |  (Gel commission V1a,    |
+--------------------------+              |   résolution en V1b)     |
                                          +--------------------------+
             │                                         │
             │ (Si délai 72 h expiré sans réponse)     │ (Décision finance_operator V1b)
             ▼                                         ▼
+--------------------------+              +--------------------------+
|       (Option A)         |              |         resolved         |
|  confirmed_tacit /       |              | (montant ajusté/annulé)  |
|  expired_unconfirmed     |              +--------------------------+
|       (Option B)         |
+--------------------------+
```

### 4.1 Transitions d'états de la déclaration de prestation

1. **Création (`∅` → `declared`) :**
   - **Acteur :** Partenaire autorisé (associé au POI via `partner_poi_assignments`).
   - **Condition :** `Booking.status == "confirmed"`, `Booking.booking_mode == "manual_confirm"`, date de fin de la réservation dépassée (`end_date <= utcnow().date()`).
   - **Action :** Enregistrement de `amount_minor`, `currency`, `tax_amount_minor`, calcul de `confirmation_deadline = utcnow() + timedelta(hours=deadline_hours)` (défaut : 72 h). Émission d'une notification voyageur `service_declaration_received`.
2. **Confirmation voyageur (`declared` → `confirmed`) :**
   - **Acteur :** Voyageur propriétaire de la réservation (`Booking.user_id == current_user.id`).
   - **Action :** Création synchrone de `service_completions` et de `commission_receivables`. Calcul immuable de la commission due (`amount_minor * rate_bps / 10000`).
3. **Contestation voyageur (`declared` → `disputed`) :**
   - **Acteur :** Voyageur propriétaire de la réservation.
   - **Condition :** Avant expiration de `confirmation_deadline`. Saisie d'un motif obligatoire (`dispute_reason`).
   - **Action :** Enregistrement de l'état `disputed`. **Aucun calcul de commission n'est effectué** tant que le dossier est contesté (`PAYMENT_DECISIONS_V1.md` §4, A14). Le traitement et la résolution de la contestation relèvent de la V1b.
4. **Expiration du délai de 72 h :**
   - Le délai de 72 heures est configurable par tenant dans `Tenant.config["service_confirmation_sla_hours"]` (défaut 72 h).
   - Point de départ : Horodatage précis UTC de création de la notification voyageur (`service_declarations.created_at`).
   - Deux options s'opposent sur le traitement de la non-réponse :
     - **Option A (Confirmation tacite) :** À l'expiration du délai sans action du voyageur, la prestation est réputée acceptée et bascule automatiquement en `confirmed` (source `"tacit_deadline"`), déclenchant le calcul de la commission.  
       _Avantages :_ Évite le blocage des flux en cas de négligence du voyageur.  
       _Risques :_ Risque de contestation ultérieure hors délai, fragilité juridique si le voyageur n'a pas lu la notification.
     - **Option B (Dossier marqué non confirmé sans facturation automatique — Recommandation `PAYMENT_DECISIONS_V1.md` §4) :** À l'expiration, la déclaration bascule en `expired_unconfirmed`. Aucune commission n'est calculée automatiquement. Le dossier est soumis au contrôle humain d'un opérateur financier.  
       _Avantages :_ Conforme au principe de prudence et au §4 de `PAYMENT_DECISIONS_V1.md` (_« L'absence de réponse n'est pas une preuve de réalisation et aucune facturation automatique n'est déclenchée »_).  
       _Risques :_ Nécessite une intervention humaine pour débloquer les créances.

> **DÉCISION PROPRIÉTAIRE REQUISE :** Trancher formellement entre l'Option A (confirmation tacite après 72 h) et l'Option B (mise en attente `expired_unconfirmed` sans calcul automatique, conforme au §4).

---

## 5. Matrice de permissions et contrôles d'accès

Conformément à l'analyse de l'addendum (`docs/payment/PAYMENT_AUDIT.md` §18.3), un administrateur du tenant (`is_admin == True`) a aujourd'hui le pouvoir d'agir sur toutes les réservations via `_scope_filter` (`backend/app/api/v1/endpoints/partner.py:76-86`). Par conséquent, `Booking.responded_by` peut être un administrateur et non un gérant de terrain.  
De plus, les gérants de POI (`POIManager`) ne doivent pas accéder aux informations fiscales, aux taux de commission ni aux factures de l'opérateur économique.

| Action                                     | Voyageur                 | Gérant POI (`POIManager`)    | Administrateur Tenant (`is_admin`) | Opérateur Financier (`finance_operator`, V1b) | Opérateur CLI direct        |
| ------------------------------------------ | ------------------------ | ---------------------------- | ---------------------------------- | --------------------------------------------- | --------------------------- |
| Gérer le POI (horaires, infos)             | Non                      | **Oui** (sur POI gérés)      | **Oui** (tous POI)                 | Non                                           | **Oui**                     |
| Déclarer une prestation                    | Non                      | **Oui** (si rattaché au POI) | **Oui** (secours / délégation)     | Non                                           | **Oui** (maintenance)       |
| Consulter les prestations déclarées        | Ses propres réservations | Prestations de ses POI       | Toutes prestations du tenant       | Prestations de son tenant                     | **Oui** (export CSV)        |
| Modifier profil contractuel partenaire     | Non                      | Non                          | **Oui** (ou contact facturation)   | Non                                           | **Oui**                     |
| Consulter taux de commission & créances    | Non                      | Non                          | **Oui**                            | **Oui**                                       | **Oui**                     |
| Corriger / ajuster une déclaration validée | Non                      | Non                          | Non (interdit silencieusement)     | **Oui** (avec motif journalisé)               | **Oui** (traçabilité audit) |
| Résoudre une contestation de voyageur      | Non                      | Non                          | Non                                | **Oui** (procédure V1b)                       | **Oui**                     |
| Reporting financier multi-partenaires      | Non                      | Non                          | Non (pas d'API transversale)       | Relevé de son tenant                          | **Oui** (script CLI isolé)  |

---

## 6. Analyse des mécanismes de preuve de la prestation

L'identifiant externe `Booking.external_id` (format `EXT-{str(booking.id)[:8]}`, défini à `backend/app/api/v1/endpoints/bookings.py:259` et `backend/app/api/v1/endpoints/partner.py:308`) est un hachage tronqué déterministe de l'UUID de réservation. Il ne constitue en aucun cas une preuve d'exécution du service (`PAYMENT_DECISIONS_V1.md` §4).

### Comparatif des options de preuve

| Critère                               | Option A : Déclaration partenaire + Confirmation voyageur in-app                                              | Option B : Déclaration partenaire + Justificatif joint (facture/ticket)               | Option C : Preuve de présence physique (Code OTP / QR code sur place)                                                   |
| ------------------------------------- | ------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------- |
| **Fonctionnement**                    | Le partenaire déclare le montant, le voyageur clique « Je confirme la prestation » dans l'application mobile. | Le partenaire téléverse une photo du reçu ou ticket de caisse lors de sa déclaration. | Le partenaire génère un QR code à l'accueil du POI, le voyageur le scanne avec l'app pour valider sa présence physique. |
| **Fiabilité**                         | Moyenne (dépend de la bonne volonté du voyageur à rouvrir l'app après son voyage).                            | Forte sur la matérialité de la dépense, mais lourde à vérifier.                       | Très forte sur la présence physique, mais ne garantit pas le montant exact payé sur place.                              |
| **Friction utilisateur**              | Très faible : simple notification push avec un bouton de validation.                                          | Élevée côté partenaire (saisie et téléversement d'image).                             | Élevée : nécessite une action synchronisée pendant la prestation sur place.                                             |
| **Coût de dev & complexité**          | Faible : réutilise l'infrastructure existante de notifications (`Notification`, `notification_service.py`).   | Moyen : gestion du stockage de fichiers sécurisé, détection PII, quota disque.        | Élevé : implémentation scanner QR mobile, synchronisation temps réel, support hors-ligne.                               |
| **Surface de fraude & contournement** | Risque d'entente ou d'inertie du voyageur ; pas de vérification de ticket.                                    | Risque de faux justificatifs ou de tickets réutilisés sans OCR comptable.             | Risque de scan anticipé sans exécution effective du service complet.                                                    |
| **Impact mobile & i18n**              | Mineur : une carte de confirmation dans l'écran réservations (`loc.bookingConfirmService`).                   | Moyen : composant d'upload d'images sur mobile et web.                                | Majeur : module caméra et permissions scanner QR sur mobile.                                                            |

### Recommandation

Pour la V1a, **l'Option A est vivement recommandée** : elle offre la friction minimale, réutilise intégralement l'infrastructure de notifications in-app existante (`mobile/lib/screens/bookings_screen.dart:292-328` et `backend/app/services/notification_service.py:35-82`), et s'adapte parfaitement au cycle de notification prévu. L'Option B ou C pourra être introduite en V1b ou V2 comme couche de contrôle renforcée sur échantillon.

> **DÉCISION PROPRIÉTAIRE REQUISE :** Valider l'Option A (déclaration partenaire + confirmation in-app voyageur) pour la livraison autonome V1a.

---

## 7. Spécification des interfaces V1a

### 7.1 Nouveaux Endpoints Backend (FastAPI)

Tous les endpoints sont montés avec isolation stricte par tenant via `x_tenant_slug: str = Header(...)` et résolution par `get_tenant_from_header` (`backend/app/core/tenant.py:1-25`).

1. `POST /api/v1/partner/bookings/{booking_id}/declare` :
   - **Acteur :** Partenaire rattaché au POI (`_require_partner`, `backend/app/api/v1/endpoints/partner.py:89`).
   - **Corps de requête :**
     ```json
     {
       "declaration_type": "service_rendered",
       "amount_minor": 1500000,
       "currency": "DZD",
       "tax_amount_minor": 0
     }
     ```
   - **Comportement :** Vérifie que la réservation est `confirmed` et terminée, crée la ligne `service_declarations`, programme la notification voyageur et enregistre l'événement dans `financial_audit_log`.
2. `POST /api/v1/bookings/{booking_id}/confirm-service` :
   - **Acteur :** Voyageur propriétaire (`current_user`).
   - **Comportement :** Fait passer la déclaration à `confirmed`, génère `service_completions` et `commission_receivables`, notifie le partenaire.
3. `POST /api/v1/bookings/{booking_id}/dispute-service` :
   - **Acteur :** Voyageur propriétaire.
   - **Corps de requête :** `{"reason": "Le montant réel payé était de 12 000 DZD et non 15 000 DZD"}`.
   - **Comportement :** Marque la déclaration comme `disputed`, suspend le calcul de commission, consigne dans le journal d'audit.

### 7.2 Intégration côté mobile (Flutter)

- **Espace partenaire (`mobile/lib/screens/partner_bookings_screen.dart`) :** Sur les réservations confirmées dont la date d'exécution est passée, ajout d'un bouton d'action _"Déclarer la prestation"_ ouvrant une modale de saisie du montant en devise locale.
- **Écran voyageur (`mobile/lib/screens/bookings_screen.dart`) :** Réception de la notification `service_declaration_received`. La carte de réservation affiche un bandeau invitant à confirmer ou contester le montant sous 72 h.

### 7.3 Script CLI de reporting financier (`app/reporting_finance.py`)

- Développé selon le standard strict de `backend/app/create_tenant.py:1-104`.
- **Usage :** `python -m app.reporting_finance --tenant-slug algeria --format csv --output /tmp/commissions_algeria.csv`.
- **Fonctionnalités :** Lecture seule, extraction des déclarations, des prestations confirmées et des créances de commission, sans aucune dépendance HTTP ni exposition réseau.

---

## 8. Stratégie de migration Alembic & Déploiement

### 8.1 Conventions de migration

- **Idempotence et caractère strictement additif :** Aucune modification de table existante (aucun renommage de colonne sur `bookings`, `pois`, `users`). Seules des tables et colonnes nouvelles sont introduites.
- **Types SQL :** UUID natifs PostgreSQL (`postgresql.UUID(as_uuid=True)`), dates en `DateTime` naive-UTC (`TIMESTAMP WITHOUT TIME ZONE`) conformément à la convention `utcnow()` (`backend/app/models.py:13-32`), devises en `String(3)`, montants en `BigInteger`.
- **Réversibilité (Downgrade) :** Chaque migration implémente une fonction `downgrade()` exhaustive supprimant les contraintes, index et tables créés dans l'ordre inverse exact de `upgrade()`.

### 8.2 Ordre de succession des révisions Alembic

La dernière révision en date sur `main` est `0016_backfill_skipped_notifs.py` (`backend/alembic/versions/0016_backfill_skipped_notifs.py:1-30`).

1. **Révision `0017_financial_foundation_entities` :** Création des tables `legal_entities`, `partner_profiles`, `partner_poi_assignments`, `commission_rules`.
2. **Révision `0018_service_declarations_receivables` :** Création des tables `service_declarations`, `service_completions`, `commission_receivables`, `financial_audit_log`.

### 8.3 Date de bascule et gestion du seed existant

- **Date de bascule (Cutover date) :** Seules les réservations créées après l'application de la révision `0018` sont éligibles à la déclaration de prestation. Les réservations historiques antérieures demeurent en lecture seule dans leur état terminal.
- **Traitement du seed sur bases existantes :**  
  Dans `backend/app/initial_data.py:20-22` :
  ```python
  result = await session.execute(select(Tenant).where(Tenant.slug == "algeria"))
  if result.scalar_one_or_none():
      return
  ```
  Sur une base existante où `algeria` existe déjà, `morocco` n'est pas injecté par le code actuel.  
  Pour le déploiement du domaine financier, l'initialisation des entités juridiques (`legal_entities`) et des règles de commission par défaut (`commission_rules`) sera encapsulée dans une fonction dédiée idempotente `_seed_financial_foundation(session: AsyncSession)` vérifiant l'existence par slug avant toute insertion, garantissant un comportement identique sur base vierge et sur base préexistante.

---

## 9. Stratégie de tests et non-régression

La suite de tests actuelle (`446 passed in 40.54s` sur le backend) doit impérativement demeurer à 100 % passante.

### 9.1 Nouveaux tests unitaires et d'intégration à prévoir (pour l'implémentation)

1. **Tests d'isolation multi-tenant :** Vérifier qu'un appel avec l'en-tête `X-Tenant-Slug: algeria` ne peut en aucun cas déclarer, consulter ou modifier une déclaration ou créance appartenant à un autre tenant (HTTP 404 strict, sans fuite d'information).
2. **Tests de la règle pays/entité :**
   - Tentative d'activer ou de calculer une commission sur un partenaire dont le pays diffère de celui de l'entité légale => Rejet explicite avec exception métier.
   - Vérification que le tenant `morocco` ne génère aucune commission en V1.
3. **Tests d'intégrité des montants :**
   - Rejet de montants négatifs ou nuls (`amount_minor <= 0`).
   - Vérification de l'exactitude des calculs en points de base sans arrondi flottant (ex. 15 000 DZD à 10 % = 1 500 DZD = 150 000 centimes exacts).
4. **Tests de la machine d'états financière :**
   - Impossibilité de déclarer sur une réservation non `confirmed`.
   - Idempotence des confirmations voyageur.
   - Gel immédiat du calcul de commission lors d'une contestation (`disputed`).
5. **Non-régression des tests existants :** Protection des tests documentés dans l'addendum `docs/payment/PAYMENT_AUDIT.md` §18.5 (`test_consent_true_on_cancelled_booking_rejected`, `test_expire_overdue_requests_notifies_both_once_and_respects_tenant_isolation`, etc.).

---

## 10. Écarts connus du domaine réservation (hors périmètre paiement)

Ces écarts sont consignés à titre d'information architecturale et **ne doivent pas être modifiés** dans le cadre du chantier paiement, afin de ne pas déstabiliser la plateforme :

1. **Accesseur mobile `canCancel` :** Dans `mobile/lib/models/booking.dart:81`, `canCancel => isPending || isAwaitingPartner;` n'inclut pas le statut `expired`, alors que le backend `backend/app/api/v1/endpoints/bookings.py:309-313` autorise expressément l'annulation d'une réservation `expired`.
2. **Double-tap sur le bouton de consentement :** Risque d'envoi concurrent de requêtes de consentement résolu côté serveur par le garde d'état 409 (`backend/app/api/v1/endpoints/bookings.py:211-212`), mais méritant un verrouillage visuel de bouton côté Flutter (`isSubmitting`).
3. **Message 409 générique :** Le message renvoyé lors d'un consentement sur un état non pending est `"Booking cannot be consented in its current state"`.

---

## 11. Risques et questions ouvertes (Décisions Propriétaire Requises)

1. **DÉCISION PROPRIÉTAIRE REQUISE 1 :** Confirmer que seul le mode de réservation `manual_confirm` est éligible à la déclaration de prestation et au calcul de commission en V1a, les modes `request` et `pay_on_site` étant exclus jusqu'à réévaluation en V1b.
2. **DÉCISION PROPRIÉTAIRE REQUISE 2 :** Valider la création des tables autonomes `partner_profiles` et `partner_poi_assignments` pour isoler la relation contractuelle financière sans dénaturer la table opérationnelle `poi_managers`.
3. **DÉCISION PROPRIÉTAIRE REQUISE 3 :** Arbitrer le traitement de l'expiration du délai de 72 h alloué au voyageur entre l'Option A (confirmation tacite automatique) et l'Option B (mise en attente `expired_unconfirmed` sans calcul de commission, recommandée par `PAYMENT_DECISIONS_V1.md` §4).
4. **DÉCISION PROPRIÉTAIRE REQUISE 4 :** Valider l'Option A pour le mécanisme de preuve de prestation en V1a (déclaration partenaire couplée à une confirmation in-app du voyageur), écartant les contraintes matérielles des justificatifs papiers ou scanners QR sur place.
5. **DÉCISION PROPRIÉTAIRE REQUISE 5 :** Confirmer le gel complet des commissions sur le tenant `morocco` en V1 en application stricte de la règle de sécurité métier pays/entité.
