import 'package:flutter/material.dart';

import 'screens/upi/prove_tab.dart';
import 'screens/upi/verify_tab.dart';
import 'screens/upi/wallets_tab.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ZkMatchIdApp());
}

class ZkMatchIdApp extends StatelessWidget {
  const ZkMatchIdApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'zk-MatchID',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.indigo,
          brightness: Brightness.light,
        ),
      ),
      home: const UpiDemoHome(),
    );
  }
}

/// UPI-like three-tab shell: Wallets | Prove | Verify.
class UpiDemoHome extends StatefulWidget {
  const UpiDemoHome({super.key});

  @override
  State<UpiDemoHome> createState() => _UpiDemoHomeState();
}

class _UpiDemoHomeState extends State<UpiDemoHome> {
  int _index = 0;

  final _tabs = const [
    WalletsTab(),
    ProveTab(),
    VerifyTab(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: _tabs,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.account_balance_wallet_outlined),
            selectedIcon: Icon(Icons.account_balance_wallet),
            label: 'Wallets',
          ),
          NavigationDestination(
            icon: Icon(Icons.qr_code_2_outlined),
            selectedIcon: Icon(Icons.qr_code_2),
            label: 'Prove',
          ),
          NavigationDestination(
            icon: Icon(Icons.document_scanner_outlined),
            selectedIcon: Icon(Icons.document_scanner),
            label: 'Verify',
          ),
        ],
      ),
    );
  }
}
