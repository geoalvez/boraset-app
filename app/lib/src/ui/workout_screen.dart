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
import 'widgets.dart';

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

  /// Ler o relógio é responsabilidade DA UI — o motor recebe o valor pronto e
  /// nunca chama DateTime.now(). É essa fronteira que mantém `decide()` puro.
  ///
  /// E ele não dispara rebuild: o tempo restante muda em minutos, não em
  /// segundos. Um Timer.periodic aqui reconstruiria a tela 60 vezes por
  /// minuto para não mudar nada.
  final DateTime _startedAt = DateTime.now();
  Duration get _elapsed => DateTime.now().difference(_startedAt);

  Duration? _budget;
  Duration? _restFrom;

  /// Cargas da última vez que cada exercício foi feito, por índice de série.
  Map<String, Map<int, double>> _previousLoads = const {};

  final String _sessionId = 'sess-${DateTime.now().millisecondsSinceEpoch}';

  /// Quando a série atual começou — vira `seconds` no banco e alimenta a
  /// estimativa personalizada. Sem isso o app nunca sai do modo "faixa".
  DateTime _setStartedAt = DateTime.now();

  Decision? _decision;

  @override
  void initState() {
    super.initState();
    _session = _sessionFor(widget.data, dayIndex: 0, week: 1);
    late WorkoutDecisionEngine e;
    e = WorkoutDecisionEngine(
      ladder: defaultLadder(() => e),
      duration: const HistoricalDurationModel(),
    );
    _engine = e;
    _recompute(const WhatNow());
    _restore();
  }

  /// Carrega configuração, perfil e cargas do banco, e abre a sessão.
  ///
  /// É aqui que o histórico volta para dentro do motor: `observedSetSeconds`
  /// tira a estimativa do modo "faixa", e `avoided` reaplica os "quero trocar"
  /// de sessões passadas sem o usuário precisar repetir.
  Future<void> _restore() async {
    final store = widget.store;
    if (store == null) return;
    final setup = await store.setup();
    final profile = await store.profile(level: setup.level);
    // Rotaciona o dia e avança a semana conforme o histórico cresce: a cada
    // volta completa da divisão, a semana avança e o volume acompanha a curva.
    final done = (await store.recentSessions(limit: 400)).length;
    final n = setup.split.days.length;
    final session = _sessionFor(widget.data,
        dayIndex: done % n, week: (done ~/ n) + 1,
        profile: profile, setup: setup);

    final loads = <String, Map<int, double>>{};
    for (final slug in session.allSlots.map((s) => s.exerciseSlug).toSet()) {
      final l = await store.lastLoadsFor(slug);
      if (l.isNotEmpty) loads[slug] = l;
    }
    if (!mounted) return;
    setState(() {
      _profile = profile;
      _previousLoads = loads;
      _session = session;
    });
    await store.startSession(_sessionId, session.name, budget: _budget);
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
    _recompute(
        action.toEvent(slot.id, record: SetRecord(index: slot.completed.length)));
  }

  // --- build ---------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final d = _decision;
    final slot = d?.next;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: slot == null
            ? _Finished(onClose: () => widget.store?.finishSession(_sessionId))
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  BsHeader(
                    _session.name,
                    action: _TimeBudgetButton(budget: _budget, onTap: _askBudget),
                  ),
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsetsDirectional.fromSTEB(20, 0, 20, 8),
                      children: [
                        _TimeCard(
                          cue: const TimePresenter().present(d!.estimate),
                          onTap: () =>
                              showDecisionHelp(context, widget.data, d.rationale),
                        ),
                        const SizedBox(height: 20),
                        _ExerciseCard(
                          data: widget.data,
                          slot: slot,
                          alternatives: d.alternatives,
                          previous: _previousLoads[slot.exerciseSlug],
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsetsDirectional.fromSTEB(20, 0, 20, 4),
                    child: Column(
                      children: [
                        if (_restFrom != null) ...[
                          _RestBar(
                            total: _restFrom!,
                            onDone: () => setState(() => _restFrom = null),
                          ),
                          const SizedBox(height: 12),
                        ],
                        BsButton('CONCLUÍDA', onPressed: () => _logSet(slot)),
                        BsQuiet('Algo deu errado',
                            onPressed: () => _showProblems(slot)),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Future<void> _askBudget() async {
    final minutes = await bsSheet<int>(
      context,
      SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(20, 10, 20, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Caption('Quanto tempo você tem?'),
              const SizedBox(height: 8),
              const Text(
                'O treino se reorganiza para caber. Os exercícios principais '
                'ficam; o que sai são acessórios.',
                style: TextStyle(color: kMuted, fontSize: 13.5, height: 1.45),
              ),
              const SizedBox(height: 18),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final m in [15, 20, 30, 45, 60])
                    BsChip(
                      label: '$m min',
                      selected: _budget?.inMinutes == m,
                      onTap: () => Navigator.pop(context, m),
                    ),
                  BsChip(
                    label: 'Sem limite',
                    selected: _budget == null,
                    onTap: () => Navigator.pop(context, 0),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (minutes == null) return;
    setState(() => _budget = minutes == 0 ? null : Duration(minutes: minutes));
    widget.store?.startSession(_sessionId, _session.name, budget: _budget);
    _recompute(TimeBudgetChanged(_budget ?? const Duration(hours: 2)));
  }

  Future<void> _logSet(ExerciseSlot slot) async {
    final result = await bsSheet<(double?, int?)>(
      context,
      _SetLogger(
        data: widget.data,
        slot: slot,
        previousLoad: _previousLoad(slot),
        exercise: widget.data.catalog[slot.exerciseSlug],
      ),
      tall: true,
    );
    if (result == null) return;
    _completeSet(slot, result.$1, result.$2);
  }

  /// A carga a pré-preencher: a desta série nesta sessão, ou a mesma série
  /// da última vez. Nunca "a carga do exercício" — Pirâmide não permite.
  double? _previousLoad(ExerciseSlot slot) {
    if (slot.completed.isNotEmpty) return slot.completed.last.loadKg;
    return _previousLoads[slot.exerciseSlug]?[slot.completed.length];
  }

  Future<void> _showProblems(ExerciseSlot slot) async {
    final action = await bsSheet<WorkoutAction>(
      context,
      SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsetsDirectional.fromSTEB(20, 10, 20, 12),
              child: Caption('O que aconteceu'),
            ),
            for (final a in WorkoutAction.values.where((a) => !a.isPrimary))
              BsRow(
                divider: a != WorkoutAction.skip,
                leading: Icon(
                  switch (a) {
                    WorkoutAction.equipmentBusy => Icons.hourglass_top_rounded,
                    WorkoutAction.wantToSwap => Icons.swap_horiz_rounded,
                    WorkoutAction.dontKnowHow => Icons.help_outline_rounded,
                    _ => Icons.skip_next_rounded,
                  },
                  size: 19,
                  color: kMuted,
                ),
                title: switch (a) {
                  WorkoutAction.equipmentBusy => 'Aparelho ocupado',
                  WorkoutAction.wantToSwap => 'Quero trocar',
                  WorkoutAction.dontKnowHow => 'Não sei fazer',
                  _ => 'Pular',
                },
                subtitle: switch (a) {
                  WorkoutAction.equipmentBusy =>
                    'Volto a sugerir daqui a alguns minutos',
                  WorkoutAction.wantToSwap => 'Não sugiro mais nas próximas vezes',
                  WorkoutAction.dontKnowHow => 'Troco por algo mais simples',
                  _ => 'Segue para o próximo',
                },
                onTap: () => Navigator.pop(context, a),
              ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
    if (action != null) _handle(action, slot);
  }
}

// --- pedaços da tela --------------------------------------------------------

class _TimeBudgetButton extends StatelessWidget {
  final Duration? budget;
  final VoidCallback onTap;
  const _TimeBudgetButton({required this.budget, required this.onTap});

  @override
  Widget build(BuildContext context) => BsChip(
        label: budget == null ? 'Sem limite' : '${budget!.inMinutes} min',
        icon: Icons.timer_outlined,
        selected: budget != null,
        onTap: onTap,
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
      TimeDisplayMode.range => '${m(cue.low)}–${m(cue.high)}',
      TimeDisplayMode.approximate => '~${m(cue.remaining)}',
      TimeDisplayMode.exact => '${m(cue.remaining)}',
    };
  }

  @override
  Widget build(BuildContext context) => BsCard(
        onTap: cue.explainable ? onTap : null,
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Caption('Tempo restante'),
                Spacer(),
                Text('por quê', style: TextStyle(color: kFaint, fontSize: 11.5)),
                SizedBox(width: 3),
                Icon(Icons.chevron_right_rounded, size: 15, color: kFaint),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(_value, style: Theme.of(context).textTheme.headlineLarge),
                const SizedBox(width: 6),
                const Padding(
                  padding: EdgeInsets.only(bottom: 6),
                  child: Text('min',
                      style: TextStyle(
                          color: kMuted,
                          fontSize: 15,
                          fontWeight: FontWeight.w600)),
                ),
              ],
            ),
            if (cue.confidence != EstimateConfidence.personalized) ...[
              const SizedBox(height: 8),
              Text(
                cue.confidence == EstimateConfidence.coldStart
                    ? 'Ainda estou aprendendo o seu ritmo — por isso a faixa.'
                    : 'Estimativa em calibração.',
                style: const TextStyle(color: kFaint, fontSize: 12.5, height: 1.4),
              ),
            ],
          ],
        ),
      );
}

class _ExerciseCard extends StatelessWidget {
  final BorasetData data;
  final ExerciseSlot slot;
  final List<Alternative> alternatives;
  final Map<int, double>? previous;

  const _ExerciseCard({
    required this.data,
    required this.slot,
    required this.alternatives,
    this.previous,
  });

  String get _reps => switch (slot.reps) {
        RepRange(:final min, :final max) => '$min–$max',
        RepPerSet(:final reps) => reps.map((r) => r?.toString() ?? 'F').join('/'),
        RepToFailure() => 'falha',
        RepOpen() => 'livre',
        RepByDuration(:final duration) => '${duration.inMinutes} min',
      };

  @override
  Widget build(BuildContext context) {
    final done = slot.completed.length;
    final unit = data.unit == WeightUnit.lb ? 'lb' : 'kg';
    final last = previous?[done];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Caption('Agora'),
        const SizedBox(height: 8),
        Text(data.nameOf(slot.exerciseSlug),
            style: Theme.of(context).textTheme.displaySmall),
        const SizedBox(height: 18),

        Row(
          children: [
            _Metric(
                label: 'Série',
                value: '${done + 1}',
                hint: 'de ${slot.plannedSets}'),
            const SizedBox(width: 10),
            _Metric(label: 'Repetições', value: _reps),
            const SizedBox(width: 10),
            _Metric(
              label: 'Última carga',
              value: last == null ? '—' : _fmt(last),
              hint: last == null ? null : unit,
            ),
          ],
        ),

        // Progresso das séries: as barras cheias contam o que já foi.
        const SizedBox(height: 16),
        Row(
          children: [
            for (var i = 0; i < slot.plannedSets; i++)
              Container(
                width: 24,
                height: 4,
                margin: const EdgeInsetsDirectional.only(end: 5),
                decoration: BoxDecoration(
                  color: i < done ? kGo : kSurfaceHi,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            const Spacer(),
            Text('${slot.rest.nominal.inSeconds}s de descanso',
                style: const TextStyle(color: kFaint, fontSize: 12)),
          ],
        ),

        // Técnicas: cada chip abre o popup. É o que aparece 2.684 vezes.
        if (slot.techniqueSlugs.isNotEmpty) ...[
          const SizedBox(height: 22),
          const Caption('Técnica'),
          const SizedBox(height: 9),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final s in slot.techniqueSlugs)
                if (data.techniques[s] != null)
                  BsChip(
                    key: ValueKey('tech-$s'),
                    label: data.techniques[s]!.name,
                    icon: data.techniques[s]!.hasCaution
                        ? Icons.warning_amber_rounded
                        : Icons.info_outline_rounded,
                    tone: data.techniques[s]!.hasCaution ? kWarn : kGo,
                    selected: true,
                    onTap: () => showTechniqueHelp(context, data, s),
                  ),
            ],
          ),
        ],

        if (alternatives.isNotEmpty) ...[
          const SizedBox(height: 22),
          const Caption('Se precisar trocar'),
          const SizedBox(height: 9),
          BsCard(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            child: Column(
              children: [
                for (final a in alternatives.take(3))
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 9),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(data.nameOf(a.slug),
                              style: const TextStyle(
                                  fontSize: 13.5, color: kMuted)),
                        ),
                        Text('${a.compatibility.round()}%',
                            style: const TextStyle(
                                color: kFaint,
                                fontSize: 12.5,
                                fontFeatures: kTabular)),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 8),
      ],
    );
  }

  static String _fmt(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
}

class _Metric extends StatelessWidget {
  final String label, value;
  final String? hint;
  const _Metric({required this.label, required this.value, this.hint});

  @override
  Widget build(BuildContext context) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          decoration: BoxDecoration(
            color: kSurface,
            borderRadius: BorderRadius.circular(kRadiusSm),
            border: Border.all(color: kLine),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Caption(label),
              const SizedBox(height: 6),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Flexible(
                    child: Text(value,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.4,
                          fontFeatures: kTabular,
                        )),
                  ),
                  if (hint != null) ...[
                    const SizedBox(width: 3),
                    Text(hint!,
                        style: const TextStyle(color: kFaint, fontSize: 11.5)),
                  ],
                ],
              ),
            ],
          ),
        ),
      );
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
    final tone = almost ? kWarn : kGo;
    final progress = 1 - (left.inSeconds / widget.total.inSeconds);

    return Container(
      padding: const EdgeInsets.fromLTRB(15, 12, 15, 12),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: .09),
        borderRadius: BorderRadius.circular(kRadiusSm),
        border: Border.all(color: tone.withValues(alpha: .28)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(
                  almost
                      ? Icons.notifications_active_rounded
                      : Icons.pause_rounded,
                  size: 17,
                  color: tone),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  almost ? 'Prepare-se para a próxima série' : 'Descanso',
                  style: TextStyle(
                      color: tone, fontSize: 14, fontWeight: FontWeight.w600),
                ),
              ),
              Text(
                '${left.inMinutes.toString().padLeft(2, '0')}:'
                '${(left.inSeconds % 60).toString().padLeft(2, '0')}',
                style: TextStyle(
                  color: tone,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  fontFeatures: kTabular,
                ),
              ),
            ],
          ),
          const SizedBox(height: 9),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: progress.clamp(0, 1),
              minHeight: 3,
              backgroundColor: tone.withValues(alpha: .16),
              valueColor: AlwaysStoppedAnimation(tone),
            ),
          ),
        ],
      ),
    );
  }
}

class _Finished extends StatefulWidget {
  final VoidCallback onClose;
  const _Finished({required this.onClose});

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
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 62,
              height: 62,
              decoration: BoxDecoration(
                color: kGo.withValues(alpha: .12),
                shape: BoxShape.circle,
                border: Border.all(color: kGo.withValues(alpha: .4)),
              ),
              child: const Icon(Icons.check_rounded, color: kGo, size: 30),
            ),
            const SizedBox(height: 20),
            Text('Treino concluído',
                style: Theme.of(context).textTheme.displaySmall),
            const SizedBox(height: 8),
            const Text('As séries foram registradas.',
                style: TextStyle(color: kMuted, fontSize: 14)),
          ],
        ),
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
    return SingleChildScrollView(
      child: Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 10,
          bottom: MediaQuery.viewInsetsOf(context).bottom + 26,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Caption('Série ${widget.slot.completed.length + 1} de '
                '${widget.slot.plannedSets}'),
            const SizedBox(height: 8),
            Text(widget.data.nameOf(widget.slot.exerciseSlug),
                style:
                    Theme.of(context).textTheme.displaySmall?.copyWith(fontSize: 21)),
            const SizedBox(height: 18),
            if (cue != null) ...[
              _LoadCueCard(cue: cue, unit: unit),
              const SizedBox(height: 16),
            ],
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _load,
                    autofocus: true,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        fontFeatures: kTabular),
                    decoration: InputDecoration(labelText: 'Carga ($unit)'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _reps,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        fontFeatures: kTabular),
                    decoration: const InputDecoration(labelText: 'Repetições'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            BsButton('Registrar série',
                onPressed: () => Navigator.pop(context, (
                      double.tryParse(_load.text.replaceAll(',', '.')),
                      int.tryParse(_reps.text),
                    ))),
          ],
        ),
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
    return BsBanner(text: message, icon: icon, tone: color);
  }

  static String _fmt(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
}

// --- o treino do dia --------------------------------------------------------

/// Monta a sessão a partir do catálogo, na hora.
///
/// Nada de ficha embarcada: a divisão, o volume e as faixas vêm do
/// `ProgramBuilder`, e a escolha de cada exercício sai do catálogo do próprio
/// usuário — filtrada pelo equipamento da academia e pelo que ele evita.
WorkoutSession _sessionFor(
  BorasetData data, {
  required int dayIndex,
  required int week,
  UserProfile profile = const UserProfile(),
  ProgramSetup? setup,
}) {
  final req = ProgramRequest(
    split: setup?.split ?? abc3,
    goal: setup?.goal ?? Goal.hipertrofia,
    level: setup?.level ?? profile.level,
    availableEquipment: setup?.equipment ?? const {},
    avoided: profile.avoided,
    week: week,
  );
  return ProgramBuilder(data.catalog).buildDay(req, dayIndex);
}
