import 'dart:io';

import 'package:dhara/core/images/image_store.dart';
import 'package:dhara/theme/tokens.dart';
import 'package:flutter/material.dart';

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
