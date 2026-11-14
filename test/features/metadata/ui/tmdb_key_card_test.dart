import 'package:dhara/core/secrets/secret_store.dart';
import 'package:dhara/features/metadata/tmdb_key.dart';
import 'package:dhara/features/metadata/ui/tmdb_key_card.dart';
import 'package:dhara/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Shaped like TMDB's, made up.
final _token = 'eyJhbGciOiJIUzI1NiJ9.${'a' * 120}.${'b' * 43}';
const _apiKey = '0123456789abcdef0123456789abcdef';

/// A secure storage that reads but does not write.
class _ReadOnlyStore extends MemorySecretStore {
  @override
  bool get keepsSecrets => true;

  @override
  Future<void> write(String name, String value) =>
      throw const SecretStoreException('read only');
}

void main() {
  Future<TmdbKeyController> show(
    WidgetTester tester, {
    SecretStore? store,
    String? saved,
  }) async {
    final secrets = store ?? MemorySecretStore();
    if (saved != null) await secrets.write('tmdb', saved);
    final controller = TmdbKeyController(secrets);
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildDharaTheme(),
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(24),
            child: TmdbKeyCard(controller: controller),
          ),
        ),
      ),
    );
    return controller;
  }

  String status(WidgetTester tester) =>
      tester.widget<Text>(find.byKey(const Key('tmdb-key-status'))).data!;

  String field(WidgetTester tester) => tester
      .widget<TextField>(find.byKey(const Key('tmdb-key-field')))
      .controller!
      .text;

  testWidgets('says whether a key is saved, once it has looked', (
    tester,
  ) async {
    final controller = await show(tester);
    expect(status(tester), 'Looking for a saved key …');
    expect(find.byKey(const Key('tmdb-key-remove')), findsNothing);

    await controller.load();
    await tester.pump();

    expect(status(tester), 'No key saved.');
    expect(find.text(tmdbAttribution), findsOneWidget);
    expect(find.textContaining('until the app closes'), findsOneWidget);
  });

  testWidgets('saves a pasted key and never shows it', (tester) async {
    final controller = await show(tester);
    await controller.load();
    await tester.pump();
    final input = tester.widget<TextField>(
      find.byKey(const Key('tmdb-key-field')),
    );
    expect(input.obscureText, isTrue);
    expect(input.enableSuggestions, isFalse);
    expect(input.autocorrect, isFalse);

    await tester.enterText(find.byKey(const Key('tmdb-key-field')), _token);
    await tester.tap(find.byKey(const Key('tmdb-key-save')));
    await tester.pump();

    expect(status(tester), 'A key is saved: API Read Access Token.');
    expect(field(tester), isEmpty, reason: 'cleared once it is saved');
    expect(find.textContaining('eyJ'), findsNothing);
    expect(await controller.key(), _token);
    expect(find.byKey(const Key('tmdb-key-remove')), findsOneWidget);
  });

  testWidgets('Enter in the field saves too', (tester) async {
    final controller = await show(tester);
    await controller.load();

    await tester.enterText(find.byKey(const Key('tmdb-key-field')), _apiKey);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(status(tester), 'A key is saved: API key.');
  });

  testWidgets('refuses what is not a key and keeps it to be corrected', (
    tester,
  ) async {
    final controller = await show(tester, saved: _apiKey);
    await controller.load();

    await tester.enterText(find.byKey(const Key('tmdb-key-field')), 'nonsense');
    await tester.tap(find.byKey(const Key('tmdb-key-save')));
    await tester.pump();

    expect(
      find.textContaining('neither a TMDB token nor a TMDB API key'),
      findsOneWidget,
    );
    expect(field(tester), 'nonsense');
    expect(status(tester), 'A key is saved: API key.');
    expect(await controller.key(), _apiKey);
  });

  testWidgets('removes the saved key', (tester) async {
    final controller = await show(tester, saved: _apiKey);
    await controller.load();
    await tester.pump();
    expect(find.textContaining(_apiKey), findsNothing);

    await tester.tap(find.byKey(const Key('tmdb-key-remove')));
    await tester.pump();

    expect(status(tester), 'No key saved.');
    expect(controller.hasKey, isFalse);
    expect(find.byKey(const Key('tmdb-key-remove')), findsNothing);
  });

  testWidgets('says so when the key cannot be saved', (tester) async {
    final controller = await show(tester, store: _ReadOnlyStore());
    await controller.load();
    await tester.pump();
    expect(find.textContaining('Windows Credential Manager'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('tmdb-key-field')), _token);
    await tester.tap(find.byKey(const Key('tmdb-key-save')));
    await tester.pump();

    expect(find.text('The key could not be saved.'), findsOneWidget);
    expect(status(tester), 'No key saved.');
  });
}
