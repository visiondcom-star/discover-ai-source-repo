"""Script d'administration : crée un tenant et son premier admin.

Usage (depuis le dossier backend, ou dans le conteneur backend) :

    python -m app.create_tenant --slug tunisia --name "Discover Tunisia" --language fr --currency TND --admin-email admin@example.com

Options facultatives : --languages fr,ar  --primary-color "#CE1126"
--secondary-color "#FFFFFF"  --admin-name "Nom Prénom".
Le mot de passe du premier admin est demandé de façon interactive, ou lu dans
la variable d'environnement TENANT_ADMIN_PASSWORD (usage non interactif).
"""
import argparse
import asyncio
import getpass
import os
import sys

from pydantic import ValidationError

from app import database
from app.schemas import TenantCreate
from app.services.tenant_service import TenantAlreadyExists, create_tenant_with_admin

MIN_PASSWORD_LENGTH = 8


def parse_args(argv=None):
    parser = argparse.ArgumentParser(
        description="Crée un tenant et son premier admin."
    )
    parser.add_argument("--slug", required=True)
    parser.add_argument("--name", required=True)
    parser.add_argument("--language", required=True, help="langue par défaut, ex. fr")
    parser.add_argument("--currency", required=True, help="devise par défaut, ex. TND")
    parser.add_argument("--languages", help="langues supportées, séparées par des virgules")
    parser.add_argument("--primary-color")
    parser.add_argument("--secondary-color")
    parser.add_argument("--admin-email", required=True)
    parser.add_argument("--admin-name")
    return parser.parse_args(argv)


def build_tenant_data(args) -> TenantCreate:
    fields = {
        "slug": args.slug,
        "name": args.name,
        "default_language": args.language,
        "default_currency": args.currency,
    }
    if args.languages:
        fields["supported_languages"] = [
            lang.strip() for lang in args.languages.split(",") if lang.strip()
        ]
    if args.primary_color:
        fields["primary_color"] = args.primary_color
    if args.secondary_color:
        fields["secondary_color"] = args.secondary_color
    return TenantCreate(**fields)


async def create_from_args(args, password, session_factory=None):
    # La fabrique de sessions est résolue à l'appel (utile pour les tests).
    factory = session_factory or database.AsyncSessionLocal
    data = build_tenant_data(args)
    async with factory() as session:
        return await create_tenant_with_admin(
            session, data, args.admin_email, password, args.admin_name
        )


async def _run(args, password):
    try:
        return await create_from_args(args, password)
    finally:
        await database.engine.dispose()


def main(argv=None) -> int:
    args = parse_args(argv)
    password = os.environ.get("TENANT_ADMIN_PASSWORD") or getpass.getpass(
        "Mot de passe du premier admin : "
    )
    if len(password) < MIN_PASSWORD_LENGTH:
        print(
            f"Erreur : mot de passe trop court (minimum {MIN_PASSWORD_LENGTH} caractères).",
            file=sys.stderr,
        )
        return 1
    try:
        tenant, admin = asyncio.run(_run(args, password))
    except TenantAlreadyExists:
        print(f"Erreur : le tenant « {args.slug} » existe déjà.", file=sys.stderr)
        return 1
    except ValidationError as exc:
        print(f"Erreur : paramètres invalides.\n{exc}", file=sys.stderr)
        return 1
    print(f"Tenant créé : {tenant.slug} ({tenant.id})")
    print(f"Premier admin : {admin.email}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
