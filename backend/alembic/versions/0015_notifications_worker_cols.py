"""add first_attempt_at and provider_message_id to notifications

Revision ID: 0015_notifications_worker_cols
Revises: 0014_notifications
Create Date: 2026-10-25 11:00:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa

revision: str = '0015_notifications_worker_cols'
down_revision: Union[str, None] = '0014_notifications'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column('notifications', sa.Column('first_attempt_at', sa.DateTime(), nullable=True))
    op.add_column('notifications', sa.Column('provider_message_id', sa.String(255), nullable=True))


def downgrade() -> None:
    op.drop_column('notifications', 'provider_message_id')
    op.drop_column('notifications', 'first_attempt_at')
