import 'dart:async';

import 'package:dhara/features/metadata/tmdb_key.dart';
import 'package:dhara/features/player/widgets/glass.dart';
import 'package:dhara/theme/tokens.dart';
import 'package:flutter/material.dart';

/// The notice TMDB asks every app that uses its API to show.
const tmdbAttribution =
    'This product uses the TMDB API but is not endorsed or certified by TMDB.';

/// Where the user pastes their TMDB key, sees whether one is saved, and
/// removes it. The key is typed into a hidden field, handed straight to
/// the secure storage and never shown again.
class TmdbKeyCard extends StatefulWidget {
  const TmdbKeyCard({super.key, required this.controller});

  final TmdbKeyController controller;

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

        return Container(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
          decoration: BoxDecoration(
            color: DharaColors.surface,
            borderRadius: BorderRadius.circular(DharaRadii.md),
            border: Border.all(color: DharaColors.stroke),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const PanelHeading('TMDB key'),
              const SizedBox(height: 8),
              Text(
                'Posters, descriptions and episode names come from The '
                'Movie Database. Paste the API Read Access Token (or the API '
                'key) from your TMDB account settings. $kept',
                style: const TextStyle(fontSize: 13, color: DharaColors.text2),
              ),
              const SizedBox(height: 12),
              Text(
                status,
                key: const Key('tmdb-key-status'),
                style: TextStyle(fontSize: 13, color: color),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('tmdb-key-field'),
                controller: _field,
                obscureText: true,
                autocorrect: false,
                enableSuggestions: false,
                enableIMEPersonalizedLearning: false,
                onSubmitted: (_) => unawaited(_save()),
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  hintText: kind == null
                      ? 'Paste the token or key'
                      : 'Paste another one to replace it',
                  errorText: _error,
                  errorMaxLines: 2,
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  DharaPillButton(
                    key: const Key('tmdb-key-save'),
                    primary: true,
                    icon: Icons.lock_outline,
                    label: 'Save key',
                    onPressed: () => unawaited(_save()),
                  ),
                  if (kind != null)
                    DharaPillButton(
                      key: const Key('tmdb-key-remove'),
                      icon: Icons.delete_outline,
                      label: 'Remove key',
                      onPressed: () => unawaited(_remove()),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              const Text(
                tmdbAttribution,
                style: TextStyle(fontSize: 11.5, color: DharaColors.text3),
              ),
            ],
          ),
        );
      },
    );
  }
}
