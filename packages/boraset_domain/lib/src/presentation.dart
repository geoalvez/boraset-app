/// BoraSet — camada de apresentação do domínio.
///
/// Traduz decisões do motor em **diretivas de UI**: o que mostrar, com que
/// urgência, e com que aviso. Continua Dart puro — a tela só renderiza.
///
/// Por que isso não mora no widget: "sugerir +100% de carga é perigoso" é
/// regra de treino, não de layout. Se ficar no widget, não tem teste e some
/// no primeiro redesign.
library;

import 'catalog.dart';
import 'engine.dart';
import 'progression.dart';

// ---------------------------------------------------------------------------
// Progressão de carga
// ---------------------------------------------------------------------------

/// Quão insistente a UI deve ser com a sugestão de carga.
enum LoadCueTone {
  /// Salto normal. Mostra o número e segue.
  suggest,

  /// Salto grande para o exercício. Mostra, mas avisa que é um degrau alto.
  suggestWithCaution,

  /// O menor incremento disponível é grande demais para ser seguro sugerir
  /// como aumento de carga. Não sugere número — explica e oferece outra saída.
  withhold,
}

/// O que a tela deve mostrar sobre carga na próxima série.
class LoadCue {
  final LoadCueTone tone;

  /// Carga sugerida. `null` quando `tone == withhold`.
  final double? suggested;
  final double? current;
  final WeightUnit unit;

  /// Fração do aumento. 0.083 = +8,3%.
  final double? jump;

  /// Chave de i18n. O texto vem do pacote de idioma; nada de string aqui.
  final LoadCueMessage message;

  /// Quando `withhold`, o que fazer em vez de subir carga.
  final String? fallbackDimension; // 'reps' | 'tempo' | 'amplitude'

  const LoadCue({
    required this.tone,
    required this.message,
    this.suggested,
    this.current,
    required this.unit,
    this.jump,
    this.fallbackDimension,
  });

  /// Percentual arredondado, pronto para interpolar no texto.
  int? get jumpPercent => jump == null ? null : (jump! * 100).round();
}

enum LoadCueMessage {
  holdAndAddReps,
  increaseLoad,
  increaseLoadBigJump,
  incrementTooCoarse,
  progressByReps,
  progressByTime,
  notEnoughHistory,
}

/// Converte `ProgressionAdvice` em `LoadCue`.
///
/// O limiar não é único: um degrau de 5 kg é trivial num agachamento e
/// absurdo numa elevação lateral. Por isso a régua é percentual, e há um
/// teto acima do qual o app simplesmente não sugere.
class ProgressionPresenter {
  /// Acima disso, avisa.
  final double cautionAt;

  /// Acima disso, não sugere — o stack da máquina é grosso demais.
  final double withholdAt;

  const ProgressionPresenter({this.cautionAt = 0.10, this.withholdAt = 0.25});

  LoadCue present(ProgressionAdvice advice, {required WeightUnit unit}) {
    switch (advice) {
      case HoldAndAddReps(:final loadKg):
        return LoadCue(
          tone: LoadCueTone.suggest,
          message: LoadCueMessage.holdAndAddReps,
          suggested: loadKg,
          current: loadKg,
          unit: unit,
        );

      case IncreaseLoad(:final from, :final to, :final jumpPercent):
        if (jumpPercent > withholdAt) {
          // Elevação lateral na polia: 5 kg → 10 kg é +100%. Sugerir isso
          // é mandar a pessoa se machucar. Melhor dizer a verdade.
          return LoadCue(
            tone: LoadCueTone.withhold,
            message: LoadCueMessage.incrementTooCoarse,
            current: from,
            unit: unit,
            jump: jumpPercent,
            fallbackDimension: 'reps',
          );
        }
        return LoadCue(
          tone: jumpPercent > cautionAt
              ? LoadCueTone.suggestWithCaution
              : LoadCueTone.suggest,
          message: jumpPercent > cautionAt
              ? LoadCueMessage.increaseLoadBigJump
              : LoadCueMessage.increaseLoad,
          suggested: to,
          current: from,
          unit: unit,
          jump: jumpPercent,
        );

      case ProgressByOther(:final dimension):
        return LoadCue(
          tone: LoadCueTone.suggest,
          message: dimension == 'tempo'
              ? LoadCueMessage.progressByTime
              : LoadCueMessage.progressByReps,
          unit: unit,
          fallbackDimension: dimension,
        );

      case NoAdvice():
        return LoadCue(
          tone: LoadCueTone.suggest,
          message: LoadCueMessage.notEnoughHistory,
          unit: unit,
        );
    }
  }
}

// ---------------------------------------------------------------------------
// Estimativa de tempo
// ---------------------------------------------------------------------------

/// Como mostrar o tempo restante.
///
/// Resolve o impasse da sala: no dia 1 o número é ficção. Mostrar "restam 21
/// min" com precisão falsa destrói a confiança na primeira vez que erra.
/// Aqui o número aparece sempre — mas a **forma** carrega a incerteza, e o
/// toque abre a justificativa.
enum TimeDisplayMode {
  /// Sem histórico: mostra faixa ("20–30 min") e admite que está calibrando.
  range,

  /// Calibrando: mostra número com "aprox.".
  approximate,

  /// Personalizado: número seco.
  exact,
}

class TimeCue {
  final TimeDisplayMode mode;
  final Duration remaining;
  final Duration low, high;
  final EstimateConfidence confidence;

  /// Sempre true: o número é tocável e abre a justificativa do motor.
  /// Foi isso que fechou a discussão — número + explicação é honesto;
  /// número sozinho é aposta.
  final bool explainable;

  const TimeCue({
    required this.mode,
    required this.remaining,
    required this.low,
    required this.high,
    required this.confidence,
    this.explainable = true,
  });
}

class TimePresenter {
  const TimePresenter();

  TimeCue present(DurationEstimate e) {
    final mode = switch (e.confidence) {
      EstimateConfidence.coldStart => TimeDisplayMode.range,
      EstimateConfidence.calibrating => TimeDisplayMode.approximate,
      EstimateConfidence.personalized => TimeDisplayMode.exact,
    };
    return TimeCue(
      mode: mode,
      remaining: e.remaining,
      low: e.remaining - e.margin,
      high: e.remaining + e.margin,
      confidence: e.confidence,
    );
  }
}

// ---------------------------------------------------------------------------
// Ações da tela de treino
// ---------------------------------------------------------------------------

/// Os botões da tela, em ordem de peso visual.
///
/// A Sally tinha razão: cinco botões iguais viram cinco decisões. `primary`
/// é um só — CONCLUÍDA, que é ~90% dos toques. O resto fica atrás de
/// "algo deu errado".
enum WorkoutAction { completed, equipmentBusy, wantToSwap, dontKnowHow, skip }

extension WorkoutActionLayout on WorkoutAction {
  bool get isPrimary => this == WorkoutAction.completed;

  SessionEvent toEvent(String slotId, {SetRecord? record}) => switch (this) {
        WorkoutAction.completed => SetCompleted(slotId, record!),
        WorkoutAction.equipmentBusy => EquipmentBusy(slotId),
        WorkoutAction.wantToSwap => WantToSwap(slotId),
        WorkoutAction.dontKnowHow => DontKnowHow(slotId),
        WorkoutAction.skip => SkipExercise(slotId),
      };
}

/// Os três tipos de ajuda vivem na mesma superfície de UI.
/// Foi o achado da rodada do popup: exercício, técnica e justificativa do
/// motor são o mesmo gesto para o usuário.
enum HelpKind { exercise, technique, engineDecision }

class HelpRequest {
  final HelpKind kind;

  /// Para exercise/technique: o slug. Para engineDecision: null.
  final String? slug;

  /// Para engineDecision: os dados que a UI vai renderizar como frase.
  final List<Rationale>? rationale;

  const HelpRequest.exercise(String this.slug)
      : kind = HelpKind.exercise, rationale = null;
  const HelpRequest.technique(String this.slug)
      : kind = HelpKind.technique, rationale = null;
  const HelpRequest.decision(List<Rationale> this.rationale)
      : kind = HelpKind.engineDecision, slug = null;
}
