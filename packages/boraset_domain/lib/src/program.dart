/// Gerador de programas de treino.
///
/// O app monta a ficha a partir do catálogo, em vez de embarcar fichas de
/// terceiros. Divisão de treino — Full Body, Upper/Lower, ABC, Push/Pull/Legs
/// — é conhecimento público de treinamento; ninguém é dono de "segunda peito,
/// quarta costas". O que tem dono é a periodização específica de um produto
/// pago, e essa não entra aqui.
///
/// A escolha do exercício de cada vaga usa o mesmo material que o resto do
/// motor: padrão de movimento, grupo alvo, equipamento disponível, nível, e
/// familiaridade como desempate.
library;

import 'catalog.dart';
import 'session.dart';

// ---------------------------------------------------------------------------
// Vocabulário
// ---------------------------------------------------------------------------

enum Goal {
  /// 8–12 repetições, descanso médio. O padrão.
  hipertrofia,

  /// 3–6 repetições, descanso longo.
  forca,

  /// 15–20 repetições, descanso curto.
  resistencia,
}

/// Prescrição derivada do objetivo.
///
/// Os números de hipertrofia não foram inventados: saíram da mineração
/// estrutural de 60 planilhas de treino — mediana de 7 exercícios por dia,
/// ~3,3 séries por exercício, faixa 10–15 dominante nos acessórios e 6–12
/// nas âncoras, descanso concentrado em 40 / 60 / 75 segundos.
///
/// Isso é regularidade de como se estrutura um treino, não a ficha de
/// ninguém. Força e resistência seguem faixas clássicas de treinamento.
class GoalScheme {
  final int anchorSets, accessorySets;
  final RepRange anchorReps, accessoryReps;
  final Duration anchorRest, accessoryRest;

  const GoalScheme({
    required this.anchorSets,
    required this.accessorySets,
    required this.anchorReps,
    required this.accessoryReps,
    required this.anchorRest,
    required this.accessoryRest,
  });

  static const _hipertrofia = GoalScheme(
    anchorSets: 4, accessorySets: 3,
    anchorReps: RepRange(6, 12), accessoryReps: RepRange(10, 15),
    anchorRest: Duration(seconds: 75), accessoryRest: Duration(seconds: 60),
  );
  static const _forca = GoalScheme(
    anchorSets: 5, accessorySets: 3,
    anchorReps: RepRange(3, 6), accessoryReps: RepRange(8, 12),
    anchorRest: Duration(minutes: 3), accessoryRest: Duration(seconds: 90),
  );
  static const _resistencia = GoalScheme(
    anchorSets: 3, accessorySets: 3,
    anchorReps: RepRange(12, 15), accessoryReps: RepRange(15, 20),
    anchorRest: Duration(seconds: 45), accessoryRest: Duration(seconds: 30),
  );

  static GoalScheme of(Goal g) => switch (g) {
        Goal.hipertrofia => _hipertrofia,
        Goal.forca => _forca,
        Goal.resistencia => _resistencia,
      };
}

/// Uma vaga no dia: "aqui vai um empurrar horizontal composto para peito".
class Slot {
  final MovementPattern pattern;
  final MuscleGroup target;

  /// Âncora = o exercício que justifica o dia. Recebe mais séries, descanso
  /// mais longo, e o motor nunca o remove por falta de tempo.
  final bool anchor;

  /// Preferir composto (âncoras) ou isolador (acessórios).
  final Mechanic? prefer;

  const Slot(this.pattern, this.target, {this.anchor = false, this.prefer});
}

class SplitDay {
  final String name;
  final Set<MuscleGroup> focus;
  final List<Slot> slots;
  const SplitDay(this.name, this.focus, this.slots);
}

class TrainingSplit {
  final String id, name;
  final int daysPerWeek;
  final List<SplitDay> days;
  final Level minLevel;
  const TrainingSplit({
    required this.id,
    required this.name,
    required this.daysPerWeek,
    required this.days,
    this.minLevel = Level.iniciante,
  });
}

// ---------------------------------------------------------------------------
// Divisões
// ---------------------------------------------------------------------------

typedef _P = MovementPattern;
typedef _M = MuscleGroup;

/// Corpo inteiro, 3x na semana. A divisão padrão para quem está começando:
/// cada grupo é treinado três vezes, com pouco volume por sessão.
final fullBody3 = TrainingSplit(
  id: 'full-body-3',
  name: 'Full Body 3x',
  daysPerWeek: 3,
  days: [
    for (final v in const [
      (_P.agachar, _P.empurrarHorizontal, _P.puxarVertical),
      (_P.dobradicaQuadril, _P.empurrarVertical, _P.puxarHorizontal),
      (_P.agachar, _P.empurrarInclinado, _P.puxarVertical),
    ])
      SplitDay('Corpo inteiro', const {_M.quadriceps, _M.peito, _M.costas}, [
        Slot(v.$1, v.$1 == _P.agachar ? _M.quadriceps : _M.isquiotibiais,
            anchor: true, prefer: Mechanic.composto),
        Slot(v.$2, v.$2 == _P.empurrarVertical ? _M.ombroAnterior : _M.peito,
            anchor: true, prefer: Mechanic.composto),
        Slot(v.$3, _M.costas, anchor: true, prefer: Mechanic.composto),
        const Slot(_P.flexaoJoelho, _M.isquiotibiais),
        const Slot(_P.flexaoPlantar, _M.panturrilha),
        const Slot(_P.antiextensao, _M.coreAnterior),
      ]),
  ],
);

/// Superior/Inferior, 4x. Mais volume por grupo que o full body, sem exigir
/// os seis dias de um PPL.
final upperLower4 = TrainingSplit(
  id: 'upper-lower-4',
  name: 'Upper / Lower 4x',
  daysPerWeek: 4,
  minLevel: Level.intermediario,
  days: const [
    SplitDay('Superior', {_M.peito, _M.costas, _M.ombroLateral}, [
      Slot(_P.empurrarHorizontal, _M.peito, anchor: true, prefer: Mechanic.composto),
      Slot(_P.puxarVertical, _M.costas, anchor: true, prefer: Mechanic.composto),
      Slot(_P.empurrarInclinado, _M.peito, prefer: Mechanic.composto),
      Slot(_P.puxarHorizontal, _M.costas, prefer: Mechanic.composto),
      Slot(_P.abducaoOmbro, _M.ombroLateral),
      Slot(_P.flexaoCotovelo, _M.biceps),
      Slot(_P.extensaoCotovelo, _M.triceps),
    ]),
    SplitDay('Inferior', {_M.quadriceps, _M.isquiotibiais, _M.gluteo}, [
      Slot(_P.agachar, _M.quadriceps, anchor: true, prefer: Mechanic.composto),
      Slot(_P.dobradicaQuadril, _M.isquiotibiais, anchor: true, prefer: Mechanic.composto),
      Slot(_P.extensaoQuadril, _M.gluteo),
      Slot(_P.extensaoJoelho, _M.quadriceps),
      Slot(_P.flexaoJoelho, _M.isquiotibiais),
      Slot(_P.flexaoPlantar, _M.panturrilha),
      Slot(_P.flexaoTronco, _M.coreAnterior),
    ]),
    SplitDay('Superior', {_M.costas, _M.peito, _M.ombroPosterior}, [
      Slot(_P.puxarHorizontal, _M.costas, anchor: true, prefer: Mechanic.composto),
      Slot(_P.empurrarVertical, _M.ombroAnterior, anchor: true, prefer: Mechanic.composto),
      Slot(_P.puxarVertical, _M.costas, prefer: Mechanic.composto),
      Slot(_P.aducaoHorizontal, _M.peito, prefer: Mechanic.isolador),
      Slot(_P.abducaoHorizontal, _M.ombroPosterior),
      Slot(_P.flexaoCotovelo, _M.biceps),
      Slot(_P.extensaoCotovelo, _M.triceps),
    ]),
    SplitDay('Inferior', {_M.gluteo, _M.quadriceps, _M.isquiotibiais}, [
      Slot(_P.dobradicaQuadril, _M.isquiotibiais, anchor: true, prefer: Mechanic.composto),
      Slot(_P.avanco, _M.quadriceps, anchor: true, prefer: Mechanic.composto),
      Slot(_P.extensaoQuadril, _M.gluteo),
      Slot(_P.abducaoQuadril, _M.abdutores),
      Slot(_P.flexaoJoelho, _M.isquiotibiais),
      Slot(_P.flexaoPlantar, _M.panturrilha),
      Slot(_P.antirotacao, _M.coreLateral),
    ]),
  ],
);

/// Push / Pull / Legs, 6x. Volume alto e frequência dobrada por grupo.
final pushPullLegs6 = TrainingSplit(
  id: 'push-pull-legs-6',
  name: 'Push / Pull / Legs 6x',
  daysPerWeek: 6,
  minLevel: Level.avancado,
  days: const [
    SplitDay('Empurrar', {_M.peito, _M.ombroAnterior, _M.triceps}, [
      Slot(_P.empurrarHorizontal, _M.peito, anchor: true, prefer: Mechanic.composto),
      Slot(_P.empurrarInclinado, _M.peito, anchor: true, prefer: Mechanic.composto),
      Slot(_P.empurrarVertical, _M.ombroAnterior, prefer: Mechanic.composto),
      Slot(_P.aducaoHorizontal, _M.peito, prefer: Mechanic.isolador),
      Slot(_P.abducaoOmbro, _M.ombroLateral),
      Slot(_P.extensaoCotovelo, _M.triceps),
    ]),
    SplitDay('Puxar', {_M.costas, _M.biceps, _M.ombroPosterior}, [
      Slot(_P.puxarVertical, _M.costas, anchor: true, prefer: Mechanic.composto),
      Slot(_P.puxarHorizontal, _M.costas, anchor: true, prefer: Mechanic.composto),
      Slot(_P.extensaoOmbro, _M.costas, prefer: Mechanic.isolador),
      Slot(_P.abducaoHorizontal, _M.ombroPosterior),
      Slot(_P.flexaoCotovelo, _M.biceps),
      Slot(_P.extensaoTronco, _M.corePosterior),
    ]),
    SplitDay('Pernas', {_M.quadriceps, _M.isquiotibiais, _M.gluteo}, [
      Slot(_P.agachar, _M.quadriceps, anchor: true, prefer: Mechanic.composto),
      Slot(_P.dobradicaQuadril, _M.isquiotibiais, anchor: true, prefer: Mechanic.composto),
      Slot(_P.extensaoJoelho, _M.quadriceps),
      Slot(_P.flexaoJoelho, _M.isquiotibiais),
      Slot(_P.extensaoQuadril, _M.gluteo),
      Slot(_P.flexaoPlantar, _M.panturrilha),
    ]),
    SplitDay('Empurrar', {_M.ombroAnterior, _M.peito, _M.triceps}, [
      Slot(_P.empurrarVertical, _M.ombroAnterior, anchor: true, prefer: Mechanic.composto),
      Slot(_P.empurrarHorizontal, _M.peito, anchor: true, prefer: Mechanic.composto),
      Slot(_P.aducaoHorizontal, _M.peito, prefer: Mechanic.isolador),
      Slot(_P.abducaoOmbro, _M.ombroLateral),
      Slot(_P.extensaoCotovelo, _M.triceps),
      Slot(_P.flexaoTronco, _M.coreAnterior),
    ]),
    SplitDay('Puxar', {_M.costas, _M.biceps, _M.trapezio}, [
      Slot(_P.puxarHorizontal, _M.costas, anchor: true, prefer: Mechanic.composto),
      Slot(_P.puxarVertical, _M.costas, anchor: true, prefer: Mechanic.composto),
      Slot(_P.abducaoHorizontal, _M.ombroPosterior),
      Slot(_P.flexaoCotovelo, _M.biceps),
      Slot(_P.rotacaoOmbro, _M.manguito),
      Slot(_P.antiextensao, _M.coreAnterior),
    ]),
    SplitDay('Pernas', {_M.gluteo, _M.isquiotibiais, _M.quadriceps}, [
      Slot(_P.avanco, _M.quadriceps, anchor: true, prefer: Mechanic.composto),
      Slot(_P.extensaoQuadril, _M.gluteo, anchor: true),
      Slot(_P.flexaoJoelho, _M.isquiotibiais),
      Slot(_P.abducaoQuadril, _M.abdutores),
      Slot(_P.aducaoQuadril, _M.adutores),
      Slot(_P.flexaoPlantar, _M.panturrilha),
    ]),
  ],
);

/// ABC, 3x. Peito+tríceps / costas+bíceps / pernas — a divisão clássica.
final abc3 = TrainingSplit(
  id: 'abc-3',
  name: 'ABC 3x',
  daysPerWeek: 3,
  minLevel: Level.intermediario,
  days: const [
    SplitDay('A — Peito e Tríceps', {_M.peito, _M.triceps}, [
      Slot(_P.empurrarHorizontal, _M.peito, anchor: true, prefer: Mechanic.composto),
      Slot(_P.empurrarInclinado, _M.peito, anchor: true, prefer: Mechanic.composto),
      Slot(_P.aducaoHorizontal, _M.peito, prefer: Mechanic.isolador),
      Slot(_P.extensaoCotovelo, _M.triceps),
      Slot(_P.extensaoCotovelo, _M.triceps, prefer: Mechanic.isolador),
      Slot(_P.flexaoTronco, _M.coreAnterior),
    ]),
    SplitDay('B — Costas e Bíceps', {_M.costas, _M.biceps}, [
      Slot(_P.puxarVertical, _M.costas, anchor: true, prefer: Mechanic.composto),
      Slot(_P.puxarHorizontal, _M.costas, anchor: true, prefer: Mechanic.composto),
      Slot(_P.abducaoHorizontal, _M.ombroPosterior),
      Slot(_P.flexaoCotovelo, _M.biceps),
      Slot(_P.flexaoCotovelo, _M.biceps, prefer: Mechanic.isolador),
      Slot(_P.extensaoTronco, _M.corePosterior),
    ]),
    SplitDay('C — Pernas e Ombros', {_M.quadriceps, _M.gluteo, _M.ombroLateral}, [
      Slot(_P.agachar, _M.quadriceps, anchor: true, prefer: Mechanic.composto),
      Slot(_P.dobradicaQuadril, _M.isquiotibiais, anchor: true, prefer: Mechanic.composto),
      Slot(_P.extensaoJoelho, _M.quadriceps),
      Slot(_P.flexaoJoelho, _M.isquiotibiais),
      Slot(_P.empurrarVertical, _M.ombroAnterior, prefer: Mechanic.composto),
      Slot(_P.abducaoOmbro, _M.ombroLateral),
      Slot(_P.flexaoPlantar, _M.panturrilha),
    ]),
  ],
);

const allSplits = <String>['full-body-3', 'upper-lower-4', 'abc-3', 'push-pull-legs-6'];
List<TrainingSplit> splitsFor(Level level) => [fullBody3, upperLower4, abc3, pushPullLegs6]
    .where((s) => s.minLevel.index <= level.index)
    .toList();

// ---------------------------------------------------------------------------
// Construção
// ---------------------------------------------------------------------------

class ProgramRequest {
  final TrainingSplit split;
  final Goal goal;
  final Level level;
  final Set<Equipment> availableEquipment;
  final Set<String> avoided;

  /// Semana do ciclo, começando em 1. O volume sobe com as semanas.
  final int week;

  const ProgramRequest({
    required this.split,
    this.goal = Goal.hipertrofia,
    this.level = Level.intermediario,
    this.availableEquipment = const {},
    this.avoided = const {},
    this.week = 1,
  });
}

class ProgramBuilder {
  final ExerciseCatalog catalog;
  const ProgramBuilder(this.catalog);

  /// Envelope de volume ao longo do ciclo.
  ///
  /// A curva veio do corpus: sobe nas semanas 4–6, RECUA nas 7–9 e sobe forte
  /// nas 10–12. Aquele recuo no meio é um deload — e é o que separa uma
  /// periodização de "vai somando série até quebrar".
  static const _weekVolume = <double>[
    1.00, 1.04, 0.99,   // 1–3   acumulação
    1.16, 1.14, 1.15,   // 4–6   sobrecarga
    0.98, 1.03, 1.04,   // 7–9   deload e retomada
    1.34, 1.36, 1.44,   // 10–12 pico
  ];

  static double weekMultiplier(int week) =>
      _weekVolume[(week - 1).clamp(0, _weekVolume.length - 1)];

  /// Séries extras nesta semana, em relação à base.
  static int _volumeBonus(int week) => ((weekMultiplier(week) - 1) * 3).round().clamp(0, 2);

  /// Com que frequência a fonte prescreve técnica por posição no dia: ~65%,
  /// razoavelmente uniforme. Aqui a técnica entra nas séries que aguentam —
  /// nunca na âncora pesada, onde ela atrapalha a carga.
  static const _techniqueRate = 0.65;

  /// Técnicas apropriadas por tipo de vaga. Sem Oclusão, Falha Total e
  /// Apneia: têm aviso de segurança e não devem ser sugeridas sozinhas.
  static const _accessoryTechniques = [
    'contracao-de-pico', 'excentrica-lenta', 'no-stop', 'repeticoes-de-reserva',
  ];
  static const _finisherTechniques = ['drop-set', 'rest-pause', '1-rest', 'no-stop'];
  static const _anchorTechniques = ['piramide-crescente', 'repeticoes-de-reserva'];

  static List<String> _techniquesFor(Slot slot, int position, int total, int seed) {
    // determinístico: mesma vaga, mesmo dia, mesma técnica sempre
    final pick = (seed * 31 + position * 17) % 100;
    if (pick >= _techniqueRate * 100) return const [];
    final pool = slot.anchor
        ? _anchorTechniques
        : (position >= total - 2 ? _finisherTechniques : _accessoryTechniques);
    return [pool[(seed + position) % pool.length]];
  }

  Exercise? _pick(Slot slot, ProgramRequest req, Set<String> used) {
    final scheme = <Exercise>[];
    for (final e in catalog.all) {
      if (used.contains(e.slug)) continue;
      if (req.avoided.contains(e.slug)) continue;
      if (e.level.index > req.level.index + 1) continue;
      if (req.availableEquipment.isNotEmpty &&
          !e.equipment.every(req.availableEquipment.contains)) continue;
      if (e.pattern != slot.pattern) continue;
      if (e.primary != slot.target && !e.secondary.contains(slot.target)) continue;
      scheme.add(e);
    }
    if (scheme.isEmpty) return null;
    scheme.sort((a, b) {
      // 1) alvo primário certo  2) mecânica pedida  3) familiaridade
      final byTarget = (b.primary == slot.target ? 1 : 0)
          .compareTo(a.primary == slot.target ? 1 : 0);
      if (byTarget != 0) return byTarget;
      if (slot.prefer != null) {
        final byMech = (b.mechanic == slot.prefer ? 1 : 0)
            .compareTo(a.mechanic == slot.prefer ? 1 : 0);
        if (byMech != 0) return byMech;
      }
      return b.familiarity.compareTo(a.familiarity);
    });
    return scheme.first;
  }

  /// Monta um dia. Vagas sem exercício disponível simplesmente não entram —
  /// é melhor um treino menor do que um treino com buraco.
  WorkoutSession buildDay(ProgramRequest req, int dayIndex) {
    final day = req.split.days[dayIndex % req.split.days.length];
    final scheme = GoalScheme.of(req.goal);
    final bonus = _volumeBonus(req.week);
    final used = <String>{};
    final blocks = <SessionBlock>[];

    var n = 0;
    for (final slot in day.slots) {
      final e = _pick(slot, req, used);
      if (e == null) continue;
      used.add(e.slug);
      final id = 's${++n}';
      blocks.add(SessionBlock(id: 'b$n', slots: [
        ExerciseSlot(
          id: id,
          exerciseSlug: e.slug,
          plannedSets: (slot.anchor ? scheme.anchorSets : scheme.accessorySets) + bonus,
          reps: slot.anchor ? scheme.anchorReps : scheme.accessoryReps,
          rest: RestFixed(slot.anchor ? scheme.anchorRest : scheme.accessoryRest),
          techniqueSlugs: req.goal == Goal.hipertrofia
              ? _techniquesFor(slot, n - 1, day.slots.length, dayIndex + req.week * 7)
              : const [],
          // Prioridade 1 = âncora: o motor nunca remove por falta de tempo.
          // Depois disso, quanto mais tarde no dia, mais dispensável.
          priority: slot.anchor ? 1 : (2 + n).clamp(2, 5),
        ),
      ]));
    }

    return WorkoutSession(
      id: '${req.split.id}-w${req.week}-d$dayIndex',
      name: '${day.name} · semana ${req.week}',
      focus: day.focus,
      blocks: blocks,
    );
  }

  /// Uma semana inteira do programa.
  List<WorkoutSession> buildWeek(ProgramRequest req) =>
      [for (var i = 0; i < req.split.days.length; i++) buildDay(req, i)];
}
