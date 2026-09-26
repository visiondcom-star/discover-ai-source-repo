"""ai quota config and usage log

Revision ID: 0010_ai_quota_usage
Revises: 0009_tenant_ai_config
Create Date: 2026-09-26 13:22:47.215091

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa

# revision identifiers, used by Alembic.
revision: str = '0010_ai_quota_usage'
down_revision: Union[str, None] = '0009_tenant_ai_config'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table('tenant_ai_quota_configs',
        sa.Column('tenant_id', sa.UUID(), nullable=False),
        sa.Column('quota_metric', sa.String(length=16), nullable=False),
        sa.Column('monthly_limit', sa.Numeric(precision=12, scale=4), nullable=False),
        sa.Column('current_period_usage', sa.Numeric(precision=12, scale=4), nullable=False),
        sa.Column('soft_limit_threshold_pct', sa.Integer(), nullable=False),
        sa.Column('soft_limit_alert_sent', sa.Boolean(), nullable=False),
        sa.Column('hard_limit_enforced', sa.Boolean(), nullable=False),
        sa.Column('billing_cycle_anchor_day', sa.Integer(), nullable=False),
        sa.Column('current_period_start', sa.DateTime(), nullable=True),
        sa.Column('current_period_end', sa.DateTime(), nullable=False),
        sa.Column('updated_at', sa.DateTime(), nullable=True),
        sa.ForeignKeyConstraint(['tenant_id'], ['tenants.id'], ondelete='CASCADE'),
        sa.PrimaryKeyConstraint('tenant_id')
    )
    op.create_table('tenant_ai_usage_logs',
        sa.Column('id', sa.UUID(), nullable=False),
        sa.Column('tenant_id', sa.UUID(), nullable=False),
        sa.Column('user_id', sa.UUID(), nullable=True),
        sa.Column('request_id', sa.UUID(), nullable=True),
        sa.Column('provider', sa.String(length=32), nullable=False),
        sa.Column('model', sa.String(length=150), nullable=False),
        sa.Column('feature', sa.String(length=64), nullable=False),
        sa.Column('prompt_tokens', sa.Integer(), nullable=False),
        sa.Column('completion_tokens', sa.Integer(), nullable=False),
        sa.Column('cached_tokens', sa.Integer(), nullable=False),
        sa.Column('estimated_cost_usd', sa.Numeric(precision=12, scale=6), nullable=False),
        sa.Column('pricing_snapshot', sa.JSON(), nullable=False),
        sa.Column('status', sa.String(length=24), nullable=False),
        sa.Column('error_code', sa.String(length=100), nullable=True),
        sa.Column('latency_ms', sa.Integer(), nullable=True),
        sa.Column('created_at', sa.DateTime(), nullable=True),
        sa.ForeignKeyConstraint(['tenant_id'], ['tenants.id'], ondelete='CASCADE'),
        sa.PrimaryKeyConstraint('id')
    )
    op.create_index('idx_tenant_quota_period_end', 'tenant_ai_quota_configs', ['current_period_end'])
    op.create_index('idx_usage_log_tenant_date', 'tenant_ai_usage_logs', ['tenant_id', 'created_at'])
    op.create_index('idx_usage_log_feature', 'tenant_ai_usage_logs', ['tenant_id', 'feature', 'created_at'])
    op.create_index('idx_usage_log_request', 'tenant_ai_usage_logs', ['request_id'])


def downgrade() -> None:
    op.drop_index('idx_usage_log_request', table_name='tenant_ai_usage_logs')
    op.drop_index('idx_usage_log_feature', table_name='tenant_ai_usage_logs')
    op.drop_index('idx_usage_log_tenant_date', table_name='tenant_ai_usage_logs')
    op.drop_index('idx_tenant_quota_period_end', table_name='tenant_ai_quota_configs')
    op.drop_table('tenant_ai_usage_logs')
    op.drop_table('tenant_ai_quota_configs')
