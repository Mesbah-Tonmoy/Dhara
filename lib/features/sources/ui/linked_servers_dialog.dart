import 'package:dhara/features/sources/portal_links.dart';
import 'package:dhara/features/sources/source.dart';
import 'package:dhara/theme/tokens.dart';
import 'package:dhara/widgets/buttons.dart';
import 'package:flutter/material.dart';

/// Lists the servers the website [source] links to ([links], from its
/// last test) and says for each whether it is in the list ([sources])
/// already. Returns the link the user wants to add as a source, or `null`
/// if the dialog is just closed.
///
/// Nothing here contacts a server: a link only becomes something the app
/// talks to once the user has added it and tested it.
Future<PortalLink?> showLinkedServersDialog(
  BuildContext context, {
  required Source source,
  required List<PortalLink> links,
  required List<Source> sources,
}) => showDialog<PortalLink>(
  context: context,
  builder: (context) => AlertDialog(
    title: Text('Servers ${source.name} links to'),
    content: SizedBox(
      width: 560,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'This address is a front page: it holds no videos itself, '
              'only links to other servers. Dhara reads a server once it '
              'is a source of its own in this list.',
              style: TextStyle(
                fontFamily: DharaFonts.ui,
                fontSize: DharaType.sm,
                height: DharaType.body,
                color: DharaColors.text2,
              ),
            ),
            const SizedBox(height: .6 * rem),
            for (final link in links)
              _LinkRow(
                key: Key('linked-${link.url.host}'),
                link: link,
                known: sourcesBehind(link, sources),
                onAdd: () => Navigator.of(context).pop(link),
              ),
          ],
        ),
      ),
    ),
    actions: [
      DharaButton(
        key: const Key('linked-close'),
        label: 'Close',
        small: true,
        autofocus: true,
        onPressed: () => Navigator.of(context).pop(),
      ),
    ],
  ),
);

class _LinkRow extends StatelessWidget {
  const _LinkRow({
    super.key,
    required this.link,
    required this.known,
    required this.onAdd,
  });

  final PortalLink link;

  /// The sources of the list this link leads to.
  final List<Source> known;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: .5 * rem),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Plain Text: both are what the page says.
                Text(
                  link.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: DharaFonts.ui,
                    fontSize: DharaType.md,
                    fontWeight: DharaType.semibold,
                    color: DharaColors.text,
                  ),
                ),
                Text(
                  '${link.url}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: DharaFonts.mono,
                    fontFamilyFallback: DharaFonts.monoFallback,
                    fontSize: DharaType.xs,
                    color: DharaColors.text3,
                  ),
                ),
                if (known.isNotEmpty)
                  Text(
                    'In your list: '
                    '${[for (final source in known) source.name].join(', ')}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: DharaFonts.ui,
                      fontSize: DharaType.xs,
                      height: 1.5,
                      color: DharaColors.good,
                    ),
                  ),
              ],
            ),
          ),
          if (known.isEmpty) ...[
            const SizedBox(width: rem),
            DharaButton(
              key: Key('linked-add-${link.url.host}'),
              label: 'Add as source',
              small: true,
              onPressed: onAdd,
            ),
          ],
        ],
      ),
    );
  }
}
