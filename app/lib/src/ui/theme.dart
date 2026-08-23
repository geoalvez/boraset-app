/// Sistema visual do BoraSet.
///
/// Duas restrições moldaram tudo aqui:
///
/// 1. A tela é lida com o braço tremendo, o celular na mão suada e alguém
///    esperando o banco. Número grande, contraste alto, uma ação óbvia.
/// 2. Não pode parecer app genérico. Componente de estoque do Material —
///    NavigationBar com pílula, SegmentedButton, FilterChip, ListTile — tem
///    assinatura visual reconhecível. Aqui eles são substituídos por peças
///    próprias, em `widgets.dart`.
///
/// A régua é uma escala de 4: todo espaçamento é múltiplo de 4, o que dá
/// ritmo vertical sem precisar decidir caso a caso.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// ---------------------------------------------------------------------------
// Cor
// ---------------------------------------------------------------------------

/// Fundo. Quase preto com um viés frio — preto puro achata a hierarquia
/// porque não sobra para onde escurecer.
const kInk = Color(0xFF0A0C0F);

/// Superfícies, em três níveis. Mais que três e a hierarquia vira ruído.
const kSurface = Color(0xFF12151A);
const kSurfaceHi = Color(0xFF191D24);
const kSurfaceTop = Color(0xFF222831);

/// Bordas de 1px carregam a separação que a sombra carregaria — sombra em
/// fundo escuro é quase invisível e custa render.
const kLine = Color(0xFF232830);
const kLineSoft = Color(0xFF1A1F26);

const kText = Color(0xFFF2F4F7);
const kMuted = Color(0xFF8B94A3);
const kFaint = Color(0xFF5A6472);

/// Um acento só. Verde = pode ir. Dois acentos competindo destroem a
/// leitura de relance.
const kGo = Color(0xFF3DDC84);
const kWarn = Color(0xFFF5A524);
const kStop = Color(0xFFF04438);

const kRadius = 14.0;
const kRadiusSm = 10.0;

/// Números tabulares: sem isso o cronômetro "pula" a cada segundo, porque
/// os dígitos têm larguras diferentes.
const kTabular = [FontFeature.tabularFigures()];

// ---------------------------------------------------------------------------
// Tipografia
// ---------------------------------------------------------------------------

const _display = TextStyle(
  fontSize: 30, height: 1.08, fontWeight: FontWeight.w700,
  letterSpacing: -0.6, color: kText,
);
const _numeral = TextStyle(
  fontSize: 46, height: 1, fontWeight: FontWeight.w700,
  letterSpacing: -1.6, color: kText, fontFeatures: kTabular,
);
const _title = TextStyle(
  fontSize: 15.5, height: 1.3, fontWeight: FontWeight.w600,
  letterSpacing: -0.1, color: kText,
);
const _body = TextStyle(
  fontSize: 14.5, height: 1.5, fontWeight: FontWeight.w400, color: kText,
);
const _label = TextStyle(
  fontSize: 10.5, fontWeight: FontWeight.w700,
  letterSpacing: 1.3, color: kFaint,
);

final borasetTheme = ThemeData(
  useMaterial3: true,
  brightness: Brightness.dark,
  scaffoldBackgroundColor: kInk,
  splashFactory: InkSparkle.splashFactory,
  colorScheme: const ColorScheme.dark(
    primary: kGo,
    onPrimary: kInk,
    surface: kSurface,
    onSurface: kText,
    error: kStop,
    outline: kLine,
  ),
  textTheme: const TextTheme(
    displaySmall: _display,
    headlineLarge: _numeral,
    titleMedium: _title,
    bodyMedium: _body,
    labelSmall: _label,
  ),
  dividerTheme: const DividerThemeData(color: kLine, thickness: 1, space: 1),
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: kSurfaceHi,
    hintStyle: const TextStyle(color: kFaint, fontSize: 14.5),
    labelStyle: const TextStyle(color: kMuted, fontSize: 13.5),
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(kRadiusSm),
      borderSide: const BorderSide(color: kLine),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(kRadiusSm),
      borderSide: const BorderSide(color: kLine),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(kRadiusSm),
      borderSide: const BorderSide(color: kGo, width: 1.4),
    ),
  ),
);

/// Barra de status transparente com ícones claros — a tela toda é escura,
/// e a barra padrão do sistema quebra a borda superior.
const kSystemChrome = SystemUiOverlayStyle(
  statusBarColor: Colors.transparent,
  statusBarIconBrightness: Brightness.light,
  systemNavigationBarColor: kSurface,
  systemNavigationBarIconBrightness: Brightness.light,
);
