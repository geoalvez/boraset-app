/// Tema do BoraSet.
///
/// Feito para ser lido com o braço tremendo, o celular na mão suada e alguém
/// esperando o banco. Números grandes, contraste alto, um botão que domina.
library;

import 'package:flutter/material.dart';

const kInk = Color(0xFF0E1116);
const kSurface = Color(0xFF171B22);
const kSurfaceHi = Color(0xFF20262F);
const kGo = Color(0xFF37D67A);
const kWarn = Color(0xFFFFB84D);
const kStop = Color(0xFFFF6B6B);
const kMuted = Color(0xFF8A93A3);

final borasetTheme = ThemeData(
  useMaterial3: true,
  brightness: Brightness.dark,
  scaffoldBackgroundColor: kInk,
  colorScheme: const ColorScheme.dark(
    primary: kGo,
    surface: kSurface,
    error: kStop,
  ),
  textTheme: const TextTheme(
    // O nome do exercício. Tem que ser legível de relance.
    displaySmall: TextStyle(fontSize: 34, fontWeight: FontWeight.w800, height: 1.1),
    // O relógio.
    headlineLarge: TextStyle(fontSize: 44, fontWeight: FontWeight.w800, height: 1),
    titleMedium: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
    bodyMedium: TextStyle(fontSize: 15, height: 1.45),
    labelSmall: TextStyle(fontSize: 12, letterSpacing: .8, color: kMuted),
  ),
);

/// Rótulo pequeno em caixa alta — usado nas legendas dos cartões.
class Caption extends StatelessWidget {
  final String text;
  final Color? color;
  const Caption(this.text, {super.key, this.color});

  @override
  Widget build(BuildContext context) => Text(
        text.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color),
      );
}
