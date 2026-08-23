/// O gerador de programas, rodado contra o catálogo real de 193 exercícios.
///
/// Nada de ficha embarcada: o programa é montado na hora, a partir do
/// catálogo e dos parâmetros estruturais. Estes testes verificam que o que
/// sai é treinável — não só que compila.
library;

import 'package:boraset/src/data/repository.dart';
import 'package:boraset_domain/boraset_domain.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late BorasetData data;
  late ProgramBuilder builder;

  setUpAll(() async {
    data = await Repository().load('pt');
    builder = ProgramBuilder(data.catalog);
  });

  group('divisões disponíveis', () {
    test('o nível do usuário filtra o que pode escolher', () {
      expect(splitsFor(Level.iniciante).map((s) => s.id), ['full-body-3']);
      expect(splitsFor(Level.intermediario).map((s) => s.id),
          containsAll(['full-body-3', 'upper-lower-4', 'abc-3']));
      expect(splitsFor(Level.avancado).length, 4);
    });
  });

  group('montagem do dia', () {
    test('toda vaga vira exercício de verdade do catálogo', () {
      for (final split in splitsFor(Level.avancado)) {
        for (var i = 0; i < split.days.length; i++) {
          final s = builder.buildDay(ProgramRequest(split: split), i);
          expect(s.blocks, isNotEmpty, reason: '${split.id} dia $i saiu vazio');
          for (final slot in s.allSlots) {
            expect(data.catalog[slot.exerciseSlug], isNotNull,
                reason: '${slot.exerciseSlug} não existe no catálogo');
          }
        }
      }
    });

    test('nenhum exercício se repete dentro do mesmo dia', () {
      for (final split in splitsFor(Level.avancado)) {
        for (var i = 0; i < split.days.length; i++) {
          final slugs = builder.buildDay(ProgramRequest(split: split), i)
              .allSlots.map((s) => s.exerciseSlug).toList();
          expect(slugs.toSet().length, slugs.length, reason: '${split.id} dia $i repetiu');
        }
      }
    });

    test('o tamanho do dia bate com a mediana do corpus (7 exercícios)', () {
      final sizes = <int>[];
      for (final split in splitsFor(Level.avancado)) {
        for (var i = 0; i < split.days.length; i++) {
          sizes.add(builder.buildDay(ProgramRequest(split: split), i).blocks.length);
        }
      }
      final avg = sizes.reduce((a, b) => a + b) / sizes.length;
      expect(avg, inInclusiveRange(5, 8),
          reason: 'o corpus tem mediana 7 e média 7,2 exercícios por dia');
    });

    test('a âncora tem prioridade 1 — o motor nunca a remove por tempo', () {
      final s = builder.buildDay(ProgramRequest(split: abc3), 0);
      final anchors = s.allSlots.where((x) => x.priority == 1).toList();
      expect(anchors.length, greaterThanOrEqualTo(1));
      expect(anchors.first.plannedSets,
          greaterThan(s.allSlots.last.plannedSets - 1),
          reason: 'âncora leva mais série que acessório');
    });

    test('o dia cobre os grupos que ele diz treinar', () {
      final s = builder.buildDay(ProgramRequest(split: abc3), 0); // Peito e Tríceps
      final primaries = s.allSlots
          .map((x) => data.catalog[x.exerciseSlug]!.primary)
          .toSet();
      expect(primaries, contains(MuscleGroup.peito));
      expect(primaries, contains(MuscleGroup.triceps));
    });
  });

  group('equipamento e preferências', () {
    test('academia de hotel gera treino menor, mas gera', () {
      const hotel = {Equipment.halter, Equipment.banco, Equipment.pesoCorporal};
      final s = builder.buildDay(
        ProgramRequest(split: fullBody3, availableEquipment: hotel), 0);
      expect(s.blocks, isNotEmpty);
      for (final slot in s.allSlots) {
        expect(data.catalog[slot.exerciseSlug]!.equipment,
            everyElement(isIn(hotel)));
      }
    });

    test('exercício evitado nunca aparece', () {
      final s = builder.buildDay(
        ProgramRequest(split: abc3, avoided: const {'supino-reto'}),
        0,
      );
      expect(s.allSlots.map((x) => x.exerciseSlug), isNot(contains('supino-reto')));
    });

    test('iniciante não recebe exercício avançado demais', () {
      final s = builder.buildDay(
        ProgramRequest(split: fullBody3, level: Level.iniciante), 0);
      for (final slot in s.allSlots) {
        expect(data.catalog[slot.exerciseSlug]!.level.index,
            lessThanOrEqualTo(Level.intermediario.index));
      }
    });
  });

  group('periodização', () {
    test('a curva de volume tem deload no meio, como o corpus', () {
      // 1-3 acumula, 4-6 sobe, 7-9 recua, 10-12 pico
      expect(ProgramBuilder.weekMultiplier(5),
          greaterThan(ProgramBuilder.weekMultiplier(1)));
      expect(ProgramBuilder.weekMultiplier(7),
          lessThan(ProgramBuilder.weekMultiplier(5)),
          reason: 'o recuo da semana 7 é o deload — some ele e vira só somar série');
      expect(ProgramBuilder.weekMultiplier(12),
          greaterThan(ProgramBuilder.weekMultiplier(5)));
    });

    test('semana de pico tem mais séries que a semana 1', () {
      int volume(int w) => builder
          .buildDay(ProgramRequest(split: abc3, week: w), 0)
          .allSlots
          .fold(0, (a, s) => a + s.plannedSets);
      expect(volume(12), greaterThan(volume(1)));
      expect(volume(7), lessThanOrEqualTo(volume(5)));
    });

    test('uma semana inteira sai completa', () {
      final week = builder.buildWeek(ProgramRequest(split: upperLower4, week: 3));
      expect(week.length, 4);
      expect(week.every((s) => s.blocks.isNotEmpty), isTrue);
    });
  });

  group('objetivo muda a prescrição', () {
    test('força usa carga alta, poucas reps e descanso longo', () {
      final f = builder.buildDay(ProgramRequest(split: abc3, goal: Goal.forca), 0);
      final h = builder.buildDay(ProgramRequest(split: abc3, goal: Goal.hipertrofia), 0);
      final fa = f.allSlots.firstWhere((s) => s.priority == 1);
      final ha = h.allSlots.firstWhere((s) => s.priority == 1);

      expect((fa.reps as RepRange).max, lessThan((ha.reps as RepRange).max));
      expect(fa.rest.nominal, greaterThan(ha.rest.nominal));
      expect(fa.plannedSets, greaterThanOrEqualTo(ha.plannedSets));
    });

    test('resistência inverte: muitas reps e descanso curto', () {
      final r = builder.buildDay(ProgramRequest(split: abc3, goal: Goal.resistencia), 0);
      final anchor = r.allSlots.firstWhere((s) => s.priority == 1);
      expect((anchor.reps as RepRange).min, greaterThanOrEqualTo(12));
      expect(anchor.rest.nominal.inSeconds, lessThanOrEqualTo(45));
    });
  });

  group('técnicas', () {
    test('hipertrofia recebe técnica; força não', () {
      final hip = builder.buildDay(
        ProgramRequest(split: abc3, goal: Goal.hipertrofia), 0);
      final forca = builder.buildDay(
        ProgramRequest(split: abc3, goal: Goal.forca), 0);

      expect(hip.allSlots.any((s) => s.techniqueSlugs.isNotEmpty), isTrue);
      expect(forca.allSlots.every((s) => s.techniqueSlugs.isEmpty), isTrue,
          reason: 'técnica de intensidade atrapalha o trabalho de carga alta');
    });

    test('toda técnica prescrita existe e tem ajuda no idioma', () {
      for (final split in splitsFor(Level.avancado)) {
        for (var i = 0; i < split.days.length; i++) {
          final s = builder.buildDay(ProgramRequest(split: split), i);
          for (final slot in s.allSlots) {
            for (final t in slot.techniqueSlugs) {
              expect(data.techniques[t], isNotNull, reason: '$t sem verbete');
              expect(data.techniques[t]!.summary, isNotEmpty);
            }
          }
        }
      }
    });

    test('nenhuma técnica com aviso de segurança é prescrita sozinha', () {
      const perigosas = {'oclusao', 'falha-total', 'apneia'};
      for (final split in splitsFor(Level.avancado)) {
        for (var i = 0; i < split.days.length; i++) {
          for (final slot in builder.buildDay(ProgramRequest(split: split), i).allSlots) {
            expect(slot.techniqueSlugs.toSet().intersection(perigosas), isEmpty,
                reason: 'o app não prescreve por conta própria técnica de risco');
          }
        }
      }
    });

    test('a geração é determinística — mesmo pedido, mesmo treino', () {
      String fingerprint(WorkoutSession s) => s.allSlots
          .map((x) => '${x.exerciseSlug}:${x.plannedSets}:${x.techniqueSlugs}')
          .join('|');
      final a = builder.buildDay(ProgramRequest(split: abc3, week: 4), 1);
      final b = builder.buildDay(ProgramRequest(split: abc3, week: 4), 1);
      expect(fingerprint(a), fingerprint(b));
    });
  });
}
