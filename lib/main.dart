import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'ui/theme/app_theme.dart';
import 'features/donate/support_molstr.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(child: MolStrApp()));
}

class MolStrApp extends StatelessWidget {
  const MolStrApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MolStr',
      debugShowCheckedModeBanner: false,
      theme: MolStrTheme.light(),
      darkTheme: MolStrTheme.dark(),
      themeMode: ThemeMode.dark,
      home: const MolStrShell(),
    );
  }
}

class MolStrShell extends StatefulWidget {
  const MolStrShell({super.key});

  @override
  State<MolStrShell> createState() => _MolStrShellState();
}

class _MolStrShellState extends State<MolStrShell> {
  int _currentIndex = 0;

  final _titles = const ['Home', 'Games', 'Notifications', 'Wallet', 'Profile'];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: MolStrColors.purple,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Center(
                child: Text(
                  'M',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Text(
              _titles[_currentIndex],
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Support MolStr',
            icon: const Icon(Icons.favorite, color: MolStrColors.lightPurple),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SupportMolStrPage()),
              );
            },
          ),
        ],
      ),
      body: IndexedStack(
        index: _currentIndex,
        children: const [
          Center(child: Text('Home Feed\n(Notes, Likes, Reposts, Zaps, Tips)', textAlign: TextAlign.center)),
          Center(child: Text('Nostr Games Showcase\n(NIP-89 Kind 31990 Discovery)', textAlign: TextAlign.center)),
          Center(child: Text('Notifications', textAlign: TextAlign.center)),
          Center(child: Text('Wallet\n(NWC Bitcoin Zaps + Monero Tips)', textAlign: TextAlign.center)),
          ProfilePlaceholderTab(),
        ],
      ),
      floatingActionButton: _currentIndex == 0
          ? FloatingActionButton(
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Note composer coming next slice')),
                );
              },
              child: const Icon(Icons.add),
            )
          : null,
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
          BottomNavigationBarItem(icon: Icon(Icons.sports_esports), label: 'Games'),
          BottomNavigationBarItem(icon: Icon(Icons.notifications), label: 'Notifs'),
          BottomNavigationBarItem(icon: Icon(Icons.account_balance_wallet), label: 'Wallet'),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Profile'),
        ],
      ),
    );
  }
}

class ProfilePlaceholderTab extends StatelessWidget {
  const ProfilePlaceholderTab({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircleAvatar(
            radius: 36,
            backgroundColor: MolStrColors.purple,
            child: Icon(Icons.person, size: 40, color: Colors.white),
          ),
          const SizedBox(height: 12),
          const Text(
            'MolStr',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          const Text(
            'MolStr@rizful.com',
            style: TextStyle(color: MolStrColors.lightPurple),
          ),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SupportMolStrPage()),
              );
            },
            icon: const Icon(Icons.favorite),
            label: const Text('Support MolStr Project'),
          ),
        ],
      ),
    );
  }
}