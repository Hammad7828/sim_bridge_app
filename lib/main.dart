import 'dart:async';
import 'dart:convert';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

void main() {
  runApp(const SimBridgeApp());
}

class SimBridgeApp extends StatelessWidget {
  const SimBridgeApp({super.key});

  static const Color _background = Color(0xFF000000);
  static const Color _surface = Color(0xFF1C1C1E);
  static const Color _dialPadButton = Color(0xFF2C2C2E);
  static const Color _callGreen = Color(0xFF34C759);
  static const Color _callRed = Color(0xFFFF3B30);
  static const Color _labelGray = Color(0xFF8E8E93);
  static const Color _textPrimary = Color(0xFFFFFFFF);

  @override
  Widget build(BuildContext context) {
    return CupertinoApp(
      title: 'SIM Bridge',
      debugShowCheckedModeBanner: false,
      theme: const CupertinoThemeData(
        brightness: Brightness.dark,
        primaryColor: _callGreen,
        scaffoldBackgroundColor: _background,
        barBackgroundColor: Color(0xFF1C1C1E),
        textTheme: CupertinoTextThemeData(
          primaryColor: _textPrimary,
          textStyle: TextStyle(
            color: _textPrimary,
            fontFamily: '.SF Pro Text',
          ),
        ),
      ),
      home: const MainShell(),
    );
  }
}

/// Bridge Service to manage local Hotspot WebSocket Connection
class BridgeService extends ChangeNotifier {
  static final BridgeService instance = BridgeService._internal();
  BridgeService._internal();

  WebSocketChannel? _channel;
  bool isConnected = false;
  String hostIp = '192.168.43.1'; // Default Android Hotspot Gateway IP
  int port = 8080;

  void connect({String? customIp}) {
    if (customIp != null && customIp.isNotEmpty) {
      hostIp = customIp;
    }

    try {
      final wsUrl = Uri.parse('ws://$hostIp:$port/callstream');
      _channel = WebSocketChannel.connect(wsUrl);

      _channel!.stream.listen(
        (message) {
          isConnected = true;
          notifyListeners();
          _handleIncomingPayload(message);
        },
        onDone: () {
          isConnected = false;
          notifyListeners();
        },
        onError: (error) {
          isConnected = false;
          notifyListeners();
        },
      );
    } catch (e) {
      isConnected = false;
      notifyListeners();
    }
  }

  void sendCallCommand(String phoneNumber, int simSlot) {
    if (_channel != null && isConnected) {
      final payload = jsonEncode({
        'action': 'DIAL',
        'number': phoneNumber,
        'sim_slot': simSlot,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      });
      _channel!.sink.add(payload);
    }
  }

  void _handleIncomingPayload(dynamic payload) {
    // Parse incoming signaling commands (e.g. RINGING, ANSWERED, ENDED)
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
  late final CupertinoTabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = CupertinoTabController(initialIndex: 3);
    // Connect to host Android Hotspot on launch
    BridgeService.instance.connect();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoTabScaffold(
      controller: _tabController,
      tabBar: CupertinoTabBar(
        backgroundColor: SimBridgeApp._surface.withValues(alpha: 0.95),
        activeColor: SimBridgeApp._callGreen,
        inactiveColor: SimBridgeApp._labelGray,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(CupertinoIcons.star),
            label: 'Favorites',
          ),
          BottomNavigationBarItem(
            icon: Icon(CupertinoIcons.clock),
            label: 'Recents',
          ),
          BottomNavigationBarItem(
            icon: Icon(CupertinoIcons.person_crop_circle),
            label: 'Contacts',
          ),
          BottomNavigationBarItem(
            icon: Icon(CupertinoIcons.circle_grid_3x3_fill),
            label: 'Keypad',
          ),
          BottomNavigationBarItem(
            icon: Icon(CupertinoIcons.settings),
            label: 'Settings',
          ),
        ],
      ),
      tabBuilder: (context, index) {
        return CupertinoTabView(
          builder: (context) {
            switch (index) {
              case 3:
                return const KeypadScreen();
              case 4:
                return const SettingsScreen();
              default:
                return const KeypadScreen();
            }
          },
        );
      },
    );
  }
}

class KeypadScreen extends StatefulWidget {
  const KeypadScreen({super.key});

  @override
  State<KeypadScreen> createState() => _KeypadScreenState();
}

class _KeypadScreenState extends State<KeypadScreen> {
  String _phoneNumber = '';

  void _onDigitPressed(String digit) {
    HapticFeedback.lightImpact();
    setState(() => _phoneNumber += digit);
  }

  void _onBackspace() {
    if (_phoneNumber.isEmpty) return;
    HapticFeedback.lightImpact();
    setState(() => _phoneNumber = _phoneNumber.substring(0, _phoneNumber.length - 1));
  }

  void _onBackspaceLongPress() {
    if (_phoneNumber.isEmpty) return;
    HapticFeedback.mediumImpact();
    setState(() => _phoneNumber = '');
  }

  void _onCall(int simSlot) {
    if (_phoneNumber.isEmpty) return;
    HapticFeedback.heavyImpact();

    // Trigger local Hotspot command to Android
    BridgeService.instance.sendCallCommand(_phoneNumber, simSlot);

    showCupertinoDialog<void>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: Text('Routing Call via SIM $simSlot'),
        content: Text('Dialing $_phoneNumber on Infinix Host...'),
        actions: [
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('End Call'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: SimBridgeApp._background,
      child: SafeArea(
        child: Column(
          children: [
            const StatusBanner(),
            const SizedBox(height: 12),
            _NumberDisplay(
              phoneNumber: _phoneNumber,
              onBackspace: _onBackspace,
              onBackspaceLongPress: _onBackspaceLongPress,
            ),
            const Spacer(),
            _DialPad(onDigitPressed: _onDigitPressed),
            const SizedBox(height: 20),
            _DualSimCallButtons(
              enabled: _phoneNumber.isNotEmpty,
              onSim1Call: () => _onCall(1),
              onSim2Call: () => _onCall(2),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}

class StatusBanner extends StatelessWidget {
  const StatusBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: BridgeService.instance,
      builder: (context, _) {
        final connected = BridgeService.instance.isConnected;
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
          color: connected
              ? SimBridgeApp._callGreen.withValues(alpha: 0.2)
              : SimBridgeApp._callRed.withValues(alpha: 0.2),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                connected ? CupertinoIcons.wifi : CupertinoIcons.wifi_exclamationmark,
                size: 14,
                color: connected ? SimBridgeApp._callGreen : SimBridgeApp._callRed,
              ),
              const SizedBox(width: 6),
              Text(
                connected
                    ? 'Connected to Android Host (${BridgeService.instance.hostIp})'
                    : 'Disconnected from Android Hotspot',
                style: TextStyle(
                  fontSize: 12,
                  color: connected ? SimBridgeApp._callGreen : SimBridgeApp._callRed,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final TextEditingController _ipController =
      TextEditingController(text: BridgeService.instance.hostIp);

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: SimBridgeApp._background,
      navigationBar: const CupertinoNavigationBar(
        middle: Text('Bridge Settings'),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Host Android Gateway IP',
                style: TextStyle(fontSize: 14, color: SimBridgeApp._labelGray),
              ),
              const SizedBox(height: 8),
              CupertinoTextField(
                controller: _ipController,
                placeholder: '192.168.43.1',
                style: const TextStyle(color: SimBridgeApp._textPrimary),
                decoration: BoxDecoration(
                  color: SimBridgeApp._surface,
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              const SizedBox(height: 16),
              CupertinoButton.filled(
                child: const Text('Reconnect'),
                onPressed: () {
                  BridgeService.instance.connect(customIp: _ipController.text);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NumberDisplay extends StatelessWidget {
  const _NumberDisplay({
    required this.phoneNumber,
    required this.onBackspace,
    required this.onBackspaceLongPress,
  });

  final String phoneNumber;
  final VoidCallback onBackspace;
  final VoidCallback onBackspaceLongPress;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: SizedBox(
        height: 56,
        child: Row(
          children: [
            Expanded(
              child: Text(
                phoneNumber.isEmpty ? 'Enter number' : phoneNumber,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: phoneNumber.length > 14 ? 28 : 36,
                  fontWeight: FontWeight.w300,
                  letterSpacing: 1.5,
                  color: phoneNumber.isEmpty
                      ? SimBridgeApp._labelGray
                      : SimBridgeApp._textPrimary,
                ),
              ),
            ),
            SizedBox(
              width: 44,
              height: 44,
              child: phoneNumber.isNotEmpty
                  ? CupertinoButton(
                      padding: EdgeInsets.zero,
                      onPressed: onBackspace,
                      child: GestureDetector(
                        onLongPress: onBackspaceLongPress,
                        child: const Icon(
                          CupertinoIcons.delete_left,
                          color: SimBridgeApp._labelGray,
                          size: 26,
                        ),
                      ),
                    )
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}

class _DialPad extends StatelessWidget {
  const _DialPad({required this.onDigitPressed});

  final ValueChanged<String> onDigitPressed;

  static const _rows = [
    [
      _DialKey('1', ''),
      _DialKey('2', 'ABC'),
      _DialKey('3', 'DEF'),
    ],
    [
      _DialKey('4', 'GHI'),
      _DialKey('5', 'JKL'),
      _DialKey('6', 'MNO'),
    ],
    [
      _DialKey('7', 'PQRS'),
      _DialKey('8', 'TUV'),
      _DialKey('9', 'WXYZ'),
    ],
    [
      _DialKey('*', ''),
      _DialKey('0', '+'),
      _DialKey('#', ''),
    ],
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: _rows.map((row) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: row.map((key) {
                return _DialPadButton(
                  digit: key.digit,
                  letters: key.letters,
                  onPressed: () => onDigitPressed(key.digit),
                );
              }).toList(),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _DialKey {
  const _DialKey(this.digit, this.letters);
  final String digit;
  final String letters;
}

class _DialPadButton extends StatelessWidget {
  const _DialPadButton({
    required this.digit,
    required this.letters,
    required this.onPressed,
  });

  final String digit;
  final String letters;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return CupertinoButton(
      padding: EdgeInsets.zero,
      onPressed: onPressed,
      child: Container(
        width: 78,
        height: 78,
        decoration: const BoxDecoration(
          color: SimBridgeApp._dialPadButton,
          shape: BoxShape.circle,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              digit,
              style: const TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.w300,
                color: SimBridgeApp._textPrimary,
                height: 1.0,
              ),
            ),
            if (letters.isNotEmpty)
              Text(
                letters,
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 2,
                  color: SimBridgeApp._textPrimary,
                  height: 1.2,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _DualSimCallButtons extends StatelessWidget {
  const _DualSimCallButtons({
    required this.enabled,
    required this.onSim1Call,
    required this.onSim2Call,
  });

  final bool enabled;
  final VoidCallback onSim1Call;
  final VoidCallback onSim2Call;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Row(
        children: [
          Expanded(
            child: _SimCallButton(
              label: 'SIM 1',
              enabled: enabled,
              onPressed: onSim1Call,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: _SimCallButton(
              label: 'SIM 2',
              enabled: enabled,
              onPressed: onSim2Call,
            ),
          ),
        ],
      ),
    );
  }
}

class _SimCallButton extends StatelessWidget {
  const _SimCallButton({
    required this.label,
    required this.enabled,
    required this.onPressed,
  });

  final String label;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final color = enabled
        ? SimBridgeApp._callGreen
        : SimBridgeApp._callGreen.withValues(alpha: 0.35);

    return CupertinoButton(
      padding: EdgeInsets.zero,
      onPressed: enabled ? onPressed : null,
      child: Container(
        height: 52,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(26),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              CupertinoIcons.phone_fill,
              color: enabled ? Colors.white : Colors.white.withValues(alpha: 0.6),
              size: 20,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: enabled ? Colors.white : Colors.white.withValues(alpha: 0.6),
              ),
            ),
          ],
        ),
      ),
    );
  }
}