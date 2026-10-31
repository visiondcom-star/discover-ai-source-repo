# Audit du Dépôt — Domaine Réservation, Architecture Technique & Prérequis Paiement

> **Document de référence :** Point de contrôle 1 du chantier paiement (conforme à `PAYMENT_ARCHITECTURE_V3.md`, section 5).  
> **Date de réalisation :** 30 octobre 2026.  
> **Branche de travail :** `docs/payment-audit`.  
> **Statut :** Travail d'audit en lecture seule du dépôt `discover-ai-source-repo`. Aucun code applicatif, aucune migration et aucune dépendance n'ont été modifiés.

---

## 1. États de réservation et machine d'états existante

### 1.1 Valeurs de `Booking.status`, constantes et contraintes

- **Modèle de données :** `Booking.status` est défini dans `backend/app/models.py:341` comme une colonne SQLAlchemy `Column(String(50), default="pending")`. Il ne s'agit pas d'un `Enum` PostgreSQL natif, ce qui permet des évolutions d'états sans migration DDL d'enum.
- **Constantes de référence :** Le fichier `backend/app/constants.py:92-94` définit formellement les états :
  - `BOOKING_STATUSES = ("pending", "requested", "confirmed", "declined", "expired", "cancelled")` (`backend/app/constants.py:92`).
  - `BOOKING_TERMINAL_STATUSES = ("confirmed", "declined", "expired", "cancelled")` (`backend/app/constants.py:94`).
  - Les réponses possibles d'un partenaire sur une demande `requested` sont `PARTNER_RESPONSES = ("confirm", "decline")` (`backend/app/constants.py:96`).
- **Contraintes en base :** Aucune contrainte `CHECK` SQL au niveau de la table `bookings` n'impose la liste à l'échelle de la base. La validation repose sur les schémas Pydantic (`backend/app/schemas.py:545-601`) et sur la logique métier des endpoints FastAPI.

### 1.2 Chaque transition d'état : fichier, ligne, acteur et endpoint

1. **Création (`∅` → `pending`) :**
   - **Fichier / Ligne :** `backend/app/api/v1/endpoints/bookings.py:113-126`.
   - **Acteur :** Voyageur authentifié (`current_user`).
   - **Endpoint :** `POST /api/v1/bookings/`.
   - **Détail :** La réservation est systématiquement initialisée à `status="pending"`, `consent_given=False`. Si le POI est en mode `manual_confirm`, `respond_by` est positionné à `utcnow() + timedelta(hours=24)` (`backend/app/api/v1/endpoints/bookings.py:123`).

2. **Demande partenaire (`pending` → `requested`) :**
   - **Fichier / Ligne :** `backend/app/api/v1/endpoints/bookings.py:217-250`.
   - **Acteur :** Voyageur authentifié (`current_user`).
   - **Endpoint :** `POST /api/v1/bookings/{booking_id}/consent` avec `data.consent = True`.
   - **Condition :** Applicable exclusivement si `booking.booking_mode == "manual_confirm"`. Si le statut n'est pas `pending`, une exception HTTP 409 est levée (`backend/app/api/v1/endpoints/bookings.py:220`).
   - **Effets :** `booking.consent_given = True`, `booking.consent_timestamp = utcnow()`, `booking.status = "requested"`. Aucun `external_id` n'est attribué à ce stade. Émission d'une notification `booking_request_received` aux gestionnaires du POI (`poi_managers`).

3. **Confirmation immédiate voyageur (`pending` → `confirmed` ou depuis `cancelled`/`confirmed`) :**
   - **Fichier / Ligne :** `backend/app/api/v1/endpoints/bookings.py:251-270`.
   - **Acteur :** Voyageur authentifié (`current_user`).
   - **Endpoint :** `POST /api/v1/bookings/{booking_id}/consent` avec `data.consent = True`.
   - **Faiblesse critique de contrôle de statut :** Contrairement à la branche `manual_confirm` qui vérifie explicitement `if booking.status != "pending": raise HTTPException(status_code=409)` (`backend/app/api/v1/endpoints/bookings.py:219-220`), la branche `else` (autres modes tels que `request` ou `pay_on_site`) ne comporte **strictement aucun contrôle d'état préalable**.
   - **Statuts atteignables et effets réels :**
     - Hors `manual_confirm`, les seuls statuts atteignables dans le cycle de vie sont `pending`, `confirmed` et `cancelled` (les statuts `declined` et `expired` n'existent qu'en mode `manual_confirm`, où `consent=True` renvoie déjà une HTTP 409 si `status != "pending"`).
     - Par conséquent, hors `manual_confirm`, `consent=True` n'a d'effet anormal que depuis deux statuts :
       - Depuis `cancelled` : **résurrection** d'une réservation annulée en `confirmed` ;
       - Depuis `confirmed` : émission d'une notification `booking_confirmed` en double sur une réservation déjà confirmée.
     - La valeur de `booking.external_id = f"EXT-{booking_id[:8]}"` étant déterministe (dérivée des 8 premiers caractères de l'UUID), elle reste identique et n'est pas remplacée par un identifiant différent.
   - **Couverture par les tests existants :**
     - Les tests existants (`backend/tests/test_bookings.py:146-181` `test_give_consent` et `backend/tests/test_booking_modes.py:53-73` `test_consent_flow_request_mode`) testent uniquement le passage nominal depuis `status="pending"`.
     - **Aucun test existant** ne teste l'appel de `give_consent` avec `consent=True` sur une réservation déjà `cancelled` ou `confirmed` pour un mode hors `manual_confirm`.

4. **Annulation par refus de consentement (tous statuts → `cancelled`) :**
   - **Fichier / Ligne :** `backend/app/api/v1/endpoints/bookings.py:271-273`.
   - **Acteur :** Voyageur authentifié (`current_user`).
   - **Endpoint :** `POST /api/v1/bookings/{booking_id}/consent` avec `data.consent = False`.
   - **Faiblesse critique et contournement du 409 :** Dans `backend/app/api/v1/endpoints/bookings.py:271-273` :
     ```python
     else:
         booking.status = "cancelled"
     ```
     Cette affectation est exécutée sans **aucun contrôle de statut ni de mode**.
   - **Statuts atteignables et alignement avec `/cancel` :**
     - L'endpoint officiel `POST /api/v1/bookings/{id}/cancel` refuse en HTTP 409 tout statut hors `("pending", "requested", "expired")` (`backend/app/api/v1/endpoints/bookings.py:309-313`), ce qui exclut `confirmed` et `cancelled`, mais aussi **`declined`**.
     - En revanche, `POST /api/v1/bookings/{booking_id}/consent` avec `consent=False` passe depuis **TOUS les statuts** (`confirmed`, `declined`, `expired`, `requested`, `cancelled`), tous modes confondus.
     - **Conséquence :** Un voyageur peut faire passer en `cancelled` une réservation déjà `confirmed` ou `declined`, contournant totalement le verrou HTTP 409 de `/cancel`.
   - **Couverture par les tests existants :**
     - Seul le cas nominal de refus depuis `pending` est testé indirectement ou documenté.
     - **Aucun test existant** dans `backend/tests/` ne vérifie le refus ou le comportement d'un `consent=False` sur une réservation au statut `confirmed`, `requested`, `declined` ou `expired`.

5. **Confirmation par le partenaire (`requested` → `confirmed`) :**
   - **Fichier / Ligne :** `backend/app/api/v1/endpoints/partner.py:305-323`.
   - **Acteur :** Partenaire gérant du POI ou administrateur du tenant (`_require_partner`, `backend/app/api/v1/endpoints/partner.py:266`).
   - **Endpoint :** `POST /api/v1/partner/bookings/{booking_id}/respond` avec `decision = "confirm"`.
   - **Verrouillage :** Requête protégée par `with_for_update()` (`backend/app/api/v1/endpoints/partner.py:287`).
   - **Effets :** `booking.status = "confirmed"`, `booking.external_id = f"EXT-{str(booking.id)[:8]}"`, `booking.responded_by = partner_id`, `booking.responded_at = utcnow()`, `booking.partner_note = data.note`. Émission d'une notification `booking_confirmed` au voyageur. Rejeu idempotent de la même décision pris en compte (`backend/app/api/v1/endpoints/partner.py:342-350`).

6. **Refus par le partenaire (`requested` → `declined`) :**
   - **Fichier / Ligne :** `backend/app/api/v1/endpoints/partner.py:324-341`.
   - **Acteur :** Partenaire gérant du POI ou administrateur du tenant (`_require_partner`).
   - **Endpoint :** `POST /api/v1/partner/bookings/{booking_id}/respond` avec `decision = "decline"`.
   - **Effets :** `booking.status = "declined"`, `booking.responded_by = partner_id`, `booking.responded_at = utcnow()`, `booking.partner_note = data.note`. Émission d'une notification `booking_declined` au voyageur.

7. **Expiration par dépassement de délai (`requested` → `expired`) :**
   - **Fichier / Ligne :** `backend/app/services/booking_lifecycle.py:30-100`.
   - **Acteur :** Système backend (mécanisme paresseux lors des lectures GET et balayage périodique par le worker de fond).
   - **Condition :** `Booking.status == "requested"`, `Booking.respond_by.is_not(None)`, `Booking.respond_by < utcnow()`.
   - **Effets :** `booking.status = "expired"`, `booking.updated_at = utcnow()`. Émission d'une notification `booking_expired` au voyageur (avec e-mail) et aux gestionnaires du POI (sans e-mail, `email=False`).

8. **Annulation explicite (`pending` | `requested` | `expired` → `cancelled`) :**
   - **Fichier / Ligne :** `backend/app/api/v1/endpoints/bookings.py:309-318`.
   - **Acteur :** Voyageur authentifié (`current_user`).
   - **Endpoint :** `POST /api/v1/bookings/{booking_id}/cancel`.
   - **Garde :** Le backend refuse en HTTP 409 toute annulation si le statut n'est pas parmi `("pending", "requested", "expired")` (`backend/app/api/v1/endpoints/bookings.py:309`). Tout statut hors de ce tuple — donc `confirmed`, `cancelled`, mais aussi **`declined`** — est refusé avec HTTP 409. Les réservations confirmées ne peuvent donc pas être annulées par cet endpoint.

### 1.3 Consommateurs des statuts

- **Application Mobile Flutter :**
  - Dans `mobile/lib/models/booking.dart:65-85`, les accesseurs booléens sont définis : `isPending` (`status == 'pending'`), `isAwaitingPartner` (`status == 'requested'`), `isConfirmed`, `isDeclined`, `isExpired`, `isCancelled`, `isTerminal`, `canCancel`, `canGiveConsent`.
  - Dans `mobile/lib/screens/bookings_screen.dart:149-179`, la fonction `styleFor(Booking booking, ColorScheme scheme, AppLocalizations loc)` attribue les libellés et couleurs. Les statuts inconnus ne font pas planter l'application : `return BookingStatusStyle(booking.status, scheme.secondaryContainer);` (`mobile/lib/screens/bookings_screen.dart:178`).
  - Dans `mobile/lib/screens/partner_bookings_screen.dart:25-45`, les demandes traitées affichent les pastilles selon `status == 'confirmed'` ou `status == 'declined'`.
- **Application Web Frontend :**
  - Dans `frontend/src/components/AppShell.tsx:647-757`, les réservations sont simulées par des données statiques de démonstration (`DEMO_BOOKINGS`, statuts textuels en dur comme `"Confirmée"`). L'intégration réelle avec `GET /api/v1/bookings/` n'est pas encore connectée côté web.
- **Notifications :**
  - Dans `backend/app/services/notification_templates.py:8-49`, les types de notifications branchés sur le cycle de vie sont : `booking_request_received`, `booking_confirmed`, `booking_declined`, `booking_expired`.

### 1.4 Écarts entre le code existant et les documents d'entrée

- Le document d'entrée V1 (`PAYMENT ARCHITECTURE V1.md`, section 5) mentionnait un tableau théorique de statuts comprenant `accepted`, `completed` et `rejected` :
  - **Correction de la correspondance `accepted` :** Dans le document de cadrage initial, `accepted` désignait l'état où le partenaire avait accepté la demande. Or, dans le code réel, **l'acceptation par le partenaire mène directement à `confirmed`** (`backend/app/api/v1/endpoints/partner.py:306`), tandis que `requested` désigne l'attente de réponse du partenaire (`backend/app/api/v1/endpoints/bookings.py:223`).
  - **Conséquence directe :** Dans l'état actuel de l'application, **`confirmed` n'implique absolument pas que la réservation a été payée**. Une réservation `confirmed` signifie uniquement que la disponibilité a été validée (automatiquement ou par le partenaire).
  - `completed` : **N'EXISTE PAS** dans `Booking.status`. Le backend n'a pas d'état matérialisant la fin de la prestation touristique (cela devra faire l'objet de la table `service_completions` en V1).
  - `rejected` : **N'EXISTE PAS** sous ce nom. Le statut réel en base est `declined` (`backend/app/api/v1/endpoints/partner.py:325`).
- **Conclusion d'architecture :** Conformément à la règle 2.1 de `PAYMENT_ARCHITECTURE_V3.md`, les statuts réels `("pending", "requested", "confirmed", "declined", "expired", "cancelled")` sont immuables. Le domaine Payment aura sa propre machine d'états sans modifier ces valeurs.

---

## 2. Délai de réponse (`respond_by`) et expiration

### 2.1 Calcul et initialisation

- **Calcul :** À la création de la réservation dans `backend/app/api/v1/endpoints/bookings.py:123` :
  ```python
  respond_by=(utcnow() + timedelta(hours=BOOKING_CONFIRM_SLA_HOURS)) if mode == "manual_confirm" else None
  ```
- **Durée du SLA :** `BOOKING_CONFIRM_SLA_HOURS = 24` (`backend/app/constants.py:88`).
- **Condition :** `respond_by` n'est renseigné que si `booking_mode == "manual_confirm"`. Pour les autres modes (`request`, `pay_on_site`, `info_only`), le champ reste `None`.

### 2.2 Expiration paresseuse dans `booking_lifecycle.py`

- La fonction `expire_overdue_requests(db: AsyncSession, tenant_id: UUID) -> int` (`backend/app/services/booking_lifecycle.py:23-100`) :
  - Recherche toutes les réservations avec `tenant_id == tenant_id`, `status == "requested"`, `respond_by < utcnow()`.
  - Verrouille les lignes avec `with_for_update()` (`backend/app/services/booking_lifecycle.py:43`).
  - Met à jour `status = "expired"` et `updated_at = utcnow()`.
  - Émet les notifications de type `booking_expired`.
  - Effectue un `await db.commit()` interne (`backend/app/services/booking_lifecycle.py:99`).
- **Points d'appel au fil de l'eau :**
  1. `list_bookings` : `backend/app/api/v1/endpoints/bookings.py:153`.
  2. `get_booking` : `backend/app/api/v1/endpoints/bookings.py:173`.
  3. `list_partner_bookings` : `backend/app/api/v1/endpoints/partner.py:214`.
  4. `get_partner_booking` : `backend/app/api/v1/endpoints/partner.py:246`.
  5. `respond_to_booking` : `backend/app/api/v1/endpoints/partner.py:276`.

### 2.3 Balayage d'expiration par le worker de fond

- **Fichier / Ligne :** `backend/app/services/notification_worker.py:441-458` (`sweep_overdue_bookings`) et `backend/app/services/notification_worker.py:481-489` dans `email_worker_loop`.
- **Fréquence :** Toutes les 60 secondes dans la boucle asynchrone du worker.
- **Fonctionnement :** Récupère tous les tenants actifs (`Tenant.is_active == True`), puis appelle `expire_overdue_requests(session, tid)` pour chacun dans une session dédiée.

### 2.4 Effets de bord sur le paiement

- Si une pré-autorisation bancaire (PSP V2) devait être posée à la création de la demande `requested`, la durée de validité de l'autorisation chez le PSP doit impérativement excéder `BOOKING_CONFIRM_SLA_HOURS` (24 heures) avec une marge de sécurité.
- Lors de l'expiration (`status -> "expired"`), le système financier devra impérativement déclencher la libération de l'autorisation (`void`), sans quoi les fonds du voyageur resteraient bloqués jusqu'à l'expiration bancaire naturelle.

---

## 3. Modes de réservation (`booking_mode`), références externes et idempotence

### 3.1 Valeurs de `booking_mode` et endpoints dépendants

- **Constantes :** Définies dans `backend/app/constants.py:79-87` :
  - `BOOKING_MODES = ("info_only", "request", "manual_confirm", "pay_on_site", "deposit", "online_payment")`.
  - `BOOKING_MODES_SUPPORTED = ("info_only", "request", "manual_confirm", "pay_on_site")`.
  - Les modes `deposit` et `online_payment` sont expressément bloqués avec HTTP 422 : `"Booking mode '...' is not supported yet"` (`backend/app/api/v1/endpoints/bookings.py:111`).
- **Origine du mode :** Le mode est configuré sur chaque POI (`POI.booking_mode`, `backend/app/models.py:247`). À la réservation, il est copié dans `Booking.booking_mode` (`backend/app/models.py:347`), ce qui fige le mode contractuel même si le POI est modifié ultérieurement.
- **Endpoints dépendants :**
  - `POST /api/v1/bookings/` : validation du mode (`backend/app/api/v1/endpoints/bookings.py:107-111`).
  - `POST /api/v1/bookings/{id}/consent` : bifurque entre passage à `requested` (si `manual_confirm`) et `confirmed` immédiat (autres modes) (`backend/app/api/v1/endpoints/bookings.py:217-255`).
  - `GET /api/v1/partner/bookings` : filtre uniquement les réservations des POI où le partenaire est assigné dans `poi_managers`.

### 3.2 Génération de la référence externe (`EXT-xxxx`)

- **Format et génération :**
  - Dans `backend/app/api/v1/endpoints/bookings.py:256` : `f"EXT-{booking_id[:8]}"` (mode immédiat).
  - Dans `backend/app/api/v1/endpoints/partner.py:308` : `f"EXT-{str(booking.id)[:8]}"` (confirmation manuelle partenaire).
- **Unicité :** Le préfixe reprend les 8 premiers caractères de l'UUID de la réservation. La colonne `Booking.external_id` (`backend/app/models.py:340`) est un `String(255)`, mais elle ne dispose pas de contrainte `UNIQUE` en base de données. L'unicité repose sur l'entropie de l'UUID v4.

### 3.3 En-tête `Idempotency-Key`

- **Stockage :** Colonnes `Booking.idempotency_key` (`String(80)`) et `Booking.request_hash` (`String(64)`) (`backend/app/models.py:349-350`).
- **Contrainte d'unicité :** `UniqueConstraint("tenant_id", "user_id", "idempotency_key", name="uq_bookings_idempotency")` (`backend/app/models.py:362`).
- **Fonctionnement :**
  - Si la même clé arrive avec le même hash de payload : rejeu de la réponse originale avec code HTTP 200 (`backend/app/api/v1/endpoints/bookings.py:64-74`).
  - Si la même clé arrive avec un payload différent : levée d'une HTTP 409 Conflict (`backend/app/api/v1/endpoints/bookings.py:61-63`).
  - En cas de collision concurrente (race condition), l'`IntegrityError` PostgreSQL est capturée pour relire la ligne gagnante (`backend/app/api/v1/endpoints/bookings.py:130-139`).
- **Durée de rétention :** Aucune purge ni expiration temporelle n'existe actuellement sur les clés d'idempotence des réservations ; elles sont conservées indéfiniment en base.

---

## 4. Prix, montants et devises actuels (Point bloquant)

### 4.1 Une réservation stocke-t-elle aujourd'hui un montant et une devise ?

- **Constat dans le modèle :**
  - `Booking.price` existe dans `backend/app/models.py:344` sous le type `Column(Float, nullable=True)`.
  - `Booking.currency` existe dans `backend/app/models.py:345` sous le type `Column(String(10))`.
  - **Inadéquation du type Float :** La présence de `Column(Float)` contredit frontalement la règle 2.4 de `PAYMENT_ARCHITECTURE_V3.md` (« All monetary amounts must be stored as integers in the currency's minor units. Never use floating-point values »). **`Booking.price` ne doit en aucun cas être réutilisé pour les calculs financiers, commissions ou transactions**. Tout montant financier devra être stocké en centimes/unités mineures entières dans les tables financières dédiées.
- **Réalité de l'alimentation au runtime :**
  - `Booking.currency` est systématiquement alimenté depuis `tenant.default_currency` à la création (`backend/app/api/v1/endpoints/bookings.py:120`).
  - **`Booking.price` N'EST JAMAIS ALIMENTÉ.** Lors de la création (`POST /api/v1/bookings/`), le champ `price` n'est pas passé au constructeur `Booking(...)` (`backend/app/api/v1/endpoints/bookings.py:113-126`). Il reste donc toujours `NULL` en base de données.
  - Dans `mobile/lib/models/booking.dart:41-42`, le code mobile documente explicitement : `/// Never populated by the current backend — rendered only when present. final double? price;`.

### 4.2 Champs de prix sur les POI

- Dans `POI` (`backend/app/models.py:232`), il n'existe qu'une fourchette qualitative : `price_range = Column(String(20), default="free")` (valeurs autorisées : `free`, `low`, `medium`, `high`).
- Il n'existe aucun champ de prix numérique ou tarifaire sur les POI dans le schéma backend.

### 4.3 Devise du tenant

- Dans `Tenant` (`backend/app/models.py:47`), la colonne `default_currency = Column(String(10))` stocke la devise du tenant (ex. `"DZD"`, `"EUR"`).

### 4.4 Deux options pour la source du montant (avec leurs compromis)

Puisqu'aucun montant fiable n'est stocké à ce jour, aucune commission ni transaction financière ne peut être calculée sans choisir une source de vérité :

- **Option A : Montant déclaré par le partenaire à la confirmation ou fin de prestation**
  - _Mécanisme :_ Le partenaire saisit le montant réel de la prestation lors de la confirmation (`POST /api/v1/partner/bookings/{id}/respond`) ou via un endpoint dédié de complétion de service.
  - _Avantages :_ Ne nécessite pas de grille tarifaire préalable complexe ; gère nativement les variations de prestations sur place (extras, suppléments, consommation réelle). Idéal pour le modèle d'intermédiation initial V1.
  - _Inconvénients :_ Le voyageur ne connaît pas le montant exact garanti en amont dans l'application ; risque de sous-déclaration ou d'oubli par le partenaire pour minimiser la commission Discover AI.
- **Option B : Montant fixé et scellé à la création de la réservation**
  - _Mécanisme :_ Le voyageur ou l'adaptateur sélectionne une offre tarifée (ex. chambre, menu, visite guidée) dont le prix en unités mineures entières est transmis et scellé dans la réservation lors du `POST /bookings/`.
  - _Avantages :_ Transparence contractuelle totale pour le voyageur avant réservation ; calcul immédiat et prévisible de la commission et de l'acompte/paiement en ligne (indispensable pour V2 PSP).
  - _Inconvénients :_ Exige l'introduction d'un modèle d'offres/tarifs sur les POI (catalogue tarifaire) qui n'existe pas dans le backend actuel ; complexité d'implémentation plus élevée.

---

## 5. Modèle partenaire, tenant et entité légale

### 5.1 Représentation d'un partenaire

- **Absence de table `partners` dédiée :** Il n'existe pas de table `partners`.
- **Rôle partenaire :** Un partenaire est un utilisateur standard (`User`, `backend/app/models.py:107`) rattaché à au moins un POI de son tenant via la table d'association `POIManager` (`backend/app/models.py:366-389`).
- **Attribut `is_partner` :** Ce n'est pas une colonne de la table `users`, mais une propriété calculée dynamiquement lors de `GET /auth/me` (`backend/app/api/v1/endpoints/auth.py:124-130`) grâce à la dépendance `get_partner_poi_ids` (`backend/app/api/v1/endpoints/partner.py:34-43`).
- **Vérification d'accès :** La fonction `_require_partner(user, poi_ids)` (`backend/app/api/v1/endpoints/partner.py:46-51`) exige que l'utilisateur soit administrateur (`user.is_admin == True`) ou qu'il possède au moins un POI dans son périmètre (`len(poi_ids) > 0`).

### 5.2 Informations légales, fiscales et pays

- **Table `users` :** Ne contient que `id`, `tenant_id`, `email`, `hashed_password`, `full_name`, `is_active`, `is_admin`, `preferences`, `created_at`, `locale` (`backend/app/models.py:107-124`). Aucun numéro de registre de commerce, identifiant fiscal, adresse ou raison sociale n'est stocké.
- **Table `POIManager` :** Ne contient que `id`, `tenant_id`, `poi_id`, `user_id`, `created_at`.
- **Table `Tenant` :** Contient `country_code` (ISO 3166-1 alpha-2, validé par `backend/app/models.py:68-77`), mais **aucune notion d'entité légale Discover AI** (société exploitante, Siren/Siret, NIF, compte bancaire).
- **`Tenant.config` :** Champ `JSON` libre (`backend/app/models.py:52`). Il est aujourd'hui utilisé pour la configuration de la recherche IA et pour les e-mails (`Tenant.config['notifications']['email']`, `backend/app/services/notification_worker.py:37-48`). Aucune clé financière n'y réside pour l'instant.

---

## 6. Fonctions financières et comptables existantes

- **Recherche globale dans le code :** Une recherche exhaustive sur `invoice`, `facture`, `payment`, `commission`, `ledger`, `tax`, `payout` révèle :
  - **AUCUNE table financière :** Pas de table de facturation, pas de grand livre (`ledger`), pas de table de transactions ou de commissions.
  - **AUCUN endpoint financier :** Aucun endpoint de paiement n'est implémenté.
  - **Seules mentions :**
    - Des mentions préliminaires de `payment providers` dans la documentation architecturale (`docs/architektur.md:186`, `README.md:280`).
    - Les colonnes dormantes `Booking.price` (float) et `Booking.currency` (string) constatées à la section 4.
    - La table `TenantAIQuotaConfig` (`backend/app/models.py:554-573`) qui gère un quota de consommation d'API IA interne en dollars (`monthly_limit`, `current_period_usage` en `Numeric(12, 4)`), mais qui concerne les coûts d'infrastructure LLM et non les transactions commerciales des utilisateurs.

---

## 7. Gestion des secrets et chiffrement réutilisable

### 7.1 Mécanisme `CredentialCrypto`

- **Fichier / Ligne :** `backend/app/services/credential_crypto.py:1-100`.
- **Algorithme :** Chiffrement authentifié **AES-256-GCM** avec nonce aléatoire de 12 octets et tag d'authentification de 16 octets.
- **Gestion des clés :** Clés maîtres versionnées configurées via la variable d'environnement `AI_MASTER_KEYS="1:<64 hex>,2:<64 hex>"` (`backend/app/services/credential_crypto.py:8-10, 53-72`).
- **Données associées authentifiées (AAD) :** Construit par `_aad(tenant_id, provider)` -> `f"{tenant_id}:{provider}".encode("utf-8")` (`backend/app/services/credential_crypto.py:79-81`). Cela garantit l'impossibilité cryptographique de transférer un secret chiffré vers un autre tenant ou un autre provider.

### 7.2 Réutilisabilité pour le domaine Payment

- Le service `CredentialCrypto` est directement réutilisable pour chiffrer les secrets marchands des prestataires de paiement (clés API Stripe, jetons Chargily, clés SATIM) ainsi que les coordonnées bancaires sensibles (RIB/IBAN) des partenaires.
- **Recommandation d'évolution :** Définir une variable d'environnement distincte (ex. `PAYMENT_MASTER_KEYS`) ou étendre le format d'AAD pour le domaine financier (ex. `f"{tenant_id}:payment:{provider_or_partner_id}"`) afin de maintenir un cloisonnement cryptographique strict avec les clés IA.

---

## 8. Tâches de fond et infrastructure asynchrone

### 8.1 Architecture du worker d'e-mails existant

- **Fichier / Ligne :** `backend/app/services/notification_worker.py:91-150` (`claim_batch`), lines `152-398` (`process_one`), lines `461-494` (`email_worker_loop`).
- **Mécanisme de verrouillage de lot :**
  - Utilise `SELECT ... FOR UPDATE SKIP LOCKED` (`backend/app/services/notification_worker.py:123`) sur SQLAlchemy asynchrone.
  - Résout élégamment la concurrence multi-instances sans blocage de verrous.
  - Verrouille un lot pendant un bail configurable (`locked_until = now + lock_seconds`, par défaut 600 secondes).
  - Reprend automatiquement les baux expirés dont le statut est resté `sending`.
  - Intègre une politique d'abandon après 5 tentatives et une fenêtre temporelle maximale de 24 heures.
- **Intégration au cycle de vie :** Démarré sous forme de `asyncio.create_task` dans le `lifespan` FastAPI (`backend/app/main.py:90-96`) et interrompu proprement lors du shutdown (`worker_task.cancel()`).

### 8.2 Réutilisabilité pour le domaine Payment

- Ce mécanisme est **parfaitement adapté et directement réutilisable** pour :
  - Le traitement asynchrone des webhooks financiers différés.
  - L'expiration automatique des autorisations PSP en attente.
  - Le calcul et l'émission périodique des créances de commission partenaires.
  - Les tâches de rapprochement financier (reconciliation batch).

---

## 9. Points d'entrée publics, sécurité et intermédiation

### 9.1 Application de `X-Tenant-Slug` et authentification

- **Résolution du Tenant :** Dans `backend/app/core/tenant.py:9-17`, `get_tenant_from_header` exige l'en-tête HTTP `X-Tenant-Slug`. Si l'en-tête est manquant, FastAPI renvoie une erreur HTTP 422 (validation header). Si le slug ne correspond à aucun tenant actif en base, une HTTP 404 est levée.
- **Authentification utilisateur :** Dans `backend/app/dependencies.py:70-126` (`get_current_user`) :
  - Vérifie le jeton Bearer (flux mobile) ou le cookie `access_token` (flux web).
  - Vérifie la signature JWT et l'appartenance `token_tenant == x_tenant_slug`.
  - Vérifie en base que `user.tenant_id == request_tenant.id` (`backend/app/dependencies.py:122`).
- **Conséquence pour les futurs webhooks PSP (V2) :**
  - Un webhook émis par Stripe ou Chargily **ne possédera ni jeton JWT, ni cookie de session, ni en-tête `X-Tenant-Slug`**.
  - Tout endpoint de webhook placé sous les routeurs actuels protégés par ces dépendances échouerait systématiquement.
  - Un routeur public dédié (`/api/v1/payments/webhooks/{endpoint_id}`), totalement exempt de ces dépendances, est indispensable.

### 9.2 Interaction avec les cookies HttpOnly et la protection CSRF

- **Fonctionnement CSRF :** Défini dans `backend/app/dependencies.py:35-67` (`require_csrf`).
  - La protection utilise le mécanisme du _double-submit cookie_ : compare le cookie `csrf_token` et l'en-tête `X-CSRF-Token`.
  - Elle s'exécute uniquement si aucun en-tête `Authorization: Bearer` n'est présent (`backend/app/dependencies.py:54`).
  - Un appel webhook externe n'aura pas de cookie `csrf_token`. Comme spécifié dans `backend/app/dependencies.py:58-59` : `if cookie_token is None: return`, la garde CSRF ne bloquera pas un appel sans cookie, à condition que le endpoint soit conçu en dehors des dépendances d'authentification utilisateur.

### 9.3 Limitation de débit (Rate Limiting)

- Actuellement, le backend n'intègre pas de middleware de rate limiting global actif (SlowAPI ou Redis Limiter) dans `app/main.py`. Seul un statut d'erreur rate-limit existe dans les constantes et les quotas IA.
- Pour la V2 (webhooks publics), une limitation de débit stricte par IP et endpoint devra être prévue pour éviter les attaques par déni de service.

---

## 10. Système de notifications et événements financiers

### 10.1 Points d'extension existants

- **Modèle :** `Notification` dans `backend/app/models.py:432-469`.
  - Colonnes : `id`, `tenant_id`, `user_id`, `type`, `booking_id`, `payload` (JSON), `locale`, `email_status`, `read_at`, `created_at`.
- **Gabarits de notifications :** `backend/app/services/notification_templates.py:8-49` (`NOTIFICATION_TEMPLATES`).
  - Dictionnaire bilingue FR/EN structuré par type.
- **Service d'émission :** `create_notification` dans `backend/app/services/notification_service.py:35-82`.
  - Prend en charge la résolution de langue (`resolve_locale`), la déduplication par savepoint SQL (`begin_nested()`), et le statut e-mail.

### 10.2 Où et comment ajouter les événements financiers

- Pour notifier les événements financiers (ex. paiement reçu, demande de paiement sur place, avis de commission émis), il suffira d'ajouter de manière additive dans `NOTIFICATION_TEMPLATES` :
  - `payment_succeeded` (titre et message en FR et EN).
  - `payment_failed` (titre et message en FR et EN).
  - `commission_invoice_available` (notification à destination du partenaire).
- Aucun changement structurel de la table `notifications` n'est requis ; le champ `payload` peut contenir les métadonnées de montant formaté et devise.

---

## 11. Couverture des tests existants et infrastructure de CI

### 11.1 Fichiers et volumétrie des tests liés à la réservation et aux partenaires
*(Note méthodologique : Les décomptes ci-dessous sont issus d'un recensement par expression régulière dans le code source ; seule une collecte d'arborescence pytest fait foi au moment de l'exécution).*

- **Réservation et consentement :**
  - `backend/tests/test_bookings.py` : ~14 fonctions de test (création, flux de consentement, annulation, idempotence des requêtes, gestion des conflits).
  - `backend/tests/test_booking_modes.py` : ~11 fonctions de test (modes `info_only`, `request`, `manual_confirm`, `pay_on_site`, rejet des modes non supportés `deposit` et `online_payment`).
- **Gestion partenaire et autorisations :**
  - `backend/tests/test_partner_manual_confirm.py` : ~24 fonctions de test (décision confirm/decline, notes partenaires, contrôle d'accès, SLA de réponse, expiration, concurrence de ligne).
  - `backend/tests/test_partner_bookings_n_plus_1.py` : ~2 fonctions de test (optimisation des requêtes partenaires).
  - `backend/tests/test_auth_is_partner.py` : ~5 fonctions de test (calcul du statut `is_partner` via `poi_managers`).
- **Expiration et cycle de vie :**
  - `backend/tests/test_notifications_emission.py` : ~5 fonctions de test (dont test unitaire complet de `expire_overdue_requests`).
  - `backend/tests/test_notification_worker.py` : ~16 fonctions de test (dont balayage `sweep_overdue_bookings`).
- **Périmètre Réservation / Partenaire / Notifications :** ~77 tests ciblés (approximatif, grep).
- **Total global du backend :** ~472 fonctions `test_` recensées dans `backend/tests/` (approximatif, grep).
- **Total global mobile :** 155 tests unitaires et widget collectés dans `mobile/test/`.

### 11.2 Fixtures partagées

- Définies dans `backend/tests/conftest.py:1-120` :
  - `TestSessionLocal` sur NullPool relié à PostgreSQL test (`backend/tests/conftest.py:22-24`).
  - `override_get_db` injectant la session de test dans FastAPI (`backend/tests/conftest.py:42`).
  - Fixtures `test_tenant`, `test_user`, `test_admin`, `test_poi`, `auth_headers`, `admin_headers`.

### 11.3 Durée d'exécution de la CI

- D'après l'historique récent des runs GitHub Actions (`gh run list -L 5`) :
  - Run PR mobile : ~5 min 57s à 8 min 41s.
  - Run complet push sur `main` (backend + frontend Playwright + flutter + docker build) : **~9 min 58s à 10 min 07s**.

---

## 12. Analyse des clients (Mobile Flutter et Web Frontend)

### 12.1 Parcours Mobile (Flutter)

- **Écran de réservation :** `_BookingSheet` dans `mobile/lib/screens/poi_detail_screen.dart:45-310`.
  - Déclenché depuis la fiche POI par le bouton « Réserver ».
  - Permet le choix de l'adaptateur (`hotel`, `restaurant`, etc.), de la date, du nombre de convives et de notes.
  - Appelle `BookingProvider.createBooking()`.
- **Écran de suivi et consentement :** `mobile/lib/screens/bookings_screen.dart:194-325` (`_BookingCard`).
  - Présente le bouton `booking_consent` (Confirmer) lorsque `booking.canGiveConsent` est vrai.
  - Ouvre une boîte de dialogue de confirmation explicite (`showConsentDialog`).
  - Présente le bouton `booking_cancel` (Annuler) lorsque `booking.canCancel` est vrai.
- **Insertion du paiement :**
  - Pour le parcours B (Marketplace / PSP en ligne) : l'étape de paiement s'insérerait soit directement après l'action de consentement du voyageur (si paiement immédiat), soit après la confirmation du partenaire (si le partenaire doit d'abord accepter).
  - Pour le parcours A / C (Intermédiation / Sur place) : l'interface actuelle affiche déjà un statut clair sans bloquer l'utilisateur.
- **Réaction à un statut inconnu :**
  - Dans `mobile/lib/screens/bookings_screen.dart:178`, le code gère explicitement l'évolutivité :
    ```dart
    // Unknown status: render the raw text, never crash.
    return BookingStatusStyle(booking.status, scheme.secondaryContainer);
    ```
  - Un nouvel état ou un statut financier imprévu ne provoquera aucun crash de l'interface mobile.

### 12.2 Parcours Web (Frontend Next.js)

- **État actuel :** Dans `frontend/src/components/AppShell.tsx:647-759` (`BookingsTab`), l'onglet des réservations affiche des données factices statiques (`DEMO_BOOKINGS`).
- **Insertion du paiement :** Le frontend web nécessitera une implémentation complète de l'API de réservation avant de pouvoir accueillir un composant de paiement interactif.

---

## 13. Migrations Alembic et conventions de base de données

### 13.1 Tête Alembic actuelle

- La tête de migration actuelle est **`0016_backfill_skipped_notifs`** (`backend/alembic/versions/0016_backfill_skipped_notifs.py:13`), révisant `0015_notifications_worker_cols`.

### 13.2 Conventions observées dans le schéma

- **Identifiants primaires :** Systématiquement `UUID(as_uuid=True)` avec valeur par défaut `uuid.uuid4` côté Python et extension `pgvector` activée.
- **Dates et horodatages :** `DateTime` sans fuseau horaire (`nullable=False` ou `nullable=True`), alimenté par l'utilitaire applicatif `utcnow()` qui produit un `datetime.now(timezone.utc).replace(tzinfo=None)`. La convention du projet est de stocker l'UTC « naïve » dans la base de données.
- **Données semi-structurées :** Type `JSON` standard de SQLAlchemy (utilisant le type PostgreSQL `json` ou `jsonb`).
- **Suppression en cascade :** Clés étrangères protégées par `ondelete="CASCADE"` vers les tenants (`ForeignKey("tenants.id", ondelete="CASCADE")`) et `ondelete="SET NULL"` pour les liaisons vers les réservations dans les notifications.

### 13.3 Politique de downgrade

- Dans les migrations de structure (ex. `0014_notifications.py`), `downgrade()` effectue un `op.drop_table(...)`.
- Dans les migrations de reprise de données (ex. `0016_backfill_skipped_notifs.py:27-29`), `downgrade()` contient un `pass` documenté lorsqu'une restauration exacte de l'état antérieur n'est pas réversible.

### 13.4 Piège de la base de test et amorçage

- **Constat dans `backend/app/main.py:36-40` :** La fonction `_run_migrations` gère les bases historiques ayant été initialisées par `Base.metadata.create_all` :
  ```python
  if asyncio.run(_has_unversioned_schema()):
      command.stamp(alembic_cfg, "0001_initial")
  command.upgrade(alembic_cfg, "head")
  ```
- **Règle absolue pour le chantier Payment :** Toute nouvelle table ou colonne doit faire l'objet d'une migration Alembic scriptée et réversible numérotée `0017_...`, sans jamais s'en remettre à `create_all`.

---

## 14. Risques de compatibilité et options d'approche additive

Afin de respecter le principe de non-régression et de préserver le fonctionnement des applications clientes en production, aucune table existante ne doit être détruite et aucune colonne existante de `bookings` ne doit être renommée.

### 14.1 Option 1 : Séparation stricte du domaine financier (Recommandée)

- **Description :**
  - La table `bookings` reste structurellement inchangée (seule une colonne facultative `cancellation_policy_version` peut y être ajoutée de manière nullable).
  - L'intégralité du domaine financier est portée par de nouvelles tables dédiées :
    - `legal_entities` (identification de la société Discover AI opérante).
    - `partner_payment_profiles` (informations de facturation et coordonnées de paiement du partenaire).
    - `commission_rules` (pourcentages ou règles de commission versionnées).
    - `service_completions` (confirmation d'exécution du service et montant déclaré).
    - `commission_receivables` (créances de commission dues par le partenaire).
    - `partner_ledger_entries` (registre financier en partie double, immuable).
  - Le cycle de vie financier dispose de sa propre machine d'états (`PaymentStateMachine`), totalement disjointe de `Booking.status`.
- **Compromis :**
  - _Avantages :_ Risque de régression nul sur l'existant ; les tests actuels de réservation et de notifications continuent de fonctionner sans modification ; conforme aux principes DDD (séparation des contextes délimités Booking et Payment).
  - _Inconvénients :_ Nécessite des jointures lors des requêtes de reporting consolidé.

### 14.2 Option 2 : Enrichissement de la table `bookings` avec colonnes financières

- **Description :**
  - Ajout direct sur `bookings` de colonnes financières : `legal_entity_id`, `actual_gross_amount`, `commission_amount`, `financial_status`, `invoiced_at`, `paid_at`.
- **Compromis :**
  - _Avantages :_ Accès immédiat aux montants depuis l'objet `Booking` sans jointure supplémentaire.
  - _Inconvénients :_ Alourdit la table `bookings` ; risque d'interférences avec les schémas Pydantic existants (`BookingResponse`, `PartnerBookingResponse`) ; viole le principe de séparation des responsabilités.

### 14.3 Option 3 : Gestion financière externalisée par métadonnées JSON

- **Description :**
  - Stocker les données financières (montant déclaré, commission, facture) dans le champ existant `Booking.booking_data` ou `Tenant.config`.
- **Compromis :**
  - _Avantages :_ Aucune migration de schéma relationnel requise.
  - _Inconvénients :_ Inacceptable pour un système financier : absence d'intégrité référentielle, impossibilité d'assurer l'immuabilité comptable, calculs complexes et lents, aucun contrôle d'unicité SQL.

---

## 15. Décisions à trancher par le propriétaire (classées par urgence)

### 🔴 Urgence 1 (Bloquant pour la conception V1) : Source de vérité du montant

- **Arbitrage requis :** Pour le parcours A (Intermédiation) en V1, Discover AI doit-il s'appuyer sur le **montant déclaré par le partenaire à la confirmation / fin de prestation** (Option A), ou imposer la création préalable d'un **catalogue tarifé fixe à la réservation** (Option B) ?
- _Impact :_ Sans cette décision, la formule de calcul de la créance de commission ne peut être figée.

### 🔴 Urgence 2 (Structurant pour la modélisation V1) : Partie contractante du partenaire

- **Arbitrage requis :** Quelle est l'entité juridique exacte qui contracte avec Discover AI et à qui est imputée la créance de commission ?
  - Un utilisateur individuel (`user_id`) ?
  - Un établissement / point d'intérêt (`poi_id`) ?
  - Une nouvelle entité « Organisation / Entreprise partenaire » (`partner_legal_entity_id`) regroupant plusieurs POI et plusieurs gestionnaires ?
- _Justification / Impact :_ Comme constaté au point 5.1, la table `POIManager` (`backend/app/models.py:366-389`) permet à un POI d'avoir **plusieurs gestionnaires** (`UniqueConstraint("tenant_id", "poi_id", "user_id")`) et à un utilisateur de gérer plusieurs POI. Si la commission est rattachée au seul `user_id`, quel partenaire reçoit la facture quand ils sont trois ? Si elle est rattachée au `poi_id`, comment facturer globalement un partenaire hôtelier multi-établissements ?

### 🔴 Urgence 3 (Structurant pour la modélisation V1) : Forme de la confirmation de prestation

- **Arbitrage requis :** La confirmation d'exécution du service (déclenchant la commission) est-elle générée automatiquement à la date de réservation, ou nécessite-t-elle une validation manuelle explicite du partenaire dans son espace ?

### 🔴 Urgence 4 (Structurant V1 / Politiques d'annulation) : Annulation d'une réservation confirmée

- **Arbitrage requis :** Dans le code actuel, l'endpoint officiel `/cancel` interdit avec HTTP 409 toute annulation d'une réservation `confirmed` (constats §1.2 et §17.2). Faut-il ouvrir un flux explicite d'annulation d'une réservation confirmée (côté voyageur, partenaire ou administrateur), et selon quelles règles (délai de prévenance, motif, pénalités) ?
- _Impact :_ Indispensable pour implémenter les politiques d'annulation versionnées (section 2.6 de `PAYMENT_ARCHITECTURE_V3.md`), déterminer si la commission Discover AI reste due en cas de désistement ou de no-show en V1, et piloter les remboursements en V2.

### 🟡 Urgence 5 (Moyen terme - Préparation V2) : Choix du pays de l'entité européenne et premier PSP

- **Arbitrage requis :** Quel est le pays d'immatriculation cible pour Discover AI Europe et quel PSP sera retenu en premier (Stripe en Europe ou Chargily Pay en Algérie) ?
- _Impact :_ Détermine les capacités à modéliser dans la matrice des adaptateurs (autorisation/capture vs encaissement direct).

### 🟢 Urgence 6 (Politique commerciale V1) : Grille et taux de commission par défaut

- **Arbitrage requis :** Quel modèle de commission appliquer par défaut (pourcentage fixe, palier, montant fixe par réservation) ?

---

## 16. Points restés « NON VÉRIFIÉ »

Aucun point critique n'est resté non vérifié. L'ensemble des 14 questions de la section 5 a été confronté directement au code source du dépôt.  
Les deux éléments factuels suivants sont explicitement consignés comme absents du code :

- **NON VÉRIFIÉ (Car inexistant dans le code) :** L'existence de tarifs numériques pour les POI. Le champ n'existe pas dans le code backend.
- **NON VÉRIFIÉ (Car inexistant dans le code) :** L'intégration réelle des réservations dans le frontend Web. Le composant `AppShell.tsx` n'utilise actuellement que des données de démonstration statiques.

---

## Annexe : Commandes de recherche principales utilisées lors de l'audit

```bash
# Vérification du modèle Booking et des colonnes financières
grep -rn "class Booking" backend/app/
sed -n '332,365p' backend/app/models.py

# Constantes de statut et modes de réservation
grep -rn "BOOKING_STATUS" backend/app/
sed -n '75,102p' backend/app/constants.py

# Transitions d'états dans les endpoints
grep -rn "Booking.status" backend/app/
sed -n '110,145p' backend/app/api/v1/endpoints/bookings.py
sed -n '210,277p' backend/app/api/v1/endpoints/bookings.py
sed -n '305,358p' backend/app/api/v1/endpoints/partner.py

# Mécanisme d'expiration des réservations
cat backend/app/services/booking_lifecycle.py
sed -n '441,490p' backend/app/services/notification_worker.py

# Modèle partenaire et POIManager
sed -n '366,395p' backend/app/models.py
grep -rn "is_partner" backend/app/

# Recherche de fonctions financières existantes
grep -rnE "commission|invoice|facture|payment|ledger" backend/app/

# Mécanisme de chiffrement des secrets
sed -n '1,100p' backend/app/services/credential_crypto.py

# Sécurité des requêtes, headers et CSRF
sed -n '1,68p' backend/app/dependencies.py
sed -n '70,126p' backend/app/dependencies.py
sed -n '1,25p' backend/app/core/tenant.py

# Schémas de notifications existants
sed -n '1,50p' backend/app/services/notification_templates.py

# Migrations Alembic
ls -la backend/alembic/versions/
sed -n '1,30p' backend/alembic/versions/0016_backfill_skipped_notifs.py

# Consommation côté mobile et web
grep -rn "styleFor" mobile/lib/
sed -n '148,180p' mobile/lib/screens/bookings_screen.dart
grep -rn "DEMO_BOOKINGS" frontend/src/
```


---

## 17. Addendum de relecture

Cet addendum consigne les conclusions critiques issues de la relecture approfondie du code source et de l'analyse des interactions croisées entre réservation, consentement, annulation et paiement.

### 17.1 Absence de contrôle d'état dans `give_consent` hors `manual_confirm` et contournement du endpoint `/cancel`
- **Faiblesse constatée :** Dans `backend/app/api/v1/endpoints/bookings.py:251-276` :
  - La branche `manual_confirm` vérifie formellement `if booking.status != "pending": raise HTTPException(status_code=409)`.
  - En revanche, la branche `else` (modes `request`, `pay_on_site`, etc.) ne comporte **aucun contrôle sur `booking.status`**.
  - Si `data.consent == True` : la réservation passe à `"confirmed"`, `consent_given` passe à `True`. La valeur de `booking.external_id = f"EXT-{booking_id[:8]}"` étant déterministe (dérivée des 8 premiers caractères de l'UUID), elle reste identique et n'est pas écrasée par une nouvelle valeur.
  - **Précision sur les statuts atteignables :** Hors `manual_confirm`, les seuls statuts possibles dans le cycle de vie sont `pending`, `confirmed` et `cancelled` (`declined` et `expired` n'existent qu'en `manual_confirm`, où `consent=True` renvoie déjà 409 si `status != "pending"`). Les effets anormaux réels de `consent=True` ne se produisent donc que depuis deux statuts :
    - La **résurrection** d'une réservation `cancelled` en `confirmed` ;
    - L'émission d'une notification `booking_confirmed` en double sur une réservation déjà `confirmed`.
  - Si `data.consent == False` (`backend/app/api/v1/endpoints/bookings.py:271-273`) : la réservation est basculée directement à `status = "cancelled"`, sans aucun contrôle de statut ni de mode. `consent=False` passe ainsi depuis **TOUS les statuts** (`confirmed`, `declined`, `expired`, `requested`, `cancelled`), tous modes confondus.
- **Contournement de la sécurité de `/cancel` :**
  - L'endpoint dédié `POST /api/v1/bookings/{booking_id}/cancel` protège les réservations en renvoyant une HTTP 409 pour tout statut hors `("pending", "requested", "expired")` (`backend/app/api/v1/endpoints/bookings.py:309-313`), refusant donc `confirmed` et `cancelled`, mais aussi **`declined`**.
  - Cependant, un voyageur peut appeler `POST /api/v1/bookings/{booking_id}/consent` avec `{"consent": false}` sur une réservation déjà `confirmed` ou `declined` : le backend exécute `booking.status = "cancelled"` sans restriction, **contournant totalement le verrou 409 de `/cancel`**.
- **Couverture de tests existante :**
  - Les tests actuels (`backend/tests/test_bookings.py` et `backend/tests/test_booking_modes.py`) vérifient uniquement le cas nominal où `give_consent` est appelé sur une réservation au statut initial `pending`.
  - Aucun test existant ne teste `give_consent` sur une réservation déjà `confirmed`, `cancelled`, `expired` ou `declined`.
- **Impact sur le système de paiement :**
  - Il est impératif que le domaine Payment ne se fie pas uniquement à `Booking.status` pour déclencher ou annuler un flux financier. Si un voyageur peut annuler une réservation confirmée via `give_consent(consent=False)` en contournant `/cancel`, le système de paiement risquerait de déclencher des remboursements indus ou de corrompre l'état des autorisations bancaires.

### 17.2 Impossibilité d'annuler une réservation confirmée via `/cancel` : impact sur la politique d'annulation et les remboursements
- **Constat dans le code :**
  - Dans `backend/app/api/v1/endpoints/bookings.py:309-313` :
    ```python
    if booking.status not in ("pending", "requested", "expired"):
        raise HTTPException(
            status_code=409,
            detail=f"Cannot cancel a booking in status '{booking.status}'",
        )
    ```
  - Une réservation `confirmed` **ne peut pas être annulée par le voyageur via le endpoint normal `/cancel`**.
- **Conséquences majeures pour le projet Paiement :**
  - Les politiques d'annulation (section 2.6 de `PAYMENT_ARCHITECTURE_V3.md` : délai d'annulation gratuite, heure limite, remboursement partiel/total) s'appliquent typiquement à des réservations qui ont été **confirmées**.
  - Or, dans l'architecture actuelle, une fois qu'une réservation est `confirmed`, le voyageur est totalement bloqué pour annuler via l'API officielle.
  - Pour supporter des politiques d'annulation et d'éventuels remboursements (V2/V3), le domaine Payment et les endpoints de réservation devront définir un nouveau flux d'annulation post-confirmation contrôlé par les règles financières de la politique d'annulation associée, sans rupture du contrat existant.

### 17.3 Inadéquation absolue de `Booking.price` (Float) pour la finance
- Dans `backend/app/models.py:344`, `price = Column(Float, nullable=True)` utilise le type virgule flottante (`FLOAT`/`REAL` SQL).
- Outre le fait qu'il n'est jamais alimenté par l'API actuelle (section 4), l'usage de nombres à virgule flottante présente des risques d'imprécision binaire inacceptables pour un grand livre financier (ex. `0.1 + 0.2 != 0.3`).
- **Recommandation (à valider) :** `Booking.price` reste un champ dormant non exploité. Toutes les futures tables financières (`service_completions`, `commission_receivables`, `partner_ledger_entries`, `payment_transactions`) utiliseront exclusivement des entiers en unités mineures (centimes) avec métadonnées d'exposant de devise, conformément à la règle 2.4.

### 17.4 Définition de la partie contractante partenaire : ambiguïté `User` vs `POI` vs `Organisation`
- Dans la structure actuelle (`backend/app/models.py:366-389`), la relation partenaire est modélisée par `POIManager` liant un `user_id` à un `poi_id`.
- **Problème d'imputation financière :**
  - Un POI peut avoir 3 gérants distincts dans `POIManager`. Si une commission est due pour une prestation réalisée dans ce POI, à quel `user_id` la facture de commission doit-elle être adressée ?
  - Inversement, un partenaire professionnel exploitant une chaîne de 5 hôtels ou plusieurs activités touristiques aura plusieurs POI.
  - La V1 du domaine Payment doit donc définir sans ambiguïté si le débiteur contractuel de Discover AI est :
    1. L'utilisateur qui confirme la prestation (`responded_by`),
    2. L'établissement (`poi_id`),
    3. Ou une entité légale partenaire dédiée (`partner_legal_entities`), regroupant les POIs sous une même raison sociale et un même compte de facturation.
