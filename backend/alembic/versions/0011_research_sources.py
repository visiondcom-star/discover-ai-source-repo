"""research sources and collection jobs

Revision ID: 0011_research_sources
Revises: 0010_ai_quota_usage
Create Date: 2026-09-27 10:00:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa

# revision identifiers, used by Alembic.
revision: str = '0011_research_sources'
down_revision: Union[str, None] = '0010_ai_quota_usage'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # 1. tenants.country_code
    op.add_column('tenants', sa.Column('country_code', sa.String(length=2), nullable=True))
    op.create_index('ix_tenants_country_code', 'tenants', ['country_code'])

    # 2. destination_research_documents columns
    op.add_column('destination_research_documents', sa.Column('license', sa.String(length=50), nullable=True))
    op.add_column('destination_research_documents', sa.Column('attribution', sa.Text(), nullable=True))

    # 3. research_source_configs table
    op.create_table(
        'research_source_configs',
        sa.Column('id', sa.UUID(), nullable=False),
        sa.Column('tenant_id', sa.UUID(), nullable=True),
        sa.Column('country_code', sa.String(length=2), nullable=True),
        sa.Column('name', sa.String(length=100), nullable=False),
        sa.Column('url', sa.String(length=500), nullable=False),
        sa.Column('source_type', sa.String(length=20), nullable=False, server_default='office_tourisme'),
        sa.Column('enabled', sa.Boolean(), nullable=False, server_default=sa.true()),
        sa.Column('config', sa.JSON(), nullable=False, server_default='{}'),
        sa.Column('created_at', sa.DateTime(), nullable=True),
        sa.Column('updated_at', sa.DateTime(), nullable=True),
        sa.ForeignKeyConstraint(['tenant_id'], ['tenants.id'], ondelete='CASCADE'),
        sa.PrimaryKeyConstraint('id'),
    )
    op.create_index('ix_research_source_configs_tenant_id', 'research_source_configs', ['tenant_id'])
    op.create_index('ix_research_source_configs_country_code', 'research_source_configs', ['country_code'])

    # 4. research_collection_jobs table
    op.create_table(
        'research_collection_jobs',
        sa.Column('id', sa.UUID(), nullable=False),
        sa.Column('tenant_id', sa.UUID(), nullable=False),
        sa.Column('status', sa.String(length=20), nullable=False, server_default='pending'),
        sa.Column('started_at', sa.DateTime(), nullable=True),
        sa.Column('finished_at', sa.DateTime(), nullable=True),
        sa.Column('documents_fetched', sa.Integer(), nullable=False, server_default='0'),
        sa.Column('documents_new', sa.Integer(), nullable=False, server_default='0'),
        sa.Column('documents_duplicate', sa.Integer(), nullable=False, server_default='0'),
        sa.Column('documents_failed', sa.Integer(), nullable=False, server_default='0'),
        sa.Column('error_message', sa.Text(), nullable=True),
        sa.Column('params', sa.JSON(), nullable=False, server_default='{}'),
        sa.Column('created_at', sa.DateTime(), nullable=True),
        sa.ForeignKeyConstraint(['tenant_id'], ['tenants.id'], ondelete='CASCADE'),
        sa.PrimaryKeyConstraint('id'),
    )
    op.create_index('ix_research_collection_jobs_tenant_id', 'research_collection_jobs', ['tenant_id'])
    op.create_index('ix_research_collection_jobs_status', 'research_collection_jobs', ['status'])


def downgrade() -> None:
    # 4. drop research_collection_jobs
    op.drop_index('ix_research_collection_jobs_status', table_name='research_collection_jobs')
    op.drop_index('ix_research_collection_jobs_tenant_id', table_name='research_collection_jobs')
    op.drop_table('research_collection_jobs')

    # 3. drop research_source_configs
    op.drop_index('ix_research_source_configs_country_code', table_name='research_source_configs')
    op.drop_index('ix_research_source_configs_tenant_id', table_name='research_source_configs')
    op.drop_table('research_source_configs')

    # 2. drop destination_research_documents columns
    op.drop_column('destination_research_documents', 'attribution')
    op.drop_column('destination_research_documents', 'license')

    # 1. drop tenants.country_code
    op.drop_index('ix_tenants_country_code', table_name='tenants')
    op.drop_column('tenants', 'country_code')
