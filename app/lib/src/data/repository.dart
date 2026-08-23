/// Carrega o catálogo (neutro) e o pacote do idioma do usuário.
///
/// A separação que o repositório respeita: identidade vem de `catalog/`,
/// texto vem de `l10n/<locale>`. Trocar de idioma recarrega só o segundo.
library;

import 'dart:convert';

import 'package:boraset_domain/boraset_domain.dart';
import 'package:flutter/services.dart' show rootBundle;

/// Nome e apelidos de um exercício ou técnica no idioma ativo.
class Named {
  final String name;
  final List<String> aliases;
  const Named(this.name, this.aliases);
}

/// O conteúdo de ajuda de uma técnica, já no idioma ativo.
class TechniqueHelp {
  final String slug;
  final String name;
  final String summary;
  final Map<String, String> sections; // what | how | when | mistake
  final String? caution;
  final String category;
  final int occurrences;

  const TechniqueHelp({
    required this.slug,
    required this.name,
    required this.summary,
    required this.sections,
    required this.category,
    required this.occurrences,
    this.caution,
  });

  bool get hasCaution => caution != null && caution!.isNotEmpty;
}

class BorasetData {
  final ExerciseCatalog catalog;
  final Map<String, Named> exerciseNames;
  final Map<String, TechniqueHelp> techniques;

  /// Rótulos das seções do popup — vêm uma vez por idioma, não por tópico.
  final Map<String, String> sectionLabels;

  final List<String> sectionOrder;
  final WeightUnit unit;
  final String locale;

  const BorasetData({
    required this.catalog,
    required this.exerciseNames,
    required this.techniques,
    required this.sectionLabels,
    required this.sectionOrder,
    required this.unit,
    required this.locale,
  });

  String nameOf(String slug) => exerciseNames[slug]?.name ?? slug;
  PlateProfile get plates =>
      unit == WeightUnit.lb ? PlateProfile.imperial : PlateProfile.metric;
}

class Repository {
  static const _base = 'assets/data';

  /// Idiomas com cobertura completa. Fora daqui, cai no inglês.
  static const supported = {
    'pt', 'en', 'es', 'fr', 'de', 'it', 'nl', 'pl', 'tr',
    'id', 'vi', 'ru', 'ja', 'ko', 'zh', 'hi', 'ar', 'th',
  };

  /// Resolve o código do dispositivo para um pacote que existe no bundle.
  static String resolveLocale(String languageCode, [String? country]) {
    if (languageCode == 'pt') return 'pt-BR';
    if (languageCode == 'zh') return 'zh-Hans';
    return supported.contains(languageCode) ? languageCode : 'en';
  }

  Future<BorasetData> load(String languageCode, {String? country}) async {
    final locale = resolveLocale(languageCode, country);

    final core = jsonDecode(await rootBundle.loadString('$_base/catalog/exercises.core.json'))
        as Map<String, dynamic>;
    final techCore = jsonDecode(await rootBundle.loadString('$_base/catalog/techniques.core.json'))
        as Map<String, dynamic>;
    final exL10n = jsonDecode(await rootBundle.loadString('$_base/l10n/exercises.$locale.json'))
        as Map<String, dynamic>;
    final techL10n = jsonDecode(await rootBundle.loadString('$_base/l10n/techniques.$locale.json'))
        as Map<String, dynamic>;
    final ui = jsonDecode(await rootBundle.loadString('$_base/l10n/ui_strings.json'))
        as Map<String, dynamic>;

    // --- catálogo (neutro de idioma) ---
    final kinship = <(MovementPattern, MovementPattern), double>{};
    (core['scoring']['kin_patterns'] as Map<String, dynamic>).forEach((k, v) {
      final parts = k.split('|');
      final a = _pattern(parts[0]), b = _pattern(parts[1]);
      if (a != null && b != null) kinship[(a, b)] = (v as num).toDouble();
    });

    final exercises = <Exercise>[];
    for (final raw in core['exercises'] as List) {
      final e = raw as Map<String, dynamic>;
      final pattern = _pattern(e['pattern'] as String);
      final primary = _muscle(e['primary'] as String);
      if (pattern == null || primary == null) continue; // vocabulário novo: ignora
      exercises.add(Exercise(
        slug: e['slug'] as String,
        name: exL10n['names']?[e['slug']]?['name'] as String? ?? e['slug'] as String,
        aliases: ((exL10n['names']?[e['slug']]?['aliases'] as List?) ?? const [])
            .cast<String>(),
        primary: primary,
        secondary: ((e['secondary'] as List).cast<String>())
            .map(_muscle).whereType<MuscleGroup>().toSet(),
        pattern: pattern,
        mechanic: e['mechanic'] == 'isolador' ? Mechanic.isolador : Mechanic.composto,
        laterality: _enum(Laterality.values, e['laterality'] as String) ?? Laterality.bilateral,
        force: _force(e['force'] as String),
        plane: _enum(Plane.values, e['plane'] as String) ?? Plane.sagital,
        loadScalability:
            _enum(LoadScalability.values, e['load_scalability'] as String) ?? LoadScalability.alta,
        equipment: ((e['equipment'] as List).cast<String>())
            .map(_equipment).whereType<Equipment>().toSet(),
        level: _enum(Level.values, e['level'] as String) ?? Level.intermediario,
        familiarity: (e['occurrences'] as num?)?.toInt() ?? 0,
      ));
    }

    // --- técnicas: core + texto do idioma ---
    final techs = <String, TechniqueHelp>{};
    for (final raw in techCore['techniques'] as List) {
      final t = raw as Map<String, dynamic>;
      final slug = t['slug'] as String;
      final loc = techL10n['topics']?[slug] as Map<String, dynamic>?;
      if (loc == null) continue;
      techs[slug] = TechniqueHelp(
        slug: slug,
        name: loc['name'] as String,
        summary: loc['summary'] as String,
        sections: ((loc['sections'] as Map?) ?? const {})
            .map((k, v) => MapEntry(k as String, v is String ? v : ''))
          ..removeWhere((_, v) => v.isEmpty),
        caution: loc['caution'] as String?,
        category: t['category'] as String,
        occurrences: (t['occurrences'] as num).toInt(),
      );
    }

    return BorasetData(
      catalog: ExerciseCatalog(
        exercises,
        scorer: CompatibilityScorer(
          weights: _weights(core['scoring']['weights'] as Map<String, dynamic>),
          kinship: kinship,
        ),
        minScore: (core['scoring']['min_score'] as num).toDouble(),
      ),
      exerciseNames: {
        for (final entry in (exL10n['names'] as Map<String, dynamic>).entries)
          entry.key: Named(
            entry.value['name'] as String,
            ((entry.value['aliases'] as List?) ?? const []).cast<String>(),
          ),
      },
      techniques: techs,
      sectionLabels: ((ui['help_section_labels'][locale] ??
              ui['help_section_labels']['en']) as Map<String, dynamic>)
          .cast<String, String>(),
      sectionOrder:
          ((techL10n['section_order'] as List?) ?? const ['what', 'how', 'when', 'mistake'])
              .cast<String>(),
      unit: (exL10n['units']?['weight'] == 'lb') ? WeightUnit.lb : WeightUnit.kg,
      locale: locale,
    );
  }

  static CompatibilityWeights _weights(Map<String, dynamic> w) => CompatibilityWeights(
        pattern: (w['pattern'] as num).toDouble(),
        primary: (w['primary'] as num).toDouble(),
        loadScalability: (w['load_scalability'] as num).toDouble(),
        mechanic: (w['mechanic'] as num).toDouble(),
        secondary: (w['secondary'] as num).toDouble(),
        force: (w['force'] as num).toDouble(),
        plane: (w['plane'] as num).toDouble(),
        laterality: (w['laterality'] as num).toDouble(),
      );

  static T? _enum<T extends Enum>(List<T> values, String snake) {
    final camel = _camel(snake);
    for (final v in values) {
      if (v.name == camel) return v;
    }
    return null;
  }

  static String _camel(String snake) {
    final parts = snake.split('_');
    return parts.first +
        parts.skip(1).map((p) => p.isEmpty ? '' : p[0].toUpperCase() + p.substring(1)).join();
  }

  static MovementPattern? _pattern(String s) => _enum(MovementPattern.values, s);
  static MuscleGroup? _muscle(String s) => _enum(MuscleGroup.values, s);
  static Equipment? _equipment(String s) => _enum(Equipment.values, s);
  static ForceVector _force(String s) =>
      _enum(ForceVector.values, s == 'nenhum' ? 'nenhum' : s) ?? ForceVector.nenhum;
}
