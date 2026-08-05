import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:http/http.dart' as http;

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

class SimInfo {
  final int slot;
  final String carrier;
  final int signalLevel;

  SimInfo({required this.slot, required this.carrier, required this.signalLevel});
}

/// Manages the WebSocket connection to the Infinix host, live device
/// status (SIM/battery), and incoming/active call state.
class BridgeService extends ChangeNotifier {
  static final BridgeService instance = BridgeService._internal();
  BridgeService._internal();

  WebSocketChannel? _channel;
  bool isConnected = false;
  String hostIp = '192.168.43.1';
  int port = 8080;
  String? lastError;
  String? lastHttpTestResult;

  // Device status from Android host
  int androidBattery = 0;
  List<SimInfo> sims = [];

  // Incoming/active call tracking
  bool isRinging = false;
  bool isCallActive = false;
  String currentCallNumber = '';

  void connect({String? customIp}) {
    if (customIp != null && customIp.isNotEmpty) {
      hostIp = customIp;
    }

    lastError = null;
    _channel?.sink.close();

    try {
      final wsUrl = Uri.parse('ws://$hostIp:$port/callstream');
      _channel = WebSocketChannel.connect(wsUrl);

      _channel!.stream.listen(
        (message) {
          if (!isConnected) {
            isConnected = true;
            lastError = null;
          }
          _handleIncomingPayload(message);
          notifyListeners();
        },
        onDone: () {
          isConnected = false;
          lastError ??= 'Connection closed (onDone)';
          notifyListeners();
        },
        onError: (error) {
          lastError = error.toString();
          isConnected = false;
          notifyListeners();
        },
      );
      notifyListeners();
    } catch (e) {
      lastError = e.toString();
      isConnected = false;
      notifyListeners();
    }
  }

  /// Raw HTTP test — isolates whether the app can reach the Infinix
  /// over plain networking at all, separate from WebSocket handshake logic.
  Future<void> testHttp({String? customIp}) async {
    final ip = customIp != null && customIp.isNotEmpty ? customIp : hostIp;
    lastHttpTestResult = 'Testing http://$ip:$port/ ...';
    notifyListeners();

    try {
      final response = await http
          .get(Uri.parse('http://$ip:$port/'))
          .timeout(const Duration(seconds: 6));
      lastHttpTestResult = 'HTTP OK — status ${response.statusCode}, body length ${response.body.length}';
    } catch (e) {
      lastHttpTestResult = 'HTTP FAILED — $e';
    }
    notifyListeners();
  }

  void sendCallCommand(String phoneNumber, int simSlot) {
    if (_channel != null && isConnected) {
      final payload = jsonEncode({
        'action': 'DIAL',
        'number': phoneNumber,
        'sim_slot': simSlot,
      });
      _channel!.sink.add(payload);
    }
  }

  void answerCall() {
    if (_channel != null && isConnected) {
      _channel!.sink.add(jsonEncode({'action': 'ANSWER'}));
    }
  }

  void hangUpCall() {
    if (_channel != null && isConnected) {
      _channel!.sink.add(jsonEncode({'action': 'HANGUP'}));
    }
  }

  void _handleIncomingPayload(dynamic payload) {
    try {
      final Map<String, dynamic> data = jsonDecode(payload as String);

      if (data['type'] == 'STATUS') {
        androidBattery = data['battery'] ?? 0;
        final List<dynamic> simList = data['sims'] ?? [];
        sims = simList
            .map((s) => SimInfo(
                  slot: s['slot'] ?? 1,
                  carrier: s['carrier'] ?? 'Unknown',
                  signalLevel: s['signalLevel'] ?? -1,
                ))
            .toList()
          ..sort((a, b) => a.slot.compareTo(b.slot));
      } else if (data['type'] == 'CALL_STATE') {
        final String state = data['state'] ?? '';
        final String number = data['number'] ?? '';

        switch (state) {
          case 'RINGING':
            isRinging = true;
            isCallActive = false;
            currentCallNumber = number;
            break;
          case 'ACTIVE':
            isRinging = false;
            isCallActive = true;
            currentCallNumber = number;
            break;
          case 'DISCONNECTED':
            isRinging = false;
            isCallActive = false;
            currentCallNumber = '';
            break;
          default:
            break;
        }
      }
    } catch (e) {
      // Ignore malformed payloads
    }
  }

  void disconnect() {
    _channel?.sink.close();
    isConnected = false;
    notifyListeners();
  }
}

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _selectedIndex = 2; // Default to Keypad tab

  @override
  void initState() {
    super.initState();
    BridgeService.instance.connect();
    BridgeService.instance.addListener(_onBridgeUpdate);
  }

  @override
  void dispose() {
    BridgeService.instance.removeListener(_onBridgeUpdate);
    super.dispose();
  }

  void _onBridgeUpdate() {
    if (BridgeService.instance.isRinging && mounted) {
      _showIncomingCallDialog();
    }
  }

  void _showIncomingCallDialog() {
    if (ModalRoute.of(context)?.isCurrent != true) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AnimatedBuilder(
          animation: BridgeService.instance,
          builder: (context, _) {
            if (!BridgeService.instance.isRinging) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (Navigator.of(dialogContext).canPop()) {
                  Navigator.of(dialogContext).pop();
                }
              });
            }

            return AlertDialog(
              backgroundColor: const Color(0xFF1C1C1E),
              title: const Text(
                'Incoming Call',
                style: TextStyle(color: Colors.white),
              ),
              content: Text(
                BridgeService.instance.currentCallNumber,
                style: const TextStyle(color: Colors.white70, fontSize: 20),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    BridgeService.instance.hangUpCall();
                    Navigator.of(dialogContext).pop();
                  },
                  child: const Text('Decline', style: TextStyle(color: Colors.red)),
                ),
                TextButton(
                  onPressed: () {
                    BridgeService.instance.answerCall();
                    Navigator.of(dialogContext).pop();
                  },
                  child: const Text('Answer', style: TextStyle(color: Colors.green)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  final List<Widget> _screens = const [
    _PlaceholderTab(title: 'Messages', icon: Icons.chat_bubble_outline),
    _PlaceholderTab(title: 'Recents', icon: Icons.access_time),
    DialerScreen(),
    _PlaceholderTab(title: 'Contacts', icon: Icons.person_outline),
    SettingsScreen(),
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
            icon: Icon(Icons.settings),
            label: 'Settings',
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

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController _ipController;

  @override
  void initState() {
    super.initState();
    _ipController = TextEditingController(text: BridgeService.instance.hostIp);
  }

  @override
  void dispose() {
    _ipController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: BridgeService.instance,
      builder: (context, _) {
        final bridge = BridgeService.instance;
        return SingleChildScrollView(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Bridge Settings',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: Colors.white),
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                decoration: BoxDecoration(
                  color: bridge.isConnected ? Colors.green.shade900 : Colors.red.shade900,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  bridge.isConnected ? 'Connected to ${bridge.hostIp}' : 'Not connected',
                  style: const TextStyle(color: Colors.white),
                ),
              ),
              if (bridge.lastError != null) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade900,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'Last error: ${bridge.lastError}',
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ),
              ],
              if (bridge.lastHttpTestResult != null) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.purple.shade900,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    bridge.lastHttpTestResult!,
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ),
              ],
              const SizedBox(height: 20),
              const Text(
                'Infinix Router IP',
                style: TextStyle(color: Colors.white70, fontSize: 13),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _ipController,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: '192.168.43.91',
                  hintStyle: const TextStyle(color: Colors.grey),
                  filled: true,
                  fillColor: Colors.grey.shade900,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    final ip = _ipController.text.trim();
                    bridge.connect(customIp: ip);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Connecting to ws://$ip:${bridge.port}/callstream')),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: const Text('Reconnect (WebSocket)'),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    final ip = _ipController.text.trim();
                    bridge.testHttp(customIp: ip);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.purple,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: const Text('Test HTTP (isolate the problem)'),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Tip: On iPhone, go to Settings > Wi-Fi > (i) next to the Infinix hotspot to find the Router IP.',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
              ),
            ],
          ),
        );
      },
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

  void _onCall(int simSlot) {
    if (_phoneNumber.isEmpty) return;
    BridgeService.instance.sendCallCommand(_phoneNumber, simSlot);
  }

  IconData _signalIcon(int level) {
    switch (level) {
      case 0:
        return Icons.signal_cellular_0_bar;
      case 1:
        return Icons.signal_cellular_alt_1_bar;
      case 2:
        return Icons.signal_cellular_alt_2_bar;
      case 3:
      case 4:
        return Icons.signal_cellular_alt;
      default:
        return Icons.signal_cellular_null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: BridgeService.instance,
      builder: (context, _) {
        final bridge = BridgeService.instance;
        final sims = bridge.sims;

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: sims.isEmpty
                        ? [
                            Text(
                              bridge.isConnected ? 'No SIM data yet' : 'Not connected',
                              style: const TextStyle(color: Colors.white70, fontSize: 12),
                            ),
                          ]
                        : sims.map((sim) {
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 2.0),
                              child: Row(
                                children: [
                                  Text('${sim.slot} ', style: const TextStyle(color: Colors.white70, fontSize: 12)),
                                  Icon(_signalIcon(sim.signalLevel), color: Colors.white, size: 14),
                                  const SizedBox(width: 4),
                                  Text(
                                    sim.carrier,
                                    style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                  ),
                  Row(
                    children: [
                      Text(
                        bridge.isConnected ? '${bridge.androidBattery}%' : '--',
                        style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(width: 4),
                      const Icon(Icons.battery_full, color: Colors.white, size: 20),
                    ],
                  ),
                ],
              ),
            ),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
              color: bridge.isConnected ? Colors.green.shade900 : Colors.red.shade900,
              child: Text(
                bridge.isConnected ? 'Connected to Infinix host' : 'Disconnected — check Hotspot / IP',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 11),
              ),
            ),
            if (bridge.isCallActive)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                color: Colors.blue.shade900,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'On call: ${bridge.currentCallNumber}',
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                    ),
                    TextButton(
                      onPressed: () => bridge.hangUpCall(),
                      child: const Text('Hang Up', style: TextStyle(color: Colors.red)),
                    ),
                  ],
                ),
              ),
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
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: sims.isEmpty
                        ? [
                            _buildCircularCallButton(simLabel: '1', onTap: () => _onCall(1)),
                          ]
                        : sims.asMap().entries.expand((entry) {
                            final sim = entry.value;
                            final isLast = entry.key == sims.length - 1;
                            return [
                              _buildCircularCallButton(
                                simLabel: '${sim.slot}',
                                onTap: () => _onCall(sim.slot),
                              ),
                              if (!isLast) const SizedBox(width: 32),
                            ];
                          }).toList(),
                  ),
                  const SizedBox(height: 30),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildKeyRow(List<String> keys, List<String> subtexts) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: List.generate(3, (index) => _buildKeypadButton(keys[index], subtexts[index])),
    );
  }

  Widget _buildKeypadButton(String key, String subtext) {
    return InkWell(
      onTap: () => _onKeyPress(key),
      borderRadius: BorderRadius.circular(40),
      child: Container(
        width: 75,
        height: 75,
        decoration: BoxDecoration(color: Colors.grey.shade900, shape: BoxShape.circle),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(key, style: const TextStyle(fontSize: 28, color: Colors.white, fontWeight: FontWeight.w400)),
            if (subtext.isNotEmpty)
              Text(subtext, style: const TextStyle(fontSize: 10, color: Colors.grey, letterSpacing: 1.5)),
          ],
        ),
      ),
    );
  }

  Widget _buildCircularCallButton({required String simLabel, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(37.5),
      child: Container(
        width: 75,
        height: 75,
        decoration: const BoxDecoration(color: Color(0xFF22C55E), shape: BoxShape.circle),
        child: Stack(
          alignment: Alignment.center,
          children: [
            const Icon(Icons.phone, color: Colors.white, size: 36),
            Positioned(
              top: 18,
              right: 22,
              child: Text(simLabel, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }
}