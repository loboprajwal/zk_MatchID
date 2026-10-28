/// A relying-party verification policy selectable on the Verifier screen.
///
/// The [id] is the stable `predicateType` key carried inside every proof
/// payload, so the Prover's proof templates and the Verifier's policies always
/// agree on what a payload attests. Nothing about the private attribute is
/// transmitted — only the boolean outcome of the selected predicate.
class VerificationPolicy {
  /// Stable identifier shared with `ProofPayload.predicateType`.
  final String id;

  /// Human readable policy name (e.g. `Age >= 18`).
  final String label;

  /// Real-world scenario the policy targets.
  final String scenario;

  /// Result card title rendered after successful evaluation.
  final String successTitle;

  const VerificationPolicy({
    required this.id,
    required this.label,
    required this.scenario,
    required this.successTitle,
  });
}

/// Preset verification profiles of the generic multi-predicate engine.
const List<VerificationPolicy> kVerificationPolicies = [
  VerificationPolicy(
    id: 'age_18',
    label: 'Age >= 18',
    scenario: 'Nightlife, hospitality & age-restricted venues',
    successTitle: 'VERIFIED: Age >= 18 ✓',
  ),
  VerificationPolicy(
    id: 'income_solvency',
    label: 'Income Solvency',
    scenario: 'Apartment rentals & loan pre-qualification',
    successTitle: 'VERIFIED: Income Solvency Met ✓',
  ),
  VerificationPolicy(
    id: 'student_status',
    label: 'Student Status',
    scenario: 'Student discounts, campus perks & software access',
    successTitle: 'VERIFIED: Active Student Status ✓',
  ),
  VerificationPolicy(
    id: 'regional_residency',
    label: 'Regional Residency',
    scenario: 'Civic subsidies, regional voting & public transport',
    successTitle: 'VERIFIED: Eligible Regional Residency ✓',
  ),
];

/// Looks up a policy by its stable [VerificationPolicy.id].
VerificationPolicy? verificationPolicyById(String id) {
  for (final policy in kVerificationPolicies) {
    if (policy.id == id) return policy;
  }
  return null;
}

/// Human readable description of an unknown/foreign `predicateType` value.
String describePredicateType(String id) {
  final policy = verificationPolicyById(id);
  return policy != null ? '"${policy.label}" ($id)' : '"$id"';
}
