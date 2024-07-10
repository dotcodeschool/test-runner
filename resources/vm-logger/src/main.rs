use std::process::{Command, Stdio};
use std::io::{BufReader, BufRead};
use std::net::TcpStream;
use std::io::Write;
use std::thread;
use std::env;

fn main() -> std::io::Result<()> {
    env_logger::init();
    let server_address = env::var("LOG_SERVER_ADDRESS").expect("LOG_SERVER_ADDRESS not set");
    
    // Start the cargo test process
    let mut child = Command::new("cargo")
        .arg("test")
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .expect("Failed to start cargo test");

    let stdout = child.stdout.take().expect("Failed to capture stdout");
    let stderr = child.stderr.take().expect("Failed to capture stderr");

    // Setup TCP connection to the log server
    let mut stream = TcpStream::connect(server_address)?;

    // Handle stdout and stderr in separate threads but write to the same TCP stream
    let mut stream_clone = stream.try_clone().expect("Failed to clone TCP stream");

    // Thread to handle stdout
    let stdout_thread = thread::spawn(move || {
        let reader = BufReader::new(stdout);
        for line in reader.lines() {
            let line = line.expect("Failed to read line from stdout");
            writeln!(stream, "stdout: {}", line).expect("Failed to write to stream");
        }
    });

    // Thread to handle stderr
    let stderr_thread = thread::spawn(move || {
        let reader = BufReader::new(stderr);
        for line in reader.lines() {
            let line = line.expect("Failed to read line from stderr");
            writeln!(stream_clone, "stderr: {}", line).expect("Failed to write to stream");
        }
    });

    // Wait for both threads to complete
    stdout_thread.join().expect("Failed to join stdout thread");
    stderr_thread.join().expect("Failed to join stderr thread");

    // Wait for the child process to finish
    child.wait()?;
    Ok(())
}
