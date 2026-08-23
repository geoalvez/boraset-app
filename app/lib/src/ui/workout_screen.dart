/// A tela de treino.
///
/// Um botão domina: CONCLUÍDA. Os outros quatro gatilhos vivem atrás de
/// "algo deu errado" — são ~10% dos toques e não merecem o mesmo peso.
///
/// Nada aqui decide nada. Toda decisão vem do `WorkoutDecisionEngine` e todo
/// julgamento de "isso é perigoso" vem do `ProgressionPresenter`. A tela lê
/// diretivas e desenha.
library;

import 'dart:async';

import 'package:boraset_domain/boraset_domain.dart';
import 'package:flutter/material.dart';

import '../data/repository.dart';
import '../data/store.dart';
import 'help_sheet.dart';
import 'theme.dart';

class WorkoutScreen extends StatefulWidget {
  final BorasetData data;
  final WorkoutStore? store;
  const WorkoutScreen({super.key, required this.data, this.store});

  @override
  State<WorkoutScreen> createState() => _WorkoutScreenState();
}

class _WorkoutScreenState extends State<WorkoutScreen> {
  late WorkoutSession _session;
  late WorkoutDecisionEngine _engine;
  BusyRegistry _busy = BusyRegistry();
  UserProfile _profile = const UserProfile();

  /// Relógio da sessão. Ler o relógio é responsabilidade DA UI — o motor
  /// recebe o valor pronto e nunca chama DateTime.now(). É essa fronteira
  /// que mantém `decide()` puro e testável.
  ///
  /// E ele não dispara rebuild: o tempo restante muda em minutos, não em
  /// segundos. Um Timer.periodic aqui reconstruiria a tela inteira 60 vezes
  /// por minuto para mudar nada.
  final DateTime _startedAt = DateTime.now();
  Duration get _elapsed => DateTime.now().difference(_startedAt);

  Duration? _budget;
  Duration? _restFrom;

  /// Cargas da última vez que cada exercício foi feito, por índice de série.
  Map<String, Map<int, double>> _previousLoads = const {};

  final String _sessionId =
      'sess-${DateTime.now().millisecondsSinceEpoch}';

  /// Quando a série atual começou — vira `seconds` no banco e alimenta a
  /// estimativa personalizada. Sem isso o app nunca sai do modo "faixa".
  DateTime _setStartedAt = DateTime.now();

  Decision? _decision;

  @override
  void initState() {
    super.initState();
    _session = _demoSession(widget.data);
    late WorkoutDecisionEngine e;
    e = WorkoutDecisionEngine(
      ladder: defaultLadder(() => e),
      duration: const HistoricalDurationModel(),
    );
    _engine = e;
    _recompute(const WhatNow());
    _restore();
  }

  /// Carrega perfil e cargas do banco, e abre a sessão.
  ///
  /// É aqui que o histórico volta para dentro do motor: `observedSetSeconds`
  /// tira a estimativa do modo "faixa", e `avoided` reaplica os "quero trocar"
  /// de sessões passadas sem o usuário precisar repetir.
  Future<void> _restore() async {
    final store = widget.store;
    if (store == null) return;
    await store.startSession(_sessionId, _session.name, budget: _budget);
    final profile = await store.profile();
    final loads = <String, Map<int, double>>{};
    for (final slug in _session.allSlots.map((s) => s.exerciseSlug).toSet()) {
      final l = await store.lastLoadsFor(slug);
      if (l.isNotEmpty) loads[slug] = l;
    }
    if (!mounted) return;
    setState(() {
      _profile = profile;
      _previousLoads = loads;
    });
    _recompute(const WhatNow());
  }

  void _recompute(SessionEvent event) {
    setState(() {
      _decision = _engine.decide(EngineInput(
        session: _session,
        catalog: widget.data.catalog,
        event: event,
        busy: _busy,
        profile: _profile,
        elapsed: _elapsed,
        timeBudget: _budget,
      ));
    });
  }

  // --- ações ---------------------------------------------------------------

  void _completeSet(ExerciseSlot slot, double? load, int? reps) {
    final seconds = DateTime.now().difference(_setStartedAt).inSeconds;
    final index = slot.completed.length;
    final record = SetRecord(
      index: index,
      loadKg: load,
      reps: reps,
      elapsed: Duration(seconds: seconds),
    );
    final updated = slot.copyWith(completed: [...slot.completed, record]);
    _replaceSlot(slot.id, updated);
    _startRest(updated.rest.nominal);
    _setStartedAt = DateTime.now();
    _recompute(SetCompleted(slot.id, record));

    widget.store?.logSet(LoggedSet(
      sessionId: _sessionId,
      slotId: slot.id,
      exerciseSlug: slot.exerciseSlug,
      setIndex: index,
      loadKg: load,
      reps: reps,
      // Descarta tempos absurdos: o app ficou em segundo plano, ou a pessoa
      // parou para conversar. Uma série de 11 minutos envenena a média.
      seconds: seconds > 0 && seconds < 600 ? seconds : null,
    ));
  }

  void _replaceSlot(String id, ExerciseSlot next) {
    _session = WorkoutSession(
      id: _session.id,
      name: _session.name,
      focus: _session.focus,
      blocks: [
        for (final b in _session.blocks)
          SessionBlock(
            id: b.id,
            origin: b.origin,
            slots: [for (final s in b.slots) s.id == id ? next : s],
          ),
      ],
    );
  }

  void _startRest(Duration d) {
    // No-Stop e bi-set emendam direto: descanso zero não abre cronômetro.
    if (d.inSeconds == 0) return;
    setState(() => _restFrom = d);
  }

  void _handle(WorkoutAction action, ExerciseSlot slot) {
    switch (action) {
      case WorkoutAction.equipmentBusy:
        _busy = _busy.markBusy(slot.exerciseSlug, _elapsed);
      case WorkoutAction.wantToSwap:
        _profile = UserProfile(
          avoided: {..._profile.avoided, slot.exerciseSlug},
          preferred: _profile.preferred,
          level: _profile.level,
          observedSetSeconds: _profile.observedSetSeconds,
          observedTransitionSeconds: _profile.observedTransitionSeconds,
        );
        widget.store?.avoid(slot.exerciseSlug); // vale para as próximas sessões
      default:
        break;
    }
    _recompute(action.toEvent(slot.id,
        record: SetRecord(index: slot.completed.length)));
  }

  // --- build ---------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final d = _decision;
    final slot = d?.next;
    final text = Theme.of(context).textTheme;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(20, 8, 20, 16),
          child: slot == null
              ? _Finished(
                  onClose: () => widget.store?.finishSession(_sessionId),
                  style: text.displaySmall)
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _Header(session: _session, onBudget: _askBudget),
                    const SizedBox(height: 14),
                    _TimeCard(
                      cue: const TimePresenter().present(d!.estimate),
                      onTap: () => showDecisionHelp(context, widget.data, d.rationale),
                    ),
                    const SizedBox(height: 18),
                    Expanded(
                      child: SingleChildScrollView(
                        child: _ExerciseCard(
                          data: widget.data,
                          slot: slot,
                          alternatives: d.alternatives,
                        ),
                      ),
                    ),
                    if (_restFrom != null)
                      _RestBar(
                        total: _restFrom!,
                        onDone: () => setState(() => _restFrom = null),
                      ),
                    const SizedBox(height: 10),
                    _Actions(
                      onDone: () => _logSet(slot),
                      onProblem: () => _showProblems(slot),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  Future<void> _askBudget() async {
    final minutes = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: kSurface,
      showDragHandle: true,
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Caption('Quanto tempo você tem?'),
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final m in [15, 20, 30, 45, 60])
                  ActionChip(
                    label: Text('$m min'),
                    onPressed: () => Navigator.pop(context, m),
                  ),
                ActionChip(
                  label: const Text('Treino normal'),
                  onPressed: () => Navigator.pop(context, 0),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    if (minutes == null) return;
    setState(() => _budget = minutes == 0 ? null : Duration(minutes: minutes));
    widget.store?.startSession(_sessionId, _session.name, budget: _budget);
    _recompute(TimeBudgetChanged(_budget ?? const Duration(hours: 2)));
  }

  Future<void> _logSet(ExerciseSlot slot) async {
    final prev = _previousLoad(slot);
    final result = await showModalBottomSheet<(double?, int?)>(
      context: context,
      backgroundColor: kSurface,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _SetLogger(
        data: widget.data,
        slot: slot,
        previousLoad: prev,
        exercise: widget.data.catalog[slot.exerciseSlug],
      ),
    );
    if (result == null) return;
    _completeSet(slot, result.$1, result.$2);
  }

  /// A carga a pré-preencher: a desta série nesta sessão, ou a mesma série
  /// da última vez. Nunca "a carga do exercício" — Pirâmide não permite.
  double? _previousLoad(ExerciseSlot slot) {
    if (slot.completed.isNotEmpty) return slot.completed.last.loadKg;
    return _previousLoads[slot.exerciseSlug]?[0];
  }

  Future<void> _showProblems(ExerciseSlot slot) async {
    final action = await showModalBottomSheet<WorkoutAction>(
      context: context,
      backgroundColor: kSurface,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final a in WorkoutAction.values.where((a) => !a.isPrimary))
              ListTile(
                leading: Icon(switch (a) {
                  WorkoutAction.equipmentBusy => Icons.hourglass_top_rounded,
                  WorkoutAction.wantToSwap => Icons.swap_horiz_rounded,
                  WorkoutAction.dontKnowHow => Icons.help_outline_rounded,
                  _ => Icons.skip_next_rounded,
                }),
                title: Text(switch (a) {
                  WorkoutAction.equipmentBusy => 'Aparelho ocupado',
                  WorkoutAction.wantToSwap => 'Quero trocar',
                  WorkoutAction.dontKnowHow => 'Não sei fazer',
                  _ => 'Pular',
                }),
                onTap: () => Navigator.pop(context, a),
              ),
          ],
        ),
      ),
    );
    if (action != null) _handle(action, slot);
  }
}

// --- pedaços da tela --------------------------------------------------------

class _Header extends StatelessWidget {
  final WorkoutSession session;
  final VoidCallback onBudget;
  const _Header({required this.session, required this.onBudget});

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Expanded(child: Caption(session.name)),
          IconButton(
            onPressed: onBudget,
            icon: const Icon(Icons.timer_outlined),
            tooltip: 'Só tenho X minutos',
          ),
        ],
      );
}

/// O tempo restante. A forma carrega a incerteza — e o toque abre o porquê.
class _TimeCard extends StatelessWidget {
  final TimeCue cue;
  final VoidCallback onTap;
  const _TimeCard({required this.cue, required this.onTap});

  String get _value {
    int m(Duration d) => d.inMinutes;
    return switch (cue.mode) {
      TimeDisplayMode.range => '${m(cue.low)}–${m(cue.high)} min',
      TimeDisplayMode.approximate => '~${m(cue.remaining)} min',
      TimeDisplayMode.exact => '${m(cue.remaining)} min',
    };
  }

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: cue.explainable ? onTap : null,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: kSurface,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Caption('Tempo restante'),
                  const Spacer(),
                  if (cue.confidence != EstimateConfidence.personalized)
                    const Icon(Icons.info_outline_rounded, size: 15, color: kMuted),
                ],
              ),
              const SizedBox(height: 4),
              Text(_value, style: Theme.of(context).textTheme.headlineLarge),
              if (cue.confidence == EstimateConfidence.coldStart)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'Ainda estou aprendendo o seu ritmo. Toque para ver como calculei.',
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(fontSize: 13, color: kMuted),
                  ),
                ),
            ],
          ),
        ),
      );
}

class _ExerciseCard extends StatelessWidget {
  final BorasetData data;
  final ExerciseSlot slot;
  final List<Alternative> alternatives;
  const _ExerciseCard({
    required this.data,
    required this.slot,
    required this.alternatives,
  });

  String get _reps => switch (slot.reps) {
        RepRange(:final min, :final max) => '$min–$max repetições',
        RepPerSet(:final reps) => reps.map((r) => r?.toString() ?? 'Falha').join(' / '),
        RepToFailure() => 'Até a falha',
        RepOpen() => 'Sem repetições definidas',
        RepByDuration(:final duration) => '${duration.inMinutes} min',
      };

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final done = slot.completed.length;
    final prev = slot.completed.isEmpty ? null : slot.completed.last.loadKg;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Caption('Próximo exercício'),
        const SizedBox(height: 6),
        Text(data.nameOf(slot.exerciseSlug), style: text.displaySmall),
        const SizedBox(height: 14),
        Row(
          children: [
            _Stat(label: 'Série', value: '${done + 1}/${slot.plannedSets}'),
            const SizedBox(width: 12),
            _Stat(label: 'Alvo', value: _reps, wide: true),
          ],
        ),
        if (prev != null) ...[
          const SizedBox(height: 12),
          _Stat(
            label: 'Carga da série anterior',
            value: '${_fmt(prev)} ${data.unit == WeightUnit.lb ? "lb" : "kg"}',
          ),
        ],

        // Técnicas: cada chip abre o popup. É o que aparece 2.684 vezes.
        if (slot.techniqueSlugs.isNotEmpty) ...[
          const SizedBox(height: 16),
          const Caption('Técnica'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final s in slot.techniqueSlugs)
                if (data.techniques[s] != null)
                  ActionChip(
                    avatar: data.techniques[s]!.hasCaution
                        ? const Icon(Icons.warning_amber_rounded, size: 16, color: kWarn)
                        : const Icon(Icons.info_outline_rounded, size: 16),
                    label: Text(data.techniques[s]!.name),
                    onPressed: () => showTechniqueHelp(context, data, s),
                  ),
            ],
          ),
        ],

        if (alternatives.isNotEmpty) ...[
          const SizedBox(height: 18),
          const Caption('Se precisar trocar'),
          const SizedBox(height: 6),
          for (final a in alternatives.take(3))
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Text(
                '${data.nameOf(a.slug)}  ·  ${a.compatibility.round()}%',
                style: text.bodyMedium?.copyWith(color: kMuted, fontSize: 14),
              ),
            ),
        ],
      ],
    );
  }

  static String _fmt(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
}

class _Stat extends StatelessWidget {
  final String label, value;
  final bool wide;
  const _Stat({required this.label, required this.value, this.wide = false});

  @override
  Widget build(BuildContext context) {
    final box = Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: kSurfaceHi,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Caption(label),
          const SizedBox(height: 3),
          Text(value, style: Theme.of(context).textTheme.titleMedium),
        ],
      ),
    );
    return wide ? Expanded(child: box) : box;
  }
}

/// O cronômetro de descanso é o ÚNICO widget que tica.
///
/// Ele existe só enquanto há descanso, e quando termina se apaga sozinho —
/// então a tela volta a ficar completamente estática entre os toques.
class _RestBar extends StatefulWidget {
  final Duration total;
  final VoidCallback onDone;
  const _RestBar({required this.total, required this.onDone});

  @override
  State<_RestBar> createState() => _RestBarState();
}

class _RestBarState extends State<_RestBar> {
  late Duration _left = widget.total;
  Timer? _t;

  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(const Duration(seconds: 1), (t) {
      final next = _left - const Duration(seconds: 1);
      if (next.inSeconds <= 0) {
        t.cancel();
        widget.onDone();
      } else {
        setState(() => _left = next);
      }
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final left = _left;
    final almost = left.inSeconds <= 10;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: (almost ? kWarn : kGo).withValues(alpha: .14),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(almost ? Icons.notifications_active_rounded : Icons.pause_rounded,
              size: 18, color: almost ? kWarn : kGo),
          const SizedBox(width: 10),
          Text(
            almost
                ? 'Prepare-se para a próxima série'
                : 'Descanso  ${left.inMinutes.toString().padLeft(2, '0')}:'
                    '${(left.inSeconds % 60).toString().padLeft(2, '0')}',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(color: almost ? kWarn : kGo),
          ),
        ],
      ),
    );
  }
}

/// Um botão grande e um discreto. Não cinco iguais.
class _Actions extends StatelessWidget {
  final VoidCallback onDone, onProblem;
  const _Actions({required this.onDone, required this.onProblem});

  @override
  Widget build(BuildContext context) => Column(
        children: [
          SizedBox(
            width: double.infinity,
            height: 62,
            child: FilledButton(
              onPressed: onDone,
              style: FilledButton.styleFrom(
                backgroundColor: kGo,
                foregroundColor: kInk,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: const Text('CONCLUÍDA',
                  style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, letterSpacing: .6)),
            ),
          ),
          TextButton(
            onPressed: onProblem,
            child: const Text('Algo deu errado', style: TextStyle(color: kMuted)),
          ),
        ],
      );
}

/// Registro da série + a sugestão de carga, com o tom que o presenter mandou.
class _SetLogger extends StatefulWidget {
  final BorasetData data;
  final ExerciseSlot slot;
  final Exercise? exercise;
  final double? previousLoad;
  const _SetLogger({
    required this.data,
    required this.slot,
    required this.exercise,
    this.previousLoad,
  });

  @override
  State<_SetLogger> createState() => _SetLoggerState();
}

class _SetLoggerState extends State<_SetLogger> {
  late final _load = TextEditingController(
      text: widget.previousLoad == null ? '' : _fmt(widget.previousLoad!));
  final _reps = TextEditingController();

  LoadCue? get _cue {
    final ex = widget.exercise;
    if (ex == null || widget.slot.completed.isEmpty) return null;
    final advice = const DoubleProgression().advise(
      exercise: ex,
      slot: widget.slot,
      lastSession: widget.slot.completed,
      plates: PlateMath(widget.data.plates),
    );
    return const ProgressionPresenter().present(advice, unit: widget.data.unit);
  }

  @override
  Widget build(BuildContext context) {
    final cue = _cue;
    final unit = widget.data.unit == WeightUnit.lb ? 'lb' : 'kg';
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 4,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (cue != null) _LoadCueCard(cue: cue, unit: unit),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _load,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(labelText: 'Carga ($unit)'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _reps,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Repetições'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: FilledButton(
              onPressed: () => Navigator.pop(context, (
                double.tryParse(_load.text.replaceAll(',', '.')),
                int.tryParse(_reps.text),
              )),
              child: const Text('Registrar série'),
            ),
          ),
        ],
      ),
    );
  }

  static String _fmt(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
}

/// Aqui o `jumpPercent` finalmente aparece para o usuário.
class _LoadCueCard extends StatelessWidget {
  final LoadCue cue;
  final String unit;
  const _LoadCueCard({required this.cue, required this.unit});

  (Color, IconData, String) get _look => switch (cue.tone) {
        LoadCueTone.suggest => (kGo, Icons.trending_up_rounded, _suggestText),
        LoadCueTone.suggestWithCaution => (
            kWarn,
            Icons.warning_amber_rounded,
            'Suba para ${_fmt(cue.suggested!)} $unit — mas é um degrau de '
                '${cue.jumpPercent}%. Se travar, fique onde está.'
          ),
        LoadCueTone.withhold => (
            kStop,
            Icons.block_rounded,
            'O menor aumento disponível aqui é de ${cue.jumpPercent}%. É muito. '
                'Fique em ${_fmt(cue.current!)} $unit e busque mais repetições.'
          ),
      };

  String get _suggestText => switch (cue.message) {
        LoadCueMessage.holdAndAddReps =>
          'Mantenha ${_fmt(cue.suggested!)} $unit e tente mais uma repetição.',
        LoadCueMessage.increaseLoad =>
          'Você fechou o topo da faixa. Suba para ${_fmt(cue.suggested!)} $unit.',
        LoadCueMessage.progressByReps =>
          'Aqui a progressão é por repetição, não por carga.',
        LoadCueMessage.progressByTime => 'Aqui a progressão é por tempo.',
        LoadCueMessage.notEnoughHistory =>
          'Primeira vez neste exercício. Registre e eu aprendo com você.',
        _ => '',
      };

  @override
  Widget build(BuildContext context) {
    final (color, icon, message) = _look;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: .4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(message,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: color, fontSize: 14.5)),
          ),
        ],
      ),
    );
  }

  static String _fmt(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
}

class _Finished extends StatefulWidget {
  final VoidCallback onClose;
  final TextStyle? style;
  const _Finished({required this.onClose, this.style});

  @override
  State<_Finished> createState() => _FinishedState();
}

class _FinishedState extends State<_Finished> {
  @override
  void initState() {
    super.initState();
    widget.onClose(); // carimba o fim da sessão no banco, uma vez só
  }

  @override
  Widget build(BuildContext context) =>
      Center(child: Text('Treino concluído', style: widget.style));
}

// --- sessão de demonstração -------------------------------------------------
// Sem persistência ainda: monta um TREINO A a partir do catálogo real.

WorkoutSession _demoSession(BorasetData data) {
  ExerciseSlot slot(String id, String slug, int sets, int priority, List<String> tech,
          {int rest = 60}) =>
      ExerciseSlot(
        id: id,
        exerciseSlug: slug,
        plannedSets: sets,
        reps: const RepRange(8, 12),
        rest: RestFixed(Duration(seconds: rest)),
        techniqueSlugs: tech,
        priority: priority,
      );

  return WorkoutSession(
    id: 'A',
    name: 'Treino A — Peito e Tríceps',
    focus: const {MuscleGroup.peito, MuscleGroup.triceps},
    blocks: [
      SessionBlock(id: 'b1', slots: [slot('s1', 'supino-reto', 3, 1, ['piramide-crescente'])]),
      SessionBlock(id: 'b2', slots: [slot('s2', 'halter-press-inclinado', 3, 2, ['contracao-de-pico'])]),
      SessionBlock(id: 'b3', slots: [slot('s3', 'crossover', 3, 3, ['no-stop'], rest: 0)]),
      SessionBlock(id: 'b4', slots: [slot('s4', 'triceps-pulley', 3, 4, ['drop-set'])]),
      SessionBlock(id: 'b5', slots: [slot('s5', 'triceps-testa', 2, 5, ['1-rest'])]),
    ],
  );
}
