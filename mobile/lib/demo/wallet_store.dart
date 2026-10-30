import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// One seeded credential document held inside a wallet (demo PII stays on device).
class WalletCredential {
  final String id;
  final String type;
  final String label;
  final String issuerId;
  final String issuerName;
  final Map<String, dynamic> subject;

  const WalletCredential({
    required this.id,
    required this.type,
    required this.label,
    required this.issuerId,
    required this.issuerName,
    required this.subject,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type,
        'label': label,
        'issuerId': issuerId,
        'issuerName': issuerName,
        'subject': subject,
      };

  factory WalletCredential.fromJson(Map<String, dynamic> json) {
    return WalletCredential(
      id: json['id'] as String,
      type: json['type'] as String,
      label: json['label'] as String,
      issuerId: json['issuerId'] as String,
      issuerName: json['issuerName'] as String,
      subject: Map<String, dynamic>.from(json['subject'] as Map),
    );
  }
}

/// Local profile fields collected during demo wallet creation.
class WalletProfile {
  String? phoneE164;
  bool otpVerified;
  String? faceImagePath;
  String? faceTemplate;
  DateTime? faceCapturedAt;

  WalletProfile({
    this.phoneE164,
    this.otpVerified = false,
    this.faceImagePath,
    this.faceTemplate,
    this.faceCapturedAt,
  });

  bool get hasPhone => phoneE164 != null && phoneE164!.isNotEmpty;
  bool get hasFace =>
      faceImagePath != null &&
      faceImagePath!.isNotEmpty &&
      faceTemplate != null &&
      faceTemplate!.isNotEmpty;

  Map<String, dynamic> toJson() => {
        'phoneE164': phoneE164,
        'otpVerified': otpVerified,
        'faceImagePath': faceImagePath,
        'faceTemplate': faceTemplate,
        'faceCapturedAt': faceCapturedAt?.toIso8601String(),
      };

  factory WalletProfile.fromJson(Map<String, dynamic>? json) {
    if (json == null) return WalletProfile();
    final captured = json['faceCapturedAt'] as String?;
    return WalletProfile(
      phoneE164: json['phoneE164'] as String?,
      otpVerified: json['otpVerified'] as bool? ?? false,
      faceImagePath: json['faceImagePath'] as String?,
      faceTemplate: json['faceTemplate'] as String?,
      faceCapturedAt:
          captured == null || captured.isEmpty ? null : DateTime.tryParse(captured),
    );
  }
}

/// A named holder wallet with its own credential set.
class DemoWallet {
  final String id;
  String name;
  final String userSecret;
  final List<WalletCredential> credentials;
  WalletProfile profile;

  DemoWallet({
    required this.id,
    required this.name,
    required this.userSecret,
    required this.credentials,
    WalletProfile? profile,
  }) : profile = profile ?? WalletProfile();

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'userSecret': userSecret,
        'credentials': credentials.map((c) => c.toJson()).toList(),
        'profile': profile.toJson(),
      };

  factory DemoWallet.fromJson(Map<String, dynamic> json) {
    return DemoWallet(
      id: json['id'] as String,
      name: json['name'] as String,
      userSecret: json['userSecret'] as String? ?? '',
      credentials: (json['credentials'] as List? ?? [])
          .map((e) => WalletCredential.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
      profile: WalletProfile.fromJson(
        json['profile'] is Map
            ? Map<String, dynamic>.from(json['profile'] as Map)
            : null,
      ),
    );
  }

  int? get birthYear {
    for (final c in credentials) {
      final y = c.subject['birthYear'];
      if (y is int) return y;
      if (y is num) return y.toInt();
    }
    return null;
  }

  int? get institutionId {
    for (final c in credentials) {
      final v = c.subject['institutionId'];
      if (v is int) return v;
      if (v is num) return v.toInt();
    }
    return null;
  }

  int? get jurisdictionCode {
    for (final c in credentials) {
      final v = c.subject['jurisdictionCode'];
      if (v is int) return v;
      if (v is num) return v.toInt();
    }
    return null;
  }
}

/// Multi-wallet store backed by SharedPreferences (demo only — not HSM-grade).
class WalletStore {
  static final WalletStore instance = WalletStore._();
  WalletStore._();

  static const _prefsKey = 'zk_match_demo_wallets_v1';
  static const _activeKey = 'zk_match_demo_active_wallet_v1';

  final List<DemoWallet> wallets = [];
  String? activeWalletId;
  bool _loaded = false;

  /// Test-only: allow re-seeding from empty prefs.
  void debugResetLoadedFlag() => _loaded = false;

  DemoWallet? get activeWallet {
    if (wallets.isEmpty) return null;
    final id = activeWalletId;
    if (id == null) return wallets.first;
    return wallets.cast<DemoWallet?>().firstWhere(
          (w) => w!.id == id,
          orElse: () => wallets.first,
        );
  }

  Future<void> ensureLoaded() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    activeWalletId = prefs.getString(_activeKey);
    if (raw == null || raw.isEmpty) {
      wallets
        ..clear()
        ..addAll(_seedWallets());
      activeWalletId = wallets.first.id;
      await _persist(prefs);
    } else {
      final list = jsonDecode(raw) as List;
      wallets
        ..clear()
        ..addAll(list.map((e) => DemoWallet.fromJson(Map<String, dynamic>.from(e as Map))));
      if (wallets.isEmpty) {
        wallets.addAll(_seedWallets());
      }
      activeWalletId ??= wallets.first.id;
    }
    _loaded = true;
  }

  Future<void> switchWallet(String id) async {
    if (!wallets.any((w) => w.id == id)) return;
    activeWalletId = id;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_activeKey, id);
  }

  Future<DemoWallet> createWallet(
    String name, {
    WalletProfile? profile,
  }) async {
    final id = 'wallet_${DateTime.now().millisecondsSinceEpoch}';
    final wallet = DemoWallet(
      id: id,
      name: name.trim().isEmpty ? 'New Wallet' : name.trim(),
      userSecret: '${DateTime.now().microsecondsSinceEpoch}',
      credentials: _defaultCredentialsFor(
        birthYear: 2001,
        institutionId: 1042,
        jurisdictionCode: 29,
        degreeLabel: 'B.Tech — Demo University',
        stateLabel: 'Resident of Karnataka (29)',
      ),
      profile: profile ?? WalletProfile(),
    );
    wallets.add(wallet);
    activeWalletId = id;
    final prefs = await SharedPreferences.getInstance();
    await _persist(prefs);
    return wallet;
  }

  Future<void> updateProfile(String walletId, WalletProfile profile) async {
    final w = wallets.cast<DemoWallet?>().firstWhere(
          (e) => e!.id == walletId,
          orElse: () => null,
        );
    if (w == null) return;
    w.profile = profile;
    final prefs = await SharedPreferences.getInstance();
    await _persist(prefs);
  }

  Future<void> renameWallet(String id, String name) async {
    final w = wallets.cast<DemoWallet?>().firstWhere((e) => e!.id == id, orElse: () => null);
    if (w == null) return;
    w.name = name.trim().isEmpty ? w.name : name.trim();
    final prefs = await SharedPreferences.getInstance();
    await _persist(prefs);
  }

  Future<void> resetToSeed() async {
    wallets
      ..clear()
      ..addAll(_seedWallets());
    activeWalletId = wallets.first.id;
    _loaded = true;
    final prefs = await SharedPreferences.getInstance();
    await _persist(prefs);
  }

  Future<void> _persist(SharedPreferences prefs) async {
    await prefs.setString(_prefsKey, jsonEncode(wallets.map((w) => w.toJson()).toList()));
    if (activeWalletId != null) {
      await prefs.setString(_activeKey, activeWalletId!);
    }
  }

  static List<DemoWallet> _seedWallets() {
    return [
      DemoWallet(
        id: 'wallet_vivek',
        name: 'Vivek Personal',
        userSecret: '11111111111111111111',
        credentials: _defaultCredentialsFor(
          birthYear: 2000,
          institutionId: 1042,
          jurisdictionCode: 29,
          degreeLabel: 'B.Tech CSE — PES University',
          stateLabel: 'Resident of Karnataka (29)',
        ),
        profile: WalletProfile(
          phoneE164: '+919876543210',
          otpVerified: true,
        ),
      ),
      DemoWallet(
        id: 'wallet_sagar',
        name: 'Sagar Work',
        userSecret: '22222222222222222222',
        credentials: _defaultCredentialsFor(
          birthYear: 1998,
          institutionId: 2087,
          jurisdictionCode: 7,
          degreeLabel: 'B.E. — VTU Affiliate',
          stateLabel: 'Resident of Delhi (7)',
        ),
        profile: WalletProfile(
          phoneE164: '+919811122233',
          otpVerified: true,
        ),
      ),
      DemoWallet(
        id: 'wallet_prajwal',
        name: 'Prajwal Uni',
        userSecret: '33333333333333333333',
        credentials: _defaultCredentialsFor(
          birthYear: 2003,
          institutionId: 1042,
          jurisdictionCode: 29,
          degreeLabel: 'B.Tech — PES University',
          stateLabel: 'Resident of Karnataka (29)',
        ),
        profile: WalletProfile(
          phoneE164: '+918022233344',
          otpVerified: true,
        ),
      ),
    ];
  }

  static List<WalletCredential> _defaultCredentialsFor({
    required int birthYear,
    required int institutionId,
    required int jurisdictionCode,
    required String degreeLabel,
    required String stateLabel,
  }) {
    return [
      WalletCredential(
        id: 'cred_aadhaar',
        type: 'Aadhaar',
        label: 'Aadhaar (DOB on file)',
        issuerId: 'did:zkmatch:gov-uidai',
        issuerName: 'UIDAI (demo)',
        subject: {
          'birthYear': birthYear,
          'dateOfBirth': '$birthYear-01-15',
          'documentType': 'Aadhaar',
        },
      ),
      WalletCredential(
        id: 'cred_degree',
        type: 'Degree',
        label: degreeLabel,
        issuerId: 'did:zkmatch:university-pes',
        issuerName: 'University Registry (demo)',
        subject: {
          'institutionId': institutionId,
          'program': 'Computer Science',
          'birthYear': birthYear,
        },
      ),
      WalletCredential(
        id: 'cred_address',
        type: 'Address',
        label: stateLabel,
        issuerId: 'did:zkmatch:municipal-bda',
        issuerName: 'Municipal Authority (demo)',
        subject: {
          'jurisdictionCode': jurisdictionCode,
          'state': stateLabel,
        },
      ),
    ];
  }
}
