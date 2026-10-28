use ark_bn254::{Bn254, Fq, Fq2, Fr, G1Affine, G2Affine};
use ark_ff::PrimeField;
use ark_groth16::{prepare_verifying_key, Groth16};
use serde_json::Value;
use sha2::{Digest, Sha256};

pub fn verify_age_proof_internal(
    proof_json: &str,
    verification_key_json: &str,
) -> Result<bool, String> {
    verify_generic_proof_internal(proof_json, verification_key_json)
}

/// Verifies a snarkjs Groth16 proof and verification key over BN254. Public
/// signals must be in the same order as the Circom main component.
pub fn verify_generic_proof_internal(
    proof_json: &str,
    verification_key_json: &str,
) -> Result<bool, String> {
    let proof: Value =
        serde_json::from_str(proof_json).map_err(|e| format!("Invalid proof JSON: {e}"))?;
    let key: Value = serde_json::from_str(verification_key_json)
        .map_err(|e| format!("Invalid verification key JSON: {e}"))?;
    let points = proof.get("proof").unwrap_or(&proof);
    if points.get("protocol").and_then(Value::as_str) != Some("groth16") {
        return Err("Proof protocol must be groth16".into());
    }
    let curve = points
        .get("curve")
        .and_then(Value::as_str)
        .unwrap_or("bn128");
    if curve != "bn128" && curve != "bn254" {
        return Err(format!("Unsupported proof curve: {curve}"));
    }

    let pi_a = g1(&points["pi_a"])?;
    let pi_b = g2(&points["pi_b"])?;
    let pi_c = g1(&points["pi_c"])?;
    let alpha_g1 = g1(&key["vk_alpha_1"])?;
    let beta_g2 = g2(&key["vk_beta_2"])?;
    let gamma_g2 = g2(&key["vk_gamma_2"])?;
    let delta_g2 = g2(&key["vk_delta_2"])?;
    let ic_values = key["IC"]
        .as_array()
        .ok_or("Verification key is missing IC")?;
    let gamma_abc_g1 = ic_values.iter().map(g1).collect::<Result<Vec<_>, _>>()?;
    let public_values = proof
        .get("public_inputs")
        .and_then(Value::as_array)
        .ok_or("Proof is missing public_inputs")?;
    if let Some(nonce) = proof.get("session_nonce").and_then(Value::as_str) {
        let expected_nonce = scalar_from_string(b"zk-matchid/session-nonce/v1", nonce);
        if public_values.get(10).and_then(Value::as_str) != Some(expected_nonce.as_str()) {
            return Ok(false);
        }
    }
    let public_inputs = public_values
        .iter()
        .map(fr_value)
        .collect::<Result<Vec<_>, _>>()?;
    if gamma_abc_g1.len() != public_inputs.len() + 1 {
        return Err(format!(
            "Verification key expects {} public inputs, received {}",
            gamma_abc_g1.len().saturating_sub(1),
            public_inputs.len()
        ));
    }

    let pvk = prepare_verifying_key(&ark_groth16::VerifyingKey::<Bn254> {
        alpha_g1,
        beta_g2,
        gamma_g2,
        delta_g2,
        gamma_abc_g1,
    });
    let proof = ark_groth16::Proof::<Bn254> {
        a: pi_a,
        b: pi_b,
        c: pi_c,
    };
    Groth16::<Bn254>::verify_proof(&pvk, &proof, &public_inputs)
        .map_err(|e| format!("Groth16 verification failed: {e}"))
}

fn coords(v: &Value, n: usize) -> Result<Vec<Fq>, String> {
    let a = v.as_array().ok_or("Malformed proof point")?;
    if a.len() < n {
        return Err("Malformed proof point coordinates".into());
    }
    a.iter().take(n).map(fq_value).collect()
}
fn g1(v: &Value) -> Result<G1Affine, String> {
    let c = coords(v, 2)?;
    let p = G1Affine::new_unchecked(c[0], c[1]);
    if !p.is_on_curve() || !p.is_in_correct_subgroup_assuming_on_curve() {
        return Err("G1 point is not on BN254".into());
    }
    Ok(p)
}
fn g2(v: &Value) -> Result<G2Affine, String> {
    let a = v.as_array().ok_or("Malformed G2 point")?;
    if a.len() < 2 {
        return Err("Malformed G2 point coordinates".into());
    }
    // snarkjs and Mopro serialize the Fq2 limbs as [c0, c1].
    let x = a[0].as_array().ok_or("Malformed G2 x coordinate")?;
    let y = a[1].as_array().ok_or("Malformed G2 y coordinate")?;
    if x.len() < 2 || y.len() < 2 {
        return Err("Malformed G2 coordinate limbs".into());
    }
    let p = G2Affine::new_unchecked(
        Fq2::new(fq_value(&x[0])?, fq_value(&x[1])?),
        Fq2::new(fq_value(&y[0])?, fq_value(&y[1])?),
    );
    if !p.is_on_curve() || !p.is_in_correct_subgroup_assuming_on_curve() {
        return Err("G2 point is not on BN254".into());
    }
    Ok(p)
}
fn parse_field<F: PrimeField>(s: &str) -> Result<F, String> {
    let (digits, radix) = s.strip_prefix("0x").map(|x| (x, 16u64)).unwrap_or((s, 10));
    if digits.is_empty() {
        return Err("Empty field element".into());
    }
    digits.chars().try_fold(F::ZERO, |acc, c| {
        let d = c
            .to_digit(radix as u32)
            .ok_or_else(|| format!("Invalid field element: {s}"))?;
        Ok(acc * F::from(radix) + F::from(d as u64))
    })
}
fn fq_value(v: &Value) -> Result<Fq, String> {
    let s = v
        .as_str()
        .map(str::to_owned)
        .or_else(|| v.as_u64().map(|n| n.to_string()))
        .ok_or("Invalid point coordinate")?;
    parse_field(&s)
}
fn fr_value(v: &Value) -> Result<Fr, String> {
    let s = v
        .as_str()
        .map(str::to_owned)
        .or_else(|| v.as_u64().map(|n| n.to_string()))
        .ok_or("Invalid public input")?;
    parse_field(&s)
}

fn scalar_from_string(domain: &[u8], value: &str) -> String {
    let mut hasher = Sha256::new();
    hasher.update(domain);
    hasher.update((value.len() as u64).to_be_bytes());
    hasher.update(value.as_bytes());
    Fr::from_be_bytes_mod_order(&hasher.finalize()).to_string()
}
