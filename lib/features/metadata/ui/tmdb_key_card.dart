import 'dart:async';

import 'package:dhara/features/metadata/tmdb_key.dart';
import 'package:dhara/theme/tokens.dart';
import 'package:dhara/widgets/buttons.dart';
import 'package:dhara/widgets/icons.dart';
import 'package:dhara/widgets/page_parts.dart';
import 'package:dhara/widgets/surfaces.dart';
import 'package:flutter/material.dart';

/// The notice TMDB asks every app that uses its API to show.
const tmdbAttribution =
    'This product uses the TMDB API but is not endorsed or certified by TMDB.';

/// Where the user pastes their TMDB key, sees whether one is saved, and
/// removes it. The key is typed into a hidden field, handed straight to
/// the secure storage and never shown again.
class TmdbKeyCard extends StatefulWidget {
  const TmdbKeyCard({super.key, required this.controller, this.framed = true});

  final TmdbKeyController controller;

  /// Draws a pane around the card; off where it sits in one already (the
  /// dialog).
  final bool framed;

  @override
  State<TmdbKeyCard> createState() => _TmdbKeyCardState();
}

class _TmdbKeyCardState extends State<TmdbKeyCard> {
  final _field = TextEditingController();
  String? _error;
  var _busy = false;

  @override
  void dispose() {
    // Nothing of a key that was typed but not saved stays behind.
    _field.clear();
    _field.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy) return;
    setState(() => _busy = true);
    final problem = await widget.controller.save(_field.text);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = switch (problem) {
        null => null,
        TmdbKeyProblem.notAKey =>
          'That is neither a TMDB token nor a TMDB API key. Copy it whole '
              'from your TMDB account settings.',
        TmdbKeyProblem.storage => 'The key could not be saved.',
      };
      if (problem == null) _field.clear();
    });
    // A key that is saved is asked about at once.
    if (problem == null) unawaited(widget.controller.test());
  }

  Future<void> _remove() async {
    if (_busy) return;
    setState(() => _busy = true);
    final problem = await widget.controller.remove();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = problem == null ? null : 'The key could not be removed.';
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final controller = widget.controller;
        final kind = controller.kind;
        final (status, color) = !controller.isLoaded
            ? ('Looking for a saved key …', DharaColors.text3)
            : controller.unreadable
            ? ('The secure storage could not be read.', DharaColors.warn)
            : kind == null
            ? ('No key saved.', DharaColors.text2)
            : ('A key is saved: ${kind.label}.', DharaColors.good);
        final kept = controller.keptAfterRestart
            ? 'It is kept in Windows Credential Manager, never in the files '
                  'of the app.'
            : 'This system has no secure storage the app can use yet, so '
                  'the key is kept until the app closes.';

        final card = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'TMDB key',
              style: TextStyle(
                fontFamily: DharaFonts.display,
                fontSize: DharaType.lg,
                fontWeight: DharaType.bold,
                color: DharaColors.text,
              ),
            ),
            const SizedBox(height: .5 * rem),
            Text(
              'Posters, descriptions and episode names come from The '
              'Movie Database. Paste the API Read Access Token (or the API '
              'key) from your TMDB account settings. $kept',
              style: _bodyStyle,
            ),
            const SizedBox(height: .8 * rem),
            Text(
              status,
              key: const Key('tmdb-key-status'),
              style: _bodyStyle.copyWith(color: color),
            ),
            if (_checkLine(controller) case (final text, final tint)?) ...[
              const SizedBox(height: .25 * rem),
              Text(
                text,
                key: const Key('tmdb-key-check'),
                style: _bodyStyle.copyWith(color: tint),
              ),
            ],
            const SizedBox(height: .8 * rem),
            DharaField(
              key: const Key('tmdb-key-field'),
              controller: _field,
              // Shown as dots, and kept from the system's keyboard.
              obscure: true,
              // In its dialog the key can be pasted at once.
              autofocus: !widget.framed,
              icon: DharaIcons.key,
              onSubmitted: (_) => unawaited(_save()),
              hint: kind == null
                  ? 'Paste the token or key'
                  : 'Paste another one to replace it',
              error: _error,
            ),
            const SizedBox(height: .8 * rem),
            Wrap(
              spacing: .5 * rem,
              runSpacing: .5 * rem,
              children: [
                DharaButton(
                  key: const Key('tmdb-key-save'),
                  style: DharaButtonStyle.primary,
                  small: true,
                  icon: DharaIcons.locked,
                  label: 'Save key',
                  onPressed: _busy ? null : () => unawaited(_save()),
                ),
                if (kind != null)
                  DharaButton(
                    key: const Key('tmdb-key-test'),
                    small: true,
                    icon: DharaIcons.testConnection,
                    label: 'Test key',
                    onPressed: () => unawaited(controller.test()),
                  ),
                if (kind != null)
                  DharaButton(
                    key: const Key('tmdb-key-remove'),
                    small: true,
                    danger: true,
                    icon: DharaIcons.remove,
                    label: 'Remove key',
                    onPressed: _busy ? null : () => unawaited(_remove()),
                  ),
              ],
            ),
            const SizedBox(height: rem),
            const Text(
              tmdbAttribution,
              style: TextStyle(
                fontFamily: DharaFonts.ui,
                fontSize: DharaType.xs,
                height: 1.4,
                color: DharaColors.text3,
              ),
            ),
          ],
        );
        if (!widget.framed) return card;
        return GlassCard(padding: const EdgeInsets.all(1.2 * rem), child: card);
      },
    );
  }
}

const _bodyStyle = TextStyle(
  fontFamily: DharaFonts.ui,
  fontSize: DharaType.sm,
  height: 1.45,
  color: DharaColors.text2,
);

/// What TMDB said about the saved key, and the colour to say it in; `null`
/// if it has not been asked.
(String, Color)? _checkLine(TmdbKeyController controller) {
  if (controller.isChecking) return ('Asking TMDB …', DharaColors.text3);
  return switch (controller.lastCheck) {
    null => null,
    TmdbKeyCheck.accepted => ('TMDB accepts this key.', DharaColors.good),
    TmdbKeyCheck.refused => (
      'TMDB does not accept this key. Copy it again from your TMDB '
          'account settings.',
      DharaColors.bad,
    ),
    TmdbKeyCheck.unreachable => (
      'TMDB could not be reached. Check the connection and test again.',
      DharaColors.warn,
    ),
  };
}

/// Shows the [TmdbKeyCard] in a dialog.
Future<void> showTmdbKeyDialog(
  BuildContext context,
  TmdbKeyController controller,
) => showDialog<void>(
  context: context,
  builder: (context) => DharaDialog(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(1.4 * rem),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TmdbKeyCard(controller: controller, framed: false),
          const SizedBox(height: rem),
          Align(
            alignment: Alignment.centerRight,
            child: DharaButton(
              key: const Key('tmdb-key-close'),
              label: 'Close',
              small: true,
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
        ],
      ),
    ),
  ),
);
