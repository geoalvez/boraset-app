/// BoraSet — os seis degraus da escada de adaptação.
///
/// Cada degrau é uma classe independente e testável isoladamente.
/// A ordem da lista É a política. Trocar a política = reordenar a lista,
/// sem tocar no motor.
library;

import 'catalog.dart';
import 'engine.dart';

typedef Rung = ({Adaptation adaptation, Rationale why});

// --- 1. REORDENAR -----------------------------------------------------------

/// O bloco travou? Adianta o próximo que não trava. Custo zero de volume.
class ReorderStrategy implements AdaptationStrategy {
  @override
  LadderStep get step => LadderStep.reorder;

  @override
  Rung? apply(LadderContext ctx) {
    final blocking = ctx.offending;
    if (blocking == null) return null;
    final blocked = ctx.input.busy.blockedAt(ctx.input.elapsed);
    final free = ctx.input.session.pending
        .where((b) => b.id != blocking.id && !b.isBlockedBy(blocked))
        .toList();
    if (free.isEmpty) return null;

    final order = [
      ...free.map((b) => b.id),
      blocking.id,
    ];
    return (
      adaptation: Reorder(order),
      why: Rationale(RationaleCode.equipmentBusyDeferred, {
        'blockedBlock': blocking.id,
        'promoted': free.first.id,
      }),
    );
  }
}

// --- 2. ADIAR (voltar depois) ----------------------------------------------

/// Marca pra reavaliar. "Ocupado" expira — o aparelho pode liberar.
class DeferStrategy implements AdaptationStrategy {
  final Duration retryAfter;
  const DeferStrategy({this.retryAfter = const Duration(minutes: 6)});

  @override
  LadderStep get step => LadderStep.defer;

  @override
  Rung? apply(LadderContext ctx) {
    final b = ctx.offending;
    if (b == null) return null;
    final retriable = ctx.input.busy.retriableAt(ctx.input.elapsed);
    final slug = b.slots.where((s) => !s.isDone).map((s) => s.exerciseSlug).firstOrNull;
    if (slug == null || !retriable.contains(slug)) return null;
    return (
      adaptation: Defer(b.id, retryAfter),
      why: Rationale(RationaleCode.equipmentBusyDeferred, {
        'slug': slug,
        'retryAfterMinutes': retryAfter.inMinutes,
      }),
    );
  }
}

// --- 3. SUBSTITUIR ----------------------------------------------------------

/// Só chega aqui quando reordenar e adiar não resolveram — ou quando o
/// gatilho é do usuário (não sei fazer / quero trocar), que não espera.
class SubstituteStrategy implements AdaptationStrategy {
  final WorkoutDecisionEngine Function() engineRef;
  const SubstituteStrategy(this.engineRef);

  @override
  LadderStep get step => LadderStep.substitute;

  @override
  Rung? apply(LadderContext ctx) {
    final i = ctx.input;
    final (slotId, code) = switch (i.event) {
      DontKnowHow e => (e.slotId, RationaleCode.userDoesNotKnowExercise),
      WantToSwap e => (e.slotId, RationaleCode.userAvoidsExercise),
      EquipmentBusy e when i.busy.isPermanent(_slugOf(i, e.slotId) ?? '') =>
        (e.slotId, RationaleCode.equipmentBusyRepeatedSoSubstituted),
      _ => (ctx.offending?.slots.firstOrNull?.id, RationaleCode.equipmentMissingInThisGym),
    };
    if (slotId == null) return null;

    final slug = _slugOf(i, slotId);
    if (slug == null) return null;

    var candidates = engineRef().viableSubstitutes(slug, i);
    // "Não sei fazer" também rebaixa a dificuldade — não adianta trocar por
    // outro exercício avançado.
    if (i.event is DontKnowHow) {
      final src = i.catalog[slug];
      candidates = candidates
          .where((c) => c.exercise.level.index <= (src?.level.index ?? 2))
          .toList();
    }
    if (candidates.isEmpty) return null;

    final best = candidates.first;
    return (
      adaptation: Substitute(slotId, slug, best.exercise.slug, best.score),
      why: Rationale(code, {
        'from': slug,
        'to': best.exercise.slug,
        'compatibility': best.score.round(),
      }),
    );
  }

  String? _slugOf(EngineInput i, String slotId) =>
      i.session.allSlots.where((s) => s.id == slotId).firstOrNull?.exerciseSlug;
}

// --- 4. REDUZIR VOLUME ------------------------------------------------------

/// Falta tempo. Tira série do acessório antes de tirar do exercício âncora,
/// e nunca abaixo de uma série.
class ReduceVolumeStrategy implements AdaptationStrategy {
  final int minSets;
  const ReduceVolumeStrategy({this.minSets = 1});

  @override
  LadderStep get step => LadderStep.reduceVolume;

  @override
  Rung? apply(LadderContext ctx) {
    final over = _overrunSeconds(ctx);
    if (over <= 0) return null;

    final candidates = ctx.input.session.pending
        .expand((b) => b.slots)
        .where((s) => !s.isDone && s.remainingSets > minSets)
        .toList()
      ..sort((a, b) {
        final byPriority = b.priority.compareTo(a.priority); // acessório primeiro
        if (byPriority != 0) return byPriority;
        return b.remainingSets.compareTo(a.remainingSets);
      });
    if (candidates.isEmpty) return null;

    final victim = candidates.first;
    return (
      adaptation: ReduceVolume(victim.id, victim.plannedSets, victim.plannedSets - 1),
      why: Rationale(RationaleCode.timeShortReducedVolume, {
        'slot': victim.id,
        'slug': victim.exerciseSlug,
        'priority': victim.priority,
        'overrunSeconds': over,
      }),
    );
  }
}

// --- 5. SUPERSÉRIE ----------------------------------------------------------

/// Junta dois blocos que não competem entre si e elimina o descanso do meio.
/// Preserva o volume inteiro — por isso vem antes de remover.
class SupersetStrategy implements AdaptationStrategy {
  @override
  LadderStep get step => LadderStep.superset;

  @override
  Rung? apply(LadderContext ctx) {
    final over = _overrunSeconds(ctx);
    if (over <= 0) return null;

    final singles = ctx.input.session.pending.where((b) => !b.isSuperset).toList();
    for (var i = 0; i < singles.length; i++) {
      for (var j = i + 1; j < singles.length; j++) {
        final a = singles[i].slots.first, b = singles[j].slots.first;
        final ea = ctx.input.catalog[a.exerciseSlug], eb = ctx.input.catalog[b.exerciseSlug];
        if (ea == null || eb == null) continue;
        if (!_pairable(ea, eb)) continue;

        final saved = Duration(
          seconds: a.remainingSets * a.rest.nominal.inSeconds,
        );
        if (saved.inSeconds <= 0) continue;
        return (
          adaptation: MergeIntoSuperset([a.id, b.id], saved),
          why: Rationale(RationaleCode.timeShortMergedSuperset, {
            'slots': [a.id, b.id],
            'savedSeconds': saved.inSeconds,
          }),
        );
      }
    }
    return null;
  }

  /// Não parear coisas que disputam o mesmo músculo ou o mesmo padrão —
  /// a segunda sairia prejudicada pela fadiga da primeira.
  static bool _pairable(Exercise a, Exercise b) =>
      a.primary != b.primary &&
      a.pattern != b.pattern &&
      !a.secondary.contains(b.primary) &&
      !b.secondary.contains(a.primary);
}

// --- 6. REMOVER -------------------------------------------------------------

/// Último recurso. Nunca remove exercício de prioridade 1, e nunca remove
/// o último representante de um grupo que é foco da sessão.
class DropStrategy implements AdaptationStrategy {
  @override
  LadderStep get step => LadderStep.drop;

  @override
  Rung? apply(LadderContext ctx) {
    final over = _overrunSeconds(ctx);
    if (over <= 0) return null;

    final pending = ctx.input.session.pending.expand((b) => b.slots).where((s) => !s.isDone);
    final focus = ctx.input.session.focus;

    final coverage = <MuscleGroup, int>{};
    for (final s in pending) {
      final e = ctx.input.catalog[s.exerciseSlug];
      if (e != null) coverage.update(e.primary, (v) => v + 1, ifAbsent: () => 1);
    }

    final victims = pending.where((s) {
      if (s.priority <= 1) return false;
      final e = ctx.input.catalog[s.exerciseSlug];
      if (e == null) return true;
      // é o último desse grupo, e o grupo é foco da sessão? não sai.
      if (focus.contains(e.primary) && (coverage[e.primary] ?? 0) <= 1) return false;
      return true;
    }).toList()
      ..sort((a, b) => b.priority.compareTo(a.priority));

    if (victims.isEmpty) {
      return (
        adaptation: DropSlot(''),
        why: const Rationale(RationaleCode.noViableSubstituteLadderExhausted),
      );
    }
    final v = victims.first;
    return (
      adaptation: DropSlot(v.id),
      why: Rationale(RationaleCode.timeShortDroppedAccessory, {
        'slot': v.id,
        'slug': v.exerciseSlug,
        'priority': v.priority,
        'overrunSeconds': over,
      }),
    );
  }
}

// --- comum ------------------------------------------------------------------

/// Quantos segundos o treino restante estoura o tempo disponível.
int _overrunSeconds(LadderContext ctx) {
  final left = ctx.input.timeLeft;
  if (left == null) return 0;
  final need = ctx.duration.estimate(ctx.input).remaining;
  return need.inSeconds - left.inSeconds;
}

/// A escada padrão, na ordem que o BoraSet usa.
List<AdaptationStrategy> defaultLadder(WorkoutDecisionEngine Function() engine) => [
      ReorderStrategy(),
      const DeferStrategy(),
      SubstituteStrategy(engine),
      const ReduceVolumeStrategy(),
      SupersetStrategy(),
      DropStrategy(),
    ];
