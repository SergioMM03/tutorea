import 'package:flutter/material.dart';

import '../data/supabase/remote_catalog.dart';
import '../data/supabase/supabase_bootstrap.dart';
import 'catalog_diagnostic.dart';

/// Punto de entrada SOLO para el diagnóstico de la Fase 14.4. La app normal
/// (lib/main.dart) no lo usa y no consulta Supabase al arrancar.
///
///   flutter run -t lib/diagnostics/catalog_diagnostic_main.dart \
///     --dart-define-from-file=env/supabase.dev.json
///
/// Lee universities, careers y subjects de ESEN, imprime el resultado en la
/// consola y lo muestra en pantalla. No escribe nada, ni en Supabase ni en el
/// dispositivo.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final lines = <String>[];
  void log(String line) {
    debugPrint(line);
    lines.add(line);
  }

  final ready = await SupabaseBootstrap.initializeIfConfigured();
  if (!ready) {
    log('${CatalogDiagnostic.tag} RESULTADO: ERROR — Supabase no se inicializó. '
        'Ejecuta con --dart-define-from-file=env/supabase.dev.json y revisa la consola.');
  } else {
    await CatalogDiagnostic(
      source: SupabaseCatalogSource.fromInitializedClient(),
      log: log,
    ).run();
  }

  runApp(_DiagnosticApp(lines: lines));
}

class _DiagnosticApp extends StatelessWidget {
  final List<String> lines;
  const _DiagnosticApp({required this.lines});

  @override
  Widget build(BuildContext context) {
    final ok = lines.any((l) => l.contains('RESULTADO: OK'));
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Diagnóstico de catálogo'),
          backgroundColor: ok ? Colors.green.shade100 : Colors.red.shade100,
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              for (final line in lines)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: SelectableText(
                    line.replaceFirst('${CatalogDiagnostic.tag} ', ''),
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
