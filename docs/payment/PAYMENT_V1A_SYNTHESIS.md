# Synthèse d'Architecture et de Cadrage — Sous-livraison V1a (Paiement)

> **Document de synthèse finale :** Synthèse exécutive du lot V1a (Fondation financière autonome), arrêtée suite aux arbitrages du point de contrôle 2 du 02/11/2026.  
> **Branche de travail :** `docs/payment-decisions-v1`.  
> **Statut :** DOCUMENTATION SANS CODE (DESIGN ONLY). Aucun code applicatif, aucune migration Alembic et aucun test n'ont été modifiés.

---

## 1. Tables réellement nécessaires en V1a (Liste minimale)

La fondation financière V1a requiert strictement les 9 tables suivantes :

1. `legal_entities` : Modélise la société Discover AI au niveau plateforme (sans `tenant_id`, une seule ligne en V1 : Algérie, `country_code = "DZ"`).
2. `tenant_legal_entity_configs` : Table d'association associant chaque tenant à son entité légale (`tenant_id` UNIQUE, `legal_entity_id`, `created_at`).
3. `partner_profiles` : Identité contractuelle de l'opérateur (`tenant_id`, `legal_name`, `trade_register_number`, `tax_identification_number` chiffré AES-GCM, `country_code`, `is_commission_enabled`).
4. `partner_poi_assignments` : Rattachement daté partenaire-POI (`tenant_id`, `partner_profile_id`, `poi_id`, `valid_from`, `valid_to`).
5. `commission_rules` : Barème de commission (`tenant_id`, `partner_profile_id` optionnel, `rate_bps` entier, `valid_from`, `valid_to`, `is_active`).
6. `service_declarations` : Déclaration post-prestation (`tenant_id`, `booking_id`, `legal_entity_id`, `applied_rate_bps`, `partner_profile_id`, `partner_assignment_id`, `poi_id`, `declared_by_user_id`, `declaration_type`, `service_date`, `amount_minor`, `currency`, `tax_amount_minor`, `status`, `confirmation_deadline`, `is_current`, `correction_count`, `needs_review`).
7. `service_completions` : Prestation formellement actée (`tenant_id`, `declaration_id` UNIQUE, `legal_entity_id`, `confirmed_at`, `confirmation_source`, `final_amount_minor`, `applied_commission_bps`, `calculated_commission_minor`, `rounding_mode`).
8. `commission_receivables` : Créance due à Discover AI (`tenant_id`, `completion_id` UNIQUE, `legal_entity_id`, `partner_profile_id`, `amount_due_minor`, `currency`, `receivable_status`, `created_at`).
9. `financial_audit_log` : Journal append-only immuable (`tenant_id`, `actor_user_id`, `operator_identifier`, `actor_role`, `action`, `target_table`, `target_id`, `payload_before`, `payload_after`, `reason`, `created_at`).

---

## 2. Migrations Alembic proposées

- **Révision 0017 (`0017_financial_foundation_entities.py`) :**  
  Création des tables de structure : `legal_entities`, `tenant_legal_entity_configs`, `partner_profiles`, `partner_poi_assignments`, `commission_rules`. Réversible par suppression dans l'ordre inverse (`alembic downgrade 0016`). Identifiant de révision unique : `0017_financial_foundation_entities`.
- **Révision 0018 (`0018_backfill_tenant_country_codes.py`) :**  
  Migration de données idempotente avec identifiant de révision unique distinct (`0018_backfill_tenant_country_codes`, révisant `0017_financial_foundation_entities`), alimentant `Tenant.country_code` (`algeria` -> `"DZ"`, `morocco` -> `"MA"`) et initialisant `Tenant.config["service_confirmation_sla_hours"] = 72`.
- **Révision 0019 (`0019_service_declarations_receivables.py`) :**  
  Création des tables opérationnelles (révisant `0018_backfill_tenant_country_codes`) : `service_declarations`, `service_completions`, `commission_receivables`, `financial_audit_log`, et du trigger PostgreSQL interdisant tout `UPDATE` ou `DELETE` sur le journal d'audit. Réversible par `alembic downgrade 0018`. L'unicité stricte de chaque identifiant de révision évite tout conflit de nommage (pas de doublon 0017/0017-bis).

---

## 3. Endpoints à créer ou modifier

Tous les endpoints respectent l'en-tête obligatoire `X-Tenant-Slug` (`backend/app/core/tenant.py:1-24`).

1. `POST /api/v1/partner/bookings/{booking_id}/declare` :
   - **Acteur :** Partenaire lié au POI (`_require_declaring_partner`, excluant `is_admin == True`, vérifiant `POIManager` et `partner_poi_assignments`).
   - **Contrôles :** `Booking.status == "confirmed"`, mode `manual_confirm`, `service_date <= utcnow().date()`, plafond d'une seule correction (`correction_count < 1`), détection d'anomalie de date (`needs_review`). Fige `legal_entity_id` et `applied_rate_bps`.
2. `POST /api/v1/bookings/{booking_id}/confirm-service` :
   - **Acteur :** Voyageur propriétaire authentifié (`current_user.id == Booking.user_id`).
   - **Contrôles :** Déclaration active en statut `declared`. Le voyageur transmet et confirme explicitement la version précise de la déclaration acceptée (`declaration_id` et numéro de version/correction). Crée `service_completions` et `commission_receivables`, émet la notification `service_confirmed`.
3. `POST /api/v1/bookings/{booking_id}/dispute-service` :
   - **Acteur :** Voyageur propriétaire authentifié.
   - **Contrôles :** Délai de 72 h non échu. Saisie obligatoire de `dispute_reason`. Bascule la déclaration à `disputed` et gèle tout calcul de commission.
4. `GET /api/v1/partner/declarations/` :
   - **Acteur :** Partenaire du POI ou administrateur du tenant en consultation.
   - **Contrôles :** Filtrage strict par POI gérés.

---

## 4. Matrice finale des rôles autorisés en V1a

| Action                                    | Voyageur                   | Gérant POI (`POIManager`)                          | Administrateur Tenant (`is_admin`) | Opérateur CLI direct              |
| ----------------------------------------- | -------------------------- | -------------------------------------------------- | ---------------------------------- | --------------------------------- |
| Déclarer une prestation                   | Non                        | **Oui** (si rattaché au POI et affectation active) | **Non** (exclu en V1a, D7)         | Non (maintenance V1b)             |
| Confirmer / contester une prestation      | **Oui** (ses réservations) | Non                                                | Non                                | Non                               |
| Consulter les déclarations                | Ses réservations           | Ses POI                                            | Tout le tenant (compatible avec D7 : consultation opérationnelle des réservations et montants déclarés sans accès aux données fiscales) | Tout le tenant                    |
| Consulter les profils fiscaux partenaires | Non                        | Non                                                | **Non** (exclu en V1a, D7)         | **Oui** (CLI direct)              |
| Reporting financier (CSV)                 | Non                        | Non                                                | Non                                | **Oui** (`app.reporting_finance`) |

---

## 5. Stratégie de tests et non-régression

### 5.1 Tests existants protégés (intégrité 100 %)

- `backend/tests/test_bookings.py:285-379` : Gardes de statut sur le consentement voyageur (`test_consent_true_on_cancelled_booking_rejected`, `test_consent_true_on_confirmed_booking_rejected`, `test_consent_false_on_confirmed_booking_rejected`, etc.).
- `backend/tests/test_booking_modes.py:23-52` : Défense des modes de réservation (`test_info_only_poi_cannot_be_booked`, `test_unsupported_mode_is_rejected_defensively`, `test_booking_freezes_mode_and_sets_sla_only_for_manual_confirm`).
- `backend/tests/test_partner_manual_confirm.py:194-284` : Cycle partenaire `manual_confirm` (`test_partner_confirms_booking_sets_metadata_and_external_id`, `test_partner_declines_booking`, etc.).
- `backend/tests/test_notifications_emission.py:41-260` : Émissions de notifications et isolation tenant (`test_expire_overdue_requests_notifies_both_once_and_respects_tenant_isolation`).
- `backend/tests/test_tenant_defaults.py:1-19` : Test de repli des paramètres par défaut (`test_tenant_default_primary_color`, à étendre).
- `mobile/test/models/booking_statuses_test.dart:9` et `mobile/test/booking_flow_test.dart:113, 134`.

### 5.2 Nouveaux tests à introduire en V1a

- `backend/tests/test_financial_models.py` : Validation des schémas SQL, contraintes d'unicité et chiffrement AES-GCM.
- `backend/tests/test_country_entity_rule.py` : Blocage côté serveur si le pays du partenaire diffère de l'entité juridique.
- `backend/tests/test_service_declaration.py` : Validation de la saisie, exclusion des administrateurs, plafond d'une correction.
- `backend/tests/test_service_confirmation.py` : Calcul exact au centime près, immuabilité des créances, gel sur contestation.
- `backend/tests/test_reporting_finance_cli.py` : Export CSV en ligne de commande et respect absolu de l'isolation des tenants.

---

## 6. Contrôles de sécurité fondamentaux

1. **Isolation multi-tenant étanche :** Chaque table financière (à l'exception de l'entité plateforme globale) porte `tenant_id` avec clé étrangère non nulle. Toute requête filtre par `tenant_id` ; toute tentative cross-tenant renvoie HTTP 404 (`backend/app/dependencies.py:144-155`).
2. **Règle pays/entité côté serveur :** La vérification `partner_profile.country_code == legal_entity.country_code` est exécutée au cœur du service métier, empêchant toute facturation transfrontalière en V1a.
3. **Sécurité cryptographique :** Les numéros d'identification fiscale sont chiffrés au repos via AES-256-GCM (`CredentialCrypto`, `backend/app/services/credential_crypto.py:25-112`).
4. **Arithmétique entière exacte :** Aucun type `Float` n'est employé ; tous les montants sont en centimes (`BigInteger`) et les taux en points de base (`Integer`).
5. **Immuabilité et confidentialité du journal d'audit :** Protégée au niveau applicatif et par un trigger PostgreSQL interdisant formellement `UPDATE` et `DELETE`. Le journal d'audit `financial_audit_log` ne contient **jamais de donnée fiscale en clair** : aucun numéro fiscal (`tax_identification_number`) ni donnée sensible ne figure en clair dans `payload_before` / `payload_after`, ni dans les logs (règle absolue sans exception).

---

## 7. Points encore bloquants avant codage (Dépendances D13 à D16)

Le démarrage effectif de la phase de développement logiciel reste conditionné à l'arbitrage par le propriétaire des quatre questions ouvertes :

- **D13 :** Chemin de provisionnement des profils partenaires et règles de commission en V1a (script CLI dédié en écriture vs saisie partenaire vs base).
- **D14 :** Possibilité technique d'émettre une correction après la confirmation du voyageur (ouverte avec réapprobation vs renvoyée à V1b).
- **D15 :** Possibilité d'approbation voyageur après `expired_unconfirmed` et seuil de contrôle temporel pour `needs_review`.
- **D16 :** Admissibilité à la déclaration d'un utilisateur cumulant le rôle d'administrateur de tenant et de gestionnaire `POIManager`.
