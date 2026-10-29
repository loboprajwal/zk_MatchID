use ark_bn254::Fr;
use ark_ff::PrimeField;
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::collections::HashMap;

#[derive(Deserialize)]
pub struct ProofRequest {
    pub attribute_value: u64,
    #[serde(alias = "user_secret_key")]
    pub user_secret: String,
    pub credential_expiry: u64,
    pub predicate_mode: u32,
    pub threshold_a: u64,
    pub threshold_b: u64,
    pub allowed_set: Vec<u64>,
    pub current_timestamp: u64,
    pub session_nonce: String,
    #[serde(alias = "issuer_ref")]
    pub issuer_reference: Option<String>,
}

#[derive(Serialize)]
pub struct ProofPoints {
    pub pi_a: Vec<String>,
    pub pi_b: Vec<Vec<String>>,
    pub pi_c: Vec<String>,
    pub protocol: String,
    pub curve: String,
}

#[derive(Serialize)]
pub struct ProofResponse {
    pub proof: ProofPoints,
    pub public_inputs: Vec<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub issuer_ref: Option<String>,
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
    let req = ProofRequest {
        attribute_value,
        user_secret: user_secret.to_owned(),
        credential_expiry,
        predicate_mode,
        threshold_a,
        threshold_b,
        allowed_set,
        current_timestamp,
        session_nonce: session_nonce.to_owned(),
        issuer_reference: Some(issuer_reference.to_owned()),
    };
    for (name, value) in [
        ("attribute_value", req.attribute_value),
        ("credential_expiry", req.credential_expiry),
        ("threshold_a", req.threshold_a),
        ("threshold_b", req.threshold_b),
        ("current_timestamp", req.current_timestamp),
    ] {
        if value > u32::MAX as u64 {
            return Err(format!("{name} must fit the circuit's 32-bit comparator"));
        }
    }
    if req.allowed_set.len() != 5 {
        return Err("allowed_set must contain exactly five values".into());
    }
    if !(1..=3).contains(&req.predicate_mode) {
        return Err("predicate_mode must be 1, 2, or 3".into());
    }
    if req.credential_expiry < req.current_timestamp {
        return Err("Credential is expired".into());
    }
    match req.predicate_mode {
        1 if req.attribute_value < req.threshold_a => {
            return Err("Threshold predicate not met".into())
        }
        2 if !req.allowed_set.contains(&req.attribute_value) => {
            return Err("Set membership predicate not met".into())
        }
        3 if req.threshold_b < req.attribute_value
            || req.threshold_b - req.attribute_value < req.threshold_a =>
        {
            return Err("Derived threshold predicate not met".into())
        }
        _ => {}
    }

    // Circom inputs are field elements. Domain-separate and hash UTF-8 secrets
    // and nonces into BN254 scalars so arbitrary Flutter strings are supported.
    let secret = scalar_from_string(b"zk-matchid/user-secret/v1", &req.user_secret);
    let nonce = scalar_from_string(b"zk-matchid/session-nonce/v1", &req.session_nonce);
    let mut inputs: HashMap<String, Vec<String>> = HashMap::new();
    inputs.insert(
        "attributeValue".into(),
        vec![req.attribute_value.to_string()],
    );
    inputs.insert("userSecretKey".into(), vec![secret]);
    inputs.insert(
        "credentialExpiry".into(),
        vec![req.credential_expiry.to_string()],
    );
    inputs.insert("predicateMode".into(), vec![req.predicate_mode.to_string()]);
    inputs.insert("thresholdA".into(), vec![req.threshold_a.to_string()]);
    inputs.insert("thresholdB".into(), vec![req.threshold_b.to_string()]);
    inputs.insert(
        "allowedSet".into(),
        req.allowed_set.iter().map(u64::to_string).collect(),
    );
    inputs.insert(
        "currentTimestamp".into(),
        vec![req.current_timestamp.to_string()],
    );
    inputs.insert("sessionNonce".into(), vec![nonce]);

    let zkey_path = concat!(
        env!("CARGO_MANIFEST_DIR"),
        "/assets/generic_verifier_final.zkey"
    )
    .to_string();
    let generated = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        mopro_ffi::generate_circom_proof_wtns(
            mopro_ffi::prover::ProofLib::Arkworks,
            zkey_path,
            inputs,
            mopro_ffi::witness::WitnessFn::RustWitness(crate::witness::generic_verifier_witness),
        )
    }))
    .map_err(|_| "Mopro proof generation panicked".to_string())?
    .map_err(|e| format!("Mopro proof generation failed: {e}"))?;
    let proof = mopro_ffi::to_ethereum_proof(generated.proof);
    let public_inputs = mopro_ffi::to_ethereum_inputs(generated.inputs);
    let response = ProofResponse {
        proof: ProofPoints {
            pi_a: vec![proof.a.x, proof.a.y, "1".into()],
            pi_b: vec![proof.b.x, proof.b.y, vec!["1".into(), "0".into()]],
            pi_c: vec![proof.c.x, proof.c.y, "1".into()],
            protocol: "groth16".to_string(),
            curve: "bn128".to_string(),
        },
        public_inputs,
        issuer_ref: req.issuer_reference,
    };

    serde_json::to_string(&response).map_err(|e| format!("Failed to serialize output: {}", e))
}

fn scalar_from_string(domain: &[u8], value: &str) -> String {
    let mut hasher = Sha256::new();
    hasher.update(domain);
    hasher.update((value.len() as u64).to_be_bytes());
    hasher.update(value.as_bytes());
    Fr::from_be_bytes_mod_order(&hasher.finalize()).to_string()
}

/// The legacy age-only interface used fixed placeholder proof points. Keep the
/// exported symbol for ABI compatibility, but fail closed instead of returning
/// proof-shaped mock data. Use the generic circuit API once its audited assets
/// are packaged.
pub fn generate_age_proof_internal(
    _birth_year: u32,
    _user_secret: &str,
    _current_year: u32,
    _age_limit: u32,
    _session_nonce: &str,
) -> Result<String, String> {
    Err("Legacy age proof generation is disabled; no cryptographic proof was produced.".into())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn generic_request_contract_uses_numeric_inputs_and_fixed_width_set() {
        let secret_key = "SECRET_KEY_999999";
        let attr_value = 77777u64;

        let sample_request = serde_json::json!({
            "attribute_value": attr_value,
            "user_secret_key": secret_key,
            "credential_expiry": 1900000000,
            "predicate_mode": 1,
            "threshold_a": 18,
            "threshold_b": 65,
            "allowed_set": [1, 2, 3, 4, 5],
            "current_timestamp": 1800000000,
            "session_nonce": "123456",
            "issuer_ref": Some("did:example:123")
        })
        .to_string();

        // Check 1: Ensure raw request parsing succeeds
        let req: ProofRequest = serde_json::from_str(&sample_request).unwrap();
        assert_eq!(req.user_secret, secret_key);
        assert_eq!(req.attribute_value, attr_value);
        assert_eq!(req.allowed_set.len(), 5);

        // Check 2: Verify structural output format without running full prover
        let dummy_response = ProofResponse {
            proof: ProofPoints {
                pi_a: vec!["1".into(), "2".into()],
                pi_b: vec![vec!["1".into(), "2".into()], vec!["3".into(), "4".into()]],
                pi_c: vec!["1".into(), "2".into()],
                protocol: "groth16".into(),
                curve: "bn128".into(),
            },
            public_inputs: vec!["1800000000".into(), "1900000000".into()],
            issuer_ref: req.issuer_reference,
        };

        let json_output = serde_json::to_string(&dummy_response).unwrap();

        // Explicit leakage assertions
        assert!(
            !json_output.contains(secret_key),
            "CRITICAL: Private userSecretKey leaked into output payload!"
        );
        assert!(
            !json_output.contains(&attr_value.to_string()),
            "CRITICAL: Private attributeValue leaked into output payload!"
        );
    }

    #[test]
    fn legacy_age_path_never_returns_mock_proof_points() {
        let result = generate_age_proof_internal(2000, "secret", 2026, 18, "nonce");
        assert!(result.is_err());
        assert!(result.unwrap_err().contains("no cryptographic proof"));
    }
}
