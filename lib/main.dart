import 'package:flutter/material.dart';

import 'app.dart';
import 'src/vault_key.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(GerfautApp(bootstrap: bootstrapGerfaut));
}
