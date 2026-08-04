import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SimBridgeApp());
}

class SimBridgeApp extends StatelessWidget {
  const SimBridgeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Sim Bridge App',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: Colors.black,
        colorScheme: const ColorScheme.dark(
          primary: Colors.green,
          surface: Colors.black,
        ),
      ),
      home: const MainShell(),
    );
  }
}

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _selectedIndex = 2; // Default to Keypad tab

  final List<Widget> _screens = const [
    _PlaceholderTab(title: 'Messages', icon: Icons.chat_bubble_outline),
    _PlaceholderTab(title: 'Recents', icon: Icons.access_time),
    DialerScreen(),
    _PlaceholderTab(title: 'Contacts', icon: Icons.person_outline),
    _PlaceholderTab(title: 'More', icon: Icons.more_horiz),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: IndexedStack(
          index: _selectedIndex,
          children: _screens,
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (index) {
          setState(() {
            _selectedIndex = index;
          });
        },
        type: BottomNavigationBarType.fixed,
        backgroundColor: const Color(0xFF1C1C1E),
        selectedItemColor: Colors.blue,
        unselectedItemColor: Colors.grey,
        showUnselectedLabels: true,
        selectedFontSize: 11,
        unselectedFontSize: 11,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.chat_bubble_outline),
            label: 'Messages',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.access_time),
            label: 'Recents',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.dialpad),
            label: 'Keypad',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person_outline),
            label: 'Contacts',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.more_horiz),
            label: 'More',
          ),
        ],
      ),
    );
  }
}

class _PlaceholderTab extends StatelessWidget {
  const _PlaceholderTab({required this.title, required this.icon});

  final String title;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 64, color: Colors.grey.shade700),
          const SizedBox(height: 16),
          Text(
            title,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Coming soon',
            style: TextStyle(fontSize: 15, color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }
}

class DialerScreen extends StatefulWidget {
  const DialerScreen({super.key});

  @override
  State<DialerScreen> createState() => _DialerScreenState();
}

class _DialerScreenState extends State<DialerScreen> {
  String _phoneNumber = '';
  bool _isConnected = false;
  String _statusText = 'Checking Hotspot Connection...';
  Timer? _networkTimer;

  // States received from Android host (update these via WebSocket payload later)
  String sim1Carrier = "Jazz 4G";
  String sim2Carrier = "Jazz";
  bool isSim1Available = true;
  bool isSim2Available = true; // Set to false to show only 1 circular call button
  int androidBattery = 90;

  @override
  void initState() {
    super.initState();
    _checkConnection();
    _networkTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      _checkConnection();
    });
  }

  @override
  void dispose() {
    _networkTimer?.cancel();
    super.dispose();
  }

  Future<void> _checkConnection() async {
    bool connected = false;
    String status = 'Disconnected from Android Hotspot';

    try {
      final interfaces = await NetworkInterface.list(
        includeLoopback: false,
        type: InternetAddressType.IPv4,
      );

      for (var interface in interfaces) {
        for (var addr in interface.addresses) {
          if (!addr.isLoopback &&
              (addr.address.startsWith('192.168.') ||
                  addr.address.startsWith('172.20.') ||
                  addr.address.startsWith('10.'))) {
            connected = true;
            status = 'Connected (${addr.address})';
            break;
          }
        }
      }
    } catch (_) {
      status = 'Disconnected from Android Hotspot';
    }

    if (mounted) {
      setState(() {
        _isConnected = connected;
        _statusText = status;
      });
    }
  }

  void _onKeyPress(String value) {
    setState(() {
      _phoneNumber += value;
    });
  }

  void _onBackspace() {
    if (_phoneNumber.isNotEmpty) {
      setState(() {
        _phoneNumber = _phoneNumber.substring(0, _phoneNumber.length - 1);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Top Header: SIM carrier status + Android battery
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (isSim1Available)
                    Row(
                      children: [
                        const Text('1 ', style: TextStyle(color: Colors.white70, fontSize: 12)),
                        const Icon(Icons.signal_cellular_alt, color: Colors.white, size: 14),
                        const SizedBox(width: 4),
                        Text(
                          sim1Carrier,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  if (isSim2Available)
                    Padding(
                      padding: const EdgeInsets.only(top: 2.0),
                      child: Row(
                        children: [
                          const Text('2 ', style: TextStyle(color: Colors.white70, fontSize: 12)),
                          const Icon(Icons.signal_cellular_alt, color: Colors.white, size: 14),
                          const SizedBox(width: 4),
                          Text(
                            sim2Carrier,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
              Row(
                children: [
                  Text(
                    '$androidBattery%',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(
                    Icons.battery_full,
                    color: Colors.white,
                    size: 20,
                  ),
                ],
              ),
            ],
          ),
        ),

        // Connection Status Banner
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
          color: _isConnected ? Colors.green.shade900 : Colors.red.shade900,
          child: Text(
            _statusText,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white, fontSize: 11),
          ),
        ),

        // Number Display Area
        Expanded(
          child: Container(
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Expanded(
                  child: Text(
                    _phoneNumber,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 36,
                      fontWeight: FontWeight.w300,
                      color: Colors.white,
                    ),
                  ),
                ),
                if (_phoneNumber.isNotEmpty)
                  IconButton(
                    onPressed: _onBackspace,
                    icon: const Icon(Icons.backspace_outlined, color: Colors.grey),
                  ),
              ],
            ),
          ),
        ),

        // Keypad
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Column(
            children: [
              _buildKeyRow(['1', '2', '3'], ['', 'ABC', 'DEF']),
              const SizedBox(height: 16),
              _buildKeyRow(['4', '5', '6'], ['GHI', 'JKL', 'MNO']),
              const SizedBox(height: 16),
              _buildKeyRow(['7', '8', '9'], ['PQRS', 'TUV', 'WXYZ']),
              const SizedBox(height: 16),
              _buildKeyRow(['*', '0', '#'], ['', '+', '']),
              const SizedBox(height: 24),

              // Circular Call Buttons (dynamic based on SIM 2 availability)
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildCircularCallButton(
                    simLabel: '1',
                    onTap: () {
                      // TODO: send DIAL command for SIM 1
                    },
                  ),
                  if (isSim2Available) ...[
                    const SizedBox(width: 32),
                    _buildCircularCallButton(
                      simLabel: '2',
                      onTap: () {
                        // TODO: send DIAL command for SIM 2
                      },
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 30),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildKeyRow(List<String> keys, List<String> subtexts) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: List.generate(3, (index) {
        return _buildKeypadButton(keys[index], subtexts[index]);
      }),
    );
  }

  Widget _buildKeypadButton(String key, String subtext) {
    return InkWell(
      onTap: () => _onKeyPress(key),
      borderRadius: BorderRadius.circular(40),
      child: Container(
        width: 75,
        height: 75,
        decoration: BoxDecoration(
          color: Colors.grey.shade900,
          shape: BoxShape.circle,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              key,
              style: const TextStyle(
                fontSize: 28,
                color: Colors.white,
                fontWeight: FontWeight.w400,
              ),
            ),
            if (subtext.isNotEmpty)
              Text(
                subtext,
                style: const TextStyle(
                  fontSize: 10,
                  color: Colors.grey,
                  letterSpacing: 1.5,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildCircularCallButton({
    required String simLabel,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(37.5),
      child: Container(
        width: 75,
        height: 75,
        decoration: const BoxDecoration(
          color: Color(0xFF22C55E),
          shape: BoxShape.circle,
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            const Icon(
              Icons.phone,
              color: Colors.white,
              size: 36,
            ),
            Positioned(
              top: 18,
              right: 22,
              child: Text(
                simLabel,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}