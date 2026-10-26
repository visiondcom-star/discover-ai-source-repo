"""backfill existing pending notifications as skipped

Revision ID: 0016_backfill_skipped_notifs
Revises: 0015_notifications_worker_cols
Create Date: 2026-10-25 12:00:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa

revision: str = '0016_backfill_skipped_notifs'
down_revision: Union[str, None] = '0015_notifications_worker_cols'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # Les notifications créées avant l'activation du worker d'envoi d'e-mails
    # ne doivent pas être envoyées tardivement aux utilisateurs.
    op.execute(
        sa.text("UPDATE notifications SET email_status = 'skipped' WHERE email_status = 'pending'")
    )


def downgrade() -> None:
    # Sans effet : on ne peut pas deviner quelles lignes étaient à l'origine pending.
    pass
