/// BoraSet — progressão de carga.
///
/// Sugerir "+2,5 kg" para quem treina nos EUA é sugerir uma anilha que não
/// existe na academia dele. Progressão só vale se o número for **alcançável**
/// com o ferro que existe na parede.
///
/// E o arredondamento não depende só do país: depende do equipamento.
/// Barra sobe de par em par. Halter pula de denominação em denominação.
/// Stack de máquina anda de placa em placa. Três matemáticas diferentes.
library;

import 'catalog.dart';
import 'session.dart';

enum WeightUnit { kg, lb }

/// Como a carga é montada neste exercício. Derivado do equipamento do catálogo.
enum LoadingMode {
  /// Barra + pares de anilha. Incremento = 2 × menor anilha.
  barbell,
  /// Halteres: denominações discretas, com saltos que crescem.
  dumbbell,
  /// Stack de máquina ou polia: múltiplos fixos de placa.
  stack,
  /// Peso corporal: não há carga a progredir. Progride em repetição ou tempo.
  bodyweight,
  /// Medido em tempo/distância. Progressão não é de carga.
  timed,
}

/// O ferro que existe naquela academia, naquele país.
class PlateProfile {
  final WeightUnit unit;

  /// Peso da barra olímpica. 20 kg / 45 lb.
  final double barWeight;

  /// Denominações de anilha disponíveis, por lado. Ordem decrescente.
  final List<double> plates;

  /// Denominações de halter, em ordem crescente.
  final List<double> dumbbells;

  /// Passo do stack de máquina/polia.
  final double stackStep;

  const PlateProfile({
    required this.unit,
    required this.barWeight,
    required this.plates,
    required this.dumbbells,
    required this.stackStep,
  });

  /// Academia métrica típica. Anilha mais leve: 1,25 kg → salto de 2,5 kg na barra.
  static const metric = PlateProfile(
    unit: WeightUnit.kg,
    barWeight: 20,
    plates: [25, 20, 15, 10, 5, 2.5, 1.25],
    dumbbells: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 12, 14, 16, 18, 20,
                22.5, 25, 27.5, 30, 32.5, 35, 40, 45, 50],
    stackStep: 5,
  );

  /// Academia imperial típica (EUA). Anilha mais leve: 2,5 lb → salto de 5 lb.
  /// 5 lb ≈ 2,27 kg — perto do salto métrico, mas NÃO igual. Arredondar de
  /// um para o outro produz número que não existe na parede.
  static const imperial = PlateProfile(
    unit: WeightUnit.lb,
    barWeight: 45,
    plates: [45, 35, 25, 10, 5, 2.5],
    dumbbells: [5, 10, 15, 20, 25, 30, 35, 40, 45, 50, 55, 60,
                65, 70, 75, 80, 85, 90, 95, 100, 110, 120],
    stackStep: 10,
  );

  static PlateProfile forLocale(String locale) =>
      locale == 'en-US' || locale == 'en_US' ? imperial : metric;

  /// Menor aumento possível na barra: um par da menor anilha.
  double get minBarbellStep => plates.last * 2;

  /// Menor carga montável na barra (barra vazia).
  double get minBarbellLoad => barWeight;
}

/// Traduz equipamento do catálogo em modo de carregamento.
LoadingMode loadingModeOf(Exercise e) {
  if (e.loadScalability == LoadScalability.tempo) return LoadingMode.timed;
  if (e.equipment.contains(Equipment.barra) || e.equipment.contains(Equipment.smith)) {
    return LoadingMode.barbell;
  }
  if (e.equipment.contains(Equipment.halter)) return LoadingMode.dumbbell;
  if (e.equipment.contains(Equipment.maquina) || e.equipment.contains(Equipment.polia)) {
    return LoadingMode.stack;
  }
  return LoadingMode.bodyweight;
}

/// Arredonda um alvo teórico para o número que a academia realmente permite.
class PlateMath {
  final PlateProfile profile;
  const PlateMath(this.profile);

  /// Sempre arredonda para o valor alcançável mais próximo.
  /// `preferUp` desempata para cima — é o que se quer numa progressão.
  double round(double target, LoadingMode mode, {bool preferUp = true}) {
    switch (mode) {
      case LoadingMode.barbell:
        if (target <= profile.barWeight) return profile.barWeight;
        final perSide = (target - profile.barWeight) / 2;
        final step = profile.plates.last;
        final n = preferUp ? (perSide / step).ceil() : (perSide / step).round();
        return profile.barWeight + n * step * 2;

      case LoadingMode.dumbbell:
        final ds = profile.dumbbells;
        if (target <= ds.first) return ds.first;
        if (target >= ds.last) return ds.last;
        for (var i = 0; i < ds.length - 1; i++) {
          if (target > ds[i] && target <= ds[i + 1]) {
            if (preferUp) return ds[i + 1];
            return (target - ds[i]) <= (ds[i + 1] - target) ? ds[i] : ds[i + 1];
          }
        }
        return ds.last;

      case LoadingMode.stack:
        final s = profile.stackStep;
        if (target <= s) return s;
        final n = preferUp ? (target / s).ceil() : (target / s).round();
        return n * s;

      case LoadingMode.bodyweight:
      case LoadingMode.timed:
        return target;
    }
  }

  /// O próximo degrau acima de `current`. Nunca devolve o mesmo valor —
  /// arredondar para cima um número que já é alcançável devolveria ele mesmo.
  double? nextUp(double current, LoadingMode mode) {
    switch (mode) {
      case LoadingMode.barbell:
        return current + profile.minBarbellStep;
      case LoadingMode.dumbbell:
        final next = profile.dumbbells.where((d) => d > current);
        return next.isEmpty ? null : next.first;
      case LoadingMode.stack:
        return round(current + profile.stackStep * 0.5, mode);
      case LoadingMode.bodyweight:
      case LoadingMode.timed:
        return null;
    }
  }
}

// ---------------------------------------------------------------------------
// Estratégias de progressão — plugáveis, como o brief pediu.
// ---------------------------------------------------------------------------

sealed class ProgressionAdvice {
  const ProgressionAdvice();
}

/// Mantenha a carga e busque mais repetições.
class HoldAndAddReps extends ProgressionAdvice {
  final double loadKg;
  final List<int> targetReps;
  const HoldAndAddReps(this.loadKg, this.targetReps);
}

/// Fechou o topo da faixa. Suba — para um valor que existe na parede.
class IncreaseLoad extends ProgressionAdvice {
  final double from, to;
  final WeightUnit unit;
  /// Quantos por cento o salto representa. Salto grande em exercício pequeno
  /// merece aviso: subir 5 lb num tríceps de 20 lb é +25%.
  final double jumpPercent;
  const IncreaseLoad(this.from, this.to, this.unit, this.jumpPercent);
}

/// Progressão de carga não se aplica (peso corporal, tempo).
class ProgressByOther extends ProgressionAdvice {
  final String dimension; // 'reps' | 'tempo' | 'amplitude'
  const ProgressByOther(this.dimension);
}

/// Não há dado suficiente para sugerir nada. Melhor calar.
class NoAdvice extends ProgressionAdvice {
  const NoAdvice();
}

abstract interface class ProgressionStrategy {
  ProgressionAdvice advise({
    required Exercise exercise,
    required ExerciseSlot slot,
    required List<SetRecord> lastSession,
    required PlateMath plates,
  });
}

/// Dupla progressão: sobe repetição dentro da faixa; ao fechar o topo em
/// todas as séries, sobe carga e volta ao piso da faixa.
///
/// É o padrão do BoraSet. Outras estratégias entram pela mesma interface.
class DoubleProgression implements ProgressionStrategy {
  /// Alerta quando o menor salto disponível é uma fração grande da carga atual.
  final double jumpWarningThreshold;
  const DoubleProgression({this.jumpWarningThreshold = 0.10});

  @override
  ProgressionAdvice advise({
    required Exercise exercise,
    required ExerciseSlot slot,
    required List<SetRecord> lastSession,
    required PlateMath plates,
  }) {
    final mode = loadingModeOf(exercise);
    if (mode == LoadingMode.timed) return const ProgressByOther('tempo');
    if (mode == LoadingMode.bodyweight) return const ProgressByOther('reps');

    final working = lastSession.where((s) => !s.warmup && s.reps != null).toList();
    if (working.isEmpty) return const NoAdvice();

    // Só a dupla progressão precisa de faixa. Com Falha, NO REPS ou
    // prescrição por série, o critério de "topo" não existe.
    if (slot.reps is! RepRange) return const NoAdvice();
    final range = slot.reps as RepRange;

    final loads = working.map((s) => s.loadKg).whereType<double>().toList();
    if (loads.isEmpty) return const NoAdvice();
    final current = loads.reduce((a, b) => a > b ? a : b);

    final hitTop = working.every((s) => (s.reps ?? 0) >= range.max);
    if (!hitTop) {
      return HoldAndAddReps(
        current,
        working.map((s) => ((s.reps ?? range.min) + 1).clamp(range.min, range.max)).toList(),
      );
    }

    final next = plates.nextUp(current, mode);
    if (next == null) return const ProgressByOther('reps');

    return IncreaseLoad(current, next, plates.profile.unit, (next - current) / current);
  }
}
