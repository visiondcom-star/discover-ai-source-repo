# Architecture & Design Technique — Domaine Paiement & Fondation Financière V1

> **Document de référence :** Point de contrôle 2 du chantier paiement (conforme à `PAYMENT_ARCHITECTURE_V3.md` (document externe non versionné, non joint à cette PR) section 4 et 5, et `docs/payment/PAYMENT_DECISIONS_V1.md` §1 à §16 intégrant les amendements A1 à A14).    
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
| Déclaration de prestation par le partenaire (`service_declarations`) avec montant et devise | **V1a** | Réservation au statut `confirmed` |
| Confirmation de prestation par le voyageur (enregistrement date, source, montant) | **V1a** | Notification voyageur in-app / push |
| Enregistrement initial de contestation par le voyageur (motif horodaté) | **V1a** | Suspension du calcul de commission dès l'ouverture (`PAYMENT_DECISIONS_V1.md` §4, A14) |
| Délai de réponse de 72 h configurable par tenant et rappels périodiques | **V1a** | Tâche d'arrière-plan / worker périodique (`backend/app/services/notification_worker.py:91-105`) |
| Calcul et snapshot immuable de la commission (`service_completions`, `commission_receivables`) | **V1a** | Uniquement après confirmation du voyageur |
| Journal d'audit financier append-only (`financial_audit_log`)                                                                 | **V1a** | Immuabilité et traçabilité des opérations                                              |
| Script CLI de consultation financière en lecture seule                                                                        | **V1a** | Modèle `backend/app/create_tenant.py:1-103`                                            |
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
- Aucun rôle de « super-administrateur » global de plateforme : l'isolation multi-tenant demeure absolue (`backend/app/core/tenant.py:1-24`, `backend/app/dependencies.py:144-155`).

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

> **NOTE D'ARBITRAGE DU POINT DE CONTRÔLE 2 (02/11/2026) :**  
> L'Option B de la sous-section 1 ci-dessous (`legal_entities` avec colonne `tenant_id`, une ligne par tenant) est formellement **SUPERSEDÉE** par la décision **D3/E3** (`docs/payment/PAYMENT_DECISIONS_V1.md:229`). La décision D3 arrête qu'il n'y a qu'une seule entité juridique Discover AI en V1 (algérienne, sans `tenant_id`), référencée par une table de configuration par tenant `tenant_legal_entity_configs` (`tenant_id` -> `legal_entity_id`). Voir le détail des conséquences techniques en section 12.

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
| partner_profile_id (UUID, FK)       |             | booking_id (UUID, FK, index)                   |
| poi_id (UUID, FK)                   |             | legal_entity_id (UUID, FK, snapshot)           |
| valid_from (DateTime)               |             | applied_rate_bps (Integer, snapshot)           |
| valid_to (DateTime, opt)            |             | partner_profile_id (UUID, FK)                  |
+-------------------------------------+             | poi_id (UUID, FK) | declared_by_user_id (UUID) |
                                                    | declaration_type (String(30))                  |
                                                    | service_date (Date)                            |
                                                    | amount_minor (BigInteger) | currency (String)  |
                                                    | tax_amount_minor (BigInteger, opt)             |
                                                    | status (String(30)) | confirmation_deadline    |
                                                    | supersedes_declaration_id (UUID, FK, opt)      |
                                                    | is_current (Boolean, default True)             |
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

- **Rôle :** Représente l'entité juridique Discover AI émettrice et responsable de l'activité financière. En V1, une unique entité Discover AI existe (Algérie, `PAYMENT_DECISIONS_V1.md` §8).
- **Architecture de scoping : Option A vs Option B**
  - **Option A (Entité plateforme sans `tenant_id`) :** L'entité légale est globale à la plateforme et référencée par les tenants via `Tenant.config["legal_entity_id"]` ou une table d'association `tenant_legal_entities`.  
    *Avantages :* Évite la duplication si plusieurs tenants partagent la même entité juridique.  
    *Risques :* Contrevient au principe architectural non négociable 2 de `CLAUDE.md:59` (*« tenant_id auf allen Kernentitäten »* [tenant_id sur toutes les entités clés]) ainsi qu'à la section *Tenant-Administration* de `CLAUDE.md:79` (*« Es gibt bewusst keinen Super-Admin auf Plattformebene »* [Il n'y a délibérément aucun super-admin au niveau plateforme]), et complique les filtres de requêtes multi-tenant.
  - **Option B (Scoping strict par tenant, une ligne par tenant — Recommandation) :** Chaque tenant déclare formellement son entité juridique responsable dans `legal_entities` avec clé étrangère `tenant_id`. En V1, seul le tenant `algeria` possède une entité active (`country_code="DZ"`).  
    *Avantages :* Respecte à 100 % l'isolation multi-tenant stricte (`backend/app/core/tenant.py:1-24`), simplifie les contrôles de sécurité et les cascades de suppression.    
    *Risques :* Duplication de métadonnées si plusieurs tenants partagent une structure juridique future.
  - > **TRANCHÉ PAR D3/E3 :** Entité unique sans `tenant_id` + table `tenant_legal_entity_configs` (`tenant_id` -> `legal_entity_id`) reliant chaque destination à l'entité unique algérienne (`docs/payment/PAYMENT_DECISIONS_V1.md:229` et section 12.1).
- **Colonnes :**
  - `id` : `UUID`, Clé Primaire (`default=uuid.uuid4`).
  - `tenant_id` : `UUID`, Clé Étrangère vers `tenants.id`, non nulle, indexée (sous Option B).
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
  - `tax_identification_number` : `String(100)`, numéro d'identification fiscale (chiffré via `CredentialCrypto`, `backend/app/services/credential_crypto.py:25-112`).
  - `country_code` : `String(2)`, code ISO 3166-1 alpha-2 du partenaire (utilisé pour la vérification pays/entité).
  - `billing_address` : `JSON`, coordonnées postales et administratives.
  - `billing_contact_user_id` : `UUID`, Clé Étrangère vers `users.id` (contact principal habilité pour la finance).
  - `is_commission_enabled` : `Boolean`, défaut `False` (activation explicite exigée par `PAYMENT_DECISIONS_V1.md` §8).
  - `created_at` : `DateTime`, défaut `utcnow`.
  - `updated_at` : `DateTime`, défaut `utcnow`, `onupdate=utcnow`.
- **Contraintes :** `Index("ix_partner_profiles_tenant_country", "tenant_id", "country_code")`.

#### 3. Table `partner_poi_assignments`

- **Rôle :** Rattachement temporel d'un POI à une entité partenaire responsable de sa gestion financière.
- **Règle de non-chevauchement temporel :** Un POI donné au sein d'un tenant ne peut être rattaché qu'à un seul profil partenaire à un instant $T$. Deux plages `[valid_from, valid_to[` ne doivent jamais se recouvrir pour un même `poi_id`.  
  *Mise en œuvre :* Vérification applicative sous verrou pessimiste (`with_for_update()`) lors des écritures.  
  *Contrainte d'exclusion PostgreSQL (`EXCLUDE USING gist`) :* L'expression `EXCLUDE USING gist (poi_id WITH =, tsrange(valid_from, coalesce(valid_to, 'infinity'::timestamp)) WITH &&)` exige l'extension PostgreSQL `btree_gist`. Or, cette extension n'est pas activée aujourd'hui sur le conteneur (`deploy/postgres/init-test-db.sql:8, 13` n'active que l'extension `vector`). L'utilisation de cette contrainte nécessite une migration Alembic exécutant `CREATE EXTENSION IF NOT EXISTS btree_gist;` et une reconstruction éventuelle de l'image de base (`docker compose build postgres` selon `CLAUDE.md:34, 110`). À défaut, la vérification applicative stricte sous transaction sérialisée suffit en V1a.
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
- **Règle de priorité et de non-chevauchement :**
  1. *Priorité de portée :* Si une règle active existe avec `partner_profile_id` spécifié (règle négociée), elle **l'emporte** sur la règle par défaut du tenant (`partner_profile_id IS NULL`).
  2. *Unicité temporelle :* Il ne peut exister qu'une seule règle active par portée (par tenant ou par couple tenant/partenaire) à une date donnée ($T \in [valid\_from, valid\_to[$).
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
- **Principe du snapshot immuable :** Les colonnes `legal_entity_id` et `applied_rate_bps` sont figées dès l'insertion de la déclaration dans `service_declarations`. Tout changement ultérieur des règles de commission dans `commission_rules` ou de l'entité juridique n'a **strictement aucun impact rétroactif** sur les déclarations existantes.
- **Mécanisme de correction (écritures compensatoires) :** Conformément à `PAYMENT_DECISIONS_V1.md` §2 et §5, **aucun `UPDATE` direct du montant ou des taxes n'est autorisé** sur une déclaration validée ou confirmée. Toute modification de montant exige la création d'un **nouvel enregistrement** liant l'ancienne déclaration via `supersedes_declaration_id`. L'ancienne déclaration passe à `is_current = False`.
- **Colonnes :**
  - `id` : `UUID`, Clé Primaire.
  - `tenant_id` : `UUID`, Clé Étrangère vers `tenants.id`, non nulle, indexée.
  - `booking_id` : `UUID`, Clé Étrangère vers `bookings.id`, non nulle, indexée.
  - `legal_entity_id` : `UUID`, Clé Étrangère vers `legal_entities.id`, non nulle (snapshot immuable pris à la déclaration).
  - `applied_rate_bps` : `Integer`, non nulle (snapshot immuable du taux en bps résolu à la déclaration).
  - `partner_profile_id` : `UUID`, Clé Étrangère vers `partner_profiles.id`, non nulle.
  - `poi_id` : `UUID`, Clé Étrangère vers `pois.id`, non nulle.
  - `declared_by_user_id` : `UUID`, Clé Étrangère vers `users.id` (gérant ayant saisi la déclaration).
  - `declaration_type` : `String(30)`, parmi `("service_rendered", "late_cancellation_fee", "no_show_fee")` (`docs/payment/PAYMENT_DECISIONS_V1.md:31`).
  - `service_date` : `Date`, date effective d'exécution du service (voir section Date de prestation ci-dessous).
  - `amount_minor` : `BigInteger`, montant total encaissé déclaré en unités mineures (centimes), non nul, strictement positif (`> 0`).
  - `currency` : `String(3)`, code devise ISO 4217 identique à `Booking.currency`.
  - `tax_amount_minor` : `BigInteger`, nullable, montant des taxes incluses identifiées et documentées.
  - `status` : `String(30)`, état de la déclaration : `"declared"`, `"confirmed"`, `"disputed"`, `"expired_unconfirmed"`, `"needs_review"`, `"superseded"`.
  - `review_reason` : `Text`, nullable (motif interne obligatoire lorsque `status == "needs_review"`).
  - `confirmation_deadline` : `DateTime`, nullable (échéance de 72 heures allouée au voyageur pour confirmer ou contester ; nulle tant que `status == "needs_review"`).
  - `flagged_at` : `DateTime`, nullable (horodatage du signalement d'anomalie `needs_review`).
  - `dispute_reason` : `Text`, motif de contestation renseigné par le voyageur en cas de désaccord.
  - `disputed_at` : `DateTime`, nullable (horodatage de contestation par le voyageur).
  - `expired_at` : `DateTime`, nullable (horodatage du passage à `expired_unconfirmed`).
  - `supersedes_declaration_id` : `UUID`, Clé Étrangère vers `service_declarations.id`, nullable (identifie la déclaration corrigée).
  - `is_current` : `Boolean`, non nulle, défaut `True` (indique la version active du type de déclaration pour la réservation).
  - `declared_by_admin` : `Boolean`, non nulle, défaut `False` (drapeau indiquant si l'action émane d'un administrateur).
  - `declaration_reason` : `Text`, nullable (obligatoire si `declared_by_admin == True` ; le motif est également consigné dans `financial_audit_log.reason`).
  - `created_at` : `DateTime`, défaut `utcnow`.
- **Contraintes et Index :** 
  - `CheckConstraint("declared_by_admin = False OR (declared_by_admin = True AND declaration_reason IS NOT NULL)", name="chk_admin_declaration_reason")`.
  - Unicité partielle compatible avec les corrections et les 3 types de déclaration :  
    `CREATE UNIQUE INDEX uq_current_declaration ON service_declarations (tenant_id, booking_id, declaration_type) WHERE is_current = True;`  
    Cette contrainte garantit qu'il ne peut exister qu'une seule déclaration active par type pour une réservation donnée, tout en autorisant l'historique de versions successives via `is_current = False`.

#### 6. Table `service_completions`

- **Rôle :** Prestation formellement actée (confirmée par le voyageur ou clôturée). Déclenche le calcul de commission.
- **Colonnes :**
  - `id` : `UUID`, Clé Primaire.
  - `tenant_id` : `UUID`, Clé Étrangère vers `tenants.id`, non nulle, indexée.
  - `declaration_id` : `UUID`, Clé Étrangère vers `service_declarations.id`, non nulle, **UNIQUE**.
  - `legal_entity_id` : `UUID`, Clé Étrangère vers `legal_entities.id`, non nulle (recopié depuis `service_declarations.legal_entity_id`).
  - `confirmed_at` : `DateTime`, horodatage de validation définitive.
  - `confirmation_source` : `String(50)`, source de confirmation (ex. `"traveller_in_app"`, `"operator_resolution"`, `"tacit_deadline"` si retenu).
  - `final_amount_minor` : `BigInteger`, assiette financière retenue (en centimes).
  - `applied_commission_bps` : `Integer`, taux en points de base appliqué (recopié depuis `service_declarations.applied_rate_bps`).
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
- **Identification des acteurs et traçabilité :** Tout acte manuel doit être nominativement imputable. Si l'action émane d'une session utilisateur interactive, `actor_user_id` est obligatoire (`UUID`). Si l'action est exécutée via un script en ligne de commande (ex. script CLI d'administration ou de maintenance), `actor_user_id` peut être `NULL` mais la colonne `operator_identifier` devient **strictement obligatoire et non nulle** (ex. `cli:sysadmin_ops_01` ou nom du compte système exécutant).
- **Immuabilité technique (Politique logicielle vs Verrou en base de données) :**
  - *Niveau 1 (Politique logicielle) :* Aucun endpoint ni repository n'expose de méthode d'altération (`UPDATE` / `DELETE`).
  - *Niveau 2 (Option de verrouillage PostgreSQL direct) :*  
    - Option A : Révocation des privilèges SQL `REVOKE UPDATE, DELETE ON financial_audit_log FROM discoverai_app;` appliquée via migration Alembic.  
    - Option B : Trigger PostgreSQL `BEFORE UPDATE OR DELETE` levant une exception `RAISE EXCEPTION 'financial_audit_log is immutable'`.  
    *Coûts et risques de migration :* L'Option A exige que l'utilisateur de connexion applicatif PostgreSQL ne soit pas superuser / propriétaire absolu de la base (sinon le REVOKE peut être contourné). L'Option B fonctionne indépendamment des rôles mais introduit un trigger PL/pgSQL exécuté sur la base de test PostgreSQL (`discoverai_test`).  
    *Recommandation :* Mettre en œuvre le trigger bloquant (Option B) en plus de la politique logicielle dès la migration V1a.
- **Colonnes :**
  - `id` : `UUID`, Clé Primaire.
  - `tenant_id` : `UUID`, non nulle, indexée.
  - `actor_user_id` : `UUID`, nullable (renseigné si session authentifiée).
  - `operator_identifier` : `String(100)`, nullable (obligatoire si `actor_user_id IS NULL`, consigne l'opérateur CLI).
  - `actor_role` : `String(50)`, rôle de l'acteur (ex. `"partner"`, `"traveller"`, `"cli_operator"`, `"admin"`).
  - `action` : `String(50)`, ex. `"declare_service"`, `"confirm_service"`, `"dispute_service"`, `"supersede_declaration"`.
  - `target_table` : `String(50)`, table visée (ex. `"service_declarations"`).
  - `target_id` : `UUID`, identifiant de la ligne ciblée.
  - `payload_before` : `JSON`, état antérieur (sérialisé).
  - `payload_after` : `JSON`, nouvel état.
  - `reason` : `Text`, motif obligatoire pour toute opération de correction ou résolution manuelle.
  - `created_at` : `DateTime`, non nulle, défaut `utcnow`.
- **Contraintes :** `CheckConstraint("actor_user_id IS NOT NULL OR operator_identifier IS NOT NULL", name="chk_audit_actor_present")`. Table strictement en écriture seule.

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

### 4.1 Date de prestation et conditions de déclaration

#### Distinction stricte entre les trois dates (Glossaire temporel)
Le domaine financier distingue rigoureusement trois dates temporelles indépendantes, qui ne doivent **jamais être confondues ni substituées** :
1. **Date prévue de la réservation (`booking_data["date"]`) :** Date souhaitée ou convenue lors de la demande de réservation, extraite du dictionnaire JSON libre `Booking.booking_data`. Elle peut être absente, partielle ou mal formée.
2. **Date de prestation déclarée par le partenaire (`service_declarations.service_date`) :** Date effective à laquelle le partenaire certifie que l'activité touristique a été réalisée. Saisie obligatoirement lors de la déclaration, elle doit être située dans le passé ou au jour même (`service_date <= utcnow().date()`).
3. **Date de création de la réservation (`Booking.created_at`) :** Horodatage technique système de création de la ligne SQL dans la table `bookings`.

**Règle absolue :** Il n'existe **aucun repli silencieux sur `Booking.created_at`**. Si la date prévue de la réservation ou la date de prestation déclarée est absente ou inexploitable, le système ne substitue jamais la date de création : le dossier bascule immédiatement sous statut d'anomalie `needs_review` (voir D15). Le contrôle de cohérence temporelle des 7 jours calendaires (D15) compare exclusivement la date prévue de réservation (`booking_data["date"]`) et la date de prestation déclarée (`service_date`).

#### Absence de colonne de date sur le modèle Booking existant
Dans le code actuel de `Booking` (`backend/app/models.py:332-364`), le modèle ne comporte **strictement aucune colonne SQL dédiée aux dates de séjour ou de prestation**. Les seules colonnes temporelles présentes sont des métadonnées système : `consent_timestamp`, `respond_by`, `responded_at`, `created_at`, `updated_at` (`backend/app/models.py:343, 348, 353-355`).  
Les dates souhaitées par le voyageur (ex. `"date"`, `"start_date"`, `"end_date"`) sont stockées de façon non structurée dans le dictionnaire JSON libre et facultatif `booking_data = Column(JSON, default=dict)` (`backend/app/models.py:346`), sans garantie de présence ni de format ISO.

Par conséquent, une condition d'éligibilité du type `end_date <= utcnow().date()` est **techniquement irréalisable sur le modèle actuel** sans convention explicite.

#### Options architecturales pour la date de prestation
- **Option A (Date de service déclarative saisie par le partenaire — Recommandation V1a) :** Le partenaire renseigne obligatoirement la date de réalisation `service_date` (`Date`) au moment où il appelle `POST /partner/bookings/{id}/declare`. Le backend applique un garde-fou strict : `service_date <= utcnow().date()` (la date ne peut pas être située dans le futur).  
  *Avantages :* Aucune migration sur la table `bookings`, zéro impact sur le frontend voyageur, compatibilité immédiate avec les réservations existantes.  
  *Risques :* Déclaration purement déclarative par le partenaire quant au jour exact de réalisation.
- **Option B (Ajout d'une colonne dédiée sur Booking) :** Migration additive Alembic ajoutant `service_date = Column(Date, nullable=True)` sur `bookings`, alimentée dès la création de réservation.  
  *Avantages :* Donnée structurée et native dès la réservation.  
  *Risques :* Nécessite une migration de schéma sur la table centrale `bookings`, des modifications de contrat API sur `POST /bookings/`, et des ajustements sur mobile et web.
- **Option C (Exigence et validation stricte dans `booking_data`) :** Rendre obligatoire la clé `"date"` ou `"end_date"` au format ISO 8601 dans `booking_data` au niveau du schéma `BookingCreate`.  
  *Avantages :* Pas de nouvelle colonne SQL.  
  *Risques :* Rupture de compatibilité avec les clients existants qui n'enverraient pas cette clé avec la casse exacte.

> **DÉCISION PROPRIÉTAIRE REQUISE :** Valider l'Option A (date de prestation déclarée par le partenaire et bornée au présent/passé) pour la V1a, sans modifier la table `bookings`.

### 4.2 Transitions d'états de la déclaration de prestation

1. **Création (`∅` → `declared`) :**
   - **Acteur :** Partenaire autorisé (associé au POI via `partner_poi_assignments`).
   - **Condition :** `Booking.status == "confirmed"`, `Booking.booking_mode == "manual_confirm"`, date de service déclarée valide (`service_date <= utcnow().date()`).
   - **Action :** Résolution et snapshot immuable de `legal_entity_id` et `applied_rate_bps`. Enregistrement de `amount_minor`, `currency`, `tax_amount_minor`, calcul de `confirmation_deadline = utcnow() + timedelta(hours=deadline_hours)` (défaut : 72 h). Émission d'une notification voyageur `service_declaration_received`.
2. **Confirmation voyageur (`declared` → `confirmed`) :**
   - **Acteur :** Voyageur propriétaire de la réservation (`Booking.user_id == current_user.id`).
   - **Action :** Création synchrone de `service_completions` et de `commission_receivables`. Calcul immuable de la commission due selon la formule définie au §4.3.
3. **Contestation voyageur (`declared` → `disputed`) :**
   - **Acteur :** Voyageur propriétaire de la réservation.
   - **Condition :** Avant expiration de `confirmation_deadline`. Saisie d'un motif obligatoire (`dispute_reason`).
   - **Action :** Enregistrement de l'état `disputed`. **Aucun calcul de commission n'est effectué** tant que le dossier est contesté (`PAYMENT_DECISIONS_V1.md` §4, A14). Le traitement et la résolution de la contestation relèvent de la V1b.
4. **Expiration du délai de 72 h :**
   - Le délai de 72 heures est configurable par tenant dans `Tenant.config["service_confirmation_sla_hours"]` (défaut 72 h).
   - Point de départ : Horodatage précis UTC de création de la notification voyageur (`service_declarations.created_at`).
   - Deux options s'opposent sur le traitement de la non-réponse :
     - **Option A (Confirmation tacite) :** À l'expiration du délai sans action du voyageur, la prestation est réputée acceptée et bascule automatiquement en `confirmed` (source `"tacit_deadline"`), déclenchant le calcul de la commission.  
       *Avantages :* Évite le blocage des flux en cas de négligence du voyageur.  
       *Risques :* Risque de contestation ultérieure hors délai, fragilité juridique si le voyageur n'a pas lu la notification.
     - **Option B (Dossier marqué non confirmé sans facturation automatique — Recommandation `PAYMENT_DECISIONS_V1.md` §4) :** À l'expiration, la déclaration bascule en `expired_unconfirmed`. Aucune commission n'est calculée automatiquement. Le dossier est soumis au contrôle humain d'un opérateur financier.  
       *Avantages :* Conforme au principe de prudence et au §4 de `PAYMENT_DECISIONS_V1.md` (*« L'absence de réponse n'est pas une preuve de réalisation et aucune facturation automatique n'est déclenchée »*).  
       *Risques :* Nécessite une intervention humaine pour débloquer les créances.

> **STATUT : TRANCHÉ PAR D5/E2** (`docs/payment/PAYMENT_DECISIONS_V1.md:229`). L'Option B est formellement retenue : après 72 h sans confirmation voyageur, la déclaration bascule en `expired_unconfirmed` ; aucune commission n'est calculée ni exigible à ce stade ; aucune facturation automatique n'est déclenchée. Le dossier est soumis au contrôle humain d'un opérateur financier en V1b.

### 4.3 Formule de calcul de la commission et politique d'arrondi

Conformément à `PAYMENT_DECISIONS_V1.md` §7 :
- **Assiette de calcul (Base) :**
  $$\text{Base} = \begin{cases} 
  \text{amount\_minor} - \text{tax\_amount\_minor} & \text{si taxes distinctes, documentées et valides} \\ 
  \text{amount\_minor} & \text{sinon (montant encaissé déclaré)}
  \end{cases}$$
  Contrôles de cohérence obligatoires (`PAYMENT_DECISIONS_V1.md` A9) : $\text{tax\_amount\_minor} \ge 0$ et $\text{tax\_amount\_minor} \le \text{amount\_minor}$.
- **Calcul de la commission :**
  $$\text{Commission} = \frac{\text{Base} \times \text{applied\_rate\_bps}}{10\,000}$$
- **Règle d'arrondi sur les unités mineures (entiers) :**
  La division par 10 000 d'un entier peut générer un reste fractionnaire de centime. Deux options d'arrondi déterministe sont proposées :
  - **Option A (Arrondi à l'unité mineure inférieure — Floor) :** Division entière $\lfloor (\text{Base} \times \text{rate\_bps}) / 10\,000 \rfloor$.  
    *Avantages :* Prudence commerciale en faveur du partenaire, aucune fraction de centime surfacturée.
  - **Option B (Arrondi bancaire au plus proche — Half to Even) :** Arrondi standard demi-pair sur le centime.  
    *Avantages :* Standard comptable limitant les biais d'agrégation statistique.
  - **Exemple chiffré comparatif :**
    - **Cas 1 (Le produit brut tombe sur un demi-centime pair) :**
      - Montant déclaré HT = 12 815,05 DZD (`Base = 1281505` centimes).
      - Taux de commission = 10,00 % (`rate_bps = 1000`).
      - Produit brut / 10 000 = $(1\,281\,505 \times 1\,000) / 10\,000 = 128\,150,5$ centimes.
      - Résultat Option A (Floor) = $128\,150$ centimes (1 281,50 DZD).
      - Résultat Option B (Half to Even) = $128\,150$ centimes (1 281,50 DZD), car 128 150 est pair.
    - **Cas 2 (Le produit brut tombe sur un demi-centime impair, illustrant l'écart) :**
      - Montant déclaré HT = 12 815,15 DZD (`Base = 1281515` centimes).
      - Taux de commission = 10,00 % (`rate_bps = 1000`).
      - Produit brut / 10 000 = $(1\,281\,515 \times 1\,000) / 10\,000 = 128\,151,5$ centimes.
      - Résultat Option A (Floor) = $128\,151$ centimes (1 281,51 DZD).
      - Résultat Option B (Half to Even) = $128\,152$ centimes (1 281,52 DZD), car 128 152 est le nombre pair le plus proche.
    - *(Calculs validés avec le module standard Python `decimal.Decimal` et les politiques `ROUND_FLOOR` et `ROUND_HALF_EVEN`).*

> **DÉCISION PROPRIÉTAIRE REQUISE :** Valider la politique d'arrondi explicite (Option A : troncature/floor, ou Option B : arrondi bancaire demi-pair).

---

## 5. Matrice de permissions et contrôles d'accès

Conformément à l'analyse de l'addendum (`docs/payment/PAYMENT_AUDIT.md` §18.3), un administrateur du tenant (`is_admin == True`) a aujourd'hui le pouvoir d'agir sur toutes les réservations via `_scope_filter` (`backend/app/api/v1/endpoints/partner.py:76-86`). Par conséquent, `Booking.responded_by` peut être un administrateur et non un gérant de terrain.  
De plus, les gérants de POI (`POIManager`) ne doivent pas accéder aux informations fiscales, aux taux de commission ni aux factures de l'opérateur économique.

### Question du rôle de l'administrateur du tenant sur la déclaration de prestation
L'administrateur du tenant doit-il être autorisé à déclarer une prestation en lieu et place du partenaire de terrain ?
- **Option A (Interdiction stricte) :** Seuls les utilisateurs expressément rattachés au POI via `partner_poi_assignments` peuvent déclarer une prestation. L'administrateur ne peut pas se substituer au partenaire de terrain.  
  *Avantages :* Évite tout abus ou déclaration arbitraire sans contact direct avec le voyageur.  
  *Risques :* Blocage opérationnel si le compte du partenaire est inaccessible ou défaillant.
- **Option B (Autorisation exceptionnelle avec traçabilité renforcée — Recommandation) :** L'administrateur peut déclarer une prestation en secours, mais cette action exige obligatoirement un motif explicite consigné dans `financial_audit_log` et marque la déclaration d'un drapeau d'audit `declared_by_admin = True`.  
  *Avantages :* Flexibilité opérationnelle tout en garantissant une traçabilité totale en cas de litige.
- > **DÉCISION PROPRIÉTAIRE REQUISE :** Valider l'Option B (autorisation de déclaration par l'admin avec motif d'audit obligatoire) ou l'Option A (réservation exclusive aux gérants de POI).

| Action | Voyageur | Gérant POI (`POIManager`) | Administrateur Tenant (`is_admin`) | Opérateur Financier (`finance_operator`, V1b) | Opérateur CLI direct (avec `operator_identifier`) |
|---|---|---|---|---|---|
| Gérer le POI (horaires, infos) | Non | **Oui** (sur POI gérés) | **Oui** (tous POI) | Non | **Oui** |
| Déclarer une prestation | Non | **Oui** (si rattaché au POI) | **Sous réserve Option B** (avec motif journalisé) | Non | **Oui** (maintenance) |
| Consulter les prestations déclarées | Ses propres réservations | Prestations de ses POI | Toutes prestations du tenant | Prestations de son tenant | **Oui** (export CSV) |
| Modifier profil contractuel partenaire | Non | Non | **Oui** (ou contact facturation) | Non | **Oui** |
| Consulter taux de commission & créances | Non | Non | **Oui** | **Oui** | **Oui** |
| Corriger / ajuster une déclaration validée | Non | Non | Non (interdit silencieusement) | **Oui** (avec motif journalisé) | **Oui** (traçabilité audit) |
| Résoudre une contestation de voyageur | Non | Non | Non | **Oui** (procédure V1b) | **Oui** |
| Reporting financier multi-partenaires | Non | Non | Non (pas d'API transversale) | Relevé de son tenant | **Oui** (script CLI isolé) |

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

Pour la V1a, **l'Option A est vivement recommandée** : elle offre la friction minimale, réutilise intégralement l'infrastructure de notifications in-app existante (`mobile/lib/screens/bookings_screen.dart:292-328` et `backend/app/services/notification_service.py:35-81`), et s'adapte parfaitement au cycle de notification prévu. L'Option B ou C pourra être introduite en V1b ou V2 comme couche de contrôle renforcée sur échantillon.

> **DÉCISION PROPRIÉTAIRE REQUISE :** Valider l'Option A (déclaration partenaire + confirmation in-app voyageur) pour la livraison autonome V1a.

---

## 7. Spécification des interfaces V1a

### 7.1 Nouveaux Endpoints Backend (FastAPI)

Tous les endpoints sont montés avec isolation stricte par tenant via `x_tenant_slug: str = Header(...)` et résolution par `get_tenant_from_header` (`backend/app/core/tenant.py:1-24`).

1. `POST /api/v1/partner/bookings/{booking_id}/declare` :
   - **Acteur :** Partenaire rattaché au POI (`_require_partner`, `backend/app/api/v1/endpoints/partner.py:89`).
   - **Corps de requête :**
     ```json
     {
       "declaration_type": "service_rendered",
       "service_date": "2026-11-01",
       "amount_minor": 1500000,
       "currency": "DZD",
       "tax_amount_minor": 0
     }
     ```
   - **Comportement :** Vérifie que la réservation est `confirmed` et que `service_date <= utcnow().date()`, résout et fige `legal_entity_id` et `applied_rate_bps`, crée la ligne `service_declarations`, programme la notification voyageur et enregistre l'événement dans `financial_audit_log`.
2. `POST /api/v1/bookings/{booking_id}/confirm-service` :
   - **Acteur :** Voyageur propriétaire (`current_user`).
   - **Comportement :** Fait passer la déclaration à `confirmed`, génère `service_completions` et `commission_receivables`, notifie le partenaire.
3. `POST /api/v1/bookings/{booking_id}/dispute-service` :
   - **Acteur :** Voyageur propriétaire.
   - **Corps de requête :** `{"reason": "Le montant réel payé était de 12 000 DZD et non 15 000 DZD"}`.
   - **Comportement :** Marque la déclaration comme `disputed`, suspend le calcul de commission, consigne dans le journal d'audit.

### 7.2 Intégration côté mobile (Flutter)

- **Espace partenaire (`mobile/lib/screens/partner_bookings_screen.dart`) :**
  - Sur les réservations confirmées dont la date d'exécution est passée, ajout d'un bouton d'action _"Déclarer la prestation"_ ouvrant une modale de saisie du montant en devise locale.
  - **Affichage des dossiers signalés ou en vérification :** Lorsqu'un dossier est sous statut `needs_review` ou `disputed`, l'espace partenaire affiche la mention neutre : *"Prestation en vérification"*, accompagnée d'un lien vers le contact support.
  - **Absence de promesse de notification et confidentialité :** Cet affichage n'engage aucune promesse de notification ultérieure au partenaire (aucune notification de D8 ne couvre une réouverture en V1a ; aucune reprise de dossier n'est automatisée). L'interface partenaire ne révèle **jamais** de motif interne d'anomalie, de résultat de contrôle antifraude, de commentaire interne de gestion, d'information fiscale sensible ni de détail sur une contestation voyageur. Elle ne laisse en aucun cas croire que le partenaire peut résoudre l'anomalie de façon autonome dans son interface.

- **Écran voyageur (`mobile/lib/screens/bookings_screen.dart`) :** Réception de la notification `service_declaration_received`. La carte de réservation affiche un bandeau invitant à confirmer ou contester le montant sous 72 h.

### 7.3 Mécanisme des rappels périodiques et gestion de l'unicité des notifications

#### Contrainte d'unicité existante sur les notifications
Dans le code actuel (`backend/app/models.py:460-469`), la table `notifications` porte un index partiel unique strict :
```python
Index(
    "uq_notifications_booking_unique",
    "tenant_id",
    "user_id",
    "booking_id",
    "type",
    unique=True,
    postgresql_where=text("booking_id IS NOT NULL"),
)
```
Dans `backend/app/services/notification_service.py:51, 68-80`, toute tentative d'insérer un doublon levant `IntegrityError` est capturée par un savepoint (`begin_nested()`) et silencieusement ignorée.  
**Conflits identifiés avec le domaine financier :**
1. Si un partenaire émet une déclaration de correction (`supersedes_declaration_id`), ou s'il déclare ultérieurement des frais (`late_cancellation_fee` ou `no_show_fee` après une première notification), l'émission d'une notification du type identique `service_declaration_received` pour la même réservation (`booking_id`) sera **rejetée silencieusement par la base** et le voyageur ne sera jamais averti.
2. De même, si le worker tente d'envoyer un rappel périodique avec le type `service_confirmation_reminder`, il ne pourra en émettre qu'un seul sur toute la durée de vie de la réservation.

#### Options architecturales pour gérer les notifications financières multiples
- **Option A (Types d'événements distincts et dédiés — Recommandation V1a) :** Conserver l'index unique existant intact (zéro risque de régression sur les notifications système en production) et introduire des types de notification distincts pour chaque événement financier :
  - Déclaration initiale : `service_declaration_received`
  - Correction de déclaration : `service_declaration_corrected`
  - Frais de no-show / annulation : `fee_declaration_received`
  - Rappel d'échéance : `service_confirmation_reminder`
- **Option B (Évolution de l'index d'unicité avec clé de déduplication / version) :** Migration Alembic modifiant `uq_notifications_booking_unique` pour inclure une clé discriminante optionnelle `dedup_key` ou `declaration_id`.  
  *Avantages :* Autorise plusieurs notifications du même type avec clés distinctes.  
  *Risques :* Migration DDL sur une table centrale en production, risque de régression sur les flux existants de réservation et consentement.

> **DÉCISION PROPRIÉTAIRE REQUISE :** Valider l'Option A (types de notification distincts par événement sans modification de l'index d'unicité) pour la V1a.

#### Fonctionnement du balayage de rappel par le worker
Conformément à `PAYMENT_DECISIONS_V1.md` §4 et A14, le voyageur dispose d'un délai configurable de 72 heures pour confirmer ou contester la prestation déclarée.  
1. **Infrastructure réutilisée :** Le worker d'arrière-plan existant (`backend/app/services/notification_worker.py:91-105`) implémente déjà l'acquisition atomique par lots sans contention via `SELECT FOR UPDATE SKIP LOCKED` (`claim_batch`), les politiques de baux expirables (`locked_until`), et les relances cadencées (`RETRY_DELAYS`, `next_attempt_at`, lignes 19-25).
2. **Balayage cadencé :**
   - Une fonction périodique `dispatch_pending_confirmation_reminders(db: AsyncSession)` inspecte les déclarations actives dans `service_declarations` avec `status == "declared"`.
   - Si le délai restant avant `confirmation_deadline` est compris entre 24 h et 25 h (soit 48 h après la déclaration initiale), et qu'aucune notification de relance n'a encore été envoyée pour cette réservation, le système émet une notification `service_confirmation_reminder` au voyageur via `create_notification` (`backend/app/services/notification_service.py:35-81`).
   - L'idempotence de la relance est garantie par l'index `uq_notifications_booking_unique` sur le type `service_confirmation_reminder`.

### 7.4 Script CLI de reporting financier (`app/reporting_finance.py`)

- Développé selon le standard strict de `backend/app/create_tenant.py:1-103`.
- **Usage :** `python -m app.reporting_finance --tenant-slug algeria --format csv --output /tmp/commissions_algeria.csv`.
- **Fonctionnalités :** Lecture seule stricte.
- **Affichage des dossiers d'exception et calcul d'ancienneté :**
  Le script permet de lister les dossiers aux statuts `needs_review`, `disputed` et `expired_unconfirmed` en restituant :
  - L'identifiant de la déclaration (`id`), le statut courant, le `tenant_id`, et la référence de réservation (`booking_id`).
  - L'horodatage précis de l'événement déclencheur : `flagged_at` pour `needs_review`, `disputed_at` pour `disputed`, et `expired_at` pour `expired_unconfirmed`.
  - **L'ancienneté du dossier :** Calculée strictement depuis l'horodatage de l'événement (`flagged_at`, `disputed_at`, ou `expired_at`), et **jamais depuis `Booking.created_at`** (qui ne reflète que la date technique de la réservation initiale).
  - Pour les dossiers `needs_review`, le CLI affiche également le motif interne consigné (`review_reason`).
  - Le script opère exclusivement en lecture seule : il n'exécute aucun changement de statut, aucun recalcul de montant, aucune résolution manuelle ni aucune facturation.

---

## 8. Stratégie de migration Alembic & Déploiement

### 8.1 Conventions de migration

- **Idempotence et caractère strictement additif :** Aucune modification de table existante (aucun renommage de colonne sur `bookings`, `pois`, `users`). Seules des tables et colonnes nouvelles sont introduites.
- **Types SQL :** UUID natifs PostgreSQL (`postgresql.UUID(as_uuid=True)`), dates en `DateTime` naive-UTC (`TIMESTAMP WITHOUT TIME ZONE`) conformément à la convention `utcnow()` (`backend/app/models.py:13-32`), devises en `String(3)`, montants en `BigInteger`.
- **Réversibilité (Downgrade) :** Chaque migration implémente une fonction `downgrade()` exhaustive supprimant les contraintes, index et tables créés dans l'ordre inverse exact de `upgrade()`.

### 8.2 Ordre de succession des révisions Alembic

La dernière révision en date sur `main` est `0016_backfill_skipped_notifs.py` (`backend/alembic/versions/0016_backfill_skipped_notifs.py:1-29`).

1. **Révision `0017_financial_foundation_entities` :** Création des tables de structure : `legal_entities`, `tenant_legal_entity_configs`, `partner_profiles`, `partner_poi_assignments`, `commission_rules`. Réversible par `alembic downgrade 0016`.
2. **Révision `0018_backfill_tenant_country_codes` :** Migration de données idempotente alimentant `Tenant.country_code` (`algeria` -> `"DZ"`, `morocco` -> `"MA"`) et initialisant `Tenant.config["service_confirmation_sla_hours"] = 72`. Réversible par `alembic downgrade 0017`.
3. **Révision `0019_service_declarations_receivables` :** Création des tables opérationnelles : `service_declarations`, `service_completions`, `commission_receivables`, `financial_audit_log` (avec trigger d'immuabilité). Réversible par `alembic downgrade 0018`.
4. **Révision `0020_user_finance_operator_role` (V1b) :** Ajout de la colonne `is_finance_operator` sur `users`. Réversible par `alembic downgrade 0019`.
5. **Révision `0021_commission_statements` (V1b) :** Création de la table `commission_statements`. Réversible par `alembic downgrade 0020`.
6. **Révision `0022_cancellation_policies` (V1c) :** Création de la table `cancellation_policies` et ajout de `cancellation_policy_version_id` sur `bookings`. Réversible par `alembic downgrade 0021`.

### 8.3 Date de bascule et gestion du seed existant

- **Date de bascule (Cutover date) :** Seules les réservations créées après l'application de la révision `0019` sont éligibles à la déclaration de prestation. Les réservations historiques antérieures demeurent en lecture seule dans leur état terminal.
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

La suite de tests backend doit impérativement demeurer à 100 % passante.  
*Note de référence de couverture :* Le fichier `CLAUDE.md:11` documente 279 tests unitaires historiques (`279/279 pytest-Tests grün`). Le nombre effectif actuel de tests est à mesurer avant l'implémentation (commande : `docker compose exec backend pytest tests/ -q`). L'ensemble des tests s'exécute sur PostgreSQL (`backend/tests/conftest.py:17-22`, base de test `discoverai_test` avec `create_async_engine`). Tout ajout de migration ou de modèle financier s'accompagnera de tests stricts sans affaiblir aucune assertion existante.

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

## 10. Écarts connus et conciliation avec les décisions V1

### 10.1 Écarts du domaine réservation existant (hors périmètre paiement)
Ces constats sont consignés à titre d'information architecturale et **ne doivent pas être modifiés** dans le cadre du chantier paiement :
1. **Accesseur mobile `canCancel` :** Dans `mobile/lib/models/booking.dart:81`, `canCancel => isPending || isAwaitingPartner;` n'inclut pas le statut `expired`, alors que le backend `backend/app/api/v1/endpoints/bookings.py:309-313` autorise expressément l'annulation d'une réservation `expired`.
2. **Double-tap sur le bouton de consentement :** Risque d'envoi concurrent de requêtes de consentement résolu côté serveur par le garde d'état 409 (`backend/app/api/v1/endpoints/bookings.py:211-212`), mais méritant un verrouillage visuel de bouton côté Flutter (`isSubmitting`).
3. **Message 409 générique :** Le message renvoyé lors d'un consentement sur un état non pending est `"Booking cannot be consented in its current state"`.

### 10.2 Écarts et arbitrages avec PAYMENT_DECISIONS_V1.md
1. **Écart sur la date d'exécution de la prestation :** `PAYMENT_DECISIONS_V1.md` §2 évoque une déclaration postérieure à la prestation. Le présent document constate formellement l'absence de colonne SQL de date sur `Booking` (`backend/app/models.py:332-364`) et soumet l'arbitrage entre une date déclarée par le partenaire (Option A) ou une nouvelle colonne en base (Option B), au lieu de supposer silencieusement l'existence d'une date de fin native.
2. **Écart sur la portée de l'unicité de déclaration :** `PAYMENT_DECISIONS_V1.md` A13 introduit trois types de déclaration distincts (`service_rendered`, `late_cancellation_fee`, `no_show_fee`). Une contrainte brute `UNIQUE(booking_id)` interdirait de déclarer des frais après un refus ou une annulation. Le présent design résout cet écart en définissant un index unique partiel sur `(tenant_id, booking_id, declaration_type) WHERE is_current = True`.

---

## 11. Risques et questions ouvertes (Statut des décisions après arbitrage du point de contrôle 2)

Les décisions initiales listées ci-dessous ont été formellement arbitrées par le propriétaire du projet lors du point de contrôle 2 (renvoi vers `docs/payment/PAYMENT_DECISIONS_V1.md:224-241` et section 12) :

1. **DÉCISION 1 (Modes éligibles) : TRANCHÉE PAR D1.** Seul le mode `manual_confirm` est éligible en V1a. Les modes `request` et `pay_on_site` restent hors commission V1a.
2. **DÉCISION 2 (Tables partenaire) : TRANCHÉE PAR D2.** Deux tables dédiées sont créées : `partner_profiles` et `partner_poi_assignments`.
3. **DÉCISION 3 (Entité juridique) : TRANCHÉE PAR D3/E3.** Une seule entité Discover AI en V1 (algérienne, sans `tenant_id`), référencée par une table de configuration par tenant `tenant_legal_entity_configs`.
4. **DÉCISION 4 (Date de prestation) : TRANCHÉE PAR D4.** Date `service_date` saisie par le partenaire (bornée au présent/passé), sans modification de `bookings`. Contrôle d'anomalie (`needs_review`) si la date est trop éloignée.
5. **DÉCISION 5 (Expiration 72 h) : TRANCHÉE PAR D5/E2.** Statut `expired_unconfirmed` sans calcul automatique ni commission exigible. Résolution en V1b.
6. **DÉCISION 6 (Arrondi) : TRANCHÉE PAR D6.** Calcul exact sur entiers et taux en points de base (`rate_bps`), aucun float. Résultat et mode d'arrondi conservés ; convention d'arrondi à valider par l'expert-comptable avant facturation.
7. **DÉCISION 7 (Rôle de l'administrateur tenant) : TRANCHÉE PAR D7/E4.** L'administrateur du tenant ne peut pas déclarer de prestation en V1a ni accéder aux profils fiscaux.
8. **DÉCISION 8 (Unicité des notifications) : TRANCHÉE PAR D8.** Sept types de notifications distincts compatibles avec l'index partiel `uq_notifications_booking_unique`.
9. **DÉCISION 9 (Preuve de prestation) : TRANCHÉE PAR D9.** Confirmation in-app par le voyageur authentifié. QR code non obligatoire en V1a.
10. **DÉCISION 10 (Tenant Maroc) : TRANCHÉE PAR D10.** Commission strictement désactivée par la règle de sécurité pays/entité côté serveur.

*(Les nouvelles questions ouvertes D13 à D16 sont consignées dans `docs/payment/PAYMENT_DECISIONS_V1.md:243-268` et `docs/payment/PAYMENT_IMPLEMENTATION.md`).*


---

## 12. Conséquences techniques des décisions D1 à D12

Cette section consigne les impacts techniques précis des arbitrages D1 à D12 validés lors du point de contrôle 2 (`docs/payment/PAYMENT_DECISIONS_V1.md:224-241`) :

### 12.1 Entité juridique Discover AI et configuration par tenant (D3/E3)
- La table `legal_entities` ne porte **pas** de colonne `tenant_id`. Elle modélise la société Discover AI au niveau plateforme (en V1 : une seule ligne, Discover AI Algérie, `country_code = "DZ"`).
- Une table de configuration dédiée `tenant_legal_entity_configs` associe chaque destination à son entité de rattachement légal :
  - `id` : `UUID`, Clé Primaire (`default=uuid.uuid4`).
  - `tenant_id` : `UUID`, Clé Étrangère vers `tenants.id`, non nulle, indexée, **UNIQUE** (un tenant pointe sur exactement une entité en V1).
  - `legal_entity_id` : `UUID`, Clé Étrangère vers `legal_entities.id`, non nulle (`ondelete="RESTRICT"`).
  - `created_at` : `DateTime`, défaut `utcnow`.
- Plusieurs tenants peuvent ainsi pointer sur la même entité juridique sans duplication de l'entité elle-même. Chaque opération financière enregistrée continue de porter explicitement `tenant_id` ET `legal_entity_id` pour préserver l'isolation et la traçabilité. Le tenant Maroc pointe sur cette même entité ou reste sans configuration active de commission. Aucune entité européenne n'est créée.

### 12.2 Structure partenaire et immuabilité de l'imputation (D2)
- La table `service_declarations` conserve un snapshot complet du partenaire responsable au moment précis de la déclaration :
  - `partner_profile_id` : `UUID`, Clé Étrangère vers `partner_profiles.id`, non nulle (`ondelete="RESTRICT"`).
  - `partner_assignment_id` : `UUID`, Clé Étrangère vers `partner_poi_assignments.id`, non nulle (`ondelete="RESTRICT"`).
- **Règles sur les clés étrangères vers `users` :**
  - Pour `service_declarations.declared_by_user_id` et `service_completions` : utilisation de `ondelete="RESTRICT"` ou conservation du nom complet textuel dénormalisé (`declared_by_user_name = Column(String(100))`) avec `ForeignKey("users.id", ondelete="SET NULL")`.
  - *Justification :* La suppression ultérieure d'un compte utilisateur ou le départ d'un gestionnaire de POI ne doit jamais altérer rétroactivement la validité comptable de la déclaration ni supprimer en cascade les preuves d'audit.

### 12.3 Démonstration D7 — Éligibilité de l'utilisateur déclarant
- **Examen de l'existant :**
  - Dans `backend/app/api/v1/endpoints/partner.py:76-86`, `_scope_filter` filtre par `if current_user.is_admin: return Booking.tenant_id == tenant_id`.
  - Dans `backend/app/api/v1/endpoints/partner.py:89-96`, `_require_partner` autorise l'accès si `current_user.is_admin or poi_ids`.
  - Dans `backend/app/dependencies.py:158-175`, `get_partner_poi_ids` extrait les POI liés par `POIManager` (`backend/app/models.py:381-386`).
  - Dans `backend/app/models.py:118, 201`, `User.is_admin` est un booléen accordant l'administration globale du tenant.
- **Conclusion de conception pour D7 :**
  - L'administrateur du tenant (`is_admin == True`) est **strictement exclu** de la faculté de déclarer une prestation en V1a.
  - La route de déclaration `POST /api/v1/partner/bookings/{booking_id}/declare` ne doit **PAS** réutiliser `_require_partner` ni `_scope_filter` tels quels car ces fonctions admettent les administrateurs sans rattachement de terrain.
  - La route exige une dépendance dédiée `_require_declaring_partner` qui :
    1. Vérifie formellement que `current_user.id` possède une ligne active dans `POIManager` pour le `poi_id` de la réservation (`backend/app/models.py:381-386`).
    2. Vérifie qu'il existe un rattachement temporellement actif dans `partner_poi_assignments` (`valid_from <= utcnow() < coalesce(valid_to, 'infinity')`) liant ce `poi_id` à un `partner_profiles` dont la commission est activée (`is_commission_enabled == True`).
  - **Résultat :** Aucun nouveau rôle opérationnel n'est inventé ; la sécurité repose sur le croisement strict des relations existantes.

### 12.4 Date de prestation et détection d'anomalie (D4)
- La table `service_declarations` inclut `service_date = Column(Date, nullable=False)` saisie par le partenaire.
- Gardes-fous côté serveur :
  - `service_date <= utcnow().date()` (date obligatoirement passée ou du jour).
  - Contrôle de cohérence temporelle : si la date déclarée présente un écart supérieur au seuil configurable dans `Tenant.config["max_declaration_delay_days"]` (défaut 7 jours) par rapport à la date prévue de la réservation (`booking_data["date"]`), le système ne valide pas silencieusement la déclaration mais positionne le statut d'anomalie `status = "needs_review"` avec `review_reason` et horodatage `flagged_at = utcnow()`. Ce dossier est consultable en CLI sans bloquer arbitrairement la saisie.
- **Requête SQL d'audit statistique de la date prévue (Point bloquant P2) :**  
  *Mention obligatoire :* P2 : NON EXÉCUTÉE : exécution réservée au propriétaire, sur la base cible, après vérification de la version PostgreSQL (SHOW server_version) et dans une transaction en lecture seule ; résultats = agrégats seulement.  
  *Population cible :* Réservations sous `booking_mode = 'manual_confirm'` ET `status = 'confirmed'` (la déclaration de prestation exige formellement `Booking.status == "confirmed"`, `docs/payment/PAYMENT_V1A_SYNTHESIS.md:40` §3).  
  *Fenêtre temporelle :* Filtre sur `Booking.created_at` avec départ paramétrable fixé à maintenant (UTC) moins 60 jours (`(now() AT TIME ZONE 'UTC') - interval '60 days'`) et fin à l'heure d'exécution (`now() AT TIME ZONE 'UTC'`). `Booking.created_at` est en UTC naïf sans fuseau (`backend/app/models.py:13-32`). La migration 0019 n'existe pas dans le dépôt (la dernière révision étant `0016_backfill_skipped_notifs.py`, `backend/alembic/versions/0016_backfill_skipped_notifs.py:1-29`) : elle ne doit pas être citée comme filtre ; une nouvelle mesure devra être exécutée après son déploiement effectif en prenant comme date de départ la date réelle de bascule.  
  *Catégories EXCLUSIVES et ordre d'évaluation séquentielle :*
  1. `1_donnees_absentes` : `booking_data` NULL, JSON null (`jsonb_typeof(d) = 'null'`) ou objet vide (`{}`).
  2. `2_structure_inattendue` : JSON non objet (tableau, texte, nombre, booléen) ; ne provoque aucune erreur SQL et n'est pas ignoré.
  3. `3_start_date_sans_date` : `start_date` présent, clé `date` absente.
  4. `4_sans_cle_date` : objet sans clé `date` ni `start_date`, ou `date` ayant une valeur JSON null.
  5. `5_date_mal_formee` : `date` présente mais non conforme au format ISO-8601 strict `AAAA-MM-JJ` ou invalide au calendrier grégorien.
  6. `6_date_valide` : `date` conforme au format `AAAA-MM-JJ` et valide au calendrier grégorien.  
  *Sortie en lignes :* tenant (`tenants.slug`), POI (`pois.name`), catégorie, $n$. Aucun identifiant d'utilisateur ni donnée personnelle.  
  *Faits relus sur le dépôt :*
  - Le mobile transmet `date` (`AAAA-MM-JJ`), `guests` et `notes` (`mobile/lib/models/booking_details.dart:8, 49`).
  - La date est obligatoire côté mobile (`mobile/lib/screens/bookings_screen.dart:460-463, 588`).
  - Aucun envoi de `booking_data` dans `frontend/src`.
  - Aucune colonne de canal n'existe sur `Booking` (`backend/app/models.py:332-364`) : « date présente » est un indice fort de réservation mobile, pas une preuve de canal.
  - Le backend accepte d'autres clés dans les détails de réservation (`backend/app/api/v1/endpoints/partner.py:45-61`).  
  *Seuils opérationnels proposés par POI :*
  - $\ge 90\,\%$ de dates valides : maintenir `needs_review` et traiter les exceptions.
  - $50\,\%$ à $90\,\%$ : décision propriétaire.
  - $< 50\,\%$ : date obligatoire côté web avant démarrage.
  - Faible volume : regarder les chiffres absolus.  
  *Validation de syntaxe sur base PostgreSQL de TEST locale :* Syntaxe des deux variantes testée et validée sur conteneur Docker local `pgvector/pgvector:pg16` (PostgreSQL 16.15) ; cela ne prouve pas que la requête fonctionne sur le schéma de production car `bookings.booking_mode` dépend de la migration `0012_booking_modes_idempotency` (`backend/alembic/versions/0012_booking_modes_idempotency.py:24`).  
  *Requête PostgreSQL 16 (utilise `pg_input_is_valid`) :*
  ```sql
  BEGIN READ ONLY;
  WITH b AS (
    SELECT bk.tenant_id, bk.poi_id, (bk.booking_data::jsonb) AS d
    FROM bookings bk
    WHERE bk.booking_mode = 'manual_confirm'
      AND bk.status = 'confirmed'
      AND bk.created_at >= (now() AT TIME ZONE 'UTC') - interval '60 days'
      AND bk.created_at <= (now() AT TIME ZONE 'UTC')
  ), c AS (
    SELECT tenant_id, poi_id,
      CASE
        WHEN d IS NULL OR jsonb_typeof(d) = 'null' OR d = '{}'::jsonb THEN '1_donnees_absentes'
        WHEN jsonb_typeof(d) <> 'object' THEN '2_structure_inattendue'
        WHEN d->>'date' IS NULL AND d->>'start_date' IS NOT NULL THEN '3_start_date_sans_date'
        WHEN d->>'date' IS NULL THEN '4_sans_cle_date'
        WHEN d->>'date' ~ '^\d{4}-\d{2}-\d{2}$' AND pg_input_is_valid(d->>'date', 'date') THEN '6_date_valide'
        ELSE '5_date_mal_formee'
      END AS categorie
    FROM b
  )
  SELECT t.slug AS tenant, p.name AS poi, c.categorie, COUNT(*) AS n
  FROM c JOIN tenants t ON t.id = c.tenant_id JOIN pois p ON p.id = c.poi_id
  GROUP BY t.slug, p.name, c.categorie
  ORDER BY t.slug, p.name, c.categorie;
  ROLLBACK;
  ```

  *Variante PostgreSQL < 16 (validation du calendrier par motifs, sans `pg_input_is_valid`) :*
  ```sql
  BEGIN READ ONLY;
  WITH b AS (
    SELECT bk.tenant_id, bk.poi_id, (bk.booking_data::jsonb) AS d
    FROM bookings bk
    WHERE bk.booking_mode = 'manual_confirm'
      AND bk.status = 'confirmed'
      AND bk.created_at >= (now() AT TIME ZONE 'UTC') - interval '60 days'
      AND bk.created_at <= (now() AT TIME ZONE 'UTC')
  ), c AS (
    SELECT tenant_id, poi_id,
      CASE
        WHEN d IS NULL OR jsonb_typeof(d) = 'null' OR d = '{}'::jsonb THEN '1_donnees_absentes'
        WHEN jsonb_typeof(d) <> 'object' THEN '2_structure_inattendue'
        WHEN d->>'date' IS NULL AND d->>'start_date' IS NOT NULL THEN '3_start_date_sans_date'
        WHEN d->>'date' IS NULL THEN '4_sans_cle_date'
        WHEN d->>'date' ~ '^\d{4}-\d{2}-\d{2}$'
          AND (
            d->>'date' ~ '^\d{4}-(0[13578]|1[02])-(0[1-9]|[12]\d|3[01])$'
            OR d->>'date' ~ '^\d{4}-(0[469]|11)-(0[1-9]|[12]\d|30)$'
            OR d->>'date' ~ '^\d{4}-02-(0[1-9]|1\d|2[0-8])$'
            OR (
              d->>'date' ~ '^\d{4}-02-29$'
              AND (
                (substring(d->>'date' from 1 for 4)::int % 4 = 0 AND substring(d->>'date' from 1 for 4)::int % 100 <> 0)
                OR substring(d->>'date' from 1 for 4)::int % 400 = 0
              )
            )
          ) THEN '6_date_valide'
        ELSE '5_date_mal_formee'
      END AS categorie
    FROM b
  )
  SELECT t.slug AS tenant, p.name AS poi, c.categorie, COUNT(*) AS n
  FROM c JOIN tenants t ON t.id = c.tenant_id JOIN pois p ON p.id = c.poi_id
  GROUP BY t.slug, p.name, c.categorie
  ORDER BY t.slug, p.name, c.categorie;
  ROLLBACK;
  ```

### 12.5 Statuts du cycle de confirmation financière (D5/E2)
- Le cycle financier de `service_declarations.status` adopte les états fermés : `"declared"`, `"confirmed"`, `"disputed"`, `"expired_unconfirmed"`, `"superseded"`.
- Après 72 h sans confirmation voyageur : passage automatique à `status = "expired_unconfirmed"`. Aucune commission n'est exigible, aucune créance n'est émise. Le dossier reste identifiable par les outils CLI d'audit. La résolution humaine éventuelle relève de la V1b.

### 12.6 Règle d'arrondi et calcul sur entiers (D6)
- Montants stockés en entiers mineurs (centimes) avec taux en points de base (`rate_bps`).
- Le mode d'arrondi par défaut appliqué par le code est conservé dans `service_completions.rounding_mode = Column(String(20))` (ex. `"half_even"` ou `"floor"` selon validation par l'expert-comptable).

### 12.7 Sept types de notifications distincts et idempotence (D8)
Pour respecter l'index partiel existant `uq_notifications_booking_unique` (`backend/app/models.py:460-469`, unique sur `tenant_id`, `user_id`, `booking_id`, `type`), sept types distincts sont déclarés dans `NOTIFICATION_TEMPLATES` (`backend/app/services/notification_templates.py:8-49`) :
1. `service_declaration_received` (prestation déclarée par le partenaire).
2. `service_confirmation_requested` (demande d'approbation transmise au voyageur).
3. `service_confirmation_reminder` (rappel automatique avant expiration).
4. `service_confirmed` (prestation approuvée par le voyageur).
5. `service_disputed` (prestation contestée par le voyageur).
6. `service_confirmation_expired` (confirmation expirée sans réponse).
7. `service_declaration_corrected` (correction émise par le partenaire).  
Chaque type étant unique par `booking_id`, aucun conflit d'insertion silencieux ne se produit pour une même réservation.

### 12.8 Règle de sécurité pays/entité côté serveur (D10)
- Le contrôle d'éligibilité est vérifié de manière défensive au niveau du service backend (`commission_service.py`) :  
  Si `partner_profile.country_code != legal_entity.country_code`, la création d'une déclaration ou d'une règle de commission est rejetée avec une exception métier HTTP 422. Les partenaires marocains (`country_code == "MA"`) sont ainsi exclus de toute facturation de commission face à l'entité algérienne (`"DZ"`).

### 12.9 Plafond d'une correction unique par réservation (D11)
- La table `service_declarations` comporte `correction_count = Column(Integer, default=0, nullable=False)`.
- Si une déclaration est déjà sous statut `"superseded"` ou si `correction_count >= 1`, toute nouvelle tentative d'appel à `/declare` pour cette même réservation renvoie une HTTP 409 (`"Only one correction allowed per booking in V1a"`). La déclaration initiale, son motif de correction et les snapshots avant/après sont conservés dans `financial_audit_log`.

### 12.10 Gel des contestations en V1a (D12/E1)
- Une déclaration passant à `status = "disputed"` fige immédiatement le dossier. Aucun recalcul de commission n'est déclenché. Le script CLI `app.reporting_finance` permet uniquement d'extraire ces dossiers sous statut contesté pour revue en V1b, sans modification manuelle en V1a.


### 12.11 Provisionnement des partenaires par script CLI sécurisé (D13)
- Un script d'administration distinct `app/provision_partner.py` (séparé du script de consultation `app/reporting_finance.py`) est conçu pour créer et associer :
  - `partner_profiles` (raison sociale, identifiant fiscal chiffré au repos via `CredentialCrypto`).
  - `partner_poi_assignments` (rattachement daté à un POI existant du tenant).
  - `commission_rules` (règle par défaut 1 000 bps = 10 % ou dérogation négociée).
  - Rattachement légal à l'entité Discover AI via `tenant_legal_entity_configs`.
- **Règles d'identification et de sécurité :**
  - Exécution réservée à un opérateur habilité. La traçabilité exige la fourniture d'une référence de ticket ou d'opération obligatoire (`--ticket-ref`).
  - Le script refuse tout paramètre fiscal sensible en argument direct de ligne de commande (pas de `--tax-id` en clair dans l'historique shell ou la table des processus `ps`) : la saisie s'effectue via un prompt masqué interactif (`getpass.getpass`) ou via un fichier de configuration temporaire à permissions restrictives (`chmod 600`), selon le modèle éprouvé de `backend/app/create_tenant.py:80-82`.
  - Chaque opération génère un enregistrement dans `financial_audit_log` avec `action = "provision_partner"`, consignant l'identité observée ou déclarée, non vérifiée par l'application, la référence du ticket, la date/heure UTC, et les identifiants créés, sans jamais écrire de donnée fiscale en clair.
- **Décision P1 (Environnement d'exécution et authentification) :**
  - *Contexte d'exploitation :* Le propriétaire du projet est la seule personne accédant au serveur de production, qui s'exécute sous Docker Compose.
  - *Modalité retenue :* Compte SSH nominatif sur le système d'exploitation de la machine hôte (clé SSH uniquement, ni root ni compte partagé) combiné à `docker compose exec backend python -m app.provision_partner ...`.
  - *Qualifications formelles d'identité :*
    - Identité transmise par variable d'environnement (ex. `OPERATOR_IDENTIFIER`) : « identité déclarée, non vérifiée ».
    - Identité vue par le conteneur (`whoami` ou utilisateur du processus Docker) : « identité observée, non vérifiée ».
    - Journaux d'accès SSH de la machine hôte (`sshd`, `auth.log`) : « source potentielle de rapprochement, à vérifier, absente du dépôt ».
  - *Absence d'authentification applicative :* L'application n'authentifie jamais l'opérateur : la traçabilité applicative n'est pas une authentification vérifiée.
  - *Limite absolue :* Aucune mesure logicielle de traçabilité n'offre de protection contre un opérateur disposant d'un accès suffisant direct à PostgreSQL.
  - *Condition de révision :* L'attribution d'un accès au serveur à une seconde personne physique rouvre immédiatement le point P1. Statut : **DÉCIDÉ SOUS RÉSERVE** (condition de révision : accès accordé à une seconde personne).
- **Comparatif des options d'exécution pour P1 :**
  - *Option A (Machine d'administration dédiée) :* Authentification nominative de l'opérateur sur le poste d'admin (compte OS / clé SSH nominative). Accès réseau sécurisé vers PostgreSQL. Logs de session locaux. Limite : contournable en cas d'accès SQL direct.
  - *Option B (Conteneur backend via `kubectl exec`) :* Authentification OIDC / certificat X.509 utilisateur avec RBAC Kubernetes et journaux d'audit de l'API Server. Limite : complexité et absence de filtrage natif des arguments de script par Kubernetes.
  - *Option C (Compte SSH nominatif sur machine hôte + `docker compose exec backend`) [RETENUE - DÉCIDÉ SOUS RÉSERVE] :* Clé SSH nominative sur le système d'exploitation de la machine hôte. Il s'agit de la commande de référence documentée dans `CLAUDE.md:11, 14, 81` (`docker compose exec backend python -m app....`). Identité du processus du conteneur non nominative (compte générique/root Docker). Traçabilité par les journaux d'accès et d'élévation de privilèges de l'hôte (`sshd`, `sudo`, `auth.log`) [source potentielle de rapprochement, à vérifier, absente du dépôt]. Limites : aucune liaison native entre l'utilisateur SSH hôte et le contexte interne du conteneur.
  - *Option D (Déclencheur d'administration externe) :* Absent du dépôt examiné (aucun workflow de déploiement en production n'est configuré dans `.github/workflows/ci.yml:1-114`).

### 12.12 Cycle de vie des versions de déclaration et confirmation atomique (D14)
- **Versionnement strict :** Chaque déclaration possède `id` (`UUID`) et `version_number = Column(Integer, default=1, nullable=False)`. Une correction crée un nouvel enregistrement portant `version_number = 2` et `supersedes_declaration_id = old_id`, tandis que l'ancienne déclaration passe à `is_current = False` et `status = "superseded"`.
- **Point de départ unique du délai de 72 h :** L'échéance `confirmation_deadline` est recalculée à partir de `created_at` de la **nouvelle version** et stockée sur celle-ci.
- **Ordre explicite des contrôles atomiques lors de la confirmation voyageur :**  
  L'endpoint `POST /api/v1/bookings/{booking_id}/confirm-service` exige dans le corps de requête l'identifiant exact de la version consultée (`declaration_id` ou `version_number`). La requête s'exécute sous verrou de ligne pessimiste (`select ... for update`) et applique les contrôles dans l'ordre séquentiel strict suivant :
  1. **Contrôle d'idempotence immédiat (Même version déjà confirmée) :** Si la déclaration visée est déjà sous statut `status == "confirmed"`, et qu'elle correspond à la version courante `is_current == True` de cette réservation, le serveur renvoie immédiatement une réponse HTTP 200 avec la confirmation existante. **Aucune seconde créance** n'est créée dans `commission_receivables` (unicité garantie par contrainte SQL).
  2. **Existence et rattachement :** Vérifier que la déclaration ciblée existe et est bien rattachée au `booking_id` de la réservation du voyageur authentifié.
  3. **Vérification de statut confirmable :** Vérifier que son statut est strictement `status == "declared"`. Si le dossier est sous statut `disputed`, `needs_review` ou `expired_unconfirmed`, la confirmation est refusée avec HTTP 409.
  4. **Contrôle de version courante :** Vérifier que `is_current == True`. Si le voyageur tente de confirmer une version antérieure déjà remplacée par une correction partenaire, le serveur rejette la requête avec HTTP 409 (`"Declaration version is superseded"`).
  5. **Contrôle d'échéance :** Vérifier que `utcnow() <= confirmation_deadline` (délai de 72 h non échu). Si le délai est dépassé, la confirmation est formellement refusée avec HTTP 409 (`"Confirmation deadline has expired"`).  
     *Traitement du passage à `expired_unconfirmed` (à valider) :*  
     Il est **strictement interdit** de compter sur une écriture en base qui serait implicitement annulée (rollback) par la levée d'une réponse d'erreur HTTP 409. Le passage à l'état `expired_unconfirmed` doit impérativement être garanti selon l'un des deux modes suivants :
     - **Mode 1 (Tâche de fond périodique / worker asynchrone) [RECOMMANDÉ, à valider] :** Le passage en `expired_unconfirmed` est exécuté de manière décorrélée par une tâche de fond périodique dédiée, conçue exactement sur le modèle existant de `expire_overdue_requests` (`backend/app/services/booking_lifecycle.py:23-100`). Ce worker balaye les déclarations échues sous `status == "declared"`, positionne atomiquement `status = "expired_unconfirmed"` avec `expired_at = utcnow()`, émet les notifications associées et valide la transaction (`commit`). Dans ce schéma, l'endpoint HTTP vérifie simplement `utcnow() <= confirmation_deadline` et lève une exception 409 en lecture seule si le délai est dépassé, sans altérer l'état de la base lors de l'appel voyageur.
     - **Mode 2 (Écriture validée explicitement avant la réponse 409) :** La transaction métier applique la mutation `status = "expired_unconfirmed"` sous verrou, valide explicitement l'écriture en base (`await db.commit()`), puis retourne la réponse d'erreur HTTP 409.
     
     *Choix de conception retenu :* Le **Mode 1 (Tâche de fond sur le modèle `expire_overdue_requests`, `backend/app/services/booking_lifecycle.py:23-100`)** est retenu comme recommandation nominale [à valider]. Il préserve l'idempotence des requêtes d'interrogation, évite tout effet de bord d'écriture non isolé en cas de requêtes concurrentes rejetées, et sépare nettement le traitement asynchrone des expirations de la réponse d'erreur synchrone aux clients.
- **Contestation d'une version périmée :** Une tentative de contester une déclaration avec `is_current == False` renvoie également une HTTP 409 (`"Cannot dispute a superseded declaration"`).

### 12.13 Traitement d'anomalie `needs_review` et blocage de flux (D15)
- **Représentation unique et cohérente :** Conformément à la recommandation d'architecture unifiée, le dossier d'anomalie est modélisé par la valeur de statut `status = "needs_review"` et la colonne explicative `review_reason = Column(Text, nullable=True)`, sans recourir à un booléen séparé redondant. Tant que la déclaration est sous ce statut, `confirmation_deadline` reste `NULL` (aucun compte à rebours de 72 h n'est enclenché).
- **Déclencheurs :** Date de prestation déclarée absente, invalide, ou présentant un écart supérieur à 7 jours calendaires par rapport à la date prévue de la réservation (`booking_data["date"]`).
- **Comportement :**
  - Aucun repli silencieux sur `Booking.created_at`.
  - Le dossier est consigné avec son motif interne d'anomalie (`review_reason`), horodaté dans `flagged_at = utcnow()`, consultable par les opérateurs via le script CLI.
  - Aucune notification n'est transmise au voyageur.
  - Aucun délai de 72 h ne commence à courir (aucun rappel n'est émis).
  - Le dossier ne peut jamais basculer automatiquement en `expired_unconfirmed`.
  - La confirmation financière reste totalement bloquée en V1a jusqu'à examen en V1b.

### 12.14 Garde-fous d'anti-auto-confirmation et limites de gérance (D16)
- **Garde-fou serveur :** Lors de l'appel à `/declare`, le service vérifie que `Booking.user_id != current_user.id` et que `Booking.user_id` n'appartient pas à l'ensemble des `user_id` rattachés au même POI dans `POIManager` (`backend/app/models.py:381-386`) au moment du contrôle.
- **Limites connues documentées :**
  - Ce contrôle est ponctuel à l'instant de la soumission de la déclaration.
  - La table `poi_managers` supprimant ses lignes en cascade (`ondelete="CASCADE"`, `backend/app/models.py:382-384`) sans colonne d'historisation de date de fin, le système ne peut pas détecter si le voyageur était un ancien gérant dont le compte a été retiré de `poi_managers` avant la réservation.
  - Le système ne détecte pas deux comptes distincts complices non rattachés au même POI.
  - « Actif » signifie que la ligne existe en base à cet instant.
- **Option de traçabilité proposée (non imposée) :** Stocker dans `service_declarations.active_managers_snapshot` la liste des `user_id` des gérants du POI présents au moment de la déclaration, à titre d'élément d'audit en cas de litige ultérieur.
