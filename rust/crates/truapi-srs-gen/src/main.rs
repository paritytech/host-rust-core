//! Emit per-domain ring-VRF prover parameters into a directory.
//!
//! Usage: `truapi-srs-gen <out-dir>`

use std::path::PathBuf;
use std::process::ExitCode;

fn main() -> ExitCode {
    let Some(out_dir) = std::env::args().nth(1).map(PathBuf::from) else {
        eprintln!("usage: truapi-srs-gen <out-dir>");
        return ExitCode::from(2);
    };

    match truapi_srs_gen::emit(&out_dir) {
        Ok(emitted) => {
            for entry in emitted {
                println!("{} {} bytes {}", entry.file, entry.bytes, entry.hash);
            }
            ExitCode::SUCCESS
        }
        Err(err) => {
            eprintln!("failed to emit ring prover parameters: {err}");
            ExitCode::FAILURE
        }
    }
}
