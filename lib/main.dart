import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
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
  final TextEditingController _breakController =
      TextEditingController(text: '5');
  int _totalFocusSecondsToday = 0;
  int _secondsLeftInDay = _computeSecondsLeftInDay();

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
      setState(() =>
          _totalFocusSecondsToday = prefs.getInt(_storageKey) ?? 0);
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
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _isBreak ? 'Break finished!' : 'Session completed!',
          ),
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
              style: const TextStyle(
                fontSize: 40,
                fontWeight: FontWeight.bold,
              ),
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

  Widget _sessionButton(String label, int minutes) {
    return ElevatedButton(
      onPressed: () => _startSession(minutes),
      child: Text(label),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Focus Session'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: SingleChildScrollView(
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
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              alignment: WrapAlignment.center,
              children: [
                _sessionButton('5 Min', 5),
                _sessionButton('15 Min', 15),
                _sessionButton('30 Min', 30),
                _sessionButton('1 Hour', 60),
                _sessionButton('2 Hours', 120),
              ],
            ),
            const SizedBox(height: 28),
            const Text(
              'Take A Break',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
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
                              int.tryParse(_breakController.text) ?? 5;
                          _startSession(mins, isBreak: true);
                        },
                  icon: const Icon(Icons.coffee),
                  label: const Text('Start Break'),
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
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: Colors.grey.shade700,
                ),
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
