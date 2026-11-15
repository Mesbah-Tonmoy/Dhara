import 'package:dhara/theme/tokens.dart';
import 'package:dhara/widgets/icons.dart';
import 'package:dhara/widgets/pressable.dart';
import 'package:dhara/widgets/surfaces.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// The top of a working page (Library index, Titles and matching): its
/// name, a line about what it is for, and its buttons on the right, which
/// move below the text when the window is narrow.
class PageHead extends StatelessWidget {
  const PageHead({
    super.key,
    required this.title,
    required this.subtitle,
    this.actions = const [],
  });

  final String title;
  final String subtitle;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.end,
      spacing: rem,
      runSpacing: rem,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 40 * rem),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Semantics(
                header: true,
                child: Text(
                  title,
                  style: const TextStyle(
                    fontFamily: DharaFonts.display,
                    fontSize: DharaType.xxl,
                    fontWeight: DharaType.bold,
                    letterSpacing: -.03 * DharaType.xxl,
                    height: 1.1,
                    color: DharaColors.text,
                  ),
                ),
              ),
              const SizedBox(height: .3 * rem),
              Text(
                subtitle,
                style: const TextStyle(
                  fontFamily: DharaFonts.ui,
                  fontSize: DharaType.sm,
                  height: 1.45,
                  color: DharaColors.text2,
                ),
              ),
            ],
          ),
        ),
        if (actions.isNotEmpty)
          Wrap(spacing: .5 * rem, runSpacing: .5 * rem, children: actions),
      ],
    );
  }
}

/// Small spaced capitals: the name of a number, a list or a field.
class CapsLabel extends StatelessWidget {
  const CapsLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
        fontFamily: DharaFonts.ui,
        fontSize: DharaType.xs,
        letterSpacing: .12 * DharaType.xs,
        color: DharaColors.text3,
      ),
    );
  }
}

/// One number of a page, with what it counts above it and a note below.
class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.label,
    required this.value,
    required this.note,
    this.valueColor = DharaColors.text,
  });

  final String label;
  final String value;
  final String note;
  final Color valueColor;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 1.2 * rem, vertical: rem),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CapsLabel(label),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: DharaFonts.display,
              fontSize: DharaType.xxl,
              fontWeight: DharaType.bold,
              height: 1.2,
              color: valueColor,
            ),
          ),
          Text(
            note,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontFamily: DharaFonts.ui,
              fontSize: DharaType.xs,
              color: DharaColors.text2,
            ),
          ),
        ],
      ),
    );
  }
}

/// [tiles] side by side, or one below the other when there is no room.
class StatRow extends StatelessWidget {
  const StatRow({super.key, required this.tiles});

  final List<Widget> tiles;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        if (box.maxWidth < 36 * rem) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (i, tile) in tiles.indexed) ...[
                if (i > 0) const SizedBox(height: .6 * rem),
                tile,
              ],
            ],
          );
        }
        return Row(
          children: [
            for (final (i, tile) in tiles.indexed) ...[
              if (i > 0) const SizedBox(width: rem),
              Expanded(child: tile),
            ],
          ],
        );
      },
    );
  }
}

/// Something the user should know before using the page: a problem with a
/// file, a run that failed.
class NoticeBar extends StatelessWidget {
  const NoticeBar(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: rem,
          vertical: .7 * rem,
        ),
        decoration: BoxDecoration(
          color: DharaColors.surface,
          borderRadius: BorderRadius.circular(DharaRadii.md),
          border: Border.all(color: DharaColors.warn.withValues(alpha: .5)),
        ),
        child: Row(
          children: [
            const Icon(
              DharaIcons.info,
              size: 1.2 * rem,
              color: DharaColors.warn,
            ),
            const SizedBox(width: .7 * rem),
            Expanded(
              child: Text(
                text,
                style: const TextStyle(
                  fontFamily: DharaFonts.ui,
                  fontSize: DharaType.sm,
                  height: 1.4,
                  color: DharaColors.text,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One line of a list on a working page: a faint pane around [child].
/// With [onPressed] it is a button: it lights up under the pointer, takes
/// the keyboard, and Enter presses it.
class RowCard extends StatelessWidget {
  const RowCard({
    super.key,
    required this.child,
    this.onPressed,
    this.semanticLabel,
    this.padding = const EdgeInsets.symmetric(
      horizontal: rem,
      vertical: .65 * rem,
    ),
  });

  final Widget child;
  final VoidCallback? onPressed;
  final String? semanticLabel;
  final EdgeInsetsGeometry padding;

  static const _corners = BorderRadius.all(Radius.circular(DharaRadii.md));

  Widget _pane({required bool lit}) => DecoratedBox(
    decoration: BoxDecoration(
      color: lit ? DharaColors.surface2 : DharaColors.surface,
      borderRadius: _corners,
      border: Border.all(
        color: lit ? DharaColors.strokeStrong : DharaColors.stroke,
      ),
    ),
    child: Padding(padding: padding, child: child),
  );

  @override
  Widget build(BuildContext context) {
    final onPressed = this.onPressed;
    return Padding(
      padding: const EdgeInsets.only(bottom: .5 * rem),
      child: onPressed == null
          ? _pane(lit: false)
          : Pressable(
              onPressed: onPressed,
              semanticLabel: semanticLabel,
              builder: (context, state) => FocusRing(
                visible: state.focused,
                radius: _corners,
                child: _pane(lit: state.active),
              ),
            ),
    );
  }
}

/// A one-line text field in the app's look: a pane with a hairline border
/// that turns to the accent colour while it holds the keyboard.
class DharaField extends StatefulWidget {
  const DharaField({
    super.key,
    required this.controller,
    this.hint,
    this.label,
    this.icon,
    this.error,
    this.obscure = false,
    this.autofocus = false,
    this.onChanged,
    this.onSubmitted,
    this.keyboardType,
    this.inputFormatters,
  });

  final TextEditingController controller;
  final String? hint;

  /// What the field is for, in small capitals above it.
  final String? label;
  final IconData? icon;

  /// What is wrong with what was typed, shown in red below the field.
  final String? error;

  /// For secrets: what is typed shows as dots, and nothing of it is
  /// offered to the system's keyboard to learn from.
  final bool obscure;
  final bool autofocus;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;

  @override
  State<DharaField> createState() => _DharaFieldState();
}

class _DharaFieldState extends State<DharaField> {
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocusChanged);
  }

  void _onFocusChanged() => setState(() {});

  @override
  void dispose() {
    _focus
      ..removeListener(_onFocusChanged)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final focused = _focus.hasFocus;
    final label = widget.label;
    final icon = widget.icon;
    final error = widget.error;
    const style = TextStyle(
      fontFamily: DharaFonts.ui,
      fontSize: DharaType.md,
      height: 1.3,
      color: DharaColors.text,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (label != null) ...[
          CapsLabel(label),
          const SizedBox(height: .3 * rem),
        ],
        // A click anywhere on the pane puts the caret into the field.
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _focus.requestFocus,
          child: AnimatedContainer(
            duration: motion(context, DharaMotion.fast),
            height: 2.6 * rem,
            padding: const EdgeInsets.symmetric(horizontal: .9 * rem),
            decoration: BoxDecoration(
              color: focused ? DharaColors.surface2 : DharaColors.surface,
              borderRadius: BorderRadius.circular(DharaRadii.md),
              border: Border.all(
                color: error != null
                    ? DharaColors.bad
                    : focused
                    ? DharaColors.accent
                    : DharaColors.stroke,
              ),
              boxShadow: focused ? DharaShadows.focusRing : null,
            ),
            child: Row(
              children: [
                if (icon != null) ...[
                  Icon(
                    icon,
                    size: 1.15 * rem,
                    color: focused ? DharaColors.text : DharaColors.text2,
                  ),
                  const SizedBox(width: .6 * rem),
                ],
                Expanded(
                  child: TextField(
                    controller: widget.controller,
                    focusNode: _focus,
                    autofocus: widget.autofocus,
                    obscureText: widget.obscure,
                    autocorrect: false,
                    enableSuggestions: false,
                    enableIMEPersonalizedLearning: !widget.obscure,
                    maxLines: 1,
                    keyboardType: widget.keyboardType,
                    inputFormatters: widget.inputFormatters,
                    onChanged: widget.onChanged,
                    onSubmitted: widget.onSubmitted,
                    style: style,
                    cursorHeight: DharaType.md * 1.3,
                    decoration: InputDecoration.collapsed(
                      hintText: widget.hint,
                      hintStyle: style.copyWith(color: DharaColors.text3),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (error != null) ...[
          const SizedBox(height: .35 * rem),
          Text(
            error,
            style: const TextStyle(
              fontFamily: DharaFonts.ui,
              fontSize: DharaType.xs,
              height: 1.4,
              color: DharaColors.bad,
            ),
          ),
        ],
      ],
    );
  }
}

/// The pane of a dialog in the app's look, no wider than [maxWidth].
class DharaDialog extends StatelessWidget {
  const DharaDialog({
    super.key,
    required this.child,
    this.maxWidth = 36 * rem,
    this.maxHeight = double.infinity,
  });

  final Widget child;
  final double maxWidth;
  final double maxHeight;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: DharaColors.bgElev,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(DharaRadii.lg),
        side: const BorderSide(color: DharaColors.strokeStrong),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth, maxHeight: maxHeight),
        child: child,
      ),
    );
  }
}
