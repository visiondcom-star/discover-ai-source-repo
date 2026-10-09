"""booking modes per POI and idempotent booking creation

Revision ID: 0012_booking_modes_idempotency
Revises: 0011_research_sources
Create Date: 2026-10-09 20:00:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa

revision: str = '0012_booking_modes_idempotency'
down_revision: Union[str, None] = '0011_research_sources'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # Mode de réservation du POI. 'request' = comportement actuel (réservable, consentement).
    op.add_column('pois', sa.Column('booking_mode', sa.String(length=20), nullable=False, server_default='request'))

    # Réservation : mode figé à la création + SLA de réponse + idempotence.
    op.add_column('bookings', sa.Column('booking_mode', sa.String(length=20), nullable=False, server_default='request'))
    op.add_column('bookings', sa.Column('respond_by', sa.DateTime(), nullable=True))
    op.add_column('bookings', sa.Column('idempotency_key', sa.String(length=80), nullable=True))
    op.add_column('bookings', sa.Column('request_hash', sa.String(length=64), nullable=True))
    # PostgreSQL : plusieurs NULL autorisés → les réservations sans clé ne sont jamais en conflit.
    op.create_unique_constraint('uq_bookings_idempotency', 'bookings', ['tenant_id', 'user_id', 'idempotency_key'])


def downgrade() -> None:
    op.drop_constraint('uq_bookings_idempotency', 'bookings', type_='unique')
    op.drop_column('bookings', 'request_hash')
    op.drop_column('bookings', 'idempotency_key')
    op.drop_column('bookings', 'respond_by')
    op.drop_column('bookings', 'booking_mode')
    op.drop_column('pois', 'booking_mode')
