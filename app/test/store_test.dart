/// Testes da persistência.
///
/// Rodam o MESMO SQL do app, via sqflite_common_ffi — banco de verdade em
/// memória, não mock. Se o schema quebrar, o teste quebra.
library;

import 'package:boraset/src/data/store.dart';
import 'package:boraset_domain/boraset_domain.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  late WorkoutStore store;

  setUp(() async {
    store = await WorkoutStore.open(
      path: inMemoryDatabasePath,
      factory: databaseFactoryFfi,
    );
  });
  tearDown(() => store.close());

  Future<void> logSession(String id, {required int sets, int seconds = 45}) async {
    await store.startSession(id, 'Treino A');
    for (var i = 0; i < sets; i++) {
      await store.logSet(LoggedSet(
        sessionId: id,
        slotId: 's1',
        exerciseSlug: 'supino-reto',
        setIndex: i,
        loadKg: 30 + i * 2.5,
        reps: 10,
        seconds: seconds,
      ));
    }
    await store.finishSession(id);
  }

  group('o laço da estimativa de tempo', () {
    // Esta é a razão de a persistência existir. Sem histórico o app fica
    // preso em "20–30 min" para sempre.
    test('sem histórico, o motor está frio', () async {
      final p = await store.profile();
      expect(p.isColdStart, isTrue);
      expect(p.observedSetSeconds, isEmpty);

      final e = const HistoricalDurationModel().estimate(_input(p));
      expect(e.confidence, EstimateConfidence.coldStart);
    });

    test('as séries registradas viram o ritmo real do usuário', () async {
      await logSession('s1', sets: 12, seconds: 70);
      final p = await store.profile();

      expect(p.observedSetSeconds['supino-reto'], closeTo(70, 0.01),
          reason: 'uma pessoa leva 40 s por série, outra 70 — agora ele sabe qual');
    });

    test('a margem encolhe conforme o histórico cresce', () async {
      final frio = const HistoricalDurationModel().estimate(_input(await store.profile()));

      await logSession('s1', sets: 20);
      final morno = const HistoricalDurationModel().estimate(_input(await store.profile()));

      expect(frio.confidence, EstimateConfidence.coldStart);
      expect(morno.confidence, EstimateConfidence.coldStart,
          reason: 'a confiança olha quantos EXERCÍCIOS distintos têm ritmo medido');
      expect(morno.remaining.inSeconds, isNot(frio.remaining.inSeconds),
          reason: 'com ritmo medido, a duração prevista muda');
    });

    test('o contador de séries cronometradas alimenta a barra de calibração',
        () async {
      expect(await store.timedSetCount(), 0);
      await logSession('s1', sets: 9);
      expect(await store.timedSetCount(), 9);
    });
  });

  group('carga por série', () {
    test('a última carga volta por índice, não como número único', () async {
      // Pirâmide: 30 / 32,5 / 35. "A carga do supino" não existe.
      await logSession('s1', sets: 3);
      final loads = await store.lastLoadsFor('supino-reto');
      expect(loads, {0: 30.0, 1: 32.5, 2: 35.0});
    });

    test('só a sessão mais recente conta', () async {
      await logSession('antiga', sets: 3);
      await store.startSession('nova', 'Treino A');
      await store.logSet(const LoggedSet(
        sessionId: 'nova',
        slotId: 's1',
        exerciseSlug: 'supino-reto',
        setIndex: 0,
        loadKg: 40,
        reps: 8,
        seconds: 50,
      ));

      final loads = await store.lastLoadsFor('supino-reto');
      expect(loads, {0: 40.0});
    });

    test('a última sessão volta pronta para a progressão', () async {
      await logSession('s1', sets: 3);
      final sets = await store.lastSessionOf('supino-reto');

      final advice = const DoubleProgression().advise(
        exercise: _supino,
        slot: _slot,
        lastSession: sets,
        plates: const PlateMath(PlateProfile.metric),
      );
      // 10 repetições numa faixa de 8–12: ainda não fechou o topo.
      expect(advice, isA<HoldAndAddReps>());
    });

    test('exercício nunca feito devolve vazio, não erro', () async {
      expect(await store.lastLoadsFor('agachamento-livre'), isEmpty);
      expect(await store.lastSessionOf('agachamento-livre'), isEmpty);
    });
  });

  group('histórico', () {
    test('resume séries e volume, ignorando aquecimento', () async {
      await store.startSession('s1', 'Treino A');
      await store.logSet(const LoggedSet(
        sessionId: 's1', slotId: 'a', exerciseSlug: 'supino-reto',
        setIndex: 0, loadKg: 20, reps: 10, warmup: true,
      ));
      await store.logSet(const LoggedSet(
        sessionId: 's1', slotId: 'a', exerciseSlug: 'supino-reto',
        setIndex: 1, loadKg: 30, reps: 10,
      ));
      await store.finishSession('s1');

      final h = await store.recentSessions();
      expect(h.single.setCount, 1, reason: 'aquecimento não é volume de trabalho');
      expect(h.single.volumeKg, 300);
      expect(h.single.duration, isNotNull);
    });

    test('sessões voltam da mais recente para a mais antiga', () async {
      await logSession('a', sets: 1);
      await logSession('b', sets: 1);
      final h = await store.recentSessions();
      expect(h.first.id, 'b');
    });

    test('apagar a sessão leva as séries junto', () async {
      await logSession('s1', sets: 3);
      await store.db.delete('sessions', where: 'id = ?', whereArgs: ['s1']);
      expect(await store.timedSetCount(), 0,
          reason: 'ON DELETE CASCADE tem que estar ligado');
    });
  });

  group('preferências', () {
    test('"quero trocar" vira filtro persistente do motor', () async {
      await store.avoid('agachamento-livre');
      await store.avoid('afundo-bulgaro');

      final p = await store.profile();
      expect(p.avoided, {'agachamento-livre', 'afundo-bulgaro'});
    });

    test('evitar o mesmo exercício duas vezes não duplica', () async {
      await store.avoid('crossover');
      await store.avoid('crossover');
      expect((await store.profile()).avoided, {'crossover'});
    });
  });
}

// --- fixtures ---------------------------------------------------------------

final _supino = Exercise(
  slug: 'supino-reto',
  name: 'Supino Reto',
  primary: MuscleGroup.peito,
  pattern: MovementPattern.empurrarHorizontal,
  mechanic: Mechanic.composto,
  laterality: Laterality.bilateral,
  force: ForceVector.empurrar,
  plane: Plane.sagital,
  loadScalability: LoadScalability.alta,
  equipment: const {Equipment.barra, Equipment.banco},
  level: Level.intermediario,
);

const _slot = ExerciseSlot(
  id: 's1',
  exerciseSlug: 'supino-reto',
  plannedSets: 3,
  reps: RepRange(8, 12),
  rest: RestFixed(Duration(seconds: 60)),
);

EngineInput _input(UserProfile p) => EngineInput(
      session: const WorkoutSession(
        id: 'A',
        name: 'A',
        blocks: [SessionBlock(id: 'b1', slots: [_slot])],
      ),
      catalog: ExerciseCatalog([_supino], scorer: const CompatibilityScorer()),
      event: const WhatNow(),
      busy: BusyRegistry(),
      profile: p,
    );
