import 'dart:async';
import 'package:flutter/widgets.dart';

/// Keep wall-clock displays correct without waking hidden/background screens.
/// Elapsed time is recomputed from its timestamp when the screen becomes active.
mixin VisibleClock<T extends StatefulWidget> on State<T> {
  Timer? _clockTimer;
  bool _clockVisible = false;
  bool _clockForeground = true;
  late final _clockObserver = _ClockLifecycle((state) {
    _clockForeground = state == AppLifecycleState.resumed;
    _scheduleClock();
  });
  void onVisibleClockTick();
  @override
  void initState() {
    super.initState();
    _clockForeground =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(_clockObserver);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _clockVisible =
        TickerMode.of(context) && (ModalRoute.of(context)?.isCurrent ?? true);
    _scheduleClock();
  }

  void _scheduleClock() {
    if (!mounted) return;
    if (!_clockVisible || !_clockForeground) {
      _clockTimer?.cancel();
      _clockTimer = null;
    } else if (_clockTimer == null) {
      onVisibleClockTick();
      _clockTimer = Timer.periodic(
        const Duration(seconds: 1),
        (_) => onVisibleClockTick(),
      );
    }
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    WidgetsBinding.instance.removeObserver(_clockObserver);
    super.dispose();
  }
}

class _ClockLifecycle extends WidgetsBindingObserver {
  final void Function(AppLifecycleState) changed;
  _ClockLifecycle(this.changed);
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) => changed(state);
}
