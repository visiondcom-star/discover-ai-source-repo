"""partner role: poi_managers table and booking response columns

Revision ID: 0013_partner_poi_managers
Revises: 0012_booking_modes_idempotency
Create Date: 2026-10-11 09:00:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

revision: str = '0013_partner_poi_managers'
down_revision: Union[str, None] = '0012_booking_modes_idempotency'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # Rattachement « partenaire » : un utilisateur du tenant gère un POI.
    # Aucune colonne ajoutée à `users` — le rôle est externe, le JWT existant
    # reste valide. Un POI peut avoir plusieurs gestionnaires et inversement.
    op.create_table(
        'poi_managers',
        sa.Column('id', postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column('tenant_id', postgresql.UUID(as_uuid=True), sa.ForeignKey('tenants.id', ondelete='CASCADE'), nullable=False),
        sa.Column('poi_id', postgresql.UUID(as_uuid=True), sa.ForeignKey('pois.id', ondelete='CASCADE'), nullable=False),
        sa.Column('user_id', postgresql.UUID(as_uuid=True), sa.ForeignKey('users.id', ondelete='CASCADE'), nullable=False),
        sa.Column('created_at', sa.DateTime(), nullable=False, server_default=sa.text('now()')),
        sa.UniqueConstraint('tenant_id', 'poi_id', 'user_id', name='uq_poi_manager'),
    )
    # La file « demandes à traiter » filtre toujours par tenant + user (ou + poi).
    op.create_index('ix_poi_managers_user', 'poi_managers', ['tenant_id', 'user_id'])
    op.create_index('ix_poi_managers_poi', 'poi_managers', ['tenant_id', 'poi_id'])

    # Réponse du partenaire sur une réservation manual_confirm.
    op.add_column('bookings', sa.Column('partner_note', sa.Text(), nullable=True))
    op.add_column('bookings', sa.Column('responded_by', postgresql.UUID(as_uuid=True), sa.ForeignKey('users.id'), nullable=True))
    op.add_column('bookings', sa.Column('responded_at', sa.DateTime(), nullable=True))
    # Index partiel : n'indexe que les lignes réellement en attente de réponse,
    # pour servir la file de traitement et l'expiration paresseuse.
    op.create_index(
        'ix_bookings_requested_deadline',
        'bookings',
        ['tenant_id', 'respond_by'],
        postgresql_where=sa.text("status = 'requested'"),
    )


def downgrade() -> None:
    op.drop_index('ix_bookings_requested_deadline', table_name='bookings')
    op.drop_column('bookings', 'responded_at')
    op.drop_column('bookings', 'responded_by')
    op.drop_column('bookings', 'partner_note')
    op.drop_index('ix_poi_managers_poi', table_name='poi_managers')
    op.drop_index('ix_poi_managers_user', table_name='poi_managers')
    op.drop_table('poi_managers')
