/// BoraSet — catálogo de exercícios.
///
/// Dart puro. Nenhum import de `package:flutter`. Roda em `dart test`.
library;

// ---------------------------------------------------------------------------
// Eixos. Vocabulários fechados — vêm de exercise_catalog.pt-BR.json.
// ---------------------------------------------------------------------------

enum MovementPattern {
  empurrarHorizontal, empurrarInclinado, empurrarDeclinado, empurrarVertical,
  puxarVertical, puxarHorizontal, extensaoOmbro, aducaoHorizontal, abducaoHorizontal,
  abducaoOmbro, flexaoOmbro, rotacaoOmbro,
  agachar, avanco, extensaoJoelho, flexaoJoelho, dobradicaQuadril,
  extensaoQuadril, abducaoQuadril, aducaoQuadril, flexaoPlantar,
  flexaoCotovelo, extensaoCotovelo,
  flexaoTronco, flexaoLateral, rotacaoTronco, extensaoTronco,
  antiextensao, antirotacao, vacuum,
  locomocao, mobilidadeOmbro, mobilidadeGeral,
}

enum MuscleGroup {
  peito, costas, ombroAnterior, ombroLateral, ombroPosterior, manguito, trapezio,
  biceps, triceps, antebraco,
  quadriceps, isquiotibiais, gluteo, adutores, abdutores, panturrilha,
  coreAnterior, coreLateral, corePosterior,
  corpoInteiro, cardio, mobilidade,
}

enum Equipment {
  pesoCorporal, barra, halter, polia, maquina, smith, banco,
  bola, elastico, step, cone, rodinha, esteira, bike, escada,
}

/// Responde: "esse exercício aguenta carga comparável?"
///
/// A ordem do enum É a escala. `index` maior = mais escalável.
enum LoadScalability {
  /// Medido em tempo/distância, não em carga. Incomparável com os demais.
  tempo,
  /// Isométrico corporal — não há como escalar carga de forma útil.
  nenhuma,
  /// Peso corporal: dá pra lastrar ou mudar alavanca, não dá pra igualar.
  baixa,
  /// Carga externa ajustável: barra, halter, polia, máquina, smith.
  alta;

  /// Degradar carga custa caro; subir é neutro.
  /// Ver `load_drop_penalty` em exercise_catalog.pt-BR.json.
  double transitionFactor(LoadScalability target) {
    if (this == tempo || target == tempo) return this == target ? 1.0 : 0.0;
    final drop = target.index - index;
    if (drop >= 0) return 1.0;
    return switch (drop) { -1 => 0.50, -2 => 0.10, _ => 0.0 };
  }
}

enum Mechanic { composto, isolador }
enum Laterality { bilateral, alternado, unilateral }
enum ForceVector { empurrar, puxar, estatico, nenhum }
enum Plane { sagital, frontal, transverso, multiplano }
enum Level { iniciante, intermediario, avancado }

// ---------------------------------------------------------------------------
// Exercise — identidade canônica. NÃO carrega estrutura de sessão.
// ---------------------------------------------------------------------------

/// Um exercício canônico do catálogo.
///
/// Invariante: um `Exercise` descreve um movimento, nunca uma prescrição.
/// Séries, repetições, carga e pareamento (bi-set) vivem na sessão.
class Exercise {
  final String slug;
  final String name;
  final List<String> aliases;

  final MuscleGroup primary;
  final Set<MuscleGroup> secondary;
  final MovementPattern pattern;
  final Mechanic mechanic;
  final Laterality laterality;
  final ForceVector force;
  final Plane plane;
  final LoadScalability loadScalability;
  final Set<Equipment> equipment;
  final Level level;

  /// Frequência no corpus de origem. Critério de desempate: o que o usuário
  /// mais provavelmente já viu. Nunca entra no score de compatibilidade.
  final int familiarity;

  const Exercise({
    required this.slug,
    required this.name,
    this.aliases = const [],
    required this.primary,
    this.secondary = const {},
    required this.pattern,
    required this.mechanic,
    required this.laterality,
    required this.force,
    required this.plane,
    required this.loadScalability,
    required this.equipment,
    required this.level,
    this.familiarity = 0,
  });

  @override
  String toString() => 'Exercise($slug)';
}

// ---------------------------------------------------------------------------
// Compatibilidade — FUNÇÃO, não tabela.
//
// REGRA DE OURO: equipamento NÃO entra aqui.
// Equipamento é filtro de disponibilidade, aplicado pelo motor, depois.
// Misturar os dois penaliza justamente a troca de equipamento, que é o
// motivo de existir a substituição.
// ---------------------------------------------------------------------------

/// Pesos do score. Somam 100. Espelham `scoring.weights` do JSON.
class CompatibilityWeights {
  final double pattern, primary, loadScalability, mechanic, secondary, force, plane, laterality;
  const CompatibilityWeights({
    this.pattern = 35, this.primary = 22, this.loadScalability = 15,
    this.mechanic = 7, this.secondary = 6, this.force = 6,
    this.plane = 5, this.laterality = 4,
  });
  static const standard = CompatibilityWeights();
}

/// Crédito parcial entre padrões aparentados. Simétrico.
typedef KinshipTable = Map<(MovementPattern, MovementPattern), double>;

class CompatibilityScorer {
  final CompatibilityWeights weights;
  final KinshipTable kinship;

  const CompatibilityScorer({
    this.weights = CompatibilityWeights.standard,
    this.kinship = const {},
  });

  double _kin(MovementPattern a, MovementPattern b) {
    if (a == b) return 1.0;
    return kinship[(a, b)] ?? kinship[(b, a)] ?? 0.0;
  }

  static double _jaccard(Set<MuscleGroup> a, Set<MuscleGroup> b) {
    if (a.isEmpty && b.isEmpty) return 1.0;
    if (a.isEmpty || b.isEmpty) return 0.0;
    return a.intersection(b).length / a.union(b).length;
  }

  /// 0–100. Quão bem `candidate` substitui `source` **como movimento**.
  /// Não sabe de academia. Não sabe do usuário.
  double score(Exercise source, Exercise candidate) {
    final w = weights;
    var s = w.pattern * _kin(source.pattern, candidate.pattern);

    s += w.primary *
        (source.primary == candidate.primary
            ? 1.0
            : (candidate.secondary.contains(source.primary) ||
                    source.secondary.contains(candidate.primary)
                ? 0.45
                : 0.0));

    s += w.loadScalability *
        source.loadScalability.transitionFactor(candidate.loadScalability);
    s += w.mechanic * (source.mechanic == candidate.mechanic ? 1.0 : 0.0);
    s += w.secondary * _jaccard(source.secondary, candidate.secondary);
    s += w.force * (source.force == candidate.force ? 1.0 : 0.0);
    s += w.plane *
        (source.plane == candidate.plane
            ? 1.0
            : (source.plane == Plane.multiplano || candidate.plane == Plane.multiplano ? 0.5 : 0.0));
    s += w.laterality *
        (1.0 - (source.laterality.index - candidate.laterality.index).abs() / 2);

    return s;
  }
}

/// Um candidato a substituição, já pontuado.
class Substitution implements Comparable<Substitution> {
  final Exercise exercise;
  final double score;
  const Substitution(this.exercise, this.score);

  /// Desempate: score → familiaridade → slug. Determinístico.
  @override
  int compareTo(Substitution other) {
    final byScore = other.score.compareTo(score);
    if (byScore != 0) return byScore;
    final byFamiliarity = other.exercise.familiarity.compareTo(exercise.familiarity);
    if (byFamiliarity != 0) return byFamiliarity;
    return exercise.slug.compareTo(other.exercise.slug);
  }
}

class ExerciseCatalog {
  final Map<String, Exercise> _bySlug;
  final CompatibilityScorer scorer;

  /// Abaixo disso não é substituição, é outro exercício.
  final double minScore;

  ExerciseCatalog(Iterable<Exercise> exercises, {required this.scorer, this.minScore = 55})
      : _bySlug = {for (final e in exercises) e.slug: e};

  Exercise? operator [](String slug) => _bySlug[slug];
  Iterable<Exercise> get all => _bySlug.values;

  /// Candidatos ordenados. Sem filtro de academia e sem filtro de usuário —
  /// puro movimento. O motor aplica os filtros depois.
  List<Substitution> equivalentsOf(String slug) {
    final source = _bySlug[slug];
    if (source == null) return const [];
    final out = <Substitution>[];
    for (final c in _bySlug.values) {
      if (c.slug == slug) continue;
      final s = scorer.score(source, c);
      if (s >= minScore) out.add(Substitution(c, s));
    }
    out.sort();
    return out;
  }
}
