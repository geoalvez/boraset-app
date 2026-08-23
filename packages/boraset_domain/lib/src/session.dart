/// BoraSet — a sessão de treino.
///
/// Separação que o catálogo obriga:
///   Exercise      identidade do movimento        (catálogo, compartilhado)
///   ExerciseSlot  o exercício DENTRO desta sessão (prescrição + execução)
///   SessionBlock  estrutura: série reta, bi-set, tri-set
///
/// O nome do exercício na planilha de origem misturava os três. Aqui não.
library;

import 'catalog.dart';

// ---------------------------------------------------------------------------
// Prescrição — os cinco formatos que existem de verdade no corpus.
// ---------------------------------------------------------------------------

/// Como as repetições foram prescritas. Tipo-soma, nunca um `int`.
sealed class RepPrescription {
  const RepPrescription();
}

/// `8 a 15` — faixa alvo. O caso mais comum.
class RepRange extends RepPrescription {
  final int min, max;
  const RepRange(this.min, this.max);
}

/// `12/12/10/10` — alvo diferente por série.
class RepPerSet extends RepPrescription {
  final List<int?> reps; // null = série até a falha, ex. `8/8/8/Falha`
  const RepPerSet(this.reps);
}

/// `Falha` — sem número, vai até falhar.
class RepToFailure extends RepPrescription {
  const RepToFailure();
}

/// `NO REPS` — sem alvo numérico; critério de esforço, não de contagem.
class RepOpen extends RepPrescription {
  const RepOpen();
}

/// `30 min` — cardio e isométrico: medido em tempo.
class RepByDuration extends RepPrescription {
  final Duration duration;
  const RepByDuration(this.duration);
}

/// Descanso prescrito. Os 20 formatos brutos do corpus colapsam nestes.
sealed class RestPrescription {
  const RestPrescription();
  /// Valor único usado pelo estimador de duração.
  Duration get nominal;
}

class RestFixed extends RestPrescription {
  final Duration value;
  const RestFixed(this.value);
  @override
  Duration get nominal => value;
}

class RestRange extends RestPrescription {
  final Duration min, max;
  const RestRange(this.min, this.max);
  @override
  Duration get nominal => Duration(seconds: (min.inSeconds + max.inSeconds) ~/ 2);
}

/// `0` / `0"` — emenda direto. Comum com No-Stop e dentro de bi-set.
class RestNone extends RestPrescription {
  const RestNone();
  @override
  Duration get nominal => Duration.zero;
}

// ---------------------------------------------------------------------------
// Execução
// ---------------------------------------------------------------------------

/// Uma série executada.
///
/// A carga vive AQUI, não no exercício. Pirâmide (328× no corpus),
/// Drop-Set e Strip-Set mudam a carga a cada série.
class SetRecord {
  final int index;
  final double? loadKg;
  final int? reps;
  final Duration? elapsed;
  final bool warmup;

  const SetRecord({
    required this.index,
    this.loadKg,
    this.reps,
    this.elapsed,
    this.warmup = false,
  });
}

/// Um exercício dentro desta sessão.
class ExerciseSlot {
  final String id;
  final String exerciseSlug;

  /// Origem: veio da ficha, ou o motor colocou aqui.
  final SlotOrigin origin;

  final int plannedSets;
  final RepPrescription reps;
  final RestPrescription rest;

  /// Códigos de `technique_help.pt-BR.json`. Podem ser vários na mesma linha.
  final List<String> techniqueSlugs;

  /// 1 = âncora da sessão (o motor remove por último). 5 = acessório.
  final int priority;

  final List<SetRecord> completed;

  const ExerciseSlot({
    required this.id,
    required this.exerciseSlug,
    required this.plannedSets,
    required this.reps,
    required this.rest,
    this.techniqueSlugs = const [],
    this.priority = 3,
    this.completed = const [],
    this.origin = SlotOrigin.planned,
  });

  int get remainingSets => (plannedSets - completed.length).clamp(0, plannedSets);
  bool get isDone => remainingSets == 0;

  ExerciseSlot copyWith({
    String? exerciseSlug,
    int? plannedSets,
    List<SetRecord>? completed,
    SlotOrigin? origin,
  }) =>
      ExerciseSlot(
        id: id,
        exerciseSlug: exerciseSlug ?? this.exerciseSlug,
        plannedSets: plannedSets ?? this.plannedSets,
        reps: reps,
        rest: rest,
        techniqueSlugs: techniqueSlugs,
        priority: priority,
        completed: completed ?? this.completed,
        origin: origin ?? this.origin,
      );
}

enum SlotOrigin { planned, substituted, addedByEngine }

/// Estrutura de sessão. Uma série reta é um bloco de um.
///
/// Bi-Set e Tri-Set vieram da ficha (135× e 2× no corpus) **ou** o motor os
/// cria para ganhar tempo. Mesma classe, `origin` diferente — foi essa
/// descoberta que impediu duas modelagens paralelas.
class SessionBlock {
  final String id;
  final List<ExerciseSlot> slots;
  final BlockOrigin origin;

  const SessionBlock({required this.id, required this.slots, this.origin = BlockOrigin.planned});

  bool get isSuperset => slots.length > 1;
  bool get isDone => slots.every((s) => s.isDone);

  /// Bloquear UM slot invalida o bloco inteiro. Bi-Set com metade ocupada
  /// não é meio bi-set — é um problema estrutural.
  bool isBlockedBy(Set<String> blockedSlugs) =>
      slots.any((s) => !s.isDone && blockedSlugs.contains(s.exerciseSlug));
}

enum BlockOrigin { planned, mergedByEngine }

class WorkoutSession {
  final String id;
  final String name;
  final List<SessionBlock> blocks;

  /// Grupos que esta sessão existe para treinar. O motor protege o volume
  /// destes antes de cortar qualquer coisa.
  final Set<MuscleGroup> focus;

  const WorkoutSession({
    required this.id,
    required this.name,
    required this.blocks,
    this.focus = const {},
  });

  Iterable<ExerciseSlot> get allSlots => blocks.expand((b) => b.slots);
  Iterable<SessionBlock> get pending => blocks.where((b) => !b.isDone);
}

// ---------------------------------------------------------------------------
// Indisponibilidade TEMPORÁRIA
// ---------------------------------------------------------------------------

/// "Aparelho ocupado" não é "aparelho inexistente".
///
/// O aparelho pode liberar em cinco minutos, então o bloqueio expira e o
/// motor pode voltar a sugerir. Só depois de `strikes` repetidos é que
/// o exercício vira candidato a substituição definitiva na sessão.
class BusyRegistry {
  final Map<String, _Busy> _entries;
  final Duration ttl;
  final int strikesUntilPermanent;

  BusyRegistry({
    this.ttl = const Duration(minutes: 8),
    this.strikesUntilPermanent = 2,
    Map<String, _Busy>? entries,
  }) : _entries = entries ?? {};

  /// `at` = relógio da sessão, injetado. O motor nunca lê o relógio do sistema.
  BusyRegistry markBusy(String slug, Duration at) {
    final prev = _entries[slug];
    return BusyRegistry(
      ttl: ttl,
      strikesUntilPermanent: strikesUntilPermanent,
      entries: {..._entries, slug: _Busy(at, (prev?.strikes ?? 0) + 1)},
    );
  }

  bool isBlocked(String slug, Duration now) {
    final e = _entries[slug];
    if (e == null) return false;
    if (e.strikes >= strikesUntilPermanent) return true; // desistiu de esperar
    return now - e.markedAt < ttl;
  }

  /// Marcado tantas vezes que não vale mais esperar.
  bool isPermanent(String slug) => (_entries[slug]?.strikes ?? 0) >= strikesUntilPermanent;

  Set<String> blockedAt(Duration now) =>
      _entries.keys.where((s) => isBlocked(s, now)).toSet();

  /// Bloqueado agora, mas ainda vale reavaliar depois — o degrau "voltar ao
  /// exercício posteriormente" da escada.
  Set<String> retriableAt(Duration now) =>
      _entries.keys.where((s) => isBlocked(s, now) && !isPermanent(s)).toSet();
}

class _Busy {
  final Duration markedAt;
  final int strikes;
  const _Busy(this.markedAt, this.strikes);
}
