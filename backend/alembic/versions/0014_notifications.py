"""notifications table and users.locale column

Revision ID: 0014_notifications
Revises: 0013_partner_poi_managers
Create Date: 2026-10-25 10:00:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

revision: str = '0014_notifications'
down_revision: Union[str, None] = '0013_partner_poi_managers'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # 1. users.locale
    op.add_column('users', sa.Column('locale', sa.String(10), nullable=True))

    # 2. notifications table
    op.create_table(
        'notifications',
        sa.Column('id', postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column('tenant_id', postgresql.UUID(as_uuid=True), sa.ForeignKey('tenants.id', ondelete='CASCADE'), nullable=False),
        sa.Column('user_id', postgresql.UUID(as_uuid=True), sa.ForeignKey('users.id', ondelete='CASCADE'), nullable=False),
        sa.Column('type', sa.String(50), nullable=False),
        sa.Column('booking_id', postgresql.UUID(as_uuid=True), sa.ForeignKey('bookings.id', ondelete='SET NULL'), nullable=True),
        sa.Column('payload', postgresql.JSON(astext_type=sa.Text()), nullable=False, server_default='{}'),
        sa.Column('locale', sa.String(10), nullable=False, server_default='en'),
        sa.Column('created_at', sa.DateTime(), nullable=False, server_default=sa.text('now()')),
        sa.Column('read_at', sa.DateTime(), nullable=True),
        sa.Column('email_status', sa.String(20), nullable=False, server_default='pending'),
        sa.Column('email_attempts', sa.Integer(), nullable=False, server_default='0'),
        sa.Column('next_attempt_at', sa.DateTime(), nullable=True),
        sa.Column('locked_until', sa.DateTime(), nullable=True),
        sa.Column('email_sent_at', sa.DateTime(), nullable=True),
        sa.Column('last_error', sa.Text(), nullable=True),
    )

    op.create_index('ix_notifications_tenant_id', 'notifications', ['tenant_id'])
    op.create_index('ix_notifications_user_id', 'notifications', ['user_id'])
    op.create_index('ix_notifications_email_status_next_attempt', 'notifications', ['email_status', 'next_attempt_at'])
    op.create_index(
        'uq_notifications_booking_unique',
        'notifications',
        ['tenant_id', 'user_id', 'booking_id', 'type'],
        unique=True,
        postgresql_where=sa.text('booking_id IS NOT NULL'),
    )


def downgrade() -> None:
    op.drop_index('uq_notifications_booking_unique', table_name='notifications')
    op.drop_index('ix_notifications_email_status_next_attempt', table_name='notifications')
    op.drop_index('ix_notifications_user_id', table_name='notifications')
    op.drop_index('ix_notifications_tenant_id', table_name='notifications')
    op.drop_table('notifications')
    op.drop_column('users', 'locale')
