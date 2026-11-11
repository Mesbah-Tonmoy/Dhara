import 'package:dhara/app.dart';
import 'package:flutter/widgets.dart';
import 'package:media_kit/media_kit.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Loads the bundled libmpv; no external player install is needed.
  MediaKit.ensureInitialized();
  runApp(const DharaApp());
}
