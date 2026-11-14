import 'dart:async';

import 'package:dhara/core/window/window_controller.dart';
import 'package:flutter/services.dart';

/// The app's window, steered through the `dhara/window` channel that the
/// Windows runner answers (`windows/runner/flutter_window.cpp`).
///
/// Until [useCustomFrame] has succeeded the system's title bar is in use
/// and [hasCustomFrame] is false; on a system whose runner has no such
/// channel it stays that way, and every call here does nothing.
class NativeWindowController extends WindowController {
  NativeWindowController({
    MethodChannel channel = const MethodChannel('dhara/window'),
  }) : _channel = channel {
    _channel.setMethodCallHandler(_onCall);
  }

  final MethodChannel _channel;
  var _customFrame = false;
  var _maximized = false;
  var _fullscreen = false;

  @override
  bool get hasCustomFrame => _customFrame;

  @override
  bool get isMaximized => _maximized;

  @override
  bool get isFullscreen => _fullscreen;

  /// Asks the runner to take the system's title bar off the window, so
  /// that the app can draw its own. Call before the first frame. Never
  /// throws; returns whether the window now has the app's own frame.
  Future<bool> useCustomFrame() async {
    try {
      final state = await _channel.invokeMethod<Object?>(
        'setCustomFrame',
        true,
      );
      _customFrame = true;
      _apply(state);
    } on MissingPluginException {
      // Not the Windows runner: the system's title bar stays.
    } on PlatformException {
      // The runner refused: the system's title bar stays.
    }
    notifyListeners();
    return _customFrame;
  }

  @override
  void startDrag() => _send('startDrag');

  @override
  void startResize(WindowEdge edge) => _send('startResize', edge.name);

  @override
  void minimize() => _send('minimize');

  @override
  void toggleMaximize() => _send('toggleMaximize');

  @override
  void close() => _send('close');

  @override
  void dispose() {
    _channel.setMethodCallHandler(null);
    super.dispose();
  }

  /// The runner reports every change of state: the window can also be
  /// maximized by snapping it, or go fullscreen from the player.
  Future<Object?> _onCall(MethodCall call) async {
    if (call.method == 'stateChanged' && _apply(call.arguments)) {
      notifyListeners();
    }
    return null;
  }

  /// Takes over what the runner says; returns whether anything changed.
  bool _apply(Object? state) {
    if (state is! Map) return false;
    final maximized = state['maximized'];
    final fullscreen = state['fullscreen'];
    if (maximized is! bool || fullscreen is! bool) return false;
    if (maximized == _maximized && fullscreen == _fullscreen) return false;
    _maximized = maximized;
    _fullscreen = fullscreen;
    return true;
  }

  void _send(String method, [Object? argument]) {
    if (!_customFrame) return;
    unawaited(
      _channel
          .invokeMethod<void>(method, argument)
          .then<void>((_) {}, onError: (Object _) {}),
    );
  }
}
