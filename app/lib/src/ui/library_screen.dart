/// Biblioteca — os 193 exercícios e as 30 técnicas, no idioma do usuário.
///
/// Aqui os `aliases` finalmente ganham função: a busca casa com o nome E com
/// os apelidos locais. Quem procura "puxada frente" acha "Pulley Frente".
/// Nos 17 idiomas gerados a lista de apelidos está vazia de propósito — e é
/// justamente esta tela que fica pior por isso, o que é bom: o buraco aparece
/// onde dói, não escondido num JSON.
library;

import 'package:boraset_domain/boraset_domain.dart';
import 'package:flutter/material.dart';

import '../data/repository.dart';
import 'help_sheet.dart';
import 'theme.dart';
import 'widgets.dart';

class LibraryScreen extends StatefulWidget {
  final BorasetData data;
  const LibraryScreen({super.key, required this.data});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  String _query = '';
  int _tab = 0;

  static String _norm(String s) => s
      .toLowerCase()
      .replaceAll(RegExp(r'[áàâã]'), 'a')
      .replaceAll(RegExp(r'[éê]'), 'e')
      .replaceAll(RegExp(r'[íî]'), 'i')
      .replaceAll(RegExp(r'[óôõ]'), 'o')
      .replaceAll(RegExp(r'[úû]'), 'u')
      .replaceAll('ç', 'c');

  List<Exercise> get _exercises {
    final q = _norm(_query);
    final all = widget.data.catalog.all.toList()
      // Frequência no corpus = o que a pessoa mais provavelmente conhece.
      ..sort((a, b) => b.familiarity.compareTo(a.familiarity));
    if (q.isEmpty) return all;
    return all.where((e) {
      final named = widget.data.exerciseNames[e.slug];
      return _norm(named?.name ?? e.slug).contains(q) ||
          (named?.aliases ?? const []).any((a) => _norm(a).contains(q));
    }).toList();
  }

  List<TechniqueHelp> get _techniques {
    final q = _norm(_query);
    final all = widget.data.techniques.values.toList()
      ..sort((a, b) => b.occurrences.compareTo(a.occurrences));
    if (q.isEmpty) return all;
    return all.where((t) => _norm(t.name).contains(q)).toList();
  }

  @override
  Widget build(BuildContext context) {
    final exCount = _exercises.length;
    final tcCount = _techniques.length;
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            const BsHeader('Biblioteca'),
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(20, 0, 20, 14),
              child: TextField(
                onChanged: (v) => setState(() => _query = v),
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search_rounded, size: 19, color: kFaint),
                  prefixIconConstraints:
                      BoxConstraints(minWidth: 42, minHeight: 20),
                  hintText: 'Buscar exercício ou técnica',
                  isDense: true,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(20, 0, 20, 12),
              child: BsSegmented<int>(
                value: _tab,
                options: {0: 'Exercícios · $exCount', 1: 'Técnicas · $tcCount'},
                onChanged: (v) => setState(() => _tab = v),
              ),
            ),
            const Divider(),
            Expanded(child: _tab == 0 ? _exerciseList() : _techniqueList()),
          ],
        ),
      ),
    );
  }

  Widget _exerciseList() {
    final list = _exercises;
    if (list.isEmpty) return const _Empty();
    return ListView.builder(
      itemCount: list.length,
      padding: EdgeInsets.zero,
      itemBuilder: (_, i) {
        final e = list[i];
        return BsRow(
          title: widget.data.nameOf(e.slug),
          subtitle: '${_muscle(e.primary)} · ${_pattern(e.pattern)}'
              '${e.laterality == Laterality.unilateral ? " · unilateral" : ""}',
          trailing: Text('${e.familiarity}×',
              style: const TextStyle(
                  color: kFaint, fontSize: 11.5, fontFeatures: kTabular)),
          onTap: () => _showExercise(e),
        );
      },
    );
  }

  Widget _techniqueList() {
    final list = _techniques;
    if (list.isEmpty) return const _Empty();
    return ListView.builder(
      itemCount: list.length,
      padding: EdgeInsets.zero,
      itemBuilder: (_, i) {
        final t = list[i];
        return BsRow(
          leading: Icon(
              t.hasCaution
                  ? Icons.warning_amber_rounded
                  : Icons.auto_awesome_outlined,
              size: 18,
              color: t.hasCaution ? kWarn : kFaint),
          title: t.name,
          subtitle: t.summary,
          // `expanded: true` porque aqui o usuário está no sofá, não na série.
          onTap: () =>
              showTechniqueHelp(context, widget.data, t.slug, expanded: true),
        );
      },
    );
  }

  /// Ficha do exercício. Não há texto autorado por exercício ainda — o que
  /// existe são os eixos e as equivalências CALCULADAS, e elas já dizem muito.
  void _showExercise(Exercise e) {
    final subs = widget.data.catalog.equivalentsOf(e.slug);
    bsSheet(
      context,
      SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsetsDirectional.fromSTEB(20, 10, 20, 26),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(widget.data.nameOf(e.slug),
                  style: Theme.of(context)
                      .textTheme
                      .displaySmall
                      ?.copyWith(fontSize: 22)),
              const SizedBox(height: 16),
              Wrap(spacing: 7, runSpacing: 7, children: [
                BsChip(label: _muscle(e.primary), selected: true),
                for (final s in e.secondary) BsChip(label: _muscle(s)),
                BsChip(label: _pattern(e.pattern)),
                BsChip(label: e.mechanic.name),
                if (e.laterality != Laterality.bilateral)
                  BsChip(label: e.laterality.name),
                BsChip(label: e.level.name),
                for (final q in e.equipment) BsChip(label: _equip(q)),
              ]),
              if (e.loadScalability != LoadScalability.alta) ...[
                const SizedBox(height: 16),
                BsBanner(
                    text: _loadNote(e.loadScalability),
                    icon: Icons.fitness_center_outlined),
              ],
              const SizedBox(height: 24),
              const Caption('Substitutos equivalentes'),
              const SizedBox(height: 10),
              if (subs.isEmpty)
                const BsBanner(
                  icon: Icons.info_outline_rounded,
                  tone: kMuted,
                  text: 'Nenhum. Este movimento não tem equivalente no catálogo — '
                      'se o aparelho estiver ocupado, o motor vai reordenar o '
                      'treino em vez de trocar.',
                )
              else
                BsCard(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                  child: Column(
                    children: [
                      for (final s in subs.take(8))
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 9),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                    widget.data.nameOf(s.exercise.slug),
                                    style: const TextStyle(fontSize: 13.5)),
                              ),
                              _Bar(pct: s.score / 100),
                              const SizedBox(width: 10),
                              SizedBox(
                                width: 34,
                                child: Text('${s.score.round()}%',
                                    textAlign: TextAlign.end,
                                    style: const TextStyle(
                                        color: kFaint,
                                        fontSize: 12,
                                        fontFeatures: kTabular)),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
      tall: true,
    );
  }

  static String _loadNote(LoadScalability l) => switch (l) {
        LoadScalability.baixa =>
          'Peso corporal: dá para lastrar, mas não dá para igualar uma carga externa.',
        LoadScalability.nenhuma =>
          'Isométrico: a progressão aqui é por tempo, não por carga.',
        LoadScalability.tempo => 'Medido em tempo ou distância, não em carga.',
        LoadScalability.alta => '',
      };

  static String _muscle(MuscleGroup m) => switch (m) {
        MuscleGroup.peito => 'peito',
        MuscleGroup.costas => 'costas',
        MuscleGroup.ombroAnterior => 'ombro anterior',
        MuscleGroup.ombroLateral => 'ombro lateral',
        MuscleGroup.ombroPosterior => 'ombro posterior',
        MuscleGroup.biceps => 'bíceps',
        MuscleGroup.triceps => 'tríceps',
        MuscleGroup.antebraco => 'antebraço',
        MuscleGroup.quadriceps => 'quadríceps',
        MuscleGroup.isquiotibiais => 'posterior de coxa',
        MuscleGroup.gluteo => 'glúteo',
        MuscleGroup.adutores => 'adutores',
        MuscleGroup.abdutores => 'abdutores',
        MuscleGroup.panturrilha => 'panturrilha',
        MuscleGroup.coreAnterior => 'abdômen',
        MuscleGroup.coreLateral => 'oblíquos',
        MuscleGroup.corePosterior => 'lombar',
        MuscleGroup.trapezio => 'trapézio',
        MuscleGroup.manguito => 'manguito rotador',
        MuscleGroup.cardio => 'cardio',
        MuscleGroup.mobilidade => 'mobilidade',
        MuscleGroup.corpoInteiro => 'corpo inteiro',
      };

  static String _pattern(MovementPattern p) => p.name
      .replaceAllMapped(RegExp(r'([A-Z])'), (m) => ' ${m[1]!.toLowerCase()}');

  static String _equip(Equipment e) => switch (e) {
        Equipment.pesoCorporal => 'peso corporal',
        Equipment.barra => 'barra',
        Equipment.halter => 'halteres',
        Equipment.polia => 'polia',
        Equipment.maquina => 'máquina',
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

/// Barra de compatibilidade — o número sozinho não dá noção de distância.
class _Bar extends StatelessWidget {
  final double pct;
  const _Bar({required this.pct});

  @override
  Widget build(BuildContext context) => Container(
        width: 46,
        height: 3,
        decoration: BoxDecoration(
          color: kSurfaceHi,
          borderRadius: BorderRadius.circular(2),
        ),
        child: FractionallySizedBox(
          alignment: AlignmentDirectional.centerStart,
          widthFactor: pct.clamp(0, 1),
          child: Container(
            decoration: BoxDecoration(
              color: pct >= .9 ? kGo : (pct >= .7 ? kWarn : kFaint),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
      );
}

class _Empty extends StatelessWidget {
  const _Empty();
  @override
  Widget build(BuildContext context) => const Center(
        child: Text('Nada encontrado',
            style: TextStyle(color: kFaint, fontSize: 14)),
      );
}
