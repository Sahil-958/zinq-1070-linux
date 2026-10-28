import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';

void main() {
  runApp(const ZinqMouseApp());
}

class ZinqMouseApp extends StatefulWidget {
  const ZinqMouseApp({super.key});

  @override
  State<ZinqMouseApp> createState() => _ZinqMouseAppState();
}

class _ZinqMouseAppState extends State<ZinqMouseApp> {
  Color _themeAccent = const Color(0xFFD0BCFF);

  void updateThemeAccent(Color newColor) {
    setState(() => _themeAccent = newColor);
  }

  @override
  Widget build(BuildContext context) {
    const Color bgVoid = Color(0xFF0C0D12);
    const Color m3Surface = Color(0xFF13151D);
    const Color m3SurfaceContainer = Color(0xFF181B24);
    const Color m3SurfaceHigh = Color(0xFF222532);

    final colorScheme = ColorScheme.dark(
      primary: _themeAccent,
      onPrimary: Colors.black,
      primaryContainer: _themeAccent.withOpacity(0.25),
      onPrimaryContainer: _themeAccent,
      surface: m3Surface,
      surfaceContainer: m3SurfaceContainer,
      surfaceContainerHigh: m3SurfaceHigh,
      outline: const Color(0xFF323648),
      error: const Color(0xFFF28B82),
    );

    return MaterialApp(
      title: 'Zinq ZQGM-1070',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: bgVoid,
        colorScheme: colorScheme,
        fontFamily: 'Roboto',
      ),
      home: MouseControllerScreen(
        accentColor: _themeAccent,
        onAccentChanged: updateThemeAccent,
      ),
    );
  }
}

class MouseControllerScreen extends StatefulWidget {
  final Color accentColor;
  final ValueChanged<Color> onAccentChanged;

  const MouseControllerScreen({
    super.key,
    required this.accentColor,
    required this.onAccentChanged,
  });

  @override
  State<MouseControllerScreen> createState() => _MouseControllerScreenState();
}

class _MouseControllerScreenState extends State<MouseControllerScreen>
    with SingleTickerProviderStateMixin {
  bool _isLoading = true;
  bool _isConnected = false;
  bool _isPolling = false;
  String _devPath = 'Searching...';
  String _ledMode = 'slow';
  int _currentStage = 0;
  List<int> _stages = [1200, 1600, 2400, 3200];
  int _fireSpeed = 50;

  String _selectedButton = '1';
  String? _hoveredButton;

  Map<String, String> _buttons = {
    '1': 'left',
    '2': 'right',
    '3': 'middle',
    '4': 'dpiloop',
    '5': 'forward',
    '6': 'back',
  };

  final Map<String, String> _buttonNames = {
    '1': 'Left Trigger',
    '2': 'Right Trigger',
    '3': 'Scroll / Middle',
    '4': 'DPI Switch',
    '5': 'Thumb Forward',
    '6': 'Thumb Backward',
  };

  final List<int> _dpiChoices = [1200, 1600, 2000, 2400, 3200];

  // Hardware Backlight Color Palette linked to physical stages
  final List<Map<String, dynamic>> _staticColors = [
    {
      'id': 'blue',
      'name': 'Electric Blue',
      'color': const Color(0xFF80D8FF),
      'stage': 0,
      'dpi': 1200,
    },
    {
      'id': 'pink',
      'name': 'Neon Pink',
      'color': const Color(0xFFFF80AB),
      'stage': 1,
      'dpi': 1600,
    },
    {
      'id': 'red',
      'name': 'Crimson Red',
      'color': const Color(0xFFFF5252),
      'stage': 2,
      'dpi': 2400,
    },
    {
      'id': 'purple',
      'name': 'Cyber Purple',
      'color': const Color(0xFFD0BCFF),
      'stage': 3,
      'dpi': 3200,
    },
  ];

  final Map<String, List<Map<String, dynamic>>> _actionCategories = {
    'Mouse Commands': [
      {'id': 'left', 'name': 'Left Click', 'icon': Icons.touch_app_rounded},
      {'id': 'right', 'name': 'Right Click', 'icon': Icons.ads_click_rounded},
      {'id': 'middle', 'name': 'Middle Click', 'icon': Icons.radio_button_checked_rounded},
      {'id': 'forward', 'name': 'Forward', 'icon': Icons.arrow_forward_rounded},
      {'id': 'back', 'name': 'Back', 'icon': Icons.arrow_back_rounded},
      {'id': 'dpiloop', 'name': 'DPI Cycle', 'icon': Icons.tune_rounded},
      {'id': 'fire', 'name': 'Rapid Fire', 'icon': Icons.bolt_rounded},
    ],
    'Media Functions': [
      {'id': 'volup', 'name': 'Volume +', 'icon': Icons.volume_up_rounded},
      {'id': 'voldown', 'name': 'Volume -', 'icon': Icons.volume_down_rounded},
      {'id': 'mute', 'name': 'Mute Audio', 'icon': Icons.volume_off_rounded},
      {'id': 'playpause', 'name': 'Play / Pause', 'icon': Icons.play_arrow_rounded},
      {'id': 'next', 'name': 'Next Track', 'icon': Icons.skip_next_rounded},
      {'id': 'prev', 'name': 'Prev Track', 'icon': Icons.skip_previous_rounded},
    ],
    'System Actions': [
      {'id': 'desktop', 'name': 'Show Desktop', 'icon': Icons.desktop_windows_rounded},
      {'id': 'browser', 'name': 'Open Browser', 'icon': Icons.language_rounded},
      {'id': 'disabled', 'name': 'Disable Key', 'icon': Icons.block_rounded},
      {'id': 'default', 'name': 'Default Func', 'icon': Icons.restore_rounded},
    ],
  };

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.18, end: 0.85).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _loadDeviceState();

    // Periodically poll live hardware state for physical DPI key clicks
    _pollTimer = Timer.periodic(const Duration(milliseconds: 400), (_) {
      if (mounted) {
        _pollLiveDeviceState();
      }
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  void _updatePulseDuration() {
    if (_ledMode == 'fast') {
      _pulseController.duration = const Duration(milliseconds: 900);
    } else if (_ledMode == 'slow') {
      _pulseController.duration = const Duration(milliseconds: 2400);
    } else {
      _pulseController.duration = const Duration(milliseconds: 2400);
    }
    if (_ledMode != 'off' && !_pulseController.isAnimating) {
      _pulseController.repeat(reverse: true);
    }
  }

  static String get _zinqBinary {
    final home = Platform.environment['HOME'] ?? '/home/sawhill';
    final localBin = '$home/.local/bin/zinq-mouse';
    if (File(localBin).existsSync()) return localBin;
    final repoBin = '$home/repos/zinq-1070-linux/bin/zinq-mouse';
    if (File(repoBin).existsSync()) return repoBin;
    return 'zinq-mouse';
  }

  static int _toHardwareButtonId(String guiId) {
    switch (guiId) {
      case '1': return 1; // Left Trigger -> HW 1
      case '2': return 3; // Right Trigger -> HW 3
      case '3': return 2; // Scroll Wheel -> HW 2
      case '4': return 6; // DPI Switch -> HW 6
      case '5': return 4; // Side Forward -> HW 4
      case '6': return 5; // Side Back -> HW 5
      default: return int.tryParse(guiId) ?? 1;
    }
  }

  Future<void> _runZinqCmd(List<String> args) async {
    try {
      await Process.run(_zinqBinary, args);
    } catch (e) {
      debugPrint('Failed to execute $_zinqBinary $args: $e');
    }
  }

  Future<void> _loadDeviceState() async {
    setState(() => _isLoading = true);
    try {
      final res = await Process.run(_zinqBinary, ['status', '--json']);

      if (res.exitCode == 0 && res.stdout.toString().isNotEmpty) {
        final data = jsonDecode(res.stdout.toString());
        final int curStg = data['current_stage'] ?? 0;
        setState(() {
          _isConnected = data['connected'] ?? false;
          _devPath = data['device_path'] ?? 'Disconnected';
          _currentStage = curStg;
          _stages = List<int>.from(data['stages'] ?? [1200, 1600, 2400, 3200]);
          _ledMode = data['led_mode'] ?? 'slow';
          _fireSpeed = data['fire_time_ms'] ?? 50;
          if (data['buttons'] != null) {
            final hw = Map<String, dynamic>.from(data['buttons']);
            _buttons = {
              '1': hw['1']?.toString() ?? 'left',
              '2': hw['3']?.toString() ?? 'right',
              '3': hw['2']?.toString() ?? 'middle',
              '4': hw['6']?.toString() ?? 'dpiloop',
              '5': hw['4']?.toString() ?? 'forward',
              '6': hw['5']?.toString() ?? 'back',
            };
          }
          _isLoading = false;
        });

        // Sync theme accent with active physical stage color
        if (curStg < _staticColors.length) {
          final matchedColor = _staticColors.firstWhere(
            (c) => c['stage'] == curStg,
            orElse: () => _staticColors[0],
          );
          widget.onAccentChanged(matchedColor['color'] as Color);
        }

        _updatePulseDuration();
      } else {
        setState(() {
          _isConnected = false;
          _devPath = 'Disconnected';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _isConnected = false;
        _isLoading = false;
      });
    }
  }

  Future<void> _pollLiveDeviceState() async {
    try {
      final res = await Process.run(_zinqBinary, ['status', '--json']);

      if (res.exitCode == 0 && res.stdout.toString().isNotEmpty) {
        final data = jsonDecode(res.stdout.toString());
        final int hwStage = data['current_stage'] ?? 0;
        final String hwMode = data['led_mode'] ?? 'slow';
        final List<int> hwStages = List<int>.from(data['stages'] ?? [1200, 1600, 2400, 3200]);

        bool stageChanged = (hwStage != _currentStage);
        bool modeChanged = (hwMode != _ledMode);
        bool stagesChanged = (_stages.length != hwStages.length ||
            List.generate(_stages.length, (i) => _stages[i] != hwStages[i]).contains(true));

        if (stageChanged || modeChanged || stagesChanged) {
          setState(() {
            _currentStage = hwStage;
            _ledMode = hwMode;
            _stages = hwStages;
          });

          if (stageChanged && hwStage < _staticColors.length) {
            final matchedColor = _staticColors.firstWhere(
              (c) => c['stage'] == hwStage,
              orElse: () => _staticColors[0],
            );
            widget.onAccentChanged(matchedColor['color'] as Color);
          }

          _updatePulseDuration();
        }
      }
    } catch (_) {}
  }

  Future<void> _manualPoll() async {
    setState(() => _isPolling = true);
    await _pollLiveDeviceState();
    await _loadDeviceState();
    setState(() => _isPolling = false);
    _showToast('Hardware queried: Stage ${_currentStage + 1} (${_stages[_currentStage]} DPI) · LED ${_ledMode.toUpperCase()}');
  }

  void _showToast(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: TextStyle(
            color: isError ? Colors.white : Colors.black,
            fontWeight: FontWeight.w600,
          ),
        ),
        backgroundColor: isError ? const Color(0xFFF28B82) : widget.accentColor,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _setLedMode(String mode) async {
    setState(() => _ledMode = mode);
    _updatePulseDuration();
    await _runZinqCmd(['led', mode]);
    _showToast('Lighting effect set to ${mode.toUpperCase()}');
  }

  Future<void> _selectStaticColor(Map<String, dynamic> colorItem) async {
    final int targetStage = colorItem['stage'] as int;
    final Color chosenColor = colorItem['color'] as Color;
    final String colorName = colorItem['name'] as String;

    widget.onAccentChanged(chosenColor);
    setState(() {
      _currentStage = targetStage;
      _ledMode = 'static';
    });

    await _runZinqCmd(['stage', '${targetStage + 1}']);
    await _runZinqCmd(['led', 'static']);
    _showToast('Hardware LED set to $colorName (Static Solid)');
  }

  Future<void> _setStage(int stageIndex) async {
    setState(() => _currentStage = stageIndex);

    // Sync theme accent with the stage's physical color
    final matchedColor = _staticColors.firstWhere(
      (c) => c['stage'] == stageIndex,
      orElse: () => _staticColors[0],
    );
    widget.onAccentChanged(matchedColor['color'] as Color);

    await _runZinqCmd(['stage', '${stageIndex + 1}']);
    _showToast('Switched to Stage ${stageIndex + 1} (${_stages[stageIndex]} DPI)');
  }

  Future<void> _setStageDpi(int stageIndex, int dpi) async {
    setState(() {
      _stages[stageIndex] = dpi;
    });
    await _runZinqCmd(['dpi', '$dpi', '--stage', '${stageIndex + 1}']);
    _showToast('Stage ${stageIndex + 1} resolution updated to $dpi DPI');
  }

  Future<void> _setButtonAction(String buttonId, String action) async {
    String effectiveAction = action;
    if (action == 'default') {
      switch (buttonId) {
        case '1': effectiveAction = 'left'; break;
        case '2': effectiveAction = 'right'; break;
        case '3': effectiveAction = 'middle'; break;
        case '4': effectiveAction = 'dpiloop'; break;
        case '5': effectiveAction = 'forward'; break;
        case '6': effectiveAction = 'back'; break;
        default: effectiveAction = 'left'; break;
      }
    }
    setState(() {
      _buttons[buttonId] = effectiveAction;
    });
    final hwId = _toHardwareButtonId(buttonId);
    await _runZinqCmd(['button', '$hwId', effectiveAction]);
    _showToast('${_buttonNames[buttonId]} mapped to ${effectiveAction.toUpperCase()}');
  }

  Future<void> _setFireSpeed(int ms) async {
    setState(() => _fireSpeed = ms);
    await _runZinqCmd(['fire', '$ms']);
  }

  Future<void> _applyAll() async {
    // 1. Button mappings (Button 6 uses authentic 0x06 DPI Loop)
    for (final entry in _buttons.entries) {
      final hwId = _toHardwareButtonId(entry.key);
      await _runZinqCmd(['button', '$hwId', entry.value]);
    }
    // 2. Rapid fire timing
    await _runZinqCmd(['fire', '$_fireSpeed']);
    // 3. Configure DPI stages
    for (int i = 0; i < 4; i++) {
      await _runZinqCmd(['dpi', '${_stages[i]}', '--stage', '${i + 1}']);
    }
    // 4. Finally activate the selected active stage & LED mode
    await _runZinqCmd(['stage', '${_currentStage + 1}']);
    await _runZinqCmd(['led', _ledMode]);
    _showToast('All configurations applied to mouse hardware!');
  }

  Future<void> _factoryReset() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1B1E28),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text('Reset Mouse Defaults?', style: TextStyle(fontWeight: FontWeight.bold)),
        content: const Text('This will restore all factory defaults for DPI, buttons, and lighting.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFF28B82),
              foregroundColor: Colors.black,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Reset'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _runZinqCmd(['reset']);
      await _loadDeviceState();
      _showToast('Mouse restored to factory defaults');
    }
  }

  @override
  Widget build(BuildContext context) {
    const Color cardBg = Color(0xFF13151D);
    const Color subCardBg = Color(0xFF1B1E27);
    const Color textSub = Color(0xFFA0A2B0);
    final Color primaryColor = widget.accentColor;

    return Scaffold(
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: Column(
                children: [
                  // --- TOP BAR: Integrated Seamless Title & Hardware Badge ---
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                    decoration: const BoxDecoration(
                      border: Border(bottom: BorderSide(color: Color(0xFF1E212D), width: 1)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // Left: Minimalist Monogram & Title
                        Row(
                          children: [
                            Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: primaryColor,
                                borderRadius: BorderRadius.circular(10),
                                boxShadow: [
                                  BoxShadow(
                                    color: primaryColor.withOpacity(0.3),
                                    blurRadius: 10,
                                    spreadRadius: 1,
                                  ),
                                ],
                              ),
                              child: const Center(
                                child: Text(
                                  'Z',
                                  style: TextStyle(
                                    color: Colors.black,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 18,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: const [
                                Text(
                                  'Zinq ZQGM-1070',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: -0.3,
                                  ),
                                ),
                                Text(
                                  'Precision Hardware Controller',
                                  style: TextStyle(fontSize: 11, color: textSub),
                                ),
                              ],
                            ),
                          ],
                        ),

                        // Center: Active State HUD Readout
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                          decoration: BoxDecoration(
                            color: subCardBg,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: const Color(0xFF282C3A)),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.speed_rounded, size: 14, color: primaryColor),
                              const SizedBox(width: 6),
                              Text(
                                'Stage ${_currentStage + 1} (${_stages[_currentStage]} DPI)',
                                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: primaryColor),
                              ),
                              const SizedBox(width: 12),
                              Container(width: 1, height: 12, color: const Color(0xFF383C50)),
                              const SizedBox(width: 12),
                              Icon(Icons.lightbulb_outline_rounded, size: 14, color: primaryColor),
                              const SizedBox(width: 6),
                              Text(
                                _ledMode.toUpperCase(),
                                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: primaryColor),
                              ),
                            ],
                          ),
                        ),

                        // Right: Online/Offline Connection Pill & Poll Device Button
                        Row(
                          children: [
                            InkWell(
                              onTap: _isPolling ? null : _manualPoll,
                              borderRadius: BorderRadius.circular(18),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: subCardBg,
                                  borderRadius: BorderRadius.circular(18),
                                  border: Border.all(color: primaryColor.withOpacity(0.4)),
                                ),
                                child: Row(
                                  children: [
                                    AnimatedRotation(
                                      turns: _isPolling ? 1.0 : 0.0,
                                      duration: const Duration(milliseconds: 600),
                                      child: Icon(Icons.sync_rounded, size: 14, color: primaryColor),
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      _isPolling ? 'Polling...' : 'Poll Hardware',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: primaryColor,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            InkWell(
                              onTap: _loadDeviceState,
                              borderRadius: BorderRadius.circular(18),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: subCardBg,
                                  borderRadius: BorderRadius.circular(18),
                                  border: Border.all(
                                    color: _isConnected ? const Color(0xFF81C784) : const Color(0xFFE57373),
                                    width: 1,
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      width: 8,
                                      height: 8,
                                      decoration: BoxDecoration(
                                        color: _isConnected ? const Color(0xFF81C784) : const Color(0xFFE57373),
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      _isConnected ? _devPath.split('/').last : 'Offline',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: _isConnected ? const Color(0xFF81C784) : const Color(0xFFE57373),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // --- UNIFIED HIGH-DENSITY DASHBOARD (Zero Waste Space) ---
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // ================= LEFT: CLEAN TECHNICAL WIREMAP =================
                          Expanded(
                            flex: 5,
                            child: Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: cardBg,
                                borderRadius: BorderRadius.circular(24),
                                border: Border.all(color: const Color(0xFF202330)),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Wiremap Title & Hint
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Row(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.all(6),
                                            decoration: BoxDecoration(
                                              color: subCardBg,
                                              borderRadius: BorderRadius.circular(8),
                                            ),
                                            child: Icon(Icons.architecture_rounded, size: 16, color: primaryColor),
                                          ),
                                          const SizedBox(width: 10),
                                          Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: const [
                                              Text('TECHNICAL WIREMAP', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                                              Text('Hover any component to illuminate solid fill', style: TextStyle(fontSize: 10, color: textSub)),
                                            ],
                                          ),
                                        ],
                                      ),
                                      // Active Button Chip
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: primaryColor.withOpacity(0.15),
                                          borderRadius: BorderRadius.circular(12),
                                          border: Border.all(color: primaryColor, width: 1),
                                        ),
                                        child: Text(
                                          'B$_selectedButton: ${(_buttons[_selectedButton] ?? 'default').toUpperCase()}',
                                          style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: primaryColor),
                                        ),
                                      ),
                                    ],
                                  ),

                                  const SizedBox(height: 8),

                                  // Interactive Wiremap Canvas with Hover Regions
                                  Expanded(
                                    child: Center(
                                      child: SizedBox(
                                        width: 290,
                                        height: 380,
                                        child: Stack(
                                          alignment: Alignment.center,
                                          children: [
                                            // Real-Time Ambient Breathing Aura
                                            if (_ledMode != 'off')
                                              AnimatedBuilder(
                                                animation: _pulseAnimation,
                                                builder: (ctx, child) {
                                                  return Opacity(
                                                    opacity: _pulseAnimation.value,
                                                    child: Container(
                                                      width: 220,
                                                      height: 310,
                                                      decoration: BoxDecoration(
                                                        borderRadius: BorderRadius.circular(110),
                                                        boxShadow: [
                                                          BoxShadow(
                                                            color: primaryColor.withOpacity(0.40),
                                                            blurRadius: 46,
                                                            spreadRadius: 8,
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                  );
                                                },
                                              ),

                                            // Wiremap Vector Painter (Clean Industrial Design)
                                            CustomPaint(
                                              size: const Size(290, 380),
                                              painter: CleanTechnicalWiremapPainter(
                                                activeLedMode: _ledMode,
                                                selectedButton: _selectedButton,
                                                hoveredButton: _hoveredButton,
                                                accentColor: primaryColor,
                                              ),
                                            ),

                                            // Interactive Hover/Tap Regions (Buttons 1 to 6)
                                            // 1: Left Trigger
                                            Positioned(
                                              top: 24,
                                              left: 45,
                                              child: _buildInteractiveWiremapRegion('1', 82, 105),
                                            ),
                                            // 2: Right Trigger
                                            Positioned(
                                              top: 24,
                                              right: 45,
                                              child: _buildInteractiveWiremapRegion('2', 82, 105),
                                            ),
                                            // 3: Scroll Wheel / Middle
                                            Positioned(
                                              top: 36,
                                              child: _buildInteractiveWiremapRegion('3', 28, 54),
                                            ),
                                            // 4: DPI Switch
                                            Positioned(
                                              top: 116,
                                              child: _buildInteractiveWiremapRegion('4', 24, 30),
                                            ),
                                            // 5: Forward Side Key
                                            Positioned(
                                              left: 14,
                                              top: 155,
                                              child: _buildInteractiveWiremapRegion('5', 24, 40),
                                            ),
                                            // 6: Backward Side Key
                                            Positioned(
                                              left: 14,
                                              top: 210,
                                              child: _buildInteractiveWiremapRegion('6', 24, 40),
                                            ),

                                            // Floating Pin Badges with Labels
                                            _buildPinCallout('1', 'Left', primaryColor, left: 8, top: 45),
                                            _buildPinCallout('2', 'Right', primaryColor, right: 8, top: 45),
                                            _buildPinCallout('3', 'Wheel', primaryColor, right: 26, top: 105),
                                            _buildPinCallout('4', 'DPI', primaryColor, right: 26, top: 145),
                                            _buildPinCallout('5', 'Fwd', primaryColor, left: 2, top: 165),
                                            _buildPinCallout('6', 'Back', primaryColor, left: 2, top: 220),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),

                          const SizedBox(width: 16),

                          // ================= RIGHT: MASTER CONTROL DECK =================
                          Expanded(
                            flex: 6,
                            child: Column(
                              children: [
                                // Panel 1: Selected Button Remapping Drawer
                                Expanded(
                                  flex: 6,
                                  child: Container(
                                    padding: const EdgeInsets.all(16),
                                    decoration: BoxDecoration(
                                      color: cardBg,
                                      borderRadius: BorderRadius.circular(20),
                                      border: Border.all(color: const Color(0xFF202330)),
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        // Button Header & Quick Selector Pills
                                        Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: [
                                            Row(
                                              children: [
                                                Icon(Icons.gamepad_rounded, size: 16, color: primaryColor),
                                                const SizedBox(width: 8),
                                                Text(
                                                  'BUTTON ${_selectedButton.toUpperCase()}: ${_buttonNames[_selectedButton]}',
                                                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                                                ),
                                              ],
                                            ),
                                            // Mini button switcher
                                            Row(
                                              children: List.generate(6, (idx) {
                                                final String bId = '${idx + 1}';
                                                final bool isCur = (_selectedButton == bId);
                                                return Padding(
                                                  padding: const EdgeInsets.only(left: 4),
                                                  child: InkWell(
                                                    onTap: () => setState(() => _selectedButton = bId),
                                                    borderRadius: BorderRadius.circular(8),
                                                    child: Container(
                                                      width: 26,
                                                      height: 24,
                                                      decoration: BoxDecoration(
                                                        color: isCur ? primaryColor : subCardBg,
                                                        borderRadius: BorderRadius.circular(6),
                                                        border: Border.all(color: isCur ? primaryColor : const Color(0xFF323646)),
                                                      ),
                                                      child: Center(
                                                        child: Text(
                                                          'B$bId',
                                                          style: TextStyle(
                                                            fontSize: 9,
                                                            fontWeight: FontWeight.bold,
                                                            color: isCur ? Colors.black : Colors.white70,
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                );
                                              }),
                                            ),
                                          ],
                                        ),

                                        const SizedBox(height: 10),
                                        const Divider(color: Color(0xFF222532), height: 1),
                                        const SizedBox(height: 10),

                                        // Action Categories & Chips
                                        Expanded(
                                          child: SingleChildScrollView(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: _actionCategories.entries.map((cat) {
                                                return Padding(
                                                  padding: const EdgeInsets.only(bottom: 10),
                                                  child: Column(
                                                    crossAxisAlignment: CrossAxisAlignment.start,
                                                    children: [
                                                      Text(
                                                        cat.key.toUpperCase(),
                                                        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: textSub, letterSpacing: 0.5),
                                                      ),
                                                      const SizedBox(height: 6),
                                                      Wrap(
                                                        spacing: 6,
                                                        runSpacing: 6,
                                                        children: cat.value.map((act) {
                                                          final bool isAssigned = (_buttons[_selectedButton] == act['id']);
                                                          return InkWell(
                                                            onTap: () => _setButtonAction(_selectedButton, act['id']),
                                                            borderRadius: BorderRadius.circular(10),
                                                            child: Container(
                                                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                                              decoration: BoxDecoration(
                                                                color: isAssigned ? primaryColor : subCardBg,
                                                                borderRadius: BorderRadius.circular(10),
                                                                border: Border.all(
                                                                  color: isAssigned ? primaryColor : const Color(0xFF34384A),
                                                                ),
                                                              ),
                                                              child: Row(
                                                                mainAxisSize: MainAxisSize.min,
                                                                children: [
                                                                  Icon(
                                                                    act['icon'] as IconData,
                                                                    size: 13,
                                                                    color: isAssigned ? Colors.black : primaryColor,
                                                                  ),
                                                                  const SizedBox(width: 5),
                                                                  Text(
                                                                    act['name'] as String,
                                                                    style: TextStyle(
                                                                      fontSize: 11,
                                                                      fontWeight: isAssigned ? FontWeight.bold : FontWeight.w500,
                                                                      color: isAssigned ? Colors.black : Colors.white,
                                                                    ),
                                                                  ),
                                                                ],
                                                              ),
                                                            ),
                                                          );
                                                        }).toList(),
                                                      ),
                                                    ],
                                                  ),
                                                );
                                              }).toList(),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),

                                const SizedBox(height: 12),

                                // Panel 2: Static Hardware Color Selector & DPI Stages
                                Container(
                                  padding: const EdgeInsets.all(14),
                                  decoration: BoxDecoration(
                                    color: cardBg,
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(color: const Color(0xFF202330)),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      // Hardware Static Color Selector
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          const Text('STATIC HARDWARE COLOR', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                                          Text('Sets active profile & solid LED', style: TextStyle(fontSize: 10, color: primaryColor)),
                                        ],
                                      ),
                                      const SizedBox(height: 8),

                                      // 4 Static Color Chips
                                      Row(
                                        children: _staticColors.map((c) {
                                          final bool isCurrent = (_currentStage == c['stage']);
                                          final Color swatchColor = c['color'] as Color;
                                          return Expanded(
                                            child: Padding(
                                              padding: const EdgeInsets.symmetric(horizontal: 4),
                                              child: InkWell(
                                                onTap: () => _selectStaticColor(c),
                                                borderRadius: BorderRadius.circular(10),
                                                child: Container(
                                                  padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                                                  decoration: BoxDecoration(
                                                    color: isCurrent ? swatchColor.withOpacity(0.25) : subCardBg,
                                                    borderRadius: BorderRadius.circular(10),
                                                    border: Border.all(
                                                      color: isCurrent ? swatchColor : const Color(0xFF2E3242),
                                                      width: isCurrent ? 1.6 : 1,
                                                    ),
                                                  ),
                                                  child: Row(
                                                    mainAxisAlignment: MainAxisAlignment.center,
                                                    children: [
                                                      Container(
                                                        width: 10,
                                                        height: 10,
                                                        decoration: BoxDecoration(
                                                          color: swatchColor,
                                                          shape: BoxShape.circle,
                                                          boxShadow: isCurrent
                                                              ? [
                                                                  BoxShadow(
                                                                    color: swatchColor.withOpacity(0.5),
                                                                    blurRadius: 6,
                                                                    spreadRadius: 1,
                                                                  )
                                                                ]
                                                              : null,
                                                        ),
                                                      ),
                                                      const SizedBox(width: 6),
                                                      Text(
                                                        c['name'].toString().split(' ').last,
                                                        style: TextStyle(
                                                          fontSize: 10,
                                                          fontWeight: FontWeight.bold,
                                                          color: isCurrent ? Colors.white : textSub,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                            ),
                                          );
                                        }).toList(),
                                      ),

                                      const SizedBox(height: 12),
                                      const Divider(color: Color(0xFF222532), height: 1),
                                      const SizedBox(height: 10),

                                      // DPI Stage Cards Row
                                      Row(
                                        children: List.generate(4, (i) {
                                          final bool isActive = (i == _currentStage);
                                          return Expanded(
                                            child: Padding(
                                              padding: EdgeInsets.only(right: i < 3 ? 8 : 0),
                                              child: InkWell(
                                                onTap: () => _setStage(i),
                                                borderRadius: BorderRadius.circular(12),
                                                child: Container(
                                                  padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 6),
                                                  decoration: BoxDecoration(
                                                    color: isActive ? primaryColor.withOpacity(0.20) : subCardBg,
                                                    borderRadius: BorderRadius.circular(12),
                                                    border: Border.all(
                                                      color: isActive ? primaryColor : const Color(0xFF303444),
                                                      width: isActive ? 1.6 : 1,
                                                    ),
                                                  ),
                                                  child: Column(
                                                    children: [
                                                      Text('STAGE ${i + 1}', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: isActive ? primaryColor : textSub)),
                                                      const SizedBox(height: 2),
                                                      Text('${_stages[i]}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                                      const Text('DPI', style: TextStyle(fontSize: 8, color: textSub)),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                            ),
                                          );
                                        }),
                                      ),

                                      const SizedBox(height: 8),

                                      // Preset Pills
                                      Row(
                                        children: [
                                          const Text('Presets: ', style: TextStyle(fontSize: 10, color: textSub)),
                                          ..._dpiChoices.map((dpi) {
                                            final bool isCur = (_stages[_currentStage] == dpi);
                                            return Padding(
                                              padding: const EdgeInsets.only(left: 6),
                                              child: InkWell(
                                                onTap: () => _setStageDpi(_currentStage, dpi),
                                                borderRadius: BorderRadius.circular(8),
                                                child: Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                                  decoration: BoxDecoration(
                                                    color: isCur ? primaryColor : subCardBg,
                                                    borderRadius: BorderRadius.circular(8),
                                                    border: Border.all(color: isCur ? primaryColor : const Color(0xFF343848)),
                                                  ),
                                                  child: Text(
                                                    '$dpi',
                                                    style: TextStyle(
                                                      fontSize: 10,
                                                      fontWeight: FontWeight.bold,
                                                      color: isCur ? Colors.black : Colors.white,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            );
                                          }),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),

                                const SizedBox(height: 12),

                                // Panel 3: Lighting Mode & Rapid Fire in one tight row
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                  decoration: BoxDecoration(
                                    color: cardBg,
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(color: const Color(0xFF202330)),
                                  ),
                                  child: Row(
                                    children: [
                                      // Lighting Pills
                                      Expanded(
                                        flex: 6,
                                        child: Row(
                                          children: [
                                            const Text('LED: ', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: textSub)),
                                            _buildLedMiniChip('slow', 'Slow', Icons.waves_rounded, primaryColor),
                                            _buildLedMiniChip('fast', 'Fast', Icons.bolt_rounded, primaryColor),
                                            _buildLedMiniChip('static', 'Solid', Icons.light_mode_rounded, primaryColor),
                                            _buildLedMiniChip('off', 'Off', Icons.power_settings_new_rounded, primaryColor),
                                          ],
                                        ),
                                      ),

                                      Container(width: 1, height: 24, color: const Color(0xFF2A2D3C)),
                                      const SizedBox(width: 12),

                                      // Rapid Fire Delay
                                      Expanded(
                                        flex: 5,
                                        child: Row(
                                          children: [
                                            const Text('Fire: ', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: textSub)),
                                            Expanded(
                                              child: SliderTheme(
                                                data: SliderTheme.of(context).copyWith(
                                                  trackHeight: 3,
                                                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                                                ),
                                                child: Slider(
                                                  value: _fireSpeed.toDouble().clamp(10, 200),
                                                  min: 10,
                                                  max: 200,
                                                  divisions: 19,
                                                  activeColor: primaryColor,
                                                  onChanged: (v) => _setFireSpeed(v.round()),
                                                ),
                                              ),
                                            ),
                                            Text(
                                              '$_fireSpeed ms',
                                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: primaryColor),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // --- BOTTOM ACTION FOOTER ---
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
                    decoration: const BoxDecoration(
                      color: Color(0xFF0F1016),
                      border: Border(top: BorderSide(color: Color(0xFF1E212D), width: 1)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          _isConnected
                              ? 'Hardware Node: $_devPath · Driver Active'
                              : 'Hardware Disconnected. Plug in mouse via USB.',
                          style: const TextStyle(fontSize: 11, color: textSub),
                        ),
                        Row(
                          children: [
                            OutlinedButton.icon(
                              onPressed: _isPolling ? null : _manualPoll,
                              icon: AnimatedRotation(
                                turns: _isPolling ? 1.0 : 0.0,
                                duration: const Duration(milliseconds: 600),
                                child: const Icon(Icons.sync_rounded, size: 15),
                              ),
                              label: Text(_isPolling ? 'Polling...' : 'Poll Hardware', style: const TextStyle(fontSize: 11)),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: primaryColor,
                                side: BorderSide(color: primaryColor.withOpacity(0.5)),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                              ),
                            ),
                            const SizedBox(width: 10),
                            OutlinedButton.icon(
                              onPressed: _factoryReset,
                              icon: const Icon(Icons.restart_alt_rounded, size: 15),
                              label: const Text('Reset Defaults', style: TextStyle(fontSize: 11)),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: const Color(0xFFF28B82),
                                side: const BorderSide(color: Color(0xFF4A2528)),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                              ),
                            ),
                            const SizedBox(width: 10),
                            FilledButton.icon(
                              onPressed: _applyAll,
                              icon: const Icon(Icons.check_rounded, size: 16),
                              label: const Text('Apply to Mouse', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                              style: FilledButton.styleFrom(
                                backgroundColor: primaryColor,
                                foregroundColor: Colors.black,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildInteractiveWiremapRegion(String buttonId, double w, double h) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hoveredButton = buttonId),
      onExit: (_) => setState(() {
        if (_hoveredButton == buttonId) _hoveredButton = null;
      }),
      child: GestureDetector(
        onTap: () => setState(() => _selectedButton = buttonId),
        child: Container(
          width: w,
          height: h,
          color: Colors.transparent, // Transparent hit-test target
        ),
      ),
    );
  }

  Widget _buildPinCallout(String id, String label, Color primaryColor, {double? left, double? right, required double top}) {
    final bool isHighlighted = (_selectedButton == id || _hoveredButton == id);
    final String currentAction = _buttons[id] ?? 'default';

    return Positioned(
      left: left,
      right: right,
      top: top,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hoveredButton = id),
        onExit: (_) => setState(() {
          if (_hoveredButton == id) _hoveredButton = null;
        }),
        child: GestureDetector(
          onTap: () => setState(() => _selectedButton = id),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: isHighlighted ? primaryColor : const Color(0xFF1A1D27),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isHighlighted ? primaryColor : const Color(0xFF363A4C),
                width: 1.2,
              ),
              boxShadow: isHighlighted
                  ? [
                      BoxShadow(
                        color: primaryColor.withOpacity(0.4),
                        blurRadius: 10,
                        spreadRadius: 1,
                      )
                    ]
                  : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    color: isHighlighted ? Colors.black : const Color(0xFF2E3244),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      id,
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                        color: isHighlighted ? primaryColor : Colors.white,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 5),
                Text(
                  currentAction,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: isHighlighted ? Colors.black : primaryColor,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLedMiniChip(String modeId, String label, IconData icon, Color primaryColor) {
    final bool isSel = (_ledMode == modeId);
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: InkWell(
        onTap: () => _setLedMode(modeId),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: isSel ? primaryColor : const Color(0xFF1B1E27),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: isSel ? primaryColor : const Color(0xFF303444)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 12, color: isSel ? Colors.black : const Color(0xFFA0A2B0)),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: isSel ? FontWeight.bold : FontWeight.w500,
                  color: isSel ? Colors.black : Colors.white70,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ================= CLEAN TECHNICAL INDUSTRIAL DESIGN WIREMAP PAINTER =================
class CleanTechnicalWiremapPainter extends CustomPainter {
  final String activeLedMode;
  final String selectedButton;
  final String? hoveredButton;
  final Color accentColor;

  CleanTechnicalWiremapPainter({
    required this.activeLedMode,
    required this.selectedButton,
    required this.hoveredButton,
    required this.accentColor,
  });

  bool isLit(String id) => (selectedButton == id || hoveredButton == id);

  @override
  void paint(Canvas canvas, Size size) {
    final double w = size.width;
    final double h = size.height;

    // Blueprint Drafting Palette
    final paintBase = Paint()
      ..color = const Color(0xFF101218)
      ..style = PaintingStyle.fill;

    final paintWireStroke = Paint()
      ..color = const Color(0xFF282C3C)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.3;

    final paintAccentGrid = Paint()
      ..color = const Color(0xFF1A1D27)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.9;

    final paintSolidHover = Paint()
      ..color = accentColor
      ..style = PaintingStyle.fill;

    final paintSolidStroke = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8;

    // 0. Precision CAD Drafting Crosshairs & Grid
    for (double x = 20; x < w; x += 32) {
      canvas.drawLine(Offset(x, 20), Offset(x, h - 20), paintAccentGrid);
    }
    for (double y = 20; y < h; y += 32) {
      canvas.drawLine(Offset(20, y), Offset(w - 20, y), paintAccentGrid);
    }

    // Corner Crosshairs (+)
    void drawCrosshair(double cx, double cy) {
      canvas.drawLine(Offset(cx - 5, cy), Offset(cx + 5, cy), Paint()..color = const Color(0xFF383C50)..strokeWidth = 1);
      canvas.drawLine(Offset(cx, cy - 5), Offset(cx, cy + 5), Paint()..color = const Color(0xFF383C50)..strokeWidth = 1);
    }
    drawCrosshair(28, 28);
    drawCrosshair(w - 28, 28);
    drawCrosshair(28, h - 28);
    drawCrosshair(w - 28, h - 28);

    // 1. Clean Ergonomic Gaming Mouse Outer Contour (Dieter Rams / Industrial CAD)
    final chassis = Path();
    chassis.moveTo(w * 0.50, h * 0.08);
    chassis.lineTo(w * 0.34, h * 0.05);
    chassis.lineTo(w * 0.16, h * 0.14);
    chassis.lineTo(w * 0.12, h * 0.34);
    // Left ergonomic thumb flare
    chassis.lineTo(w * 0.07, h * 0.52);
    chassis.lineTo(w * 0.09, h * 0.72);
    // Lower palm flare
    chassis.lineTo(w * 0.22, h * 0.90);
    chassis.lineTo(w * 0.50, h * 0.95);
    // Right lower palm flare
    chassis.lineTo(w * 0.78, h * 0.90);
    chassis.lineTo(w * 0.91, h * 0.72);
    // Right finger flare
    chassis.lineTo(w * 0.93, h * 0.52);
    chassis.lineTo(w * 0.88, h * 0.34);
    chassis.lineTo(w * 0.84, h * 0.14);
    chassis.lineTo(w * 0.66, h * 0.05);
    chassis.close();

    canvas.drawPath(chassis, paintBase);
    canvas.drawPath(chassis, paintWireStroke);

    // 2. Button 1: Left Trigger Wing (Turns SOLID on hover/select)
    final b1Path = Path();
    b1Path.moveTo(w * 0.46, h * 0.07);
    b1Path.lineTo(w * 0.34, h * 0.05);
    b1Path.lineTo(w * 0.16, h * 0.14);
    b1Path.lineTo(w * 0.13, h * 0.35);
    b1Path.lineTo(w * 0.44, h * 0.35);
    b1Path.lineTo(w * 0.44, h * 0.14);
    b1Path.close();

    if (isLit('1')) {
      canvas.drawPath(b1Path, paintSolidHover);
      canvas.drawPath(b1Path, paintSolidStroke);
    } else {
      canvas.drawPath(b1Path, Paint()..color = const Color(0xFF151722)..style = PaintingStyle.fill);
      canvas.drawPath(b1Path, paintWireStroke);
    }

    // 3. Button 2: Right Trigger Wing (Turns SOLID on hover/select)
    final b2Path = Path();
    b2Path.moveTo(w * 0.54, h * 0.07);
    b2Path.lineTo(w * 0.66, h * 0.05);
    b2Path.lineTo(w * 0.84, h * 0.14);
    b2Path.lineTo(w * 0.87, h * 0.35);
    b2Path.lineTo(w * 0.56, h * 0.35);
    b2Path.lineTo(w * 0.56, h * 0.14);
    b2Path.close();

    if (isLit('2')) {
      canvas.drawPath(b2Path, paintSolidHover);
      canvas.drawPath(b2Path, paintSolidStroke);
    } else {
      canvas.drawPath(b2Path, Paint()..color = const Color(0xFF151722)..style = PaintingStyle.fill);
      canvas.drawPath(b2Path, paintWireStroke);
    }

    // 4. Button 3: Precision Scroll Wheel / Middle Click (Turns SOLID on hover/select)
    final wheelRect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset(w * 0.50, h * 0.20), width: 22, height: 48),
      const Radius.circular(8),
    );

    if (isLit('3')) {
      canvas.drawRRect(wheelRect, paintSolidHover);
      canvas.drawRRect(wheelRect, paintSolidStroke);
    } else {
      canvas.drawRRect(wheelRect, Paint()..color = const Color(0xFF0E1016)..style = PaintingStyle.fill);
      canvas.drawRRect(wheelRect, paintWireStroke);
      // Clean technical ribbing
      for (int i = 0; i < 5; i++) {
        canvas.drawLine(
          Offset(w * 0.44, h * 0.15 + (i * 7)),
          Offset(w * 0.56, h * 0.15 + (i * 7)),
          paintWireStroke,
        );
      }
    }

    // 5. Button 4: Beveled DPI Switch Key (Turns SOLID on hover/select)
    final dpiRect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset(w * 0.50, h * 0.38), width: 20, height: 26),
      const Radius.circular(6),
    );

    if (isLit('4')) {
      canvas.drawRRect(dpiRect, paintSolidHover);
      canvas.drawRRect(dpiRect, paintSolidStroke);
    } else {
      canvas.drawRRect(dpiRect, Paint()..color = const Color(0xFF1E212E)..style = PaintingStyle.fill);
      canvas.drawRRect(dpiRect, paintWireStroke);
    }

    // 6. Button 5: Side Forward Key (Turns SOLID on hover/select)
    final b5Path = Path();
    b5Path.moveTo(w * 0.08, h * 0.42);
    b5Path.lineTo(w * 0.14, h * 0.44);
    b5Path.lineTo(w * 0.13, h * 0.52);
    b5Path.lineTo(w * 0.07, h * 0.50);
    b5Path.close();

    if (isLit('5')) {
      canvas.drawPath(b5Path, paintSolidHover);
      canvas.drawPath(b5Path, paintSolidStroke);
    } else {
      canvas.drawPath(b5Path, Paint()..color = const Color(0xFF202330)..style = PaintingStyle.fill);
      canvas.drawPath(b5Path, paintWireStroke);
    }

    // 7. Button 6: Side Backward Key (Turns SOLID on hover/select)
    final b6Path = Path();
    b6Path.moveTo(w * 0.08, h * 0.55);
    b6Path.lineTo(w * 0.14, h * 0.57);
    b6Path.lineTo(w * 0.13, h * 0.65);
    b6Path.lineTo(w * 0.08, h * 0.63);
    b6Path.close();

    if (isLit('6')) {
      canvas.drawPath(b6Path, paintSolidHover);
      canvas.drawPath(b6Path, paintSolidStroke);
    } else {
      canvas.drawPath(b6Path, Paint()..color = const Color(0xFF202330)..style = PaintingStyle.fill);
      canvas.drawPath(b6Path, paintWireStroke);
    }

    // 8. MINIMALIST PALM ACCENT (Clean Concentric Geometry, No Cheesy Lightning Logo)
    final palmCenter = Offset(w * 0.50, h * 0.72);

    // Inner Concentric Calibrated Rings
    canvas.drawCircle(palmCenter, 28, paintWireStroke);
    canvas.drawCircle(
      palmCenter,
      16,
      Paint()
        ..color = activeLedMode == 'off' ? const Color(0xFF1E212D) : accentColor.withOpacity(0.35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4,
    );

    // Center illuminated LED core dot
    canvas.drawCircle(
      palmCenter,
      5,
      Paint()
        ..color = activeLedMode == 'off' ? const Color(0xFF1E212D) : accentColor
        ..style = PaintingStyle.fill,
    );

    // Technical Subtle Tick Lines
    for (int i = 0; i < 4; i++) {
      final double angle = i * (math.pi / 2);
      final double x1 = palmCenter.dx + math.cos(angle) * 32;
      final double y1 = palmCenter.dy + math.sin(angle) * 32;
      final double x2 = palmCenter.dx + math.cos(angle) * 38;
      final double y2 = palmCenter.dy + math.sin(angle) * 38;
      canvas.drawLine(Offset(x1, y1), Offset(x2, y2), paintWireStroke);
    }
  }

  @override
  bool shouldRepaint(covariant CleanTechnicalWiremapPainter oldDelegate) {
    return oldDelegate.activeLedMode != activeLedMode ||
        oldDelegate.selectedButton != selectedButton ||
        oldDelegate.hoveredButton != hoveredButton ||
        oldDelegate.accentColor != accentColor;
  }
}
