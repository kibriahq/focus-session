# Persist Timer State Across App Close

## Problem
When the app is closed/killed while a timer is running, all in-memory state is lost. On reopening, the user sees no active session and the completed focus time is lost.

## Root Cause
`_endTime`, `_phase`, `_totalDuration`, and `_isBreak` are stored only in memory. `SharedPreferences` is used for daily focus seconds but not for active timer state.

## Solution
Persist the active timer state to `SharedPreferences` and restore it on app startup.

## Implementation Plan

### 1. Add persistence helpers

Add a `_persistTimer()` method that saves to `SharedPreferences`:
- `'timer_phase'` → `_phase.name` ("running", "paused", "idle")
- `'timer_end_time'` → `_endTime!.toIso8601String()` (when not null)
- `'timer_total_duration'` → `_totalDuration`
- `'timer_is_break'` → `_isBreak`

Add a `_clearPersistedTimer()` method that removes all timer keys from `SharedPreferences`.

### 2. Call `_persistTimer()` when timer state changes
- In `_startSession()` after setting `_endTime`
- In `_resume()` after setting `_endTime`
- In `_pause()` when switching to paused (optional but recommended)

### 3. Call `_clearPersistedTimer()` when timer naturally ends
- In `_completeSession()` after setting state to idle
- In any method that sets `_phase = TimerPhase.idle`

### 4. Restore timer state on app startup
In `initState()` (after `_loadFocusTime()`), add a `_restoreTimer()` call:

```dart
Future<void> _restoreTimer() async {
  final prefs = await SharedPreferences.getInstance();
  final phaseStr = prefs.getString('timer_phase');
  if (phaseStr == null || phaseStr == 'idle') return;

  final endTimeStr = prefs.getString('timer_end_time');
  final totalDuration = prefs.getInt('timer_total_duration') ?? 0;
  final isBreak = prefs.getBool('timer_is_break') ?? false;

  if (endTimeStr == null) {
    await _clearPersistedTimer();
    return;
  }

  final endTime = DateTime.tryParse(endTimeStr);
  if (endTime == null) {
    await _clearPersistedTimer();
    return;
  }

  final now = DateTime.now();
  final diff = endTime.difference(now).inSeconds;

  if (diff <= 0) {
    // Session completed while app was closed — process silently
    final focusToAdd = isBreak ? 0 : totalDuration;
    if (focusToAdd > 0) {
      _totalFocusSecondsToday += focusToAdd;
      await prefs.setInt(_storageKey, _totalFocusSecondsToday);
    }
    await _clearPersistedTimer();
    return;
  }

  // Session still active — restore it
  setState(() {
    _phase = TimerPhase.running;
    _totalDuration = totalDuration;
    _remaining = diff;
    _isBreak = isBreak;
    _endTime = endTime;
    _runId++;
  });
  _scheduleRefresh(_runId);
}
```

**Note:** When the app was closed and the session already completed, we process the completion silently (no sound, no SnackBar) because the user was not present. The focus seconds are still added.

### 5. Handle edge case in `_completeSession()` for sound/SnackBar
Since `_completeSession()` plays a sound and shows a SnackBar, it should only do so when called during normal operation (user present). The `_restoreTimer()` path handles its own silent completion without calling `_completeSession()`.

## Validation
1. Start a 1-minute focus session
2. Close the app (force-close / swipe away)
3. Wait a few seconds, then reopen the app
4. Expected: timer shows correct remaining time and continues ticking
5. Wait for timer to complete
6. Expected: focus time is added (check daily total)
7. Repeat, but close the app and wait until after the timer would have ended
8. Expected: on reopening, timer is idle and focus time has been added

## Files to Modify
- `lib/main.dart` — only file that needs changes
- No new dependencies needed (uses existing `shared_preferences`)
