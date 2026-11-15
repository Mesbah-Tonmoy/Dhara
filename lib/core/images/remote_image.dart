import 'dart:io';

import 'package:dhara/core/images/image_store.dart';
import 'package:dhara/theme/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// Makes the [RemoteImageStore] available to the widget tree. Without one
/// above it, a [TmdbPicture] shows its placeholder.
class ImageStoreScope extends InheritedWidget {
  const ImageStoreScope({super.key, required this.store, required super.child});

  final RemoteImageStore? store;

  static RemoteImageStore? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ImageStoreScope>()?.store;

  @override
  bool updateShouldNotify(ImageStoreScope old) => store != old.store;
}

/// A poster, backdrop or still from TMDB in a box of a fixed size, with
/// rounded corners. Until the picture is there, and if there is none, the
/// box shows [placeholder].
class TmdbPicture extends StatefulWidget {
  const TmdbPicture({
    super.key,
    required this.path,
    required this.size,
    required this.width,
    required this.height,
    this.placeholder = Icons.movie_outlined,
  });

  /// As TMDB gives it ("/abc123.jpg"), or `null` if there is no picture.
  final String? path;

  /// One of [RemoteImageStore.sizes].
  final String size;
  final double width;
  final double height;
  final IconData placeholder;

  @override
  State<TmdbPicture> createState() => _TmdbPictureState();
}

class _TmdbPictureState extends State<TmdbPicture> {
  RemoteImageStore? _store;
  File? _file;
  var _asked = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final store = ImageStoreScope.of(context);
    if (store == _store && _asked > 0) return;
    _store = store;
    _load();
  }

  @override
  void didUpdateWidget(TmdbPicture old) {
    super.didUpdateWidget(old);
    if (old.path != widget.path || old.size != widget.size) _load();
  }

  void _load() {
    final number = ++_asked;
    final path = widget.path;
    final store = _store;
    _file = null;
    if (path == null || store == null) return;
    store.file(widget.size, path).then((file) {
      // Only the answer for the picture now shown counts.
      if (mounted && number == _asked) setState(() => _file = file);
    });
  }

  @override
  Widget build(BuildContext context) {
    final file = _file;
    final empty = ColoredBox(
      color: DharaColors.surface2,
      child: Center(
        child: Icon(
          widget.placeholder,
          size: widget.width < 60 ? 18 : 28,
          color: DharaColors.text3,
        ),
      ),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(DharaRadii.sm),
      child: SizedBox(
        width: widget.width,
        height: widget.height,
        child: file == null
            ? empty
            : Image.file(
                file,
                fit: BoxFit.cover,
                // Decoded no larger than it is shown.
                cacheWidth:
                    (widget.width * MediaQuery.devicePixelRatioOf(context))
                        .round(),
                gaplessPlayback: true,
                errorBuilder: (_, _, _) => empty,
              ),
      ),
    );
  }
}

/// A poster, backdrop or still from TMDB that fills the box it is given.
/// Until the picture is there, and if there is none, it shows
/// [placeholder]; the picture then fades in over it.
///
/// While the list it is in is being flung, it does not ask for the picture
/// yet: nothing is downloaded or decoded for a card that only flies past.
class TmdbCover extends StatefulWidget {
  const TmdbCover({
    super.key,
    required this.path,
    required this.size,
    required this.placeholder,
    this.fadeIn = DharaMotion.base,
    this.onPicture,
  }) : anilist = false;

  /// The cover of an anime from AniList's picture server instead; [path]
  /// is as `anilistCoverPath` returns it.
  const TmdbCover.anilist({
    super.key,
    required this.path,
    required this.placeholder,
    this.fadeIn = DharaMotion.base,
    this.onPicture,
  }) : anilist = true,
       size = '';

  /// See [TmdbCover.anilist].
  final bool anilist;

  /// As TMDB gives it ("/abc123.jpg"), or `null` if there is no picture.
  final String? path;

  /// One of [RemoteImageStore.sizes].
  final String size;
  final Widget placeholder;
  final Duration fadeIn;

  /// Told `true` once the picture starts to show, and `false` if it is
  /// then taken away again (another [path]). Called between frames.
  final ValueChanged<bool>? onPicture;

  @override
  State<TmdbCover> createState() => _TmdbCoverState();
}

class _TmdbCoverState extends State<TmdbCover> {
  RemoteImageStore? _store;
  File? _file;
  var _asked = 0;

  /// The picture has faded in: the placeholder under it is not drawn.
  var _covered = false;

  /// What [TmdbCover.onPicture] was last told.
  var _told = false;

  void _tell(bool showing) {
    if (_told == showing) return;
    _told = showing;
    final number = _asked;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (mounted && number == _asked) widget.onPicture?.call(showing);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final store = ImageStoreScope.of(context);
    if (store == _store && _asked > 0) return;
    _store = store;
    _load();
  }

  @override
  void didUpdateWidget(TmdbCover old) {
    super.didUpdateWidget(old);
    if (old.path != widget.path ||
        old.size != widget.size ||
        old.anilist != widget.anilist) {
      _load();
    }
  }

  @override
  void dispose() {
    // Answers and waiting frames for this one no longer count.
    _asked++;
    super.dispose();
  }

  void _load() {
    final number = ++_asked;
    _file = null;
    _covered = false;
    _tell(false);
    _ask(number);
  }

  void _ask(int number) {
    final path = widget.path;
    final store = _store;
    if (path == null || store == null) return;
    if (Scrollable.recommendDeferredLoadingForContext(context)) {
      // Flung past: look again on the next frame, until the list slows
      // down or this card is gone.
      SchedulerBinding.instance.scheduleFrameCallback((_) {
        if (mounted && number == _asked) _ask(number);
      });
      return;
    }
    final picture = widget.anilist
        ? store.anilistCover(path)
        : store.file(widget.size, path);
    picture.then((file) {
      // Only the answer for the picture now shown counts.
      if (mounted && number == _asked) setState(() => _file = file);
    });
  }

  @override
  Widget build(BuildContext context) {
    final file = _file;
    if (file == null) return widget.placeholder;
    final fade = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : widget.fadeIn;
    return LayoutBuilder(
      builder: (context, box) => Stack(
        fit: StackFit.expand,
        children: [
          // Stays until the picture has faded in over it.
          if (!_covered) widget.placeholder,
          Image.file(
            file,
            key: ValueKey(file.path),
            fit: BoxFit.cover,
            // Decoded no larger than it is shown.
            cacheWidth: box.maxWidth.isFinite
                ? (box.maxWidth * MediaQuery.devicePixelRatioOf(context)).ceil()
                : null,
            gaplessPlayback: true,
            excludeFromSemantics: true,
            // A file that is no picture after all: the placeholder stays.
            errorBuilder: (_, _, _) => const SizedBox.shrink(),
            frameBuilder: (context, child, frame, alreadyThere) {
              if (alreadyThere || frame != null) _tell(true);
              if (alreadyThere) {
                // Decoded before: no fade, and nothing to keep under it.
                if (!_covered) {
                  SchedulerBinding.instance.addPostFrameCallback((_) {
                    if (mounted && _file == file) {
                      setState(() => _covered = true);
                    }
                  });
                }
                return child;
              }
              return AnimatedOpacity(
                opacity: frame == null ? 0 : 1,
                duration: fade,
                curve: Curves.easeOut,
                onEnd: () {
                  if (mounted && frame != null) {
                    setState(() => _covered = true);
                  }
                },
                child: child,
              );
            },
          ),
        ],
      ),
    );
  }
}
