import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class _AppLifecycleNotifier extends Notifier<AppLifecycleState> {
  @override
  AppLifecycleState build() => AppLifecycleState.resumed;

  void updateState(AppLifecycleState state) {
    this.state = state;
  }
}

final appLifecycleProvider =
    NotifierProvider<_AppLifecycleNotifier, AppLifecycleState>(
      _AppLifecycleNotifier.new,
    );

class _LifecycleObserver extends WidgetsBindingObserver {
  final void Function(AppLifecycleState) onChange;

  _LifecycleObserver(this.onChange);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    onChange(state);
  }
}

final appLifecycleObserverProvider = Provider<void>((ref) {
  final observer = _LifecycleObserver((state) {
    ref.read(appLifecycleProvider.notifier).updateState(state);
  });
  WidgetsBinding.instance.addObserver(observer);
  ref.onDispose(() => WidgetsBinding.instance.removeObserver(observer));
});
