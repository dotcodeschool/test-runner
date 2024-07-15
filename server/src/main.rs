use actix_web::{post, web::Json, App, HttpResponse, HttpServer, Responder};
use serde::Deserialize;

#[derive(Deserialize)]
struct RepoRequest {
    repo_name: String,
}

#[post("/schedule-test")]
async fn schedule_test(data: Json<RepoRequest>) -> impl Responder {
    HttpResponse::Ok().body(format!("Scheduling test for repo: {}", data.repo_name))
}

#[actix_web::main]
async fn main() -> std::io::Result<()> {
    HttpServer::new(|| App::new().service(schedule_test))
        .bind("127.0.0.1:8080")?
        .run()
        .await
}
