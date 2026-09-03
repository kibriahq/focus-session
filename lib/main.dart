import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';

void main() {
  SystemChrome.setSystemUIOverlayStyle(
    SystemUiOverlayStyle(
      statusBarColor: Colors.blueGrey[50],
      statusBarIconBrightness: Brightness.dark,
      statusBarBrightness: Brightness.light,
    ),
  );

  runApp(const FocusSessionApp());
}

class FocusSessionApp extends StatelessWidget {
  const FocusSessionApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Focus Session',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blueAccent),
        useMaterial3: true,
      ),
      home: const FocusHomePage(),
    );
  }
}

class FocusHomePage extends StatefulWidget {
  const FocusHomePage({super.key});

  @override
  State<FocusHomePage> createState() => _FocusHomePageState();
}

class _FocusHomePageState extends State<FocusHomePage> {
  static const String _storageKey = 'focus_total_seconds';
  static const String _dateKey = 'focus_date';

  TimerPhase _phase = TimerPhase.idle;
  int _totalDuration = 0;
  int _remaining = 0;
  bool _isBreak = false;
  final TextEditingController _breakController = TextEditingController(
    text: '5',
  );
  int _totalFocusSecondsToday = 0;
  int _secondsLeftInDay = _computeSecondsLeftInDay();
  final AudioPlayer _audioPlayer = AudioPlayer();

  Future<void> _playCompletionSound() async {
    try {
      final bytes = _buildChimeWav();
      await _audioPlayer.play(BytesSource(bytes), volume: 0.7);
    } catch (_) {
      // Ignore playback errors.
    }
  }

  static Uint8List _buildChimeWav() {
    const sampleRate = 44100;
    const durationSec = 1;
    const numSamples = sampleRate * durationSec;
    const numChannels = 1;
    const bytesPerSample = 2;
    final dataSize = numSamples * numChannels * bytesPerSample;
    final buffer = ByteData(44 + dataSize);

    final riff = Uint8List.fromList('RIFF'.codeUnits);
    final wave = Uint8List.fromList('WAVE'.codeUnits);
    final fmt = Uint8List.fromList('fmt '.codeUnits);
    final data = Uint8List.fromList('data'.codeUnits);
    buffer.buffer.asUint8List(0, 4).setAll(0, riff);
    buffer.setUint32(4, 36 + dataSize, Endian.little);
    buffer.buffer.asUint8List(8, 4).setAll(0, wave);
    buffer.buffer.asUint8List(12, 4).setAll(0, fmt);
    buffer.setUint32(16, 16, Endian.little);
    buffer.setUint16(20, 1, Endian.little);
    buffer.setUint16(22, numChannels, Endian.little);
    buffer.setUint32(24, sampleRate, Endian.little);
    buffer.setUint32(
      28,
      sampleRate * numChannels * bytesPerSample,
      Endian.little,
    );
    buffer.setUint16(32, numChannels * bytesPerSample, Endian.little);
    buffer.setUint16(34, 16, Endian.little);
    buffer.buffer.asUint8List(36, 4).setAll(0, data);
    buffer.setUint32(40, dataSize, Endian.little);

    final notes = [523.25, 659.25, 783.99, 1046.50];
    final samplesPerNote = numSamples ~/ notes.length;
    var offset = 44;
    for (var n = 0; n < notes.length; n++) {
      final freq = notes[n];
      for (var i = 0; i < samplesPerNote; i++) {
        final t = i / sampleRate;
        final env = 1 - (i / samplesPerNote);
        final sample = (32767 * 0.6 * env * sin(2 * pi * freq * t)).toInt();
        buffer.setInt16(offset, sample, Endian.little);
        offset += bytesPerSample;
      }
    }
    return buffer.buffer.asUint8List();
  }

  @override
  void initState() {
    super.initState();
    _loadFocusTime();
    Future.delayed(Duration.zero, _updateTimeLeftInDay);
  }

  static int _computeSecondsLeftInDay() {
    final now = DateTime.now();
    final endOfDay = DateTime(now.year, now.month, now.day, 23, 59, 59);
    return endOfDay.difference(now).inSeconds;
  }

  void _updateTimeLeftInDay() {
    if (!mounted) return;
    setState(() => _secondsLeftInDay = _computeSecondsLeftInDay());
    Future.delayed(const Duration(seconds: 1), _updateTimeLeftInDay);
  }

  @override
  void dispose() {
    _breakController.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }

  int get _elapsed => _totalDuration - _remaining;

  double get _progress {
    if (_totalDuration == 0) return 0;
    return _elapsed / _totalDuration;
  }

  Future<void> _loadFocusTime() async {
    final prefs = await SharedPreferences.getInstance();
    final today = DateTime.now();
    final todayStr = '${today.year}-${today.month}-${today.day}';
    final savedDate = prefs.getString(_dateKey);

    if (savedDate != todayStr) {
      await prefs.setString(_dateKey, todayStr);
      await prefs.setInt(_storageKey, 0);
      setState(() => _totalFocusSecondsToday = 0);
    } else {
      setState(() => _totalFocusSecondsToday = prefs.getInt(_storageKey) ?? 0);
    }
  }

  Future<void> _addFocusSeconds(int seconds) async {
    final prefs = await SharedPreferences.getInstance();
    _totalFocusSecondsToday += seconds;
    await prefs.setInt(_storageKey, _totalFocusSecondsToday);
    setState(() {});
  }

  void _tick() {
    if (_phase != TimerPhase.running) return;
    if (_remaining > 0) {
      setState(() => _remaining--);
      Future.delayed(const Duration(seconds: 1), _tick);
    } else {
      _completeSession();
    }
  }

  bool get _isActive =>
      _phase == TimerPhase.running || _phase == TimerPhase.paused;

  void _startSession(int minutes, {bool isBreak = false}) {
    final addSeconds = minutes * 60;
    if (_isActive) {
      setState(() {
        _totalDuration += addSeconds;
        _remaining += addSeconds;
      });
      return;
    }
    setState(() {
      _totalDuration = addSeconds;
      _remaining = _totalDuration;
      _isBreak = isBreak;
      _phase = TimerPhase.running;
    });
    _tick();
  }

  void _pause() {
    setState(() => _phase = TimerPhase.paused);
  }

  void _resume() {
    setState(() => _phase = TimerPhase.running);
    _tick();
  }

  void _stop() {
    final completedElapsed =
        _phase == TimerPhase.running || _phase == TimerPhase.paused
        ? _elapsed
        : 0;
    if (!_isBreak && completedElapsed > 0) {
      _addFocusSeconds(completedElapsed);
    }
    setState(() {
      _phase = TimerPhase.idle;
      _totalDuration = 0;
      _remaining = 0;
      _isBreak = false;
    });
  }

  void _completeSession() {
    if (!_isBreak) {
      _addFocusSeconds(_totalDuration);
    }
    setState(() {
      _phase = TimerPhase.idle;
      _totalDuration = 0;
      _remaining = 0;
      _isBreak = false;
    });
    _playCompletionSound();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_isBreak ? 'Break finished!' : 'Session completed!'),
        ),
      );
    }
  }

  String _formatTime(int totalSeconds) {
    final h = totalSeconds ~/ 3600;
    final m = (totalSeconds % 3600) ~/ 60;
    final s = totalSeconds % 60;
    if (h > 0) {
      return '${h.toString().padLeft(2, '0')}:'
          '${m.toString().padLeft(2, '0')}:'
          '${s.toString().padLeft(2, '0')}';
    }
    return '${m.toString().padLeft(2, '0')}:'
        '${s.toString().padLeft(2, '0')}';
  }

  Widget _buildTimerCircle() {
    final isActive =
        _phase == TimerPhase.running || _phase == TimerPhase.paused;
    return Stack(
      alignment: Alignment.center,
      children: [
        SizedBox(
          width: 240,
          height: 240,
          child: CircularProgressIndicator(
            value: isActive ? _progress : 0,
            strokeWidth: 12,
            backgroundColor: Colors.grey.shade300,
            strokeCap: StrokeCap.round,
            valueColor: AlwaysStoppedAnimation<Color>(
              _isBreak ? Colors.green : Colors.blueAccent,
            ),
          ),
        ),
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              isActive ? _formatTime(_remaining) : '00:00',
              style: const TextStyle(fontSize: 40, fontWeight: FontWeight.bold),
            ),
            if (isActive)
              Text(
                _isBreak ? 'Break' : 'Focus',
                style: const TextStyle(fontSize: 16, color: Colors.grey),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildTimerControls() {
    if (_phase == TimerPhase.idle) return const SizedBox.shrink();
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (_phase == TimerPhase.running)
          ElevatedButton.icon(
            onPressed: _pause,
            icon: const Icon(Icons.pause),
            label: const Text('Pause'),
          )
        else if (_phase == TimerPhase.paused)
          ElevatedButton.icon(
            onPressed: _resume,
            icon: const Icon(Icons.play_arrow),
            label: const Text('Resume'),
          ),
        const SizedBox(width: 16),
        ElevatedButton.icon(
          onPressed: _stop,
          icon: const Icon(Icons.stop),
          label: const Text('Stop'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.redAccent,
            foregroundColor: Colors.white,
          ),
        ),
      ],
    );
  }

  Widget _sessionButton(String label, int minutes, MaterialColor color) {
    return ElevatedButton(
      onPressed: () => _startSession(minutes),
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 2,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: color[50],
              borderRadius: BorderRadius.circular(40),
            ),
            child: Icon(Icons.timer_outlined, color: color[500], size: 18),
          ),
          const SizedBox(width: 8),
          Text(label),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // appBar: AppBar(
      //   toolbarHeight: 0,
      //   backgroundColor: Colors.blueGrey[50],
      // ),
      body: SizedBox.expand(
        child: Stack(
          children: [
            // Header
            Container(
              height: 230,
              width: double.infinity,
              color: Colors.blueGrey[50],
              padding: const EdgeInsets.only(top: 20, left: 16, right: 16),
              child: SafeArea(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Focus Session',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: Colors.blueGrey,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Stay focused and track your time',
                      style: TextStyle(fontSize: 16, color: Colors.blueGrey),
                    ),
                  ],
                ),
              ),
            ),

            // Body
            Positioned(
              top: 155,
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                margin: EdgeInsets.only(right: 10, left: 10),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                ),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      _buildTimerCircle(),
                      const SizedBox(height: 16),
                      _buildTimerControls(),
                      const SizedBox(height: 24),
                      const Text(
                        'Start A Session',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Column(
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: _sessionButton('5 Min', 5, Colors.red),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _sessionButton(
                                  '15 Min',
                                  15,
                                  Colors.orange,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _sessionButton(
                                  '30 Min',
                                  30,
                                  Colors.blue,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: _sessionButton(
                                  '1 Hour',
                                  60,
                                  Colors.green,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _sessionButton(
                                  '2 Hrs',
                                  120,
                                  Colors.purple,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _sessionButton(
                                  '3 Hrs',
                                  180,
                                  Colors.pink,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 28),
                      const Text(
                        'Take A Break',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(
                            width: 100,
                            child: TextField(
                              controller: _breakController,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: 'Minutes',
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          ElevatedButton.icon(
                            onPressed: _isActive
                                ? null
                                : () {
                                    final mins =
                                        int.tryParse(_breakController.text) ??
                                        5;
                                    _startSession(mins, isBreak: true);
                                  },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.white,
                              foregroundColor: Colors.black87,
                              elevation: 2,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 8,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            icon: Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: Colors.green[50],
                                borderRadius: BorderRadius.circular(40),
                              ),
                              child: Icon(
                                Icons.coffee_outlined,
                                color: Colors.green[500],
                                size: 30,
                              ),
                            ),
                            label: Text(
                              'Start Break',
                              style: TextStyle(
                                color: Colors.green[700]
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 28),
                      Row(
                        children: [
                          Expanded(
                            child: _statCard(
                              context,
                              icon: Icons.timer_outlined,
                              label: 'Total Focus Time',
                              value: _formatTime(_totalFocusSecondsToday),
                              color: Colors.blueAccent,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: _statCard(
                              context,
                              icon: Icons.schedule_outlined,
                              label: 'Time Left In Day',
                              value: _formatTime(_secondsLeftInDay),
                              color: Colors.green,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Widget _statCard(
  BuildContext context, {
  required IconData icon,
  required String label,
  required String value,
  required Color color,
}) {
  return Card(
    elevation: 4,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            color.withValues(alpha: 0.12),
            color.withValues(alpha: 0.04),
          ],
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(height: 8),
          Text(
            label,
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(color: Colors.grey.shade700),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    ),
  );
}

enum TimerPhase { idle, running, paused }
