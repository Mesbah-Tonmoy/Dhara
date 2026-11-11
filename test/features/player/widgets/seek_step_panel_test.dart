import 'package:dhara/features/player/widgets/seek_step_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Hosts the panel with real state, like the settings would.
class _Host extends StatefulWidget {
  const _Host({required this.back, required this.forward});

  final int back;
  final int forward;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  late int back = widget.back;
  late int forward = widget.forward;

  @override
  Widget build(BuildContext context) {
    return SeekStepPanel(
      backSeconds: back,
      forwardSeconds: forward,
      onBackChanged: (v) => setState(() => back = v),
      onForwardChanged: (v) => setState(() => forward = v),
    );
  }
}

Future<_HostState> _pump(
  WidgetTester tester, {
  int back = 10,
  int forward = 30,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 520,
            child: _Host(back: back, forward: forward),
          ),
        ),
      ),
    ),
  );
  return tester.state<_HostState>(find.byType(_Host));
}

/// Whether the chip with [key] is drawn as the active choice.
bool _selected(WidgetTester tester, String key) {
  final chip = tester.widget<Semantics>(
    find
        .descendant(
          of: find.byKey(Key(key)),
          matching: find.byType(Semantics),
        )
        .first,
  );
  return chip.properties.selected ?? false;
}

Finder _customField(String id) {
  return find.descendant(
    of: find.byKey(Key('step-$id-custom')),
    matching: find.byType(TextField),
  );
}

void main() {
  testWidgets('offers every preset for both directions', (tester) async {
    await _pump(tester);

    for (final id in ['back', 'forward']) {
      for (final preset in [5, 10, 15, 30, 60, 90, 120]) {
        expect(find.byKey(Key('step-$id-$preset')), findsOneWidget);
      }
      expect(find.byKey(Key('step-$id-custom')), findsOneWidget);
    }
  });

  testWidgets('marks the active value in each row', (tester) async {
    await _pump(tester, back: 10, forward: 45);

    expect(_selected(tester, 'step-back-10'), isTrue);
    expect(_selected(tester, 'step-back-30'), isFalse);
    expect(_selected(tester, 'step-back-custom'), isFalse);

    expect(_selected(tester, 'step-forward-custom'), isTrue);
    for (final preset in [5, 10, 15, 30, 60, 90, 120]) {
      expect(_selected(tester, 'step-forward-$preset'), isFalse);
    }
  });

  testWidgets('picking a preset changes only that direction', (tester) async {
    final host = await _pump(tester);

    await tester.tap(find.byKey(const Key('step-back-60')));
    await tester.pump();

    expect(host.back, 60);
    expect(host.forward, 30);

    await tester.tap(find.byKey(const Key('step-forward-5')));
    await tester.pump();

    expect(host.back, 60);
    expect(host.forward, 5);
  });

  testWidgets('a typed custom value is applied as it is typed', (tester) async {
    final host = await _pump(tester);

    await tester.enterText(_customField('forward'), '45');
    await tester.pump();

    expect(host.forward, 45);
    expect(host.back, 10);
  });

  testWidgets('custom values are limited to 1–600 seconds', (tester) async {
    final host = await _pump(tester);

    await tester.enterText(_customField('back'), '999');
    await tester.pump();
    expect(host.back, 600);

    await tester.enterText(_customField('back'), '0');
    await tester.pump();
    expect(host.back, 1);
  });

  testWidgets('ignores an empty field and non-digits', (tester) async {
    final host = await _pump(tester, back: 45);

    await tester.enterText(_customField('back'), '');
    await tester.pump();
    expect(host.back, 45);

    await tester.enterText(_customField('back'), '-7x');
    await tester.pump();
    expect(host.back, 7, reason: 'only the digits are kept');
  });

  testWidgets('shows a stored custom value in the field', (tester) async {
    await _pump(tester, back: 45);

    expect(
      tester.widget<TextField>(_customField('back')).controller!.text,
      '45',
    );
    expect(
      tester.widget<TextField>(_customField('forward')).controller!.text,
      '',
    );
  });

  testWidgets('picking a preset clears the custom field', (tester) async {
    await _pump(tester, back: 45);

    await tester.tap(find.byKey(const Key('step-back-15')));
    await tester.pump();

    expect(
      tester.widget<TextField>(_customField('back')).controller!.text,
      '',
    );
  });

  testWidgets('shows the applied value after leaving the field',
      (tester) async {
    await _pump(tester);

    await tester.enterText(_customField('back'), '999');
    await tester.pump();
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(
      tester.widget<TextField>(_customField('back')).controller!.text,
      '600',
    );
  });
}
