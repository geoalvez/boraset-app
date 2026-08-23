/// Testes do núcleo do BoraSet.
///
/// Cada teste aqui corresponde a uma afirmação que foi feita sobre o produto.
/// Se a afirmação estiver errada, o teste quebra — que é o ponto de o motor
/// ser Dart puro.
library;

import 'package:boraset_domain/boraset_domain.dart';
import 'package:test/test.dart';

// --- fixtures mínimas -------------------------------------------------------

const _kin = <(MovementPattern, MovementPattern), double>{
  (MovementPattern.empurrarHorizontal, MovementPattern.empurrarInclinado): .75,
  (MovementPattern.empurrarHorizontal, MovementPattern.aducaoHorizontal): .55,
  (MovementPattern.agachar, MovementPattern.extensaoJoelho): .50,
};

Exercise _ex(
  String slug, {
  required MuscleGroup primary,
  Set<MuscleGroup> secondary = const {},
  required MovementPattern pattern,
  Mechanic mechanic = Mechanic.composto,
  Laterality laterality = Laterality.bilateral,
  ForceVector force = ForceVector.empurrar,
  Plane plane = Plane.sagital,
  required LoadScalability load,
  required Set<Equipment> equipment,
  Level level = Level.intermediario,
  int familiarity = 0,
}) =>
    Exercise(
      slug: slug,
      name: slug,
      primary: primary,
      secondary: secondary,
      pattern: pattern,
      mechanic: mechanic,
      laterality: laterality,
      force: force,
      plane: plane,
      loadScalability: load,
      equipment: equipment,
      level: level,
      familiarity: familiarity,
    );

final supinoReto = _ex('supino-reto',
    primary: MuscleGroup.peito,
    secondary: {MuscleGroup.triceps, MuscleGroup.ombroAnterior},
    pattern: MovementPattern.empurrarHorizontal,
    load: LoadScalability.alta,
    equipment: {Equipment.barra, Equipment.banco},
    familiarity: 74);

final supinoHalteres = _ex('halter-press-reto',
    primary: MuscleGroup.peito,
    secondary: {MuscleGroup.triceps, MuscleGroup.ombroAnterior},
    pattern: MovementPattern.empurrarHorizontal,
    load: LoadScalability.alta,
    equipment: {Equipment.halter, Equipment.banco},
    familiarity: 36);

final supinoMaquina = _ex('supino-maquina',
    primary: MuscleGroup.peito,
    secondary: {MuscleGroup.triceps, MuscleGroup.ombroAnterior},
    pattern: MovementPattern.empurrarHorizontal,
    load: LoadScalability.alta,
    equipment: {Equipment.maquina},
    level: Level.iniciante,
    familiarity: 25);

final flexao = _ex('flexao-de-braco',
    primary: MuscleGroup.peito,
    secondary: {MuscleGroup.triceps, MuscleGroup.coreAnterior},
    pattern: MovementPattern.empurrarHorizontal,
    load: LoadScalability.baixa,
    equipment: {Equipment.pesoCorporal},
    level: Level.iniciante,
    familiarity: 9);

final cadeiraAdutora = _ex('cadeira-adutora',
    primary: MuscleGroup.adutores,
    pattern: MovementPattern.aducaoQuadril,
    mechanic: Mechanic.isolador,
    force: ForceVector.puxar,
    plane: Plane.frontal,
    load: LoadScalability.alta,
    equipment: {Equipment.maquina},
    familiarity: 47);

ExerciseCatalog _catalog() => ExerciseCatalog(
      [supinoReto, supinoHalteres, supinoMaquina, flexao, cadeiraAdutora],
      scorer: const CompatibilityScorer(kinship: _kin),
    );

ExerciseSlot _slot(String id, String slug,
        {int sets = 3, int priority = 3, List<SetRecord> done = const []}) =>
    ExerciseSlot(
      id: id,
      exerciseSlug: slug,
      plannedSets: sets,
      reps: const RepRange(8, 12),
      rest: const RestFixed(Duration(seconds: 60)),
      priority: priority,
      completed: done,
    );

void main() {
  group('compatibilidade', () {
    final c = _catalog();

    test('equipamento não afeta o score — trocar barra por máquina é 100%', () {
      final s = const CompatibilityScorer(kinship: _kin)
          .score(supinoReto, supinoMaquina);
      expect(s, closeTo(100, 0.01),
          reason: 'mesmo movimento, equipamento diferente: deve pontuar cheio');
    });

    test('degradar carga externa para peso corporal custa caro', () {
      final comCarga = const CompatibilityScorer(kinship: _kin)
          .score(supinoReto, supinoHalteres);
      final semCarga =
          const CompatibilityScorer(kinship: _kin).score(supinoReto, flexao);
      expect(comCarga, greaterThan(semCarga));
      expect(semCarga, lessThan(90),
          reason: 'flexão não pode passar por substituto quase perfeito do supino');
    });

    test('subir de peso corporal para carga externa é neutro', () {
      final descendo =
          const CompatibilityScorer(kinship: _kin).score(supinoReto, flexao);
      final subindo =
          const CompatibilityScorer(kinship: _kin).score(flexao, supinoReto);
      expect(subindo, greaterThan(descendo),
          reason: 'a penalidade de carga é assimétrica por design');
    });

    test('empate de score é desfeito por familiaridade', () {
      final eq = c.equivalentsOf('supino-reto');
      final cem = eq.where((e) => e.score >= 99.99).toList();
      expect(cem.length, greaterThanOrEqualTo(2));
      for (var i = 1; i < cem.length; i++) {
        expect(cem[i - 1].exercise.familiarity,
            greaterThanOrEqualTo(cem[i].exercise.familiarity));
      }
    });

    test('cadeira adutora é órfã — nenhum equivalente acima do mínimo', () {
      expect(c.equivalentsOf('cadeira-adutora'), isEmpty,
          reason: 'adução de quadril só tem um aparelho; o motor precisa '
              'dos outros degraus da escada');
    });
  });

  group('indisponibilidade temporária', () {
    test('"ocupado" expira; "ocupado de novo" vira permanente', () {
      var reg = BusyRegistry(ttl: const Duration(minutes: 8));
      reg = reg.markBusy('crossover', const Duration(minutes: 10));

      expect(reg.isBlocked('crossover', const Duration(minutes: 12)), isTrue);
      expect(reg.isBlocked('crossover', const Duration(minutes: 19)), isFalse,
          reason: 'passou o TTL: o aparelho pode ter liberado');
      expect(reg.isPermanent('crossover'), isFalse);

      reg = reg.markBusy('crossover', const Duration(minutes: 20));
      expect(reg.isPermanent('crossover'), isTrue);
      expect(reg.isBlocked('crossover', const Duration(hours: 5)), isTrue,
          reason: 'marcou duas vezes: não vale mais esperar');
    });
  });

  group('bloco de sessão', () {
    test('bi-set com metade ocupada invalida o bloco inteiro', () {
      final bloco = SessionBlock(
        id: 'b1',
        slots: [_slot('s1', 'supino-reto'), _slot('s2', 'flexao-de-braco')],
      );
      expect(bloco.isSuperset, isTrue);
      expect(bloco.isBlockedBy({'supino-reto'}), isTrue,
          reason: 'meio bi-set não é bi-set');
    });
  });

  group('matemática de anilha', () {
    const metric = PlateMath(PlateProfile.metric);
    const imperial = PlateMath(PlateProfile.imperial);

    test('barra sobe de par em par, e o par muda com o país', () {
      expect(metric.nextUp(30, LoadingMode.barbell), 32.5);
      expect(imperial.nextUp(135, LoadingMode.barbell), 140);
    });

    test('converter 2,5 kg para lb daria um número que não existe', () {
      const convertido = 2.5 / 0.45359237; // 5,51 lb
      expect(PlateProfile.imperial.minBarbellStep, 5.0);
      expect(convertido, isNot(closeTo(5.0, 0.1)));
    });

    test('halter pula em degraus irregulares', () {
      expect(metric.nextUp(10, LoadingMode.dumbbell), 12); // +20%
      expect(metric.nextUp(30, LoadingMode.dumbbell), 32.5); // +8%
    });

    test('barra vazia é o piso — exercício leve não tem versão com barra', () {
      expect(metric.round(12, LoadingMode.barbell), PlateProfile.metric.barWeight);
    });

    test('arredonda sempre para cima numa progressão', () {
      expect(metric.round(31, LoadingMode.barbell), 32.5);
      expect(metric.round(22, LoadingMode.stack), 25);
    });
  });

  group('progressão', () {
    const strategy = DoubleProgression();
    const plates = PlateMath(PlateProfile.metric);

    test('não fechou o topo da faixa: mantém a carga', () {
      final r = strategy.advise(
        exercise: supinoReto,
        slot: _slot('s1', 'supino-reto'),
        lastSession: const [
          SetRecord(index: 0, loadKg: 30, reps: 10),
          SetRecord(index: 1, loadKg: 30, reps: 10),
          SetRecord(index: 2, loadKg: 30, reps: 9),
        ],
        plates: plates,
      );
      expect(r, isA<HoldAndAddReps>());
      expect((r as HoldAndAddReps).loadKg, 30);
    });

    test('fechou o topo: sobe para um valor que existe na parede', () {
      final r = strategy.advise(
        exercise: supinoReto,
        slot: _slot('s1', 'supino-reto'),
        lastSession: const [
          SetRecord(index: 0, loadKg: 30, reps: 12),
          SetRecord(index: 1, loadKg: 30, reps: 12),
          SetRecord(index: 2, loadKg: 30, reps: 12),
        ],
        plates: plates,
      );
      expect(r, isA<IncreaseLoad>());
      expect((r as IncreaseLoad).to, 32.5);
    });

    test('sem faixa de repetição, prefere calar a chutar', () {
      final slot = ExerciseSlot(
        id: 's1',
        exerciseSlug: 'supino-reto',
        plannedSets: 3,
        reps: const RepToFailure(),
        rest: const RestFixed(Duration(seconds: 60)),
      );
      final r = strategy.advise(
        exercise: supinoReto,
        slot: slot,
        lastSession: const [SetRecord(index: 0, loadKg: 30, reps: 8)],
        plates: plates,
      );
      expect(r, isA<NoAdvice>());
    });

    test('peso corporal progride por outra dimensão', () {
      final r = strategy.advise(
        exercise: flexao,
        slot: _slot('s1', 'flexao-de-braco'),
        lastSession: const [SetRecord(index: 0, reps: 12)],
        plates: plates,
      );
      expect(r, isA<ProgressByOther>());
      expect((r as ProgressByOther).dimension, 'reps');
    });
  });

  group('apresentação', () {
    const presenter = ProgressionPresenter();

    LoadCue cue(double from, double to) => presenter.present(
          IncreaseLoad(from, to, WeightUnit.kg, (to - from) / from),
          unit: WeightUnit.kg,
        );

    test('salto normal: sugere o número', () {
      expect(cue(30, 32.5).tone, LoadCueTone.suggest); // +8%
    });

    test('salto grande: sugere com aviso', () {
      final c = cue(20, 22.5); // +12,5%
      expect(c.tone, LoadCueTone.suggestWithCaution);
      expect(c.jumpPercent, 13);
    });

    test('stack grosso demais: NÃO sugere número', () {
      final c = cue(5, 10); // +100%
      expect(c.tone, LoadCueTone.withhold);
      expect(c.suggested, isNull,
          reason: 'mandar dobrar a carga da elevação lateral é perigoso');
      expect(c.fallbackDimension, 'reps');
    });

    test('a incerteza do tempo vira forma, não sumiço do número', () {
      const p = TimePresenter();
      final frio = p.present(const DurationEstimate(
          Duration(minutes: 25), Duration(minutes: 9), EstimateConfidence.coldStart));
      final quente = p.present(const DurationEstimate(
          Duration(minutes: 25), Duration(minutes: 2), EstimateConfidence.personalized));

      expect(frio.mode, TimeDisplayMode.range);
      expect(quente.mode, TimeDisplayMode.exact);
      expect(frio.remaining, quente.remaining,
          reason: 'o número é o mesmo; muda só como ele é apresentado');
      expect(frio.explainable, isTrue);
      expect(frio.high - frio.low, greaterThan(quente.high - quente.low));
    });

    test('só CONCLUÍDA é ação primária', () {
      final primarias =
          WorkoutAction.values.where((a) => a.isPrimary).toList();
      expect(primarias, [WorkoutAction.completed]);
    });
  });

  group('motor e escada', () {
    late WorkoutDecisionEngine engine;

    EngineInput input({
      required SessionEvent event,
      BusyRegistry? busy,
      Duration elapsed = Duration.zero,
      Duration? budget,
      UserProfile profile = const UserProfile(),
    }) =>
        EngineInput(
          session: WorkoutSession(
            id: 'A',
            name: 'Peito',
            focus: const {MuscleGroup.peito},
            blocks: [
              SessionBlock(id: 'b1', slots: [_slot('s1', 'supino-reto', priority: 1)]),
              SessionBlock(id: 'b2', slots: [_slot('s2', 'supino-maquina')]),
              SessionBlock(id: 'b3', slots: [_slot('s3', 'flexao-de-braco', priority: 5)]),
            ],
          ),
          catalog: _catalog(),
          event: event,
          busy: busy ?? BusyRegistry(),
          elapsed: elapsed,
          timeBudget: budget,
          profile: profile,
        );

    setUp(() {
      late WorkoutDecisionEngine e;
      e = WorkoutDecisionEngine(
        ladder: defaultLadder(() => e),
        duration: const HistoricalDurationModel(),
      );
      engine = e;
    });

    test('aparelho ocupado reordena antes de substituir', () {
      final busy = BusyRegistry().markBusy('supino-reto', Duration.zero);
      final d = engine.decide(input(event: const EquipmentBusy('s1'), busy: busy));

      expect(d.adaptations.first.step, LadderStep.reorder,
          reason: 'reordenar tem custo zero de volume; vem primeiro');
      expect(d.next?.exerciseSlug, isNot('supino-reto'));
    });

    test('a decisão é pura — mesmo input, mesma saída', () {
      final busy = BusyRegistry().markBusy('supino-reto', Duration.zero);
      final a = engine.decide(input(event: const EquipmentBusy('s1'), busy: busy));
      final b = engine.decide(input(event: const EquipmentBusy('s1'), busy: busy));
      expect(a.adaptations.first.step, b.adaptations.first.step);
      expect(a.next?.id, b.next?.id);
      expect(a.estimate.remaining, b.estimate.remaining);
    });

    test('sem tempo apertado e sem bloqueio, não mexe no treino', () {
      final d = engine.decide(input(event: const WhatNow()));
      expect(d.adaptations, isEmpty);
      expect(d.rationale.first.code, RationaleCode.onTrackNoChange);
    });

    test('tempo curto corta volume do acessório, não da âncora', () {
      final d = engine.decide(input(
        event: const TimeBudgetChanged(Duration(minutes: 5)),
        budget: const Duration(minutes: 5),
      ));
      final cut = d.adaptations.whereType<ReduceVolume>().firstOrNull;
      expect(cut, isNotNull);
      expect(cut!.slotId, 's3', reason: 'prioridade 5 é o acessório');
    });

    test('a estimativa admite que está fria no dia 1', () {
      final d = engine.decide(input(event: const WhatNow()));
      expect(d.estimate.confidence, EstimateConfidence.coldStart);
      expect(d.estimate.margin.inSeconds, greaterThan(0));
    });

    test('"não sei fazer" não troca por outro exercício mais difícil', () {
      final d = engine.decide(input(
        event: const DontKnowHow('s1'),
        profile: const UserProfile(level: Level.iniciante),
      ));
      final sub = d.adaptations.whereType<Substitute>().firstOrNull;
      expect(sub, isNotNull);
      final novo = _catalog()[sub!.toSlug]!;
      expect(novo.level.index, lessThanOrEqualTo(supinoReto.level.index));
    });

    test('preferências do usuário filtram sem tocar no score', () {
      final semFiltro = engine.viableSubstitutes('supino-reto', input(event: const WhatNow()));
      final comFiltro = engine.viableSubstitutes(
        'supino-reto',
        input(
          event: const WhatNow(),
          profile: const UserProfile(avoided: {'supino-maquina'}),
        ),
      );
      expect(comFiltro.length, semFiltro.length - 1);
      expect(comFiltro.map((s) => s.exercise.slug), isNot(contains('supino-maquina')));
    });
  });
}
