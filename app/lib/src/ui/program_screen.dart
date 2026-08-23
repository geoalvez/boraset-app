/// Programa — onde o usuário diz o que quer, e vê o que vai receber.
///
/// A tela não pergunta tudo de uma vez. Divisão, objetivo e nível já vêm com
/// padrão razoável; o equipamento começa vazio, que significa "assume que a
/// academia tem tudo". Pedir inventário de ferro antes do primeiro treino
/// afugenta quem só queria treinar.
///
/// A prévia embaixo não é enfeite: é o que separa "escolhi Upper/Lower" de
/// "vi o que Upper/Lower vai me dar na quarta-feira".
library;

import 'package:boraset_domain/boraset_domain.dart';
import 'package:flutter/material.dart';

import '../data/repository.dart';
import '../data/store.dart';
import 'help_sheet.dart';
import 'theme.dart';
import 'widgets.dart';

class ProgramScreen extends StatefulWidget {
  final BorasetData data;
  final WorkoutStore store;

  /// Chamado quando a configuração muda, para a tela de treino se refazer.
  final VoidCallback onChanged;

  const ProgramScreen({
    super.key,
    required this.data,
    required this.store,
    required this.onChanged,
  });

  @override
  State<ProgramScreen> createState() => _ProgramScreenState();
}

class _ProgramScreenState extends State<ProgramScreen> {
  ProgramSetup? _setup;
  int _previewDay = 0;

  @override
  void initState() {
    super.initState();
    widget.store.setup().then((s) {
      if (mounted) setState(() => _setup = s);
    });
  }

  Future<void> _save(ProgramSetup next) async {
    setState(() {
      _setup = next;
      _previewDay = _previewDay % next.split.days.length;
    });
    await widget.store.saveSetup(
      splitId: next.splitId,
      goal: next.goal,
      level: next.level,
      equipment: next.equipment,
    );
    widget.onChanged();
  }

  ProgramSetup _with(
    ProgramSetup s, {
    String? splitId,
    Goal? goal,
    Level? level,
    Set<Equipment>? equipment,
  }) =>
      ProgramSetup(
        splitId: splitId ?? s.splitId,
        goal: goal ?? s.goal,
        level: level ?? s.level,
        equipment: equipment ?? s.equipment,
        configured: true,
      );

  @override
  Widget build(BuildContext context) {
    final s = _setup;
    if (s == null) {
      return const Scaffold(
        body: Center(
          child: SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2)),
        ),
      );
    }
    final available = splitsFor(s.level);
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            BsHeader(
              'Programa',
              subtitle: s.configured
                  ? null
                  : 'Ainda no padrão. Ajuste abaixo — a prévia acompanha.',
            ),
            _Section(
              label: 'Nível',
              child: BsSegmented<Level>(
                value: s.level,
                options: const {
                  Level.iniciante: 'Iniciante',
                  Level.intermediario: 'Intermediário',
                  Level.avancado: 'Avançado',
                },
                onChanged: (v) {
                  // Baixar o nível pode tirar a divisão escolhida do cardápio.
                  final ok = splitsFor(v);
                  _save(_with(s,
                      level: v,
                      splitId: ok.any((x) => x.id == s.splitId)
                          ? s.splitId
                          : ok.first.id));
                },
              ),
            ),
            _Section(
              label: 'Objetivo',
              note: _goalNote(s.goal),
              child: BsSegmented<Goal>(
                value: s.goal,
                options: const {
                  Goal.hipertrofia: 'Hipertrofia',
                  Goal.forca: 'Força',
                  Goal.resistencia: 'Resistência',
                },
                onChanged: (v) => _save(_with(s, goal: v)),
              ),
            ),
            _Section(
              label: 'Divisão',
              note: available.length < 4
                  ? 'Divisões de mais dias aparecem conforme o nível sobe. '
                      'Frequência alta sem base é o caminho mais curto para parar.'
                  : null,
              child: Column(
                children: [
                  for (final split in available)
                    _SplitTile(
                      split: split,
                      selected: split.id == s.splitId,
                      onTap: () => _save(_with(s, splitId: split.id)),
                    ),
                ],
              ),
            ),
            _Section(
              label: 'Equipamento da academia',
              note: s.equipment.isEmpty
                  ? 'Nada marcado: assumo que tem tudo. Marque só se a sua for limitada.'
                  : '${s.equipment.length} selecionados — o gerador não sugere o resto.',
              child: Wrap(
                spacing: 7,
                runSpacing: 7,
                children: [
                  for (final e in Equipment.values)
                    BsChip(
                      label: _equip(e),
                      selected: s.equipment.contains(e),
                      onTap: () {
                        final next = {...s.equipment};
                        s.equipment.contains(e) ? next.remove(e) : next.add(e);
                        _save(_with(s, equipment: next));
                      },
                    ),
                ],
              ),
            ),
            _Section(
              label: 'O que você vai receber',
              child: _Preview(
                data: widget.data,
                setup: s,
                dayIndex: _previewDay,
                onDay: (i) => setState(() => _previewDay = i),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _goalNote(Goal g) => switch (g) {
        Goal.hipertrofia =>
          'Faixa de 6–15 repetições, descanso médio, técnicas de intensidade nos acessórios.',
        Goal.forca =>
          'Cargas altas, 3–6 repetições, descanso longo. Sem técnica de intensidade — '
              'ela atrapalha o trabalho de carga.',
        Goal.resistencia =>
          'Muitas repetições e descanso curto. Volume alto com carga baixa.',
      };

  static String _equip(Equipment e) => switch (e) {
        Equipment.pesoCorporal => 'peso corporal',
        Equipment.barra => 'barra',
        Equipment.halter => 'halteres',
        Equipment.polia => 'polia',
        Equipment.maquina => 'máquinas',
        Equipment.smith => 'smith',
        Equipment.banco => 'banco',
        Equipment.bola => 'bola',
        Equipment.elastico => 'elástico',
        Equipment.step => 'step',
        Equipment.cone => 'cone',
        Equipment.rodinha => 'rodinha',
        Equipment.esteira => 'esteira',
        Equipment.bike => 'bike',
        Equipment.escada => 'escada',
      };
}

class _Section extends StatelessWidget {
  final String label;
  final String? note;
  final Widget child;
  const _Section({required this.label, required this.child, this.note});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(20, 0, 20, 26),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Caption(label),
            const SizedBox(height: 10),
            child,
            if (note != null) ...[
              const SizedBox(height: 9),
              Text(note!,
                  style: const TextStyle(
                      color: kFaint, fontSize: 12.5, height: 1.45)),
            ],
          ],
        ),
      );
}

class _SplitTile extends StatelessWidget {
  final TrainingSplit split;
  final bool selected;
  final VoidCallback onTap;
  const _SplitTile(
      {required this.split, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: BsCard(
          onTap: onTap,
          background: selected ? kGo.withValues(alpha: .08) : kSurface,
          border: selected ? kGo.withValues(alpha: .4) : kLine,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          child: Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: selected ? kGo : Colors.transparent,
                  border: Border.all(color: selected ? kGo : kLine, width: 1.5),
                ),
                child: selected
                    ? const Icon(Icons.check_rounded, size: 12, color: kInk)
                    : null,
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(split.name,
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 3),
                    Text(
                        '${split.daysPerWeek}× por semana · '
                        '${split.days.length} treinos diferentes',
                        style: const TextStyle(color: kFaint, fontSize: 12.5)),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
}

/// A prévia do treino que a configuração atual produz.
class _Preview extends StatelessWidget {
  final BorasetData data;
  final ProgramSetup setup;
  final int dayIndex;
  final ValueChanged<int> onDay;
  const _Preview({
    required this.data,
    required this.setup,
    required this.dayIndex,
    required this.onDay,
  });

  @override
  Widget build(BuildContext context) {
    final split = setup.split;
    final day = dayIndex % split.days.length;
    final session = ProgramBuilder(data.catalog).buildDay(
      ProgramRequest(
        split: split,
        goal: setup.goal,
        level: setup.level,
        availableEquipment: setup.equipment,
        week: 1,
      ),
      day,
    );

    return BsCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (var i = 0; i < split.days.length; i++)
                  Padding(
                    padding: const EdgeInsetsDirectional.only(end: 7),
                    child: BsChip(
                      label: split.days[i].name.split(' — ').first,
                      selected: i == day,
                      onTap: () => onDay(i),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (session.blocks.isEmpty)
            const BsBanner(
              text: 'Com esse equipamento não dá para montar este dia. Marque '
                  'mais itens ou escolha uma divisão com menos exigência de aparelho.',
            )
          else ...[
            for (final slot in session.allSlots) _Row(data: data, slot: slot),
            const Divider(height: 20),
            Row(
              children: [
                Text('${session.allSlots.length} exercícios',
                    style: const TextStyle(color: kFaint, fontSize: 12)),
                const Text(' · ', style: TextStyle(color: kFaint, fontSize: 12)),
                Text(
                    '${session.allSlots.fold(0, (a, s) => a + s.plannedSets)} séries',
                    style: const TextStyle(color: kFaint, fontSize: 12)),
                const Spacer(),
                const Text('semana 1 de 12',
                    style: TextStyle(color: kFaint, fontSize: 12)),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final BorasetData data;
  final ExerciseSlot slot;
  const _Row({required this.data, required this.slot});

  String get _reps => switch (slot.reps) {
        RepRange(:final min, :final max) => '$min–$max',
        RepToFailure() => 'falha',
        RepOpen() => 'livre',
        RepPerSet(:final reps) => reps.map((r) => r ?? 'F').join('/'),
        RepByDuration(:final duration) => '${duration.inMinutes}min',
      };

  @override
  Widget build(BuildContext context) {
    final anchor = slot.priority == 1;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 3,
            height: 15,
            margin: const EdgeInsetsDirectional.only(end: 10, top: 2),
            decoration: BoxDecoration(
              color: anchor ? kGo : kLine,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(data.nameOf(slot.exerciseSlug),
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.25,
                      fontWeight: anchor ? FontWeight.w600 : FontWeight.w400,
                    )),
                if (slot.techniqueSlugs.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Wrap(
                      spacing: 8,
                      children: [
                        for (final t in slot.techniqueSlugs)
                          if (data.techniques[t] != null)
                            GestureDetector(
                              onTap: () => showTechniqueHelp(context, data, t),
                              child: Text(data.techniques[t]!.name,
                                  style: const TextStyle(
                                      fontSize: 11.5,
                                      color: kGo,
                                      fontWeight: FontWeight.w500)),
                            ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          Text('${slot.plannedSets}×$_reps',
              style: const TextStyle(
                  color: kMuted, fontSize: 12.5, fontFeatures: kTabular)),
          const SizedBox(width: 10),
          SizedBox(
            width: 32,
            child: Text('${slot.rest.nominal.inSeconds}s',
                textAlign: TextAlign.end,
                style: const TextStyle(
                    color: kFaint, fontSize: 12, fontFeatures: kTabular)),
          ),
        ],
      ),
    );
  }
}
