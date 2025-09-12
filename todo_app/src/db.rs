use crate::models::{CreateTask, Task};
use sqlx::PgPool;

// Function to create a new task for a given user
pub async fn create_task(
    pool: &PgPool,
    user_id: String,
    new_task: CreateTask,
) -> Result<Task, sqlx::Error> {
    let task =
        sqlx::query_as::<_, Task>("INSERT INTO tasks (user_id, title) VALUES ($1, $2) RETURNING *")
            .bind(user_id)
            .bind(&new_task.title)
            .fetch_one(pool)
            .await?;

    Ok(task)
}

// Function to retrieve all tasks for a given user
pub async fn get_tasks_for_user(pool: &PgPool, user_id: String) -> Result<Vec<Task>, sqlx::Error> {
    let tasks = sqlx::query_as::<_, Task>(
        "SELECT * FROM tasks WHERE user_id = $1 ORDER BY created_at DESC",
    )
    .bind(user_id)
    .fetch_all(pool)
    .await?;

    Ok(tasks)
}
