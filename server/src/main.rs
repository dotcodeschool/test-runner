use actix_web::{post, web::Json, App, HttpResponse, HttpServer, Responder};
use log::info;
use serde::Deserialize;

#[derive(Deserialize)]
struct RepoRequest {
    repo_name: String,
}

#[post("/schedule-test")]
async fn schedule_test(data: Json<RepoRequest>) -> impl Responder {
    let repo_name = data.repo_name.clone();
    info!("Scheduling test for repo: {}", repo_name);
    spawn_test_task(repo_name).await;
    HttpResponse::Ok().body(format!("Scheduling test for repo: {}", data.repo_name))
}

#[actix_web::main]
async fn main() -> std::io::Result<()> {
    env_logger::init();
    let port = std::env::var("PORT").unwrap_or("8080".to_string());
    info!("Starting server at port: {}", port);
    HttpServer::new(|| App::new().service(schedule_test))
        .bind(format!("127.0.0.1:{}", port))?
        .run()
        .await
}

async fn spawn_test_task(repo_name: String) {
    info!("Spawning test task for repo: {}", repo_name);
    tokio::spawn(async move {
        tokio::time::sleep(std::time::Duration::from_secs(5)).await;
        info!("Test completed for repo: {}", repo_name);
    });
}
