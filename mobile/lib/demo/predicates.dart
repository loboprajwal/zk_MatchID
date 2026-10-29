/// Demo predicates the holder can prove without disclosing raw PII.
class DemoPredicate {
  final String id;
  final String label;
  final String description;
  final String issuerReference;
  final String claim;
  final String consentSummary;

  const DemoPredicate({
    required this.id,
    required this.label,
    required this.description,
    required this.issuerReference,
    required this.claim,
    required this.consentSummary,
  });
}

const List<DemoPredicate> kDemoPredicates = [
  DemoPredicate(
    id: 'age_18',
    label: 'Age ≥ 18',
    description: 'Prove you are at least 18 years old',
    issuerReference: 'did:zkmatch:gov-uidai',
    claim: 'Age >= 18 verified — DOB not disclosed',
    consentSummary:
        'The verifier will learn only that you are 18+. Your date of birth, Aadhaar number, and name stay private.',
  ),
  DemoPredicate(
    id: 'age_21',
    label: 'Age ≥ 21',
    description: 'Prove you are at least 21 years old',
    issuerReference: 'did:zkmatch:gov-uidai',
    claim: 'Age >= 21 verified — DOB not disclosed',
    consentSummary:
        'The verifier will learn only that you are 21+. Your date of birth and identity number stay private.',
  ),
  DemoPredicate(
    id: 'degree',
    label: 'Holds a degree',
    description: 'Prove you hold an accredited degree',
    issuerReference: 'did:zkmatch:university-pes',
    claim: 'Accredited degree possession verified — student ID not disclosed',
    consentSummary:
        'The verifier will learn only that you hold a degree from an accredited set. Student ID, grades, and transcripts stay private.',
  ),
  DemoPredicate(
    id: 'residency',
    label: 'Resident of eligible state',
    description: 'Prove residency in an eligible Indian state',
    issuerReference: 'did:zkmatch:municipal-bda',
    claim: 'Eligible state residency verified — address not disclosed',
    consentSummary:
        'The verifier will learn only that you reside in an eligible state. Full address and pin code stay private.',
  ),
];
