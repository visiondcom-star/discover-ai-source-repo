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
3. **Sorties brutes courtes :** Toutes les commandes de vérification de build, lint, format et tests sont inspectées via des sorties brutes courtes sans altération (`| tail -15`).
4. **Intégrité de la suite de tests :** Aucun test existant ne doit être supprimé ni affaibli. La suite complète (backend, mobile, frontend) doit demeurer verte avant toute proposition de fusion.
5. **Prérogative de fusion du propriétaire :** L'agent ne fusionne jamais aucune branche ni Pull Request sur `main` ; la revue et la fusion relèvent exclusivement du propriétaire.
6. **Conformité aux règles d'architecture (`CLAUDE.md:58-65, 77-85`) :**
   - Présence obligatoire de la colonne `tenant_id` sur toute nouvelle table créée.
   - Test d'isolation multi-tenant systématique pour chaque nouvelle route exposée.
   - Protection des routes administratives `/{tenant_id}/...` via `get_tenant_admin` (`backend/app/dependencies.py:144-155`).
   - Zéro code spécifique en dur par pays (règle `if country == ...` interdite) ; le comportement repose exclusivement sur la configuration des données.

---

## 2. Tableau des dépendances bloquantes (D1 à D11)

L'implémentation effective ne pourra débuter sur les étapes concernées tant que le propriétaire n'aura pas formellement arbitré les décisions suivantes :

| Id      | Question à trancher                                                                                | Options ouvertes                                                                                                                                                                                                                                   | Étapes impactées     | Version |
| ------- | -------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------- | ------- |
| **D1**  | Modes de réservation éligibles à la commission (`docs/payment/PAYMENT_DESIGN.md:69-94`)            | **Option A :** `manual_confirm` uniquement.<br>**Option B :** `manual_confirm` + `pay_on_site` (avec refonte du flux de notification partenaire).                                                                                                  | Étape 1.3, Étape 1.4 | V1a     |
| **D2**  | Modèle relationnel contractuel partenaire (`docs/payment/PAYMENT_DESIGN.md:126-133`)               | **Option A :** Surcharger la table existante `poi_managers`.<br>**Option B :** Créer les tables dédiées `partner_profiles` et `partner_poi_assignments`.                                                                                           | Étape 1.1            | V1a     |
| **D3**  | Scoping de l'entité juridique Discover AI (`docs/payment/PAYMENT_DESIGN.md:206-213`)               | **Option A :** Entité de plateforme globale sans `tenant_id`.<br>**Option B :** Une ligne `legal_entities` par tenant (recommandée par le principe 2 de `CLAUDE.md:59`).                                                                           | Étape 1.1, Étape 1.2 | V1a     |
| **D4**  | Source de la date effective de prestation (`docs/payment/PAYMENT_DESIGN.md:415-422`)               | **Option A :** Date `service_date` déclarée par le partenaire (bornée au présent/passé).<br>**Option B :** Colonne native ajoutée sur `Booking`.<br>**Option C :** Clé obligatoire dans le JSON `booking_data`.                                    | Étape 1.3            | V1a     |
| **D5**  | Sort d'une déclaration sans réponse après 72 h (`docs/payment/PAYMENT_DESIGN.md:391-399`)          | **Option A :** Confirmation tacite automatique avec calcul de commission.<br>**Option B :** Bascule en statut `expired_unconfirmed` sans calcul automatique (`docs/payment/PAYMENT_DECISIONS_V1.md:62-63`).                                        | Étape 1.4, Étape 1.5 | V1a     |
| **D6**  | Politique d'arrondi sur les centimes (`docs/payment/PAYMENT_DESIGN.md:474-481`)                    | **Option A :** Troncature à l'unité mineure inférieure (floor).<br>**Option B :** Arrondi bancaire au plus proche (half to even).                                                                                                                  | Étape 1.4            | V1a     |
| **D7**  | Faculté de déclaration par l'administrateur du tenant (`docs/payment/PAYMENT_DESIGN.md:504-512`)   | **Option A :** Interdiction stricte (réservé aux gestionnaires rattachés au POI).<br>**Option B :** Autorisation exceptionnelle de secours avec traçabilité obligatoire (`declared_by_admin = True`, `declaration_reason`).                        | Étape 1.3            | V1a     |
| **D8**  | Unicité des notifications par réservation (`docs/payment/PAYMENT_DESIGN.md:601-611`)               | **Option A :** Types distincts (`service_declaration_received`, `service_declaration_corrected`, `fee_declaration_received`).<br>**Option B :** Évolution de l'index partiel `uq_notifications_booking_unique` pour ajouter une clé discriminante. | Étape 1.5            | V1a     |
| **D9**  | Mécanisme de preuve de la prestation (`docs/payment/PAYMENT_DESIGN.md:427-441`)                    | **Option A :** Confirmation in-app par le voyageur.<br>**Option B :** Téléversement d'un justificatif comptable.<br>**Option C :** Validation sur place par QR code / OTP.                                                                         | Étape 1.4, Étape 1.6 | V1a     |
| **D10** | Statut du tenant `morocco` en V1 (`docs/payment/PAYMENT_DESIGN.md:374-378`)                        | **Option A :** Blocage absolu de la commission via la règle pays/entité.<br>**Option B :** Création d'une entité juridique marocaine (hors périmètre V1).                                                                                          | Étape 1.2            | V1a     |
| **D11** | Gestion des corrections multiples face à l'index de notification (`backend/app/models.py:460-469`) | **Option A :** Plafonner à une seule correction par réservation en V1a.<br>**Option B :** Faire évoluer l'index SQL partiel vers un index acceptant une version de déclaration.                                                                    | Étape 1.3, Étape 1.5 | V1a     |

---

## 3. Découpage détaillé de la sous-livraison V1a (Fondation financière autonome)

La sous-livraison V1a met en place le socle relationnel, le calcul de commission après confirmation voyageur et la consultation par CLI, sans dépendre du moteur de litige complet ni des politiques d'annulation.

```
+---------------------------------------------------------------------------------------------------+
| Étape 1.1 : Modèles ORM & Migration Alembic 0017 (legal_entities, partner_profiles, rules)       |
| -> Dépend de D2, D3                                                                               |
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
| Étape 1.3 : Déclaration de prestation (API partner declare & migration Alembic 0018)              |
| -> Dépend de D1, D4, D7, D11                                                                      |
+---------------------------------------------------------------------------------------------------+
                                                  │
                                                  ▼
+---------------------------------------------------------------------------------------------------+
| Étape 1.4 : Confirmation voyageur, calcul de commission & enregistrement contestation initial     |
| -> Dépend de D1, D5, D6, D9                                                                       |
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
| -> Indépendant des décisions litigieuses                                                          |
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
- **Tests à écrire :** `backend/tests/test_financial_models.py` (`test_legal_entity_creation_requires_tenant`, `test_partner_profile_tax_id_encryption`, `test_partner_poi_assignment_validity`).
- **Critère d'acceptation :** `alembic upgrade head` puis `alembic downgrade -1` s'exécutent sans erreur ; tests unitaires ORM au vert.
- **Risque :** Conflit sur la gestion des clés de chiffrement `CredentialCrypto` lors de l'enregistrement de `tax_identification_number`.
- **Retour arrière :** `alembic downgrade 0016_backfill_skipped_notifs`.
- **Dépendances :** Dépend de **D2** (tables partenaires dédiées vs `poi_managers`) et **D3** (entité par tenant vs globale).

### Étape 1.2 — Validation de la règle pays/entité et initialisation idempotente du seed

- **Objectif :** Implémenter le service d'évaluation d'éligibilité pays/entité et injecter l'entité légale de référence d'Algérie dans `initial_data.py`.
- **Fichiers à modifier / créer :**
  - `backend/app/services/commission_service.py` (vérification `partner_profile.country_code == legal_entity.country_code`).
  - `backend/app/initial_data.py` (fonction idempotente `_seed_financial_foundation`).
- **Migration :** Aucune (données d'initialisation applicative).
- **Tests à écrire :** `backend/tests/test_country_entity_rule.py` (`test_commission_disabled_when_countries_differ`, `test_morocco_tenant_has_no_active_commission`, `test_seed_financial_foundation_is_idempotent`).
- **Critère d'acceptation :** Réexécuter `initial_data.py` sur une base existante ne lève aucune exception et n'insère aucun doublon.
- **Risque :** Présence de valeurs `NULL` dans `Tenant.country_code` (`backend/app/models.py:51`).
- **Retour arrière :** Revert du commit unitaire.
- **Dépendances :** Dépend de **D3** et **D10**.

### Étape 1.3 — Endpoint de déclaration de prestation partenaire et table d'audit

- **Objectif :** Créer la table `service_declarations`, la table `financial_audit_log` (avec trigger d'immuabilité) et exposer la route `POST /api/v1/partner/bookings/{booking_id}/declare`.
- **Fichiers à modifier / créer :**
  - `backend/app/models.py` (modèles `ServiceDeclaration`, `FinancialAuditLog`).
  - `backend/alembic/versions/0018_service_declarations_receivables.py` (création des tables et du trigger PostgreSQL d'immuabilité).
  - `backend/app/schemas.py` (`ServiceDeclarationCreate`, `ServiceDeclarationResponse`).
  - `backend/app/api/v1/endpoints/partner.py` (route de déclaration sous contrôle `_require_partner`).
- **Migration :** Révision `0018_service_declarations_receivables`.
- **Tests à écrire :** `backend/tests/test_service_declaration.py` (`test_partner_can_declare_completed_booking`, `test_declaration_freezes_legal_entity_and_rate_snapshot`, `test_declaration_rejected_if_date_in_future`, `test_audit_log_forbids_update_and_delete`).
- **Critère d'acceptation :** Une réservation `confirmed` en mode `manual_confirm` peut recevoir une déclaration ; `applied_rate_bps` est figé ; toute tentative de `UPDATE` sur `financial_audit_log` lève une exception SQL.
- **Risque :** Conflit sur la contrainte d'unicité en cas de corrections multiples.
- **Retour arrière :** `alembic downgrade 0017_financial_foundation_entities`.
- **Dépendances :** Dépend de **D1**, **D4**, **D7**, **D11**.

### Étape 1.4 — Confirmation, calcul immuable de la commission et contestation initiale

- **Objectif :** Créer les tables `service_completions` et `commission_receivables`, exposer les routes voyageur `confirm-service` et `dispute-service`.
- **Fichiers à modifier / créer :**
  - `backend/app/api/v1/endpoints/bookings.py` (routes voyageur authentifié).
  - `backend/app/services/commission_service.py` (formule arithmétique exacte avec règle d'arrondi).
- **Migration :** Comprise dans la révision `0018`.
- **Tests à écrire :** `backend/tests/test_service_confirmation.py` (`test_traveller_confirm_creates_completion_and_receivable`, `test_commission_rounding_floor_vs_half_even`, `test_traveller_dispute_suspends_commission_calculation`).
- **Critère d'acceptation :** La confirmation génère une créance au centime près ; la contestation bascule la déclaration en `disputed` sans créer de créance.
- **Risque :** Erreur d'arrondi sur les fractions de centime.
- **Retour arrière :** Revert du commit applicatif.
- **Dépendances :** Dépend de **D1**, **D5**, **D6**, **D9**.

### Étape 1.5 — Intégration des notifications financières et worker de relance

- **Objectif :** Ajouter les types de notifications de déclaration, relance et confirmation, et intégrer la tâche de balayage périodique dans le worker de fond.
- **Fichiers à modifier / créer :**
  - `backend/app/services/notification_templates.py` (templates multilingues FR/EN).
  - `backend/app/services/notification_worker.py` (fonction `dispatch_pending_confirmation_reminders` via `claim_batch`).
- **Migration :** Aucune (ou ajout de clé discriminante si D8 retient l'Option B).
- **Tests à écrire :** `backend/tests/test_financial_notifications.py` (`test_declaration_emits_notification_to_traveller`, `test_reminder_dispatched_at_48h_mark`, `test_notification_idempotence_prevents_duplicate_reminders`).
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
- **Tests à écrire :** `mobile/test/financial_flow_test.dart` (`renders declare service action on completed partner booking`, `traveller confirms service and triggers completion`).
- **Critère d'acceptation :** `flutter test` vert ; `dart format` propre ; aucune anomalie lors de `flutter analyze`.
- **Risque :** Régression sur l'affichage des statuts de réservation existants dans `styleFor` (`mobile/lib/screens/bookings_screen.dart:149-179`).
- **Retour arrière :** Revert du commit Flutter.
- **Dépendances :** Dépend de **D9**.

### Étape 1.7 — Script CLI de reporting financier en lecture seule

- **Objectif :** Développer le module d'administration autonome `app.reporting_finance` pour extraire les créances et déclarations par tenant en format CSV.
- **Fichiers à modifier / créer :**
  - `backend/app/reporting_finance.py` (architecture CLI calquée sur `backend/app/create_tenant.py:1-104`).
- **Tests à écrire :** `backend/tests/test_reporting_finance_cli.py` (`test_cli_exports_tenant_receivables_csv`, `test_cli_respects_tenant_isolation`).
- **Critère d'acceptation :** `python -m app.reporting_finance --tenant-slug algeria --format csv` génère un fichier CSV exploitable sans nécessiter de serveur HTTP actif.
- **Risque :** Fuite de données cross-tenant en cas d'omission du filtre `tenant_id`.
- **Retour arrière :** Suppression du fichier.
- **Dépendances :** Indépendant des décisions litigieuses (lecture seule).

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
- **Tests :** `test_finance_operator_access_granted`, `test_standard_admin_forbidden_on_dispute_resolution`.
- **Critère d'acceptation :** Seul un utilisateur portant l'attribut `is_finance_operator = True` peut accéder aux endpoints de litige.

### Étape 2.2 — Moteur de résolution des contestations (Cycle en 6 étapes)

- **Objectif :** Exposer l'API de traitement des litiges permettant à un opérateur financier de confirmer, corriger avec justification, ou annuler une commission litigieuse (`docs/payment/PAYMENT_DECISIONS_V1.md:71-80`).
- **Tests :** `test_dispute_resolution_creates_audit_entry_with_mandatory_reason`.
- **Critère d'acceptation :** Clôture d'un litige impossible sans saisie d'un motif textuel non vide stocké dans `financial_audit_log`.

### Étape 2.3 — Émission des relevés de commission et enregistrement des factures externes

- **Objectif :** Permettre l'agrégation mensuelle des créances `commission_receivables` en relevés de commission téléchargeables et stocker la référence de facture externe (`docs/payment/PAYMENT_DECISIONS_V1.md:143`).
- **Tests :** `test_generate_commission_statement_sums_unbilled_receivables`.
- **Critère d'acceptation :** Production d'un relevé ventilé avec archivage de la date d'émission.

### Étape 2.4 — Outils de détection du contournement et rapprochement manuel

- **Objectif :** Ajouter au script CLI des métriques de surveillance (ratio réservations annulées / prestations déclarées par partenaire, `docs/payment/PAYMENT_DECISIONS_V1.md:155`).
- **Tests :** `test_cli_flags_anomalous_cancellation_ratio`.
- **Critère d'acceptation :** Le rapport met en évidence les partenaires présentant un écart statistique significatif.

---

## 5. Découpage détaillé de la sous-livraison V1c (Politiques d'annulation et gestion des indemnités)

> **Prérequis strict :** La sous-livraison V1b doit être validée, et la date de bascule formellement arrêtée par le propriétaire.

### Étape 3.1 — Modèle des politiques d'annulation versionnées

- **Objectif :** Créer la table `cancellation_policies` (délais de gratuité, pourcentages retenus) et ajouter la colonne facultative `cancellation_policy_version_id` sur `Booking` (`backend/app/models.py:332`).
- **Tests :** `test_booking_freezes_cancellation_policy_version_at_consent`.
- **Critère d'acceptation :** La modification d'une politique n'altère pas les réservations déjà enregistrées.

### Étape 3.2 — Parcours d'annulation post-confirmation avec motifs contrôlés

- **Objectif :** Évoluer l'endpoint `POST /api/v1/bookings/{id}/cancel` (`backend/app/api/v1/endpoints/bookings.py:309`) pour permettre l'annulation encadrée après confirmation selon une liste fermée de motifs.
- **Tests :** `test_post_confirmation_cancellation_applies_policy_penalty`.
- **Critère d'acceptation :** L'annulation tardive calcule les frais retenus opposables au voyageur.

### Étape 3.3 — Déclaration des indemnités de no-show et annulation tardive

- **Objectif :** Activer les types de déclaration `late_cancellation_fee` et `no_show_fee` dans `service_declarations` avec application du taux de commission sur le montant effectivement retenu (`docs/payment/PAYMENT_DECISIONS_V1.md:88-89`).
- **Tests :** `test_commission_calculated_on_declared_no_show_fee`.
- **Critère d'acceptation :** Une déclaration d'indemnité génère la créance de commission correspondante.

### Étape 3.4 — Procédure d'arbitrage de la force majeure par opérateur

- **Objectif :** Permettre l'exonération totale de frais et de commission sur décision exclusive d'un opérateur autorisé (`docs/payment/PAYMENT_DECISIONS_V1.md:94`).
- **Tests :** `test_force_majeure_waives_cancellation_commission`.
- **Critère d'acceptation :** La qualification de force majeure annule toute créance de commission avec trace d'audit.

---

## 6. Stratégie de livraison et de revue (Pull Requests)

Deux options d'organisation des livraisons sont soumises à l'arbitrage :

- **Option A — Une Pull Request par sous-livraison complète (3 PRs : V1a, V1b, V1c) :**
  - _Avantages :_ Vision d'ensemble cohérente, intégration de bout en bout validée avant revue, réduction du nombre de fusions.
  - _Risques :_ Volume de code important par PR, revue plus dense, temps de blocage plus long avant retour.
- **Option B — Une Pull Request par étape unitaire (8 PRs pour V1a) :**
  - _Avantages :_ Revues ultra-ciblées, validation incrémentale pas à pas, risque de régression isolé à un seul composant.
  - _Risques :_ Multiplicité des branches et des étapes de revue administrative.

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

_(Cette étape sera exécutée lors du lancement effectif du chantier de code ; aucun script n'est exécuté dans ce commit documentaire)._

---

## 9. Risques techniques et plan de retour arrière global

En cas de dysfonctionnement critique constaté en recette ou en production :

1. **Désactivation par drapeau de configuration (Kill switch instantané) :**  
   Positionnement de `is_commission_enabled = False` sur `partner_profiles` ou désactivation globale dans `Tenant.config["features"]["commission"] = False`. La plateforme continue d'assurer les réservations et confirmations sans bloquer le voyageur.
2. **Réversibilité totale des schémas SQL (Alembic Downgrade) :**  
   Exécution séquentielle de `alembic downgrade 0017` puis `alembic downgrade 0016`. Les nouvelles tables financières sont supprimées proprement sans altérer les tables existantes (`bookings`, `users`, `pois`).
3. **Immuabilité garantie du domaine de réservation :**  
   Comme aucune colonne existante de `bookings` n'est renommée et qu'aucun nouvel état n'est injecté dans `Booking.status`, le moteur historique de réservation demeure 100 % opérationnel même en cas de retrait complet du module financier.

---

## 10. Critères d'acceptation du point de contrôle 2

Le passage effectif au développement logiciel ne pourra intervenir que lorsque les conditions suivantes seront réunies et validées par le propriétaire :

- [ ] Les dépendances bloquantes **D1 à D11** ont fait l'objet d'un choix formel par le propriétaire.
- [ ] Les écarts **E1 à E4** relevés dans `docs/payment/PAYMENT_COMPLIANCE.md:140-143` ont été tranchés.
- [ ] L'Étape 0 de mesure de référence des tests a été exécutée et consignée.
- [ ] Le propriétaire du projet a formulé son accord écrit explicite pour l'ouverture de la sous-livraison V1a.
