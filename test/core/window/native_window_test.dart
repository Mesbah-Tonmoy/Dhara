import 'package:dhara/core/window/native_window.dart';
import 'package:dhara/core/window/window_controller.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('dhara/window');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  /// Stands in for the Windows runner; notes every call it gets.
  List<MethodCall> runner({
    Map<String, Object?> state = const {
      'maximized': false,
      'fullscreen': false,
    },
    bool refuses = false,
  }) {
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (refuses) throw PlatformException(code: 'no-window');
      return call.method == 'setCustomFrame' ? state : null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    return calls;
  }

  /// What the runner sends when the window's state changes.
  Future<void> fromRunner(Object? arguments) => messenger.handlePlatformMessage(
    channel.name,
    const StandardMethodCodec().encodeMethodCall(
      MethodCall('stateChanged', arguments),
    ),
    (_) {},
  );

  test('starts with the system\'s title bar', () {
    final window = NativeWindowController();
    addTearDown(window.dispose);

    expect(window.hasCustomFrame, isFalse);
    expect(window.isMaximized, isFalse);
    expect(window.isFullscreen, isFalse);
  });

  test('takes over the frame when the runner agrees, with the state the '
      'window is in', () async {
    final calls = runner(state: {'maximized': true, 'fullscreen': false});
    final window = NativeWindowController();
    addTearDown(window.dispose);
    var notified = 0;
    window.addListener(() => notified++);

    expect(await window.useCustomFrame(), isTrue);

    expect(calls.single.method, 'setCustomFrame');
    expect(calls.single.arguments, isTrue);
    expect(window.hasCustomFrame, isTrue);
    expect(window.isMaximized, isTrue);
    expect(notified, 1);
  });

  test('keeps the system\'s title bar where there is no such runner, and '
      'then asks nothing of it', () async {
    final window = NativeWindowController();
    addTearDown(window.dispose);

    expect(await window.useCustomFrame(), isFalse);
    expect(window.hasCustomFrame, isFalse);

    final calls = runner();
    window
      ..startDrag()
      ..minimize()
      ..toggleMaximize()
      ..close();
    await Future<void>.delayed(Duration.zero);
    expect(calls, isEmpty);
  });

  test('keeps the system\'s title bar when the runner refuses', () async {
    runner(refuses: true);
    final window = NativeWindowController();
    addTearDown(window.dispose);

    expect(await window.useCustomFrame(), isFalse);
    expect(window.hasCustomFrame, isFalse);
  });

  test('passes on what the title bar asks for', () async {
    final calls = runner();
    final window = NativeWindowController();
    addTearDown(window.dispose);
    await window.useCustomFrame();
    calls.clear();

    window
      ..startDrag()
      ..startResize(WindowEdge.top)
      ..startResize(WindowEdge.topLeft)
      ..startResize(WindowEdge.topRight)
      ..minimize()
      ..toggleMaximize()
      ..close();
    await Future<void>.delayed(Duration.zero);

    expect(
      [for (final call in calls) (call.method, call.arguments)],
      [
        ('startDrag', null),
        ('startResize', 'top'),
        ('startResize', 'topLeft'),
        ('startResize', 'topRight'),
        ('minimize', null),
        ('toggleMaximize', null),
        ('close', null),
      ],
    );
  });

  test('follows the state the runner reports, and tells its listeners '
      'only of changes', () async {
    runner();
    final window = NativeWindowController();
    addTearDown(window.dispose);
    await window.useCustomFrame();
    var notified = 0;
    window.addListener(() => notified++);

    await fromRunner({'maximized': true, 'fullscreen': false});
    expect(window.isMaximized, isTrue);
    expect(notified, 1);

    await fromRunner({'maximized': true, 'fullscreen': false});
    expect(notified, 1);

    await fromRunner({'maximized': true, 'fullscreen': true});
    expect(window.isFullscreen, isTrue);
    expect(notified, 2);
  });

  test('ignores a report that is not what it expects', () async {
    runner();
    final window = NativeWindowController();
    addTearDown(window.dispose);
    await window.useCustomFrame();
    var notified = 0;
    window.addListener(() => notified++);

    for (final report in <Object?>[
      null,
      'maximized',
      {'maximized': 'yes', 'fullscreen': false},
      {'maximized': true},
    ]) {
      await fromRunner(report);
    }

    expect(window.isMaximized, isFalse);
    expect(notified, 0);
  });

  test('a failing call does not surface as an error', () async {
    final calls = runner();
    final window = NativeWindowController();
    addTearDown(window.dispose);
    await window.useCustomFrame();
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      throw PlatformException(code: 'no-window');
    });

    window.minimize();
    await Future<void>.delayed(Duration.zero);

    expect(calls.last.method, 'minimize');
  });
}
