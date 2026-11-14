import 'package:dhara/shell/app_shell.dart';
import 'package:dhara/theme/scale.dart';
import 'package:dhara/widgets/toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/test_app.dart';

void main() {
  testWidgets('the app boots into the shell, on Home', (tester) async {
    await tester.pumpWidget(testApp().app);

    expect(find.byType(AppShell), findsOneWidget);
    expect(find.byKey(const Key('app-title')), findsOneWidget);
    expect(find.byKey(const Key('shell-search')), findsOneWidget);
    expect(find.byKey(const Key('rail-home')), findsOneWidget);
  });

  testWidgets('the whole app is scaled and can show messages', (tester) async {
    await tester.pumpWidget(testApp().app);

    final shell = find.byType(AppShell);
    expect(
      find.ancestor(of: shell, matching: find.byType(DharaScale)),
      findsOneWidget,
    );
    expect(
      find.ancestor(of: shell, matching: find.byType(ToastHost)),
      findsOneWidget,
    );
  });
}
