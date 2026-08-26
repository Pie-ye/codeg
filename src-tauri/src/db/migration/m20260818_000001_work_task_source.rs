use sea_orm_migration::prelude::*;

#[derive(DeriveMigrationName)]
pub struct Migration;

#[async_trait::async_trait]
impl MigrationTrait for Migration {
    async fn up(&self, manager: &SchemaManager) -> Result<(), DbErr> {
        // Identify the external source that created a work task. All three
        // values are optional so existing/manual tasks remain unchanged.
        manager
            .alter_table(
                Table::alter()
                    .table(WorkTask::Table)
                    .add_column(ColumnDef::new(WorkTask::SourceKind).text().null())
                    .to_owned(),
            )
            .await?;
        manager
            .alter_table(
                Table::alter()
                    .table(WorkTask::Table)
                    .add_column(ColumnDef::new(WorkTask::SourceKey).text().null())
                    .to_owned(),
            )
            .await?;
        manager
            .alter_table(
                Table::alter()
                    .table(WorkTask::Table)
                    .add_column(ColumnDef::new(WorkTask::SourceMeta).text().null())
                    .to_owned(),
            )
            .await?;

        manager
            .create_index(
                Index::create()
                    .name("idx_work_task_source_key")
                    .table(WorkTask::Table)
                    .col(WorkTask::SourceKey)
                    .to_owned(),
            )
            .await
    }

    async fn down(&self, manager: &SchemaManager) -> Result<(), DbErr> {
        manager
            .drop_index(
                Index::drop()
                    .name("idx_work_task_source_key")
                    .table(WorkTask::Table)
                    .to_owned(),
            )
            .await?;
        manager
            .alter_table(
                Table::alter()
                    .table(WorkTask::Table)
                    .drop_column(WorkTask::SourceMeta)
                    .to_owned(),
            )
            .await?;
        manager
            .alter_table(
                Table::alter()
                    .table(WorkTask::Table)
                    .drop_column(WorkTask::SourceKey)
                    .to_owned(),
            )
            .await?;
        manager
            .alter_table(
                Table::alter()
                    .table(WorkTask::Table)
                    .drop_column(WorkTask::SourceKind)
                    .to_owned(),
            )
            .await
    }
}

#[derive(DeriveIden)]
enum WorkTask {
    Table,
    SourceKind,
    SourceKey,
    SourceMeta,
}
