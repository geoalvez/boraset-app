/// BoraSet — WorkoutDecisionEngine.
///
/// O coração do produto. Dart puro, sem I/O, sem relógio, sem Flutter.
///
/// Contrato: `decide(EngineInput) -> Decision`. Função pura.
/// Mesmo input, mesmo output, sempre. É isso que torna o motor testável
/// sem emulador e auditável quando o usuário perguntar "por que você
/// tirou esse exercício?".
library;

import 'catalog.dart';
import 'session.dart';

// ---------------------------------------------------------------------------
// ENTRADA
// ---------------------------------------------------------------------------

/// O que o usuário tocou. Espelha 1:1 os botões da tela de treino.
sealed class SessionEvent {
  const SessionEvent();
}

/// Botão principal: "O QUE FAÇO AGORA?"
class WhatNow extends SessionEvent { const WhatNow(); }

class SetCompleted extends SessionEvent {
  final String slotId;
  final SetRecord record;
  const SetCompleted(this.slotId, this.record);
}

/// APARELHO OCUPADO — bloqueio temporário, com prazo.
class EquipmentBusy extends SessionEvent {
  final String slotId;
  const EquipmentBusy(this.slotId);
}

/// QUERO TROCAR — preferência. Alimenta o aprendizado de comportamento.
class WantToSwap extends SessionEvent {
  final String slotId;
  const WantToSwap(this.slotId);
}

/// NÃO SEI FAZER — exclui e rebaixa a dificuldade do substituto.
class DontKnowHow extends SessionEvent {
  final String slotId;
  const DontKnowHow(this.slotId);
}

class SkipExercise extends SessionEvent {
  final String slotId;
  const SkipExercise(this.slotId);
}

/// "Só tenho X minutos" — pode chegar no começo ou no meio.
class TimeBudgetChanged extends SessionEvent {
  final Duration remaining;
  const TimeBudgetChanged(this.remaining);
}

/// Equipamento que ESTA academia não tem. Diferente de ocupado: não expira.
class EquipmentUnavailable extends SessionEvent {
  final Set<Equipment> missing;
  const EquipmentUnavailable(this.missing);
}

/// Preferências do usuário. Terceiro filtro, independente dos outros dois.
class UserProfile {
  final Set<String> avoided;      // nunca sugerir
  final Set<String> preferred;    // desempate a favor
  final Level level;
  /// Segundos por série observados. Vazio = cold start.
  final Map<String, double> observedSetSeconds;
  final double? observedTransitionSeconds;

  const UserProfile({
    this.avoided = const {},
    this.preferred = const {},
    this.level = Level.intermediario,
    this.observedSetSeconds = const {},
    this.observedTransitionSeconds,
  });

  bool get isColdStart => observedSetSeconds.length < 12;
}

class EngineInput {
  final WorkoutSession session;
  final ExerciseCatalog catalog;
  final UserProfile profile;
  final BusyRegistry busy;

  /// Equipamento presente NESTA academia.
  final Set<Equipment> availableEquipment;

  /// Tempo decorrido desde o início. Injetado — o motor não lê relógio.
  final Duration elapsed;

  /// Tempo total que o usuário disse ter. `null` = treino normal, sem teto.
  final Duration? timeBudget;

  final SessionEvent event;

  const EngineInput({
    required this.session,
    required this.catalog,
    required this.event,
    this.profile = const UserProfile(),
    required this.busy,
    this.availableEquipment = const {},
    this.elapsed = Duration.zero,
    this.timeBudget,
  });

  Duration? get timeLeft =>
      timeBudget == null ? null : timeBudget! - elapsed;
}

// ---------------------------------------------------------------------------
// SAÍDA
// ---------------------------------------------------------------------------

/// Os seis degraus da escada, em ordem de preferência.
/// O motor só desce um degrau quando o anterior não resolve.
enum LadderStep { reorder, defer, substitute, reduceVolume, superset, drop }

sealed class Adaptation {
  const Adaptation();
  LadderStep get step;
}

class Reorder extends Adaptation {
  final List<String> newBlockOrder;
  const Reorder(this.newBlockOrder);
  @override
  LadderStep get step => LadderStep.reorder;
}

class Defer extends Adaptation {
  final String blockId;
  /// Quando faz sentido reavaliar. O aparelho pode liberar.
  final Duration retryAfter;
  const Defer(this.blockId, this.retryAfter);
  @override
  LadderStep get step => LadderStep.defer;
}

class Substitute extends Adaptation {
  final String slotId, fromSlug, toSlug;
  final double compatibility;
  const Substitute(this.slotId, this.fromSlug, this.toSlug, this.compatibility);
  @override
  LadderStep get step => LadderStep.substitute;
}

class ReduceVolume extends Adaptation {
  final String slotId;
  final int fromSets, toSets;
  const ReduceVolume(this.slotId, this.fromSets, this.toSets);
  @override
  LadderStep get step => LadderStep.reduceVolume;
}

class MergeIntoSuperset extends Adaptation {
  final List<String> slotIds;
  final Duration timeSaved;
  const MergeIntoSuperset(this.slotIds, this.timeSaved);
  @override
  LadderStep get step => LadderStep.superset;
}

class DropSlot extends Adaptation {
  final String slotId;
  const DropSlot(this.slotId);
  @override
  LadderStep get step => LadderStep.drop;
}

/// Por que o motor decidiu assim.
///
/// DADO ESTRUTURADO, não string. A UI monta a frase, e o mesmo objeto
/// serve para pt-BR, para log e para auditoria. Se isto fosse texto, a
/// explicabilidade morreria na primeira tradução.
class Rationale {
  final RationaleCode code;
  final Map<String, Object?> facts;
  const Rationale(this.code, [this.facts = const {}]);
}

enum RationaleCode {
  equipmentBusyDeferred,
  equipmentBusyRepeatedSoSubstituted,
  equipmentMissingInThisGym,
  userAvoidsExercise,
  userDoesNotKnowExercise,
  timeShortReducedVolume,
  timeShortMergedSuperset,
  timeShortDroppedAccessory,
  patternAlreadyCoveredThisSession,
  onTrackNoChange,
  noViableSubstituteLadderExhausted,
}

/// Estimativa de duração — com incerteza explícita.
///
/// No dia 1 não existe histórico e o número é chute. Esconder isso destrói
/// a confiança na primeira vez que erra. A UI decide se mostra
/// "restam 21 min" ou "dá pra fazer mais uns 3 exercícios" olhando
/// `confidence` — não é decisão do motor.
class DurationEstimate {
  final Duration remaining;
  final Duration margin;
  final EstimateConfidence confidence;
  const DurationEstimate(this.remaining, this.margin, this.confidence);
}

enum EstimateConfidence { coldStart, calibrating, personalized }

class Alternative {
  final String slug;
  final double compatibility;
  final bool availableHere;
  const Alternative(this.slug, this.compatibility, this.availableHere);
}

class Decision {
  /// O que fazer agora. `null` = sessão encerrada.
  final ExerciseSlot? next;
  final List<Adaptation> adaptations;
  final List<Rationale> rationale;
  final DurationEstimate estimate;
  final List<Alternative> alternatives;

  const Decision({
    required this.next,
    this.adaptations = const [],
    this.rationale = const [],
    required this.estimate,
    this.alternatives = const [],
  });
}

// ---------------------------------------------------------------------------
// MODELO DE DURAÇÃO
// ---------------------------------------------------------------------------

/// Estima quanto falta. Injetável: dá pra trocar a estratégia sem tocar no motor.
abstract interface class DurationModel {
  DurationEstimate estimate(EngineInput input);
  Duration blockCost(SessionBlock block, EngineInput input);
}

/// Prior populacional + atualização por histórico individual.
///
/// Uma pessoa leva 40s por série, outra leva 70. Enquanto não houver
/// histórico, usa o prior e ADMITE a incerteza via `confidence`.
class HistoricalDurationModel implements DurationModel {
  final double priorSetSeconds;
  final double priorTransitionSeconds;
  const HistoricalDurationModel({
    this.priorSetSeconds = 45,
    this.priorTransitionSeconds = 40,
  });

  double _setSeconds(String slug, UserProfile p) =>
      p.observedSetSeconds[slug] ??
      (p.observedSetSeconds.isEmpty
          ? priorSetSeconds
          : p.observedSetSeconds.values.reduce((a, b) => a + b) /
              p.observedSetSeconds.length);

  @override
  Duration blockCost(SessionBlock block, EngineInput input) {
    var seconds = 0.0;
    for (final slot in block.slots) {
      final n = slot.remainingSets;
      if (n == 0) continue;
      seconds += n * _setSeconds(slot.exerciseSlug, input.profile);
      // Dentro de um bi-set não há descanso entre os slots — só ao fim do bloco.
      final restsInside = block.isSuperset ? n - 1 : n;
      seconds += restsInside.clamp(0, n) * slot.rest.nominal.inSeconds;
    }
    seconds += input.profile.observedTransitionSeconds ?? priorTransitionSeconds;
    return Duration(seconds: seconds.round());
  }

  @override
  DurationEstimate estimate(EngineInput input) {
    final total = input.session.pending
        .map((b) => blockCost(b, input))
        .fold(Duration.zero, (a, b) => a + b);

    final n = input.profile.observedSetSeconds.length;
    final (confidence, marginPct) = switch (n) {
      < 12 => (EstimateConfidence.coldStart, 0.35),
      < 40 => (EstimateConfidence.calibrating, 0.18),
      _ => (EstimateConfidence.personalized, 0.08),
    };
    return DurationEstimate(
      total,
      Duration(seconds: (total.inSeconds * marginPct).round()),
      confidence,
    );
  }
}

// ---------------------------------------------------------------------------
// A ESCADA
// ---------------------------------------------------------------------------

/// Contexto de um degrau: o problema a resolver, mais tudo que o motor sabe.
class LadderContext {
  final EngineInput input;
  final DurationModel duration;
  final SessionBlock? offending;
  const LadderContext(this.input, this.duration, {this.offending});
}

/// Um degrau. Devolve `null` quando não resolve — e aí o motor desce.
abstract interface class AdaptationStrategy {
  LadderStep get step;
  ({Adaptation adaptation, Rationale why})? apply(LadderContext ctx);
}

/// O motor. Composição de degraus + estimador. Nada mais.
class WorkoutDecisionEngine {
  final List<AdaptationStrategy> ladder;
  final DurationModel duration;

  const WorkoutDecisionEngine({required this.ladder, required this.duration});

  /// Filtro 2 — a academia. Não sabe de biomecânica.
  bool _availableHere(Exercise e, EngineInput i) =>
      i.availableEquipment.isEmpty || e.equipment.every(i.availableEquipment.contains);

  /// Filtro 3 — o usuário. Não sabe de biomecânica nem de academia.
  bool _acceptedBy(Exercise e, EngineInput i) =>
      !i.profile.avoided.contains(e.slug) && e.level.index <= i.profile.level.index + 1;

  /// Compõe os três filtros. A ordem não importa — são independentes por design.
  List<Substitution> viableSubstitutes(String slug, EngineInput i, {Duration? now}) {
    final blocked = i.busy.blockedAt(now ?? i.elapsed);
    return i.catalog
        .equivalentsOf(slug)
        .where((s) =>
            !blocked.contains(s.exercise.slug) &&
            _availableHere(s.exercise, i) &&
            _acceptedBy(s.exercise, i))
        .toList();
  }

  /// A decisão. Pura.
  Decision decide(EngineInput input) {
    final ctx = LadderContext(input, duration, offending: _offendingBlock(input));
    final adaptations = <Adaptation>[];
    final why = <Rationale>[];

    for (final rung in ladder) {
      final r = rung.apply(ctx);
      if (r != null) {
        adaptations.add(r.adaptation);
        why.add(r.why);
        break; // primeiro degrau que resolve, vence
      }
    }
    if (adaptations.isEmpty) {
      why.add(const Rationale(RationaleCode.onTrackNoChange));
    }

    final next = _pickNext(input, adaptations);
    return Decision(
      next: next,
      adaptations: adaptations,
      rationale: why,
      estimate: duration.estimate(input),
      alternatives: next == null
          ? const []
          : viableSubstitutes(next.exerciseSlug, input)
              .take(3)
              .map((s) => Alternative(s.exercise.slug, s.score, true))
              .toList(),
    );
  }

  SessionBlock? _offendingBlock(EngineInput i) {
    final blocked = i.busy.blockedAt(i.elapsed);
    for (final b in i.session.pending) {
      if (b.isBlockedBy(blocked)) return b;
    }
    return null;
  }

  ExerciseSlot? _pickNext(EngineInput i, List<Adaptation> applied) {
    final blocked = i.busy.blockedAt(i.elapsed);
    final deferred = applied.whereType<Defer>().map((d) => d.blockId).toSet();
    for (final b in i.session.pending) {
      if (deferred.contains(b.id) || b.isBlockedBy(blocked)) continue;
      final slot = b.slots.where((s) => !s.isDone).firstOrNull;
      if (slot != null) return slot;
    }
    return null;
  }
}
