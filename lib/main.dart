import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

import 'app/adoetz_app.dart';
import 'app/dependencies.dart';
import 'app/providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('id_ID');
  Intl.defaultLocale = 'id_ID';
  final dependencies = await AppDependencies.create();
  runApp(
    ProviderScope(
      overrides: [depsProvider.overrideWithValue(dependencies)],
      child: const AdoetzApp(),
    ),
  );
}
