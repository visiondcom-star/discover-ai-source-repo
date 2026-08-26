# TODO — chantiers planifiés

Suivi des prochains incréments décidés en revue. Chaque entrée est autonome :
contexte, portée et références de commits pour reprendre sans ré-archéologie.

## Sécurité

### [x] Web : migration token `localStorage` → cookie `HttpOnly`
- **Pourquoi** : le frontend Next.js stocke le JWT dans `localStorage`
  (`frontend/src/lib/*`, hooks `useAuth`/client API) — lisible par tout XSS.
  C'est la principale dette sécurité identifiée en revue CORS (le garde CORS
  était « cosmétique » tant que cette migration n'est pas faite).
- **Portée** : endpoint FastAPI de session/refresh avec `Set-Cookie`
  (`HttpOnly; Secure; SameSite=Strict`), suppression du stockage local côté
  SPA, stratégie CSRF (SameSite couvre l'essentiel, token double-submit non
  moins), **mobile non concerné** (token déjà en Keychain/Keystore via
  `flutter_secure_storage`).
- **Attention** : réactiver `allow_credentials=True` dans `app/main.py`
  délibérément — il a été retiré (`be33c35`) faute de cookies ; la liste
  d'origins strictes est déjà garantie en prod par le garde anti-wildcard
  (`31512ee`). Ne rien réactiver sans les deux.
- **⚠️ À vérifier lors du déploiement prod réel** : que `${DOMAIN}` et
  `${API_DOMAIN}` restent same-site (même domaine racine). Le cookie d'auth
  `SameSite=Lax` ne survivra **pas** à deux domaines racine distincts
  (ex. `app.discovery.com` vs `api.discovery.com` → cookie rejeté côté web,
  401 silencieux). À valider en pré-prod avec deux sous-domaines *différents*
  ou prévoir un `Domain=.exemple.com` explicite au `Set-Cookie`.

### [x] Backend : migration `python-jose` → `PyJWT`
- **Pourquoi** : `python-jose==3.5.0` (`f66ddf8`) corrige les CVE-2024 connues,
  mais le projet amont reste globalement non maintenu (warnings internes
  `jose/jwt.py` observés avant le bump).
- **Portée** : usage confiné à `backend/app/core/security.py`
  (encode/decode HS256) ; API quasi identique. Mettre à jour
  `requirements.txt`, relancer la suite auth complète contre Postgres réel.
- **Fait** : `PyJWT==2.13.0` (HS256 → extra `cryptography` non requis),
  `except jwt.PyJWTError` remplace `except JWTError` ; validé par la suite
  complète (83/83 contre Postgres réel) + login réel décodé (header HS256).

## Mobile Flutter

### [ ] Incrément suivant : trip generation, chat, carte
- **Contexte** : l'incrément `27abd24` a volontairement ramené l'app à
  **auth + liste POIs** ; les anciens écrans/providers (home, map, trip,
  chat) ont été supprimés avec leur code mort.
- **Repartir de** : schémas backend `trips`/`chat` (aucune divergence de
  modèle), pattern Provider + interfaces `AuthApi`/`PoisApi` injectables
  établies dans `lib/services/api_service.dart`, config via `--dart-define`
  (`API_BASE_URL`, `TENANT_SLUG`, `DEMO_EMAIL` — cf. `lib/config.dart`,
  principe n°1 CLAUDE.md : zéro tenant en dur).

### [ ] Validation sur device réel iOS/Android
- **Contexte** : aucun simulateur/émulateur disponible sur la machine de dev
  actuelle (`xcrun simctl` : section iOS vide, aucun AVD) ; la vérification
  visuelle a été faite **sur web Chrome** (login réel 200 + liste POIs +
  erreur 401, captures et journaux réseau).
- **À revalider en conditions réelles** : `flutter_secure_storage` (chiffrement
  natif Keychain/Keystore, comportement différent du stub web), permissions
  localisation, hot-reload USB.

## Backend

### [x] Résidus DZD en dur
- `mobile/lib/models/tenant.dart:28` ; `backend/app/models.py` — colonnes
  Trip/Booking/Tenant.
- **Impact** : limité — ce sont des valeurs par défaut au niveau DB, plus
  jamais atteintes en pratique côté trip generation depuis `8a95afd`.
- **Pourquoi nettoyer** : cohérence si un tenant additionnel est ajouté.
