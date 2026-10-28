pub mod prover;
pub mod verifier;
pub mod witness;
use std::ffi::{CStr, CString};
use std::os::raw::c_char;

// -----------------------------------------------------------------------------
// High-Level Rust API / UniFFI Interface
// -----------------------------------------------------------------------------

pub fn generate_age_proof(
    birth_year: u32,
    user_secret: String,
    current_year: u32,
    age_limit: u32,
    session_nonce: String,
) -> Result<String, String> {
    prover::generate_age_proof_internal(
        birth_year,
        &user_secret,
        current_year,
        age_limit,
        &session_nonce,
    )
}

pub fn verify_age_proof(proof_json: String, verification_key: String) -> Result<bool, String> {
    verifier::verify_age_proof_internal(&proof_json, &verification_key)
}

pub fn generate_generic_proof(
    attribute_value: u64,
    user_secret: &str,
    credential_expiry: u64,
    predicate_mode: u32,
    threshold_a: u64,
    threshold_b: u64,
    allowed_set: Vec<u64>,
    current_timestamp: u64,
    session_nonce: &str,
    issuer_reference: &str,
) -> Result<String, String> {
    prover::generate_generic_proof(
        attribute_value,
        user_secret,
        credential_expiry,
        predicate_mode,
        threshold_a,
        threshold_b,
        allowed_set,
        current_timestamp,
        session_nonce,
        issuer_reference,
    )
}

pub fn verify_generic_proof(proof_json: String, verification_key: String) -> Result<bool, String> {
    verifier::verify_generic_proof_internal(&proof_json, &verification_key)
}

// -----------------------------------------------------------------------------
// C-ABI Exports for Flutter (Dart FFI)
// -----------------------------------------------------------------------------

#[no_mangle]
pub extern "C" fn ffi_generate_age_proof(
    birth_year: u32,
    user_secret: *const c_char,
    current_year: u32,
    age_limit: u32,
    session_nonce: *const c_char,
) -> *mut c_char {
    if user_secret.is_null() || session_nonce.is_null() {
        return CString::new("{\"error\": \"Null pointer provided\"}")
            .unwrap()
            .into_raw();
    }

    let secret_str = unsafe {
        match CStr::from_ptr(user_secret).to_str() {
            Ok(s) => s,
            Err(_) => {
                return CString::new("{\"error\": \"Invalid UTF-8 in secret\"}")
                    .unwrap()
                    .into_raw()
            }
        }
    };

    let nonce_str = unsafe {
        match CStr::from_ptr(session_nonce).to_str() {
            Ok(s) => s,
            Err(_) => {
                return CString::new("{\"error\": \"Invalid UTF-8 in nonce\"}")
                    .unwrap()
                    .into_raw()
            }
        }
    };

    match prover::generate_age_proof_internal(
        birth_year,
        secret_str,
        current_year,
        age_limit,
        nonce_str,
    ) {
        Ok(json) => CString::new(json).unwrap().into_raw(),
        Err(err) => {
            let err_json = format!("{{\"error\": \"{}\"}}", err);
            CString::new(err_json).unwrap().into_raw()
        }
    }
}

#[no_mangle]
pub extern "C" fn ffi_verify_age_proof(
    proof_json: *const c_char,
    verification_key: *const c_char,
) -> i32 {
    if proof_json.is_null() || verification_key.is_null() {
        return 0;
    }

    let proof_str = unsafe {
        match CStr::from_ptr(proof_json).to_str() {
            Ok(s) => s,
            Err(_) => return 0,
        }
    };

    let vkey_str = unsafe {
        match CStr::from_ptr(verification_key).to_str() {
            Ok(s) => s,
            Err(_) => return 0,
        }
    };

    match verifier::verify_age_proof_internal(proof_str, vkey_str) {
        Ok(true) => 1,
        _ => 0,
    }
}

#[no_mangle]
pub extern "C" fn ffi_free_string(s: *mut c_char) {
    if !s.is_null() {
        unsafe {
            let _ = CString::from_raw(s);
        }
    }
}

/// Request JSON uses the snake_case keys sent by Flutter's NativeBridge.
#[no_mangle]
pub extern "C" fn ffi_generate_generic_proof(request_json: *const c_char) -> *mut c_char {
    let response = if request_json.is_null() {
        serde_json::json!({"error":"Null request pointer"}).to_string()
    } else {
        let request = unsafe { CStr::from_ptr(request_json) }.to_str();
        match request {
            Err(_) => serde_json::json!({"error":"Invalid UTF-8 request"}).to_string(),
            Ok(json) => match serde_json::from_str::<prover::ProofRequest>(json) {
                Err(e) => {
                    serde_json::json!({"error":format!("Invalid generic proof request: {e}")})
                        .to_string()
                }
                Ok(r) => match generate_generic_proof(
                    r.attribute_value,
                    &r.user_secret,
                    r.credential_expiry,
                    r.predicate_mode,
                    r.threshold_a,
                    r.threshold_b,
                    r.allowed_set,
                    r.current_timestamp,
                    &r.session_nonce,
                    r.issuer_reference.as_deref().unwrap_or(""),
                ) {
                    Ok(value) => value,
                    Err(e) => serde_json::json!({"error":e}).to_string(),
                },
            },
        }
    };
    CString::new(response)
        .unwrap_or_else(|_| CString::new("{\"error\":\"Invalid response\"}").unwrap())
        .into_raw()
}

/// Returns 1 for a valid proof, 0 for an invalid proof, and -1 for malformed
/// JSON or verification-key errors. Flutter treats only 1 as success.
#[no_mangle]
pub extern "C" fn ffi_verify_generic_proof(
    proof_json: *const c_char,
    verification_key: *const c_char,
) -> i32 {
    if proof_json.is_null() || verification_key.is_null() {
        return -1;
    }
    let proof = unsafe { CStr::from_ptr(proof_json) }.to_str();
    let key = unsafe { CStr::from_ptr(verification_key) }.to_str();
    match (proof, key) {
        (Ok(p), Ok(k)) => match verifier::verify_generic_proof_internal(p, k) {
            Ok(true) => 1,
            Ok(false) => 0,
            Err(_) => -1,
        },
        _ => -1,
    }
}
