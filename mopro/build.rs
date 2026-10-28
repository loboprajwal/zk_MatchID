use std::{env, fs, path::PathBuf};

fn main() {
    println!("cargo:rerun-if-changed=assets/generic_verifier.wasm");
    println!("cargo:rerun-if-env-changed=MOPRO_SKIP_WITNESS_TRANSPILATION");
    if env::var_os("MOPRO_SKIP_WITNESS_TRANSPILATION").is_some() {
        println!("cargo:warning=Skipping witness transpilation by explicit request");
        return;
    }
    if env::var("TARGET").is_ok_and(|target| target.ends_with("windows-msvc")) {
        panic!("rust-witness 0.1.x passes GCC-only warning flags to MSVC. Build an Android/iOS target with its Clang toolchain, or set MOPRO_SKIP_WITNESS_TRANSPILATION=1 for a Rust-only cargo check.");
    }
    let wasm_dir = "assets".to_string();

    // rust-witness 0.1.x builds w2c2 with CMake on Windows but looks for the
    // binary one directory above CMake's Visual Studio output. Bootstrap it,
    // copy the generated executable into the expected location, then transpile.
    #[cfg(windows)]
    {
        let _ =
            std::panic::catch_unwind(|| rust_witness::transpile::transpile_wasm(wasm_dir.clone()));
        let out = PathBuf::from(env::var("OUT_DIR").expect("OUT_DIR missing"));
        let built = out.join("w2c2/build/w2c2/Debug/w2c2.exe");
        let expected_dir = out.join("w2c2/build/w2c2");
        if built.is_file() {
            fs::create_dir_all(&expected_dir).expect("Could not create w2c2 output folder");
            fs::copy(built, expected_dir.join("w2c2.exe"))
                .expect("Could not install w2c2 executable");
        }
    }

    rust_witness::transpile::transpile_wasm(wasm_dir);
}
