# Plan d'Implémentation Technique — Domaine Paiement (V1a / V1b / V1c)

> **Document de référence :** Point de contrôle 2 du chantier paiement (s'appuie sur `docs/payment/PAYMENT_DECISIONS_V1.md`, `docs/payment/PAYMENT_DESIGN.md` et `docs/payment/PAYMENT_COMPLIANCE.md`).  
> **Date de rédaction :** 2 novembre 2026.  
> **Branche de travail :** `docs/payment-decisions-v1`.  
> **Statut :** PLAN DE DÉPLOIEMENT SANS CODE (DESIGN ONLY). Ce document ne constitue pas une autorisation de coder. Aucune migration, aucun test, aucun modèle et aucun endpoint applicatif ne sont modifiés par ce document. Il structure le phasage d'exécution en sous-livraisons progressives pour revue et approbation formelle du propriétaire.

---

## 1. Principes et garde-fous opérationnels

L'implémentation future du domaine paiement devra respecter les règles absolues suivantes :
1. **Un commit par étape unitaire :** Chaque étape correspond à un commit unique portant un objectif technique vérifiable et autonome.
2. **Push normal exclusif :** Jamais de force-push (`git push --force` strictement proscrit). En cas de correction, un nouveau commit incrémental est ajouté.
3. **Sorties brutes complètes :** Toutes les commandes de vérification de build, lint, format et tests sont inspectées via des sorties brutes complètes, découpées en blocs de 100 lignes maximum, jamais de 'lines truncated'.
4. **Intégrité de la suite de tests :** Aucun test existant ne doit être supprimé ni affaibli. La suite complète (backend, mobile, frontend) doit demeurer verte avant toute proposition de fusion.
5. **Prérogative de fusion du propriétaire :** L'agent ne fusionne jamais aucune branche ni Pull Request sur `main` ; la revue et la fusion relèvent exclusivement du propriétaire.
6. **Conformité aux règles d'architecture (`CLAUDE.md:58-65, 77-85`) :**
   - Présence obligatoire de la colonne `tenant_id` sur toute nouvelle table créée.
   - Test d'isolation multi-tenant systématique pour chaque nouvelle route exposée.
   - Protection des routes administratives `/{tenant_id}/...` via `get_tenant_admin` (`backend/app/dependencies.py:144-155`).
   - Zéro code spécifique en dur par pays (règle `if country == ...` interdite) ; le comportement repose exclusivement sur la configuration des données.

---

## 2. Tableau des dépendances bloquantes (D1 à D12 et E1 à E4)

L'implémentation effective ne pourra débuter sur les étapes concernées tant que le propriétaire n'aura pas formellement arbitré les décisions suivantes :

| Id | Question à trancher | Options ouvertes | Étapes impactées | Version |
|---|---|---|---|---|
| **D1** | Modes de réservation éligibles à la commission (`docs/payment/PAYMENT_DESIGN.md:69-94`) | **Option A :** `manual_confirm` uniquement.<br>**Option B :** `manual_confirm` + `pay_on_site` (avec refonte du flux de notification partenaire). | Étape 1.3, Étape 1.4 | V1a |
| **D2** | Modèle relationnel contractuel partenaire (`docs/payment/PAYMENT_DESIGN.md:126-133`) | **Option A :** Surcharger la table existante `poi_managers`.<br>**Option B :** Créer les tables dédiées `partner_profiles` et `partner_poi_assignments`. | Étape 1.1 | V1a |
| **D3** | Scoping de l'entité juridique Discover AI (`docs/payment/PAYMENT_DESIGN.md:206-213`) | **Option A :** Entité de plateforme globale sans `tenant_id`.<br>**Option B :** Une ligne `legal_entities` par tenant (alignée sur le principe 2 de `CLAUDE.md:59`). *(Lié à l'écart E3).* | Étape 1.1, Étape 1.2 | V1a |
| **D4** | Source de la date effective de prestation (`docs/payment/PAYMENT_DESIGN.md:415-422`) | **Option A :** Date `service_date` déclarée par le partenaire (bornée au présent/passé).<br>**Option B :** Colonne native ajoutée sur `Booking`.<br>**Option C :** Clé obligatoire dans le JSON `booking_data`. | Étape 1.3 | V1a |
| **D5** | Sort d'une déclaration sans réponse après 72 h (`docs/payment/PAYMENT_DESIGN.md:391-399`) | **Option A :** Confirmation tacite automatique avec calcul de commission.<br>**Option B :** Bascule en statut `expired_unconfirmed` sans calcul automatique (`docs/payment/PAYMENT_DECISIONS_V1.md:62-63`). *(Lié à l'écart E2).* | Étape 1.4, Étape 1.5, V1a-inter | V1a |
| **D6** | Politique d'arrondi sur les centimes (`docs/payment/PAYMENT_DESIGN.md:474-481`) | **Option A :** Troncature à l'unité mineure inférieure (floor).<br>**Option B :** Arrondi bancaire au plus proche (half to even). | Étape 1.4 | V1a |
| **D7** | Faculté de déclaration par l'administrateur du tenant (`docs/payment/PAYMENT_DESIGN.md:504-512`) | **Option A :** Interdiction stricte (réservé aux gestionnaires rattachés au POI).<br>**Option B :** Autorisation exceptionnelle de secours avec traçabilité obligatoire (`declared_by_admin = True`, `declaration_reason`). *(Lié à l'écart E4).* | Étape 1.3 | V1a |
| **D8** | Unicité des notifications par réservation (`docs/payment/PAYMENT_DESIGN.md:601-611`) | **Option A :** Types distincts (`service_declaration_received`, `service_declaration_corrected`, `fee_declaration_received`).<br>**Option B :** Évolution de l'index partiel `uq_notifications_booking_unique` pour ajouter une clé discriminante. | Étape 1.5 | V1a |
| **D9** | Mécanisme de preuve de la prestation (`docs/payment/PAYMENT_DESIGN.md:427-441`) | **Option A :** Confirmation in-app par le voyageur.<br>**Option B :** Téléversement d'un justificatif comptable.<br>**Option C :** Validation sur place par QR code / OTP. | Étape 1.4, Étape 1.6 | V1a |
| **D10** | Statut du tenant `morocco` en V1 (`docs/payment/PAYMENT_DESIGN.md:374-378`) | **Option A :** Blocage absolu de la commission via la règle pays/entité.<br>**Option B :** Création d'une entité juridique marocaine (hors périmètre V1). | Étape 1.2, Étape 1.2-bis | V1a |
| **D11** | Gestion des corrections multiples face à l'index de notification (`backend/app/models.py:460-469`) | **Option A :** Plafonner à une seule correction par réservation en V1a.<br>**Option B :** Faire évoluer l'index SQL partiel vers un index acceptant une version de déclaration. | Étape 1.3, Étape 1.5 | V1a |
| **D12** | Traitement des dossiers non résolus pendant l'intervalle V1a/V1b (`docs/payment/PAYMENT_DECISIONS_V1.md:79`) | **Option A :** Consultation CLI seule et gel total du calcul jusqu'à la livraison du rôle `finance_operator` en V1b.<br>**Option B :** Action corrective manuelle permise par script CLI avec `operator_identifier` obligatoire dès la V1a (ce qui lève l'écart E1). | Section 3 (inter-V1), Étape 1.7 | V1a |
| **E1** | Droits d'écriture des scripts CLI en V1a (`docs/payment/PAYMENT_COMPLIANCE.md:161`) | **Option A :** CLI en lecture seule stricte en V1a (`docs/payment/PAYMENT_DECISIONS_V1.md:79`).<br>**Option B :** CLI habilité à corriger/résoudre avec `operator_identifier` (`docs/payment/PAYMENT_DESIGN.md:513`). | Étape 1.7, Étape 2.2 | V1a/V1b |
| **E2** | Sort des 72 h sans réponse : décision vs design (`docs/payment/PAYMENT_COMPLIANCE.md:162`) | Identique à **D5** : arbitrage entre Option A (tacite) et Option B (`expired_unconfirmed`). | Étape 1.4, Étape 1.5 | V1a |
| **E3** | Entité unique vs entité par tenant (`docs/payment/PAYMENT_COMPLIANCE.md:163`) | Identique à **D3** : arbitrage entre Option A (globale) et Option B (par tenant). | Étape 1.1, Étape 1.2 | V1a |
| **E4** | Faculté de déclaration par l'admin tenant (`docs/payment/PAYMENT_COMPLIANCE.md:164`) | Identique à **D7** : arbitrage entre Option A (interdit) et Option B (permis avec motif). | Étape 1.3 | V1a |

---

## 3. Découpage détaillé de la sous-livraison V1a (Fondation financière autonome)

La sous-livraison V1a met en place le socle relationnel, le calcul de commission après confirmation voyageur et la consultation par CLI, sans dépendre du moteur de litige complet ni des politiques d'annulation.

### Dossiers non résolus entre V1a et V1b
Pendant la période où la V1a est en production mais où le rôle `finance_operator` n'existe pas encore (`docs/payment/PAYMENT_DECISIONS_V1.md:79`), deux situations d'attente humaine peuvent survenir :
1. Une déclaration contestée par le voyageur (`status == "disputed"`).
2. Une déclaration échue sans réponse sous l'Option B de D5 (`status == "expired_unconfirmed"`).

Deux options sont soumises à l'arbitrage du propriétaire (Dépendance **D12**) :
- **Option A (Gel strict et consultation CLI seule) :** Les déclarations contestées ou échues restent figées en base ; aucun calcul de commission n'est exécuté ; le script CLI permet uniquement de lister ces dossiers en attente. Leur résolution attend le déploiement formel de la V1b.  
  *Avantages :* Respecte scrupuleusement la règle de lecture seule du CLI en V1a (`docs/payment/PAYMENT_DECISIONS_V1.md:79`).  
  *Inconvénients :* Les créances litigieuses restent bloquées jusqu'à la livraison V1b.
- **Option B (Action corrective exceptionnelle par CLI) :** Le script CLI d'administration permet de clore ou corriger un dossier contesté en consignant obligatoirement `operator_identifier` et `reason` dans `financial_audit_log`.  
  *Avantages :* Évite l'accumulation de dossiers bloqués.  
  *Inconvénients :* Anticipe sur la V1b et lève l'écart E1.

```
+---------------------------------------------------------------------------------------------------+
| Étape 1.1 : Modèles ORM & Migration Alembic 0017 (legal_entities, partner_profiles, rules)       |
| -> Dépend de D2, D3 / E3                                                                          |
+---------------------------------------------------------------------------------------------------+
                                                  │
                                                  ▼
+---------------------------------------------------------------------------------------------------+
| Étape 1.2 : Logique pays/entité & Seed idempotent initial_data.py                                  |
| -> Dépend de D3, D10                                                                              |
+---------------------------------------------------------------------------------------------------+
                                                  │
                                                  ▼
+---------------------------------------------------------------------------------------------------+
| Étape 1.2-bis : Backfill country_code des tenants & configuration SLA 72h                         |
| -> Dépend de D10 et PAYMENT_COMPLIANCE.md §6.2                                                    |
+---------------------------------------------------------------------------------------------------+
                                                  │
                                                  ▼
+---------------------------------------------------------------------------------------------------+
| Étape 1.3 : Déclaration de prestation (API partner declare & migration Alembic 0018)              |
| -> Dépend de D1, D4, D7 / E4, D11                                                                 |
+---------------------------------------------------------------------------------------------------+
                                                  │
                                                  ▼
+---------------------------------------------------------------------------------------------------+
| Étape 1.4 : Confirmation voyageur, calcul de commission & enregistrement contestation initial     |
| -> Dépend de D1, D5 / E2, D6, D9                                                                  |
+---------------------------------------------------------------------------------------------------+
                                                  │
                                                  ▼
+---------------------------------------------------------------------------------------------------+
| Étape 1.5 : Système de notifications financières & worker de rappel périodique                    |
| -> Dépend de D5, D8, D11                                                                          |
+---------------------------------------------------------------------------------------------------+
                                                  │
                                                  ▼
+---------------------------------------------------------------------------------------------------+
| Étape 1.6 : Interfaces mobiles Flutter (action partenaire, confirmation voyageur, i18n FR/AR/EN) |
| -> Dépend de D9                                                                                   |
+---------------------------------------------------------------------------------------------------+
                                                  │
                                                  ▼
+---------------------------------------------------------------------------------------------------+
| Étape 1.7 : Script CLI de reporting financier en lecture seule (app/reporting_finance.py)         |
| -> Dépend de D12 / E1                                                                             |
+---------------------------------------------------------------------------------------------------+
                                                  │
                                                  ▼
+---------------------------------------------------------------------------------------------------+
| Étape 1.8 : Documentation d'exploitation et guide d'auditabilité comptable                        |
| -> Clôture du lot V1a                                                                             |
+---------------------------------------------------------------------------------------------------+
```

### Étape 1.1 — Modèles de structure financière et migration Alembic 0017
- **Objectif :** Créer les tables de socle `legal_entities`, `partner_profiles`, `partner_poi_assignments` et `commission_rules`.
- **Fichiers à modifier / créer :**
  - `backend/app/models.py` (ajout des classes ORM avec `tenant_id` obligatoire).
  - `backend/alembic/versions/0017_financial_foundation_entities.py` (migration réversible).
- **Migration :** Révision `0017_financial_foundation_entities` (succédant à `0016_backfill_skipped_notifs.py`, `backend/alembic/versions/0016_backfill_skipped_notifs.py:13`).
- **Tests à écrire :** `backend/tests/test_financial_models.py` :
  - `test_legal_entity_creation_requires_tenant`
  - `test_partner_profile_tax_id_encryption`
  - `test_partner_poi_assignment_validity`
  - `test_financial_models_tenant_isolation` (vérifie via les fixtures `other_tenant`, `other_admin`, `other_admin_headers` de `backend/tests/conftest.py:164-199` qu'une entité ou profil du tenant A n'est jamais accessible avec l'en-tête du tenant B).
- **Critère d'acceptation :** `alembic upgrade head` puis `alembic downgrade -1` s'exécutent sans erreur ; tests unitaires ORM et d'isolation au vert.
- **Risque :** Conflit sur la gestion des clés de chiffrement `CredentialCrypto` lors de l'enregistrement de `tax_identification_number`.
- **Retour arrière :** `alembic downgrade 0016_backfill_skipped_notifs`.
- **Dépendances :** Dépend de **D2** (tables partenaires dédiées vs `poi_managers`) et **D3 / E3** (entité par tenant vs globale).

### Étape 1.2 — Validation de la règle pays/entité et initialisation idempotente du seed
- **Objectif :** Implémenter le service d'évaluation d'éligibilité pays/entité et injecter l'entité légale de référence d'Algérie dans `initial_data.py`.
- **Fichiers à modifier / créer :**
  - `backend/app/services/commission_service.py` (vérification `partner_profile.country_code == legal_entity.country_code`).
  - `backend/app/initial_data.py` (fonction idempotente `_seed_financial_foundation`).
- **Migration :** Aucune (données d'initialisation applicative).
- **Tests à écrire :** `backend/tests/test_country_entity_rule.py` :
  - `test_commission_disabled_when_countries_differ`
  - `test_morocco_tenant_has_no_active_commission`
  - `test_seed_financial_foundation_is_idempotent`
- **Critère d'acceptation :** Réexécuter `initial_data.py` sur une base existante ne lève aucune exception et n'insère aucun doublon.
- **Risque :** Présence de valeurs `NULL` dans `Tenant.country_code` (`backend/app/models.py:51`).
- **Retour arrière :** Revert du commit unitaire.
- **Dépendances :** Dépend de **D3** et **D10**.

### Étape 1.2-bis — Backfill de `country_code` et configuration du SLA de confirmation
- **Objectif :** Renseigner par migration de données la colonne `Tenant.country_code` pour les tenants existants (`algeria` -> `"DZ"`, `morocco` -> `"MA"`) à partir des informations fournies par le propriétaire (`docs/payment/PAYMENT_COMPLIANCE.md:193`), et initialiser la clé `Tenant.config["service_confirmation_sla_hours"] = 72` par défaut.
- **Mécanisme de migration retenu :** Le script de seed `backend/app/initial_data.py:20-22` effectue un retour anticipé immédiat dès que le tenant `algeria` existe :
  ```python
  result = await session.execute(select(Tenant).where(Tenant.slug == "algeria"))
  if result.scalar_one_or_none():
      return
  ```
  Par conséquent, `initial_data.py` ne peut pas renseigner `country_code` sur des bases de données existantes où `algeria` préexiste déjà. Le mécanisme retenu est donc une migration de données Alembic dédiée (exécutant des ordres SQL `UPDATE tenants SET country_code = ...` ciblés et idempotents).
- **Fichiers à modifier / créer :**
  - `backend/alembic/versions/0017_backfill_tenant_country_codes.py` (migration de données Alembic dédiée).
  - `backend/app/initial_data.py` (alimentation explicite de `country_code` pour les nouvelles bases).
  - `backend/tests/test_tenant_defaults.py` (fichier existant créé par la PR #47, à étendre).
- **Migration :** Révision Alembic de données (ex. `0017_backfill_tenant_country_codes.py` ou intégrée à la migration de schéma V1a).
- **Tests à étendre :** Le fichier `backend/tests/test_tenant_defaults.py:1-20` existe déjà et protège actuellement `test_tenant_default_primary_color`. Il sera étendu avec :
  - `test_tenant_seed_populates_country_code_dz`
  - `test_tenant_config_contains_service_confirmation_sla_hours`
- **Critère d'acceptation :** Tous les tenants ont un `country_code` non nul à 2 lettres et un SLA de confirmation à 72 heures.
- **Risque :** Conflit avec le validateur `@validates("country_code")` (`backend/app/models.py:68-76`).
- **Retour arrière :** Revert de la migration de données.
- **Dépendances :** Dépend de **D10** et des données du propriétaire (`docs/payment/PAYMENT_COMPLIANCE.md:193`).

### Étape 1.3 — Endpoint de déclaration de prestation partenaire et table d'audit
- **Objectif :** Créer la table `service_declarations`, la table `financial_audit_log` (avec trigger d'immuabilité) et exposer la route `POST /api/v1/partner/bookings/{booking_id}/declare`.
- **Fichiers à modifier / créer :**
  - `backend/app/models.py` (modèles `ServiceDeclaration`, `FinancialAuditLog`).
  - `backend/alembic/versions/0018_service_declarations_receivables.py` (création des tables et du trigger PostgreSQL d'immuabilité).
  - `backend/app/schemas.py` (`ServiceDeclarationCreate`, `ServiceDeclarationResponse`).
  - `backend/app/api/v1/endpoints/partner.py` (route de déclaration sous contrôle `_require_partner`).
- **Migration :** Révision `0018_service_declarations_receivables`.
- **Tests à écrire :** `backend/tests/test_service_declaration.py` :
  - `test_partner_can_declare_completed_booking`
  - `test_declaration_freezes_legal_entity_and_rate_snapshot`
  - `test_declaration_rejected_if_date_in_future`
  - `test_audit_log_forbids_update_and_delete`
  - `test_partner_declare_tenant_isolation_returns_404` (test d'isolation vérifiant qu'un appel avec l'en-tête `other_tenant.slug` renvoie HTTP 404, calqué sur `backend/tests/conftest.py:164-199`).
- **Critère d'acceptation :** Une réservation `confirmed` en mode `manual_confirm` peut recevoir une déclaration ; `applied_rate_bps` est figé ; toute tentative de `UPDATE` sur `financial_audit_log` lève une exception SQL ; l'isolation cross-tenant renvoie 404.
- **Risque :** Conflit sur la contrainte d'unicité en cas de corrections multiples.
- **Retour arrière :** `alembic downgrade 0017_financial_foundation_entities`.
- **Dépendances :** Dépend de **D1**, **D4**, **D7 / E4**, **D11**.

### Étape 1.4 — Confirmation, calcul immuable de la commission et contestation initiale
- **Objectif :** Créer les tables `service_completions` et `commission_receivables`, exposer les routes voyageur `confirm-service` et `dispute-service`.
- **Fichiers à modifier / créer :**
  - `backend/app/api/v1/endpoints/bookings.py` (routes voyageur authentifié).
  - `backend/app/services/commission_service.py` (formule arithmétique exacte avec règle d'arrondi).
- **Migration :** Comprise dans la révision `0018`.
- **Tests à écrire :** `backend/tests/test_service_confirmation.py` :
  - `test_traveller_confirm_creates_completion_and_receivable`
  - `test_commission_rounding_floor_vs_half_even`
  - `test_traveller_dispute_suspends_commission_calculation`
  - `test_confirm_service_tenant_isolation_returns_404` (test d'isolation cross-tenant avec `other_admin_headers`, `backend/tests/conftest.py:192-199`).
- **Critère d'acceptation :** La confirmation génère une créance au centime près ; la contestation bascule la déclaration en `disputed` sans créer de créance ; appel cross-tenant rejeté en 404.
- **Risque :** Erreur d'arrondi sur les fractions de centime.
- **Retour arrière :** Revert du commit applicatif.
- **Dépendances :** Dépend de **D1**, **D5 / E2**, **D6**, **D9**.

### Étape 1.5 — Intégration des notifications financières et worker de relance
- **Objectif :** Ajouter les types de notifications de déclaration, relance et confirmation, et intégrer la tâche de balayage périodique dans le worker de fond.
- **Fichiers à modifier / créer :**
  - `backend/app/services/notification_templates.py` (templates multilingues).  
    *Constat sur l'existant :* Le fichier `backend/app/services/notification_templates.py:1-50` ne supporte actuellement que `"fr"` et `"en"` (avec repli gracieux sur `"en"` à la ligne 70). La langue arabe (`"ar"`) est actuellement absente des gabarits backend. L'alignement complet avec les 3 langues du mobile (FR/AR/EN) constitue un écart technique à combler lors de cette étape.
  - `backend/app/services/notification_worker.py` (fonction `dispatch_pending_confirmation_reminders` via `claim_batch`).
- **Migration :** Aucune (ou ajout de clé discriminante si D8 retient l'Option B).
- **Tests à écrire :** `backend/tests/test_financial_notifications.py` :
  - `test_declaration_emits_notification_to_traveller`
  - `test_reminder_dispatched_at_48h_mark`
  - `test_notification_idempotence_prevents_duplicate_reminders`
- **Critère d'acceptation :** Le voyageur reçoit une notification in-app à la déclaration ; une relance est émise à H+48 si le dossier est toujours en attente.
- **Risque :** Élimination silencieuse de notifications par l'index partiel `uq_notifications_booking_unique` (`backend/app/models.py:460-469`).
- **Retour arrière :** Revert du commit.
- **Dépendances :** Dépend de **D5**, **D8**, **D11**.

### Étape 1.6 — Intégration mobile Flutter (espace partenaire et écran voyageur)
- **Objectif :** Permettre la saisie de la déclaration côté partenaire et la confirmation/contestation côté voyageur dans l'application mobile.
- **Fichiers à modifier / créer :**
  - `mobile/lib/screens/partner_bookings_screen.dart` (action déclarative pour réservations confirmées échues).
  - `mobile/lib/screens/bookings_screen.dart` (bandeau de validation de service et dialogue de contestation).
  - `mobile/lib/l10n/` (chaînes localisées en français, arabe et anglais).
- **Tests à écrire :** `mobile/test/financial_flow_test.dart` :
  - `renders declare service action on completed partner booking`
  - `traveller confirms service and triggers completion`
- **Critère d'acceptation :** `flutter test` vert ; `dart format` propre ; aucune anomalie lors de `flutter analyze`.
- **Risque :** Régression sur l'affichage des statuts de réservation existants dans `styleFor` (`mobile/lib/screens/bookings_screen.dart:149-179`).
- **Retour arrière :** Revert du commit Flutter.
- **Dépendances :** Dépend de **D9**.

### Étape 1.7 — Script CLI de reporting financier en lecture seule
- **Objectif :** Développer le module d'administration autonome `app.reporting_finance` pour extraire les créances et déclarations par tenant en format CSV.
- **Fichiers à modifier / créer :**
  - `backend/app/reporting_finance.py` (architecture CLI calquée sur `backend/app/create_tenant.py:1-104`).
- **Tests à écrire :** `backend/tests/test_reporting_finance_cli.py` :
  - `test_cli_exports_tenant_receivables_csv`
  - `test_cli_respects_tenant_isolation`
- **Critère d'acceptation :** `python -m app.reporting_finance --tenant-slug algeria --format csv` génère un fichier CSV exploitable sans nécessiter de serveur HTTP actif.
- **Risque :** Fuite de données cross-tenant en cas d'omission du filtre `tenant_id`.
- **Retour arrière :** Suppression du fichier.
- **Dépendances :** Dépend de **D12 / E1**.

### Étape 1.8 — Documentation d'exploitation et guide d'auditabilité
- **Objectif :** Rédiger le guide d'exploitation financière pour les administrateurs et auditeurs (commandes CLI, vérification des triggers d'immuabilité, consultation des logs).
- **Fichiers à modifier / créer :**
  - `docs/payment/PAYMENT_OPERATIONS_V1A.md`.
- **Critère d'acceptation :** Documentation relue et validée par le propriétaire.
- **Dépendances :** Clôture du lot V1a.

---

## 4. Découpage détaillé de la sous-livraison V1b (Contrôle financier et traitement des litiges)

> **Prérequis strict :** La sous-livraison V1a doit être entièrement déployée, testée et validée en environnement de préproduction avant d'engager la V1b.

### Étape 2.1 — Rôle nominatif `finance_operator` et matrice de permissions RBAC
- **Objectif :** Introduire la permission `finance_operator` sur `User` (`backend/app/models.py:192`) et restreindre les routes financières sensibles aux seuls opérateurs habilités (`backend/app/dependencies.py`).
- **Impact sur les tables existantes :** Migration additive ajoutant `is_finance_operator = Column(Boolean, default=False, nullable=False)` sur la table existante `users`.
- **Fichiers à modifier / créer :**
  - `backend/app/models.py` (colonne sur `User`).
  - `backend/alembic/versions/0019_user_finance_operator_role.py` (migration additive).
  - `backend/app/dependencies.py` (dépendance `get_finance_operator` vérifiant `current_user.is_finance_operator`).
- **Migration :** Révision `0019_user_finance_operator_role`.
- **Tests à écrire :** `backend/tests/test_finance_operator_rbac.py` :
  - `test_finance_operator_access_granted`
  - `test_standard_admin_forbidden_on_dispute_resolution`
  - `test_non_regression_user_jwt_login` (vérifie que l'ajout de la colonne n'invalide pas l'authentification existante).
- **Critère d'acceptation :** Seul un utilisateur portant `is_finance_operator == True` accède aux routes de litige.
- **Risque :** Régression sur les fixtures d'utilisateurs existantes dans `conftest.py`.
- **Retour arrière :** `alembic downgrade 0018_service_declarations_receivables`.
- **Dépendances :** Prérequis V1a validée.

### Étape 2.2 — Moteur de résolution des contestations (Cycle en 6 étapes)
- **Objectif :** Exposer l'API de traitement des litiges permettant à un opérateur financier de confirmer, corriger avec justification, ou annuler une commission litigieuse (`docs/payment/PAYMENT_DECISIONS_V1.md:71-80`).
- **Fichiers à modifier / créer :**
  - `backend/app/api/v1/endpoints/finance.py` (routes `/api/v1/finance/disputes/{declaration_id}/resolve`).
  - `backend/app/services/dispute_service.py` (cycle en 6 étapes).
- **Migration :** Aucune (utilise les tables `service_declarations` et `financial_audit_log` créées en V1a).
- **Tests à écrire :** `backend/tests/test_dispute_resolution.py` :
  - `test_dispute_resolution_creates_audit_entry_with_mandatory_reason`
  - `test_dispute_resolution_updates_commission_receivable`
  - `test_dispute_resolution_tenant_isolation_returns_404`
- **Critère d'acceptation :** Clôture d'un litige impossible sans saisie d'un motif textuel non vide stocké dans `financial_audit_log.reason`.
- **Risque :** Modification accidentelle de créances déjà réglées.
- **Retour arrière :** Revert du commit applicatif.
- **Dépendances :** Étape 2.1.

### Étape 2.3 — Émission des relevés de commission et enregistrement des factures externes
- **Objectif :** Permettre l'agrégation mensuelle des créances `commission_receivables` en relevés de commission téléchargeables et stocker la référence de facture externe (`docs/payment/PAYMENT_DECISIONS_V1.md:143`).
- **Fichiers à modifier / créer :**
  - `backend/app/models.py` (modèle `CommissionStatement`).
  - `backend/alembic/versions/0020_commission_statements.py` (table `commission_statements`).
  - `backend/app/api/v1/endpoints/finance.py` (génération et clôture des relevés).
- **Migration :** Révision `0020_commission_statements`.
- **Tests à écrire :** `backend/tests/test_commission_statements.py` :
  - `test_generate_commission_statement_sums_unbilled_receivables`
  - `test_attach_external_invoice_reference`
- **Critère d'acceptation :** Production d'un relevé ventilé avec archivage de la date d'émission et statut `invoiced`.
- **Risque :** Double facturation d'une même créance.
- **Retour arrière :** `alembic downgrade 0019_user_finance_operator_role`.
- **Dépendances :** Étape 2.1.

### Étape 2.4 — Outils de détection du contournement et rapprochement manuel
- **Objectif :** Ajouter au script CLI des métriques de surveillance (ratio réservations annulées / prestations déclarées par partenaire, `docs/payment/PAYMENT_DECISIONS_V1.md:155`).
- **Fichiers à modifier / créer :**
  - `backend/app/reporting_finance.py` (commande `--check-bypass-ratios`).
- **Migration :** Aucune.
- **Tests à écrire :** `backend/tests/test_reporting_finance_cli.py` :
  - `test_cli_flags_anomalous_cancellation_ratio`
- **Critère d'acceptation :** Le rapport met en évidence les partenaires présentant un écart statistique significatif.
- **Risque :** Faux positifs sur des partenaires à faible volume.
- **Retour arrière :** Revert du commit.
- **Dépendances :** Étape 2.3.

---

## 5. Découpage détaillé de la sous-livraison V1c (Politiques d'annulation et gestion des indemnités)

> **Prérequis strict :** La sous-livraison V1b doit être validée, et la date de bascule formellement arrêtée par le propriétaire.

### Étape 3.1 — Modèle des politiques d'annulation versionnées
- **Objectif :** Créer la table `cancellation_policies` (délais de gratuité, pourcentages retenus) et ajouter la colonne facultative `cancellation_policy_version_id` sur `Booking` (`backend/app/models.py:332`).
- **Impact sur les tables existantes :** Migration additive ajoutant `cancellation_policy_version_id = Column(UUID(as_uuid=True), ForeignKey("cancellation_policies.id"), nullable=True)` sur `bookings`.
- **Fichiers à modifier / créer :**
  - `backend/app/models.py` (table `cancellation_policies`, colonne sur `Booking`).
  - `backend/alembic/versions/0021_cancellation_policies.py` (migration additive).
- **Migration :** Révision `0021_cancellation_policies`.
- **Tests à écrire :** `backend/tests/test_cancellation_policies.py` :
  - `test_booking_freezes_cancellation_policy_version_at_consent`
  - `test_non_regression_existing_bookings_have_null_policy_version`
- **Critère d'acceptation :** La modification d'une politique n'altère pas les réservations déjà enregistrées ; les réservations historiques conservent `NULL`.
- **Risque :** Dépendance de clé étrangère sur une table volumineuse.
- **Retour arrière :** `alembic downgrade 0020_commission_statements`.
- **Dépendances :** Prérequis V1b validée.

### Étape 3.2 — Parcours d'annulation post-confirmation avec motifs contrôlés
- **Objectif :** Évoluer l'endpoint `POST /api/v1/bookings/{id}/cancel` (`backend/app/api/v1/endpoints/bookings.py:309`) pour permettre l'annulation encadrée après confirmation selon une liste fermée de motifs.
- **Tests existants à protéger impérativement :**
  - `backend/tests/test_bookings.py:184-214` (`test_cancel_booking` : annulation nominale d'une réservation pending).
  - Protection des gardes d'état sur `cancel` (`backend/app/api/v1/endpoints/bookings.py:309-313` refusant les statuts non annulables).
- **Fichiers à modifier / créer :**
  - `backend/app/api/v1/endpoints/bookings.py` (évolution de `cancel_booking` avec motif et calcul des frais retenus).
- **Migration :** Aucune.
- **Tests à écrire :** `backend/tests/test_cancellation_post_confirmation.py` :
  - `test_post_confirmation_cancellation_applies_policy_penalty`
  - `test_cancellation_without_mandatory_reason_rejected`
- **Critère d'acceptation :** L'annulation tardive calcule les frais retenus opposables au voyageur sans briser le comportement nominal de `test_cancel_booking`.
- **Risque :** Régression sur le flux d'annulation historique des réservations pending.
- **Retour arrière :** Revert du commit applicatif.
- **Dépendances :** Étape 3.1.

### Étape 3.3 — Déclaration des indemnités de no-show et annulation tardive
- **Objectif :** Activer les types de déclaration `late_cancellation_fee` et `no_show_fee` dans `service_declarations` avec application du taux de commission sur le montant effectivement retenu (`docs/payment/PAYMENT_DECISIONS_V1.md:88-89`).
- **Fichiers à modifier / créer :**
  - `backend/app/api/v1/endpoints/partner.py` (validation des déclarations d'indemnité sur réservations annulées).
- **Migration :** Aucune.
- **Tests à écrire :** `backend/tests/test_fee_declarations.py` :
  - `test_commission_calculated_on_declared_no_show_fee`
  - `test_fee_declaration_rejected_if_amount_exceeds_policy_penalty`
- **Critère d'acceptation :** Une déclaration d'indemnité génère la créance de commission correspondante plafonnée au barème de la politique.
- **Risque :** Surestimation de l'indemnité déclarée par le partenaire.
- **Retour arrière :** Revert du commit.
- **Dépendances :** Étape 3.2.

### Étape 3.4 — Procédure d'arbitrage de la force majeure par opérateur
- **Objectif :** Permettre l'exonération totale de frais et de commission sur décision exclusive d'un opérateur autorisé (`docs/payment/PAYMENT_DECISIONS_V1.md:94`).
- **Fichiers à modifier / créer :**
  - `backend/app/api/v1/endpoints/finance.py` (route `/force-majeure`).
- **Migration :** Aucune.
- **Tests à écrire :** `backend/tests/test_force_majeure.py` :
  - `test_force_majeure_waives_cancellation_commission`
  - `test_force_majeure_requires_finance_operator`
- **Critère d'acceptation :** La qualification de force majeure annule toute créance de commission avec trace d'audit.
- **Risque :** Annulation abusive de commissions légitimes.
- **Retour arrière :** Revert du commit.
- **Dépendances :** Étape 3.3.

---

## 6. Stratégie de livraison et de revue (Pull Requests)

Deux options d'organisation des livraisons sont soumises à l'arbitrage :

- **Option A — Une Pull Request par sous-livraison complète (3 PRs : V1a, V1b, V1c) :**
  - *Avantages :* Vision d'ensemble cohérente, intégration de bout en bout validée avant revue, réduction du nombre de fusions.
  - *Risques :* Volume de code important par PR, revue plus dense, temps de blocage plus long avant retour.
- **Option B — Une Pull Request par étape unitaire (8 PRs pour V1a) :**
  - *Avantages :* Revues ultra-ciblées, validation incrémentale pas à pas, risque de régression isolé à un seul composant.
  - *Risques :* Multiplicité des branches et des étapes de revue administrative.

Dans les deux options, **la sous-livraison V1a demeure strictement autonome et fusionnable seule** sans nécessiter la livraison immédiate de V1b ou V1c.

---

## 7. Stratégie de tests et non-régression

### 7.1 Commandes d'exécution de référence
Les suites de vérification automatisées doivent être exécutées avec les commandes exactes suivantes :
- **Backend (Pytest) :**  
  `docker compose exec backend pytest tests/ -q` (ou en local : `cd backend && pytest tests/ -q`).
- **Mobile (Flutter) :**  
  `cd mobile && dart format --output=none --set-exit-if-changed lib test && flutter analyze && flutter test`.
- **Frontend (Playwright E2E) :**  
  `docker compose --profile test run --rm playwright`.

### 7.2 Tests existants critiques à protéger prioritairement
Conformément à l'inventaire de `docs/payment/PAYMENT_AUDIT.md:728-753`, les tests suivants ne doivent subir aucun affaiblissement :
1. `backend/tests/test_bookings.py` :
   - `test_consent_true_on_cancelled_booking_rejected` (ligne 285)
   - `test_consent_true_on_confirmed_booking_rejected` (ligne 306)
   - `test_consent_false_on_confirmed_booking_rejected` (ligne 326)
   - `test_consent_false_on_non_pending_manual_confirm_rejected` (ligne 341)
   - `test_consent_non_regression_from_pending` (ligne 365)
2. `backend/tests/test_booking_modes.py` :
   - `test_info_only_poi_cannot_be_booked` (ligne 23)
   - `test_unsupported_mode_is_rejected_defensively` (ligne 34)
   - `test_booking_freezes_mode_and_sets_sla_only_for_manual_confirm` (ligne 46)
3. `backend/tests/test_partner_manual_confirm.py` :
   - `test_partner_confirms_booking_sets_metadata_and_external_id` (ligne 194)
   - `test_partner_declines_booking` (ligne 227)
   - `test_same_decision_replays_idempotently_opposite_conflicts` (ligne 245)
   - `test_overdue_request_expires_and_cannot_be_answered` (ligne 267)
4. `backend/tests/test_notifications_emission.py` :
   - `test_consent_standard_emits_confirmed_notification` (ligne 41)
   - `test_consent_manual_confirm_notifies_poi_managers` (ligne 110)
   - `test_partner_confirm_and_decline_emit_notifications` (ligne 169)
   - `test_expire_overdue_requests_notifies_both_once_and_respects_tenant_isolation` (ligne 258)
5. `mobile/test/models/booking_statuses_test.dart` (ligne 9) et `mobile/test/booking_flow_test.dart` (lignes 113, 134).

---

## 8. Étape 0 (Préalable avant tout codage)

Avant d'engager le moindre commit applicatif, l'Étape 0 d'établissement de la ligne de base devra obligatoirement constater :
1. **Mesure de référence de la suite backend :** Exécution de `pytest tests/ -q` sur la branche `main` à jour, avec consignation brute du nombre exact de tests passants dans le journal de déploiement.
2. **Vérification de la révision Alembic de tête :** Constat formel que `alembic current` pointe sur `0016_backfill_skipped_notifs` (`backend/alembic/versions/0016_backfill_skipped_notifs.py:13`).
3. **Vérification du démarrage de l'environnement local :** Constat que PostgreSQL, Redis et l'application FastAPI démarrent sans avertissement de schéma.

*(Cette étape sera exécutée lors du lancement effectif du chantier de code ; aucun script n'est exécuté dans ce commit documentaire).*

---

## 9. Risques techniques et plan de retour arrière global

En cas de dysfonctionnement critique constaté en recette ou en production :

1. **Désactivation par drapeau de configuration (Kill switch instantané) :**  
   Positionnement de `is_commission_enabled = False` sur `partner_profiles`. La plateforme continue d'assurer les réservations et confirmations sans bloquer le voyageur.
2. **Périmètre et impact du retour arrière Alembic (Downgrade) :**  
   - Pour la sous-livraison **V1a**, le retour arrière est **strictement total et sans résidu** : les tables financières créées (`legal_entities`, `partner_profiles`, `partner_poi_assignments`, `commission_rules`, `service_declarations`, `service_completions`, `commission_receivables`, `financial_audit_log`) sont supprimées par `alembic downgrade 0016` sans toucher aux tables centrales.  
   - En revanche, pour **V1b et V1c**, les migrations apportent des modifications additives sur les tables existantes (`is_finance_operator` sur `users`, `cancellation_policy_version_id` sur `bookings`). Un downgrade de V1b ou V1c supprime ces colonnes spécifiques.  
   - **Exigence d'export préalable des données comptables :** Tout `alembic downgrade` sur une base de production supprime irréversiblement les créances et journaux financiers enregistrés. En conséquence, **un export complet CSV via `app.reporting_finance` est formellement obligatoire** avant toute exécution de commande downgrade en production.
3. **Immuabilité garantie du domaine de réservation :**  
   Comme aucune colonne existante de `bookings` n'est renommée et qu'aucun nouvel état n'est injecté dans `Booking.status`, le moteur historique de réservation demeure 100 % opérationnel même en cas de retrait complet du module financier.

---

## 10. Critères d'acceptation du point de contrôle 2

Le passage effectif au développement logiciel ne pourra intervenir que lorsque les conditions suivantes seront réunies et validées par le propriétaire :
- [ ] Les dépendances bloquantes **D1 à D12** ont fait l'objet d'un choix formel par le propriétaire.
- [ ] Les écarts **E1 à E4** relevés dans `docs/payment/PAYMENT_COMPLIANCE.md:155-165` ont été tranchés.
- [ ] L'Étape 0 de mesure de référence des tests a été exécutée et consignée.
- [ ] Le propriétaire du projet a formulé son accord écrit explicite pour l'ouverture de la sous-livraison V1a.


---

## 11. Plan V1a/V1b/V1c après arbitrage du point de contrôle 2

Cette section consigne la réaffectation des étapes et la résolution des dépendances suite aux arbitrages du 02/11/2026 :

### 11.1 Statut des dépendances et résolution des écarts E1 à E4
- **D1 à D12 :** Formellement **TRANCHÉES** par le propriétaire du projet (renvoi exhaustif vers `docs/payment/PAYMENT_DECISIONS_V1.md:224-241`, Annexe C).
- **Écarts E1 à E4 :** Entièrement **RÉSOLUS** par les arbitrages D1 à D12 :
  - **E1 (CLI V1a) :** Résolu par **D12** (lecture seule stricte en V1a ; aucune modification manuelle par CLI).
  - **E2 (Délai 72 h) :** Résolu par **D5** (statut `expired_unconfirmed`, pas de facturation automatique en V1a).
  - **E3 (Entité légale) :** Résolu par **D3** (entité unique algérienne, table de configuration `tenant_legal_entity_configs`).
  - **E4 (Admin tenant) :** Résolu par **D7** (exclusion stricte de l'administrateur de tenant de la faculté de déclarer).
- **D13 à D16 :** Nouvelles questions ouvertes à trancher par le propriétaire (`docs/payment/PAYMENT_DECISIONS_V1.md:243-268`, Annexe D).

### 11.2 Réaffectation des étapes techniques de la sous-livraison V1a
1. **Étape 1.1 (Modèles et migration 0017) :** Modifiée selon D3. La table `legal_entities` est créée sans colonne `tenant_id` ; une table d'association `tenant_legal_entity_configs` (`tenant_id` UNIQUE -> `legal_entity_id`) gère le rattachement par tenant.
2. **Étape 1.3 (Déclaration partenaire) :** Modifiée selon D7 et D11. La dépendance de sécurité est `_require_declaring_partner` (excluant `is_admin == True`, exigeant une liaison active dans `POIManager` et `partner_poi_assignments`). Le plafond technique est fixé à **une seule correction** par réservation (`correction_count < 1`).
3. **Étape 1.4 (Confirmation et créance) :** Modifiée selon D5. À l'expiration du SLA sans confirmation voyageur, la déclaration bascule en `expired_unconfirmed` ; aucune commission n'est exigible, aucune créance n'est générée.
4. **Étape 1.5 (Notifications financières) :** Modifiée selon D8. Implémentation des **sept types d'événements distincts** garantissant l'absence de conflit avec l'index partiel `uq_notifications_booking_unique` (`backend/app/models.py:460-469`).

### 11.3 Séparation étanche des livraisons et verrou d'autorisation
- **V1a (Fondation) :** Modèles, règles de pays, déclaration, confirmation in-app, expiration 72 h, calcul immuable, notifications et CLI en lecture seule.
- **V1b (Contrôle financier) :** Résolution humaine des litiges par `finance_operator`, relevés périodiques, métriques d'anti-contournement.
- **V1c (Annulations) :** Politiques d'annulation versionnées, motifs post-confirmation, déclaration d'indemnités et force majeure.

> **RÈGLE ABSOLUE D'ENGAGEMENT :** Aucune ligne de code, aucune migration Alembic et aucun test applicatif ne sera créé ou modifié sans l'autorisation écrite explicite du propriétaire du projet validant le démarrage de l'étape concernée.
