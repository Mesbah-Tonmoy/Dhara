import 'package:dhara/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('app boots and shows the placeholder title', (tester) async {
    await tester.pumpWidget(const DharaApp());

    expect(find.byKey(const Key('app-title')), findsOneWidget);
  });
}
