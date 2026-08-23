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

  @override
  Widget build(BuildContext context) {
    final s = _setup;
    if (s == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final available = splitsFor(s.level);
    return Scaffold(
      appBar: AppBar(title: const Text('Programa')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          const Caption('Nível'),
          const SizedBox(height: 8),
          _Choice<Level>(
            value: s.level,
            options: const {
              Level.iniciante: 'Iniciante',
              Level.intermediario: 'Intermediário',
              Level.avancado: 'Avançado',
            },
            onChanged: (v) {
              // Baixar o nível pode tirar a divisão escolhida do cardápio.
              final ok = splitsFor(v);
              _save(ProgramSetup(
                splitId: ok.any((x) => x.id == s.splitId) ? s.splitId : ok.first.id,
                goal: s.goal, level: v, equipment: s.equipment, configured: true,
              ));
            },
          ),
          const SizedBox(height: 22),

          const Caption('Objetivo'),
          const SizedBox(height: 8),
          _Choice<Goal>(
            value: s.goal,
            options: const {
              Goal.hipertrofia: 'Hipertrofia',
              Goal.forca: 'Força',
              Goal.resistencia: 'Resistência',
            },
            onChanged: (v) => _save(ProgramSetup(
              splitId: s.splitId, goal: v, level: s.level,
              equipment: s.equipment, configured: true,
            )),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(_goalNote(s.goal),
                style: const TextStyle(color: kMuted, fontSize: 13)),
          ),
          const SizedBox(height: 22),

          const Caption('Divisão'),
          const SizedBox(height: 8),
          for (final split in available)
            _SplitTile(
              split: split,
              selected: split.id == s.splitId,
              onTap: () => _save(ProgramSetup(
                splitId: split.id, goal: s.goal, level: s.level,
                equipment: s.equipment, configured: true,
              )),
            ),
          if (available.length < 4)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'Divisões de mais dias aparecem conforme o nível sobe. '
                'Frequência alta sem base é o caminho mais curto para parar.',
                style: TextStyle(color: kMuted.withValues(alpha: .9), fontSize: 12.5),
              ),
            ),
          const SizedBox(height: 22),

          const Caption('Equipamento da sua academia'),
          const SizedBox(height: 4),
          Text(
            s.equipment.isEmpty
                ? 'Nada marcado: assumo que tem tudo. Marque só se a sua for limitada.'
                : '${s.equipment.length} selecionados — o gerador não vai sugerir o resto.',
            style: const TextStyle(color: kMuted, fontSize: 13),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final e in Equipment.values)
                FilterChip(
                  label: Text(_equip(e)),
                  selected: s.equipment.contains(e),
                  onSelected: (on) {
                    final next = {...s.equipment};
                    on ? next.add(e) : next.remove(e);
                    _save(ProgramSetup(
                      splitId: s.splitId, goal: s.goal, level: s.level,
                      equipment: next, configured: true,
                    ));
                  },
                ),
            ],
          ),
          const SizedBox(height: 28),

          const Caption('O que você vai receber'),
          const SizedBox(height: 10),
          _Preview(
            data: widget.data,
            setup: s,
            dayIndex: _previewDay,
            onDay: (i) => setState(() => _previewDay = i),
          ),
        ],
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

class _Choice<T> extends StatelessWidget {
  final T value;
  final Map<T, String> options;
  final ValueChanged<T> onChanged;
  const _Choice({required this.value, required this.options, required this.onChanged});

  @override
  Widget build(BuildContext context) => SegmentedButton<T>(
        segments: [
          for (final e in options.entries)
            ButtonSegment(value: e.key, label: Text(e.value)),
        ],
        selected: {value},
        showSelectedIcon: false,
        onSelectionChanged: (s) => onChanged(s.first),
      );
}

class _SplitTile extends StatelessWidget {
  final TrainingSplit split;
  final bool selected;
  final VoidCallback onTap;
  const _SplitTile({required this.split, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: selected ? kGo.withValues(alpha: .12) : kSurfaceHi,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: selected ? kGo.withValues(alpha: .5) : Colors.transparent),
          ),
          child: Row(
            children: [
              Icon(selected ? Icons.check_circle_rounded : Icons.circle_outlined,
                  size: 20, color: selected ? kGo : kMuted),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(split.name, style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 2),
                    Text('${split.daysPerWeek}x por semana · ${split.days.length} treinos diferentes',
                        style: const TextStyle(color: kMuted, fontSize: 12.5)),
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
    final unit = data.unit == WeightUnit.lb ? 'lb' : 'kg';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: kSurface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (var i = 0; i < split.days.length; i++)
                  Padding(
                    padding: const EdgeInsetsDirectional.only(end: 8),
                    child: ChoiceChip(
                      label: Text(split.days[i].name.split(' — ').first),
                      selected: i == day,
                      onSelected: (_) => onDay(i),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          if (session.blocks.isEmpty)
            const Text(
              'Com esse equipamento não dá para montar este dia. Marque mais itens '
              'ou escolha uma divisão com menos exigência de aparelho.',
              style: TextStyle(color: kWarn, fontSize: 13.5),
            )
          else
            for (final slot in session.allSlots) _Row(data: data, slot: slot, unit: unit),
          const SizedBox(height: 10),
          Text(
            '${session.allSlots.length} exercícios · '
            '${session.allSlots.fold(0, (a, s) => a + s.plannedSets)} séries · '
            'semana 1 de 12',
            style: const TextStyle(color: kMuted, fontSize: 12.5),
          ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final BorasetData data;
  final ExerciseSlot slot;
  final String unit;
  const _Row({required this.data, required this.slot, required this.unit});

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
      padding: const EdgeInsets.only(bottom: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 14,
            child: anchor
                ? const Icon(Icons.push_pin_rounded, size: 13, color: kGo)
                : null,
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(data.nameOf(slot.exerciseSlug),
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: anchor ? FontWeight.w600 : FontWeight.w400,
                    )),
                if (slot.techniqueSlugs.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Wrap(
                      spacing: 6,
                      children: [
                        for (final t in slot.techniqueSlugs)
                          if (data.techniques[t] != null)
                            GestureDetector(
                              onTap: () => showTechniqueHelp(context, data, t),
                              child: Text(
                                data.techniques[t]!.name,
                                style: const TextStyle(
                                    fontSize: 12,
                                    color: kGo,
                                    decoration: TextDecoration.underline),
                              ),
                            ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          Text('${slot.plannedSets}× $_reps',
              style: const TextStyle(color: kMuted, fontSize: 13)),
          const SizedBox(width: 10),
          SizedBox(
            width: 38,
            child: Text('${slot.rest.nominal.inSeconds}s',
                textAlign: TextAlign.end,
                style: const TextStyle(color: kMuted, fontSize: 12.5)),
          ),
        ],
      ),
    );
  }
}
