/// BoraSet — ponto de entrada.
///
/// Regra de layout da casa: nunca `left`/`right`, sempre `start`/`end`.
/// Árabe, hebraico, persa e urdu invertem a direção da tela; acertar isso
/// desde a primeira tela custa zero, e retrofitar depois custa semanas.
library;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'src/data/repository.dart';
import 'src/ui/theme.dart';
import 'src/ui/workout_screen.dart';

void main() => runApp(const BorasetApp());

class BorasetApp extends StatelessWidget {
  const BorasetApp({super.key});

  static const _locales = [
    Locale('pt', 'BR'), Locale('en'), Locale('es'), Locale('fr'),
    Locale('de'), Locale('it'), Locale('nl'), Locale('pl'),
    Locale('tr'), Locale('id'), Locale('vi'), Locale('ru'),
    Locale('ja'), Locale('ko'), Locale('zh'), Locale('hi'),
    Locale('ar'), Locale('th'),
  ];

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'BoraSet',
        debugShowCheckedModeBanner: false,
        theme: borasetTheme,
        supportedLocales: _locales,
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: const _Boot(),
      );
}

/// Carrega catálogo + pacote de idioma antes de abrir a tela de treino.
class _Boot extends StatefulWidget {
  const _Boot();
  @override
  State<_Boot> createState() => _BootState();
}

class _BootState extends State<_Boot> {
  Future<BorasetData>? _future;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final l = Localizations.localeOf(context);
    _future ??= Repository().load(l.languageCode, country: l.countryCode);
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<BorasetData>(
        future: _future,
        builder: (context, snap) {
          if (snap.hasError) {
            return Scaffold(
              body: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text('${snap.error}', textAlign: TextAlign.center),
                ),
              ),
            );
          }
          if (!snap.hasData) {
            return const Scaffold(body: Center(child: CircularProgressIndicator()));
          }
          return WorkoutScreen(data: snap.data!);
        },
      );
}
