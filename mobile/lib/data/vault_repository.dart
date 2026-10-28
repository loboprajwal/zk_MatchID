abstract interface class VaultRepository {
  Future<List<Map<String, dynamic>>> read();

  Future<List<Map<String, dynamic>>> readActivity();

  Future<Map<String, dynamic>?> readWalletConfig();

  Future<String?> readVerifiedPhone();

  Future<void> saveVerifiedPhone(String phoneNumber);

  Future<void> createWallet(String name,
      {String? mnemonicDerivedKey, bool deviceLockEnabled = true});

  Future<void> add(Map<String, dynamic> credential);

  Future<void> write(List<Map<String, dynamic>> credentials);

  Future<List<Map<String, dynamic>>> addActivity(String title, String detail);

  Future<void> wipe();

  Future<bool> isBackupSkipped();

  Future<void> setBackupSkipped(bool skipped);

  Future<bool> isBackupCompleted();

  Future<void> setBackupCompleted(bool completed);

  Future<Map<String, dynamic>> createBackupSnapshot();

  Future<void> restoreBackupSnapshot(Map<String, dynamic> snapshot);
}
