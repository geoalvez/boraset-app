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

class LibraryScreen extends StatefulWidget {
  final BorasetData data;
  const LibraryScreen({super.key, required this.data});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen>
    with SingleTickerProviderStateMixin {
  late final _tabs = TabController(length: 2, vsync: this);
  String _query = '';

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  String _norm(String s) => s
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
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('Biblioteca'),
          bottom: TabBar(
            controller: _tabs,
            tabs: const [Tab(text: 'Exercícios'), Tab(text: 'Técnicas')],
          ),
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: TextField(
                onChanged: (v) => setState(() => _query = v),
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search_rounded),
                  hintText: 'Buscar',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ),
            Expanded(
              child: TabBarView(
                controller: _tabs,
                children: [_exerciseList(), _techniqueList()],
              ),
            ),
          ],
        ),
      );

  Widget _exerciseList() {
    final list = _exercises;
    if (list.isEmpty) return const _Empty();
    return ListView.builder(
      itemCount: list.length,
      itemBuilder: (_, i) {
        final e = list[i];
        return ListTile(
          title: Text(widget.data.nameOf(e.slug)),
          subtitle: Text(
            '${_muscle(e.primary)} · ${_pattern(e.pattern)}'
            '${e.laterality == Laterality.unilateral ? " · unilateral" : ""}',
            style: const TextStyle(color: kMuted, fontSize: 13),
          ),
          trailing: Text('${e.familiarity}×',
              style: const TextStyle(color: kMuted, fontSize: 12)),
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
      itemBuilder: (_, i) {
        final t = list[i];
        return ListTile(
          leading: t.hasCaution
              ? const Icon(Icons.warning_amber_rounded, color: kWarn)
              : const Icon(Icons.article_outlined, color: kMuted),
          title: Text(t.name),
          subtitle: Text(t.summary,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: kMuted, fontSize: 13)),
          // `expanded: true` porque aqui o usuário está no sofá, não na série.
          onTap: () => showTechniqueHelp(context, widget.data, t.slug, expanded: true),
        );
      },
    );
  }

  /// Ficha do exercício. Não há texto autorado por exercício ainda — o que
  /// existe são os eixos e as equivalências CALCULADAS, e elas já dizem muito.
  void _showExercise(Exercise e) {
    final subs = widget.data.catalog.equivalentsOf(e.slug);
    showModalBottomSheet(
      context: context,
      backgroundColor: kSurface,
      isScrollControlled: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (_) => SafeArea(
        child: ConstrainedBox(
          constraints:
              BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .8),
          child: SingleChildScrollView(
            padding: const EdgeInsetsDirectional.fromSTEB(20, 4, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(widget.data.nameOf(e.slug),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontSize: 21)),
                const SizedBox(height: 14),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  _Tag(_muscle(e.primary)),
                  for (final s in e.secondary) _Tag(_muscle(s), dim: true),
                  _Tag(_pattern(e.pattern)),
                  _Tag(e.mechanic.name),
                  _Tag(e.laterality.name),
                  _Tag(e.level.name),
                  for (final q in e.equipment) _Tag(_equip(q), dim: true),
                ]),
                if (e.loadScalability != LoadScalability.alta) ...[
                  const SizedBox(height: 14),
                  Text(_loadNote(e.loadScalability),
                      style: const TextStyle(color: kWarn, fontSize: 13.5)),
                ],
                const SizedBox(height: 20),
                const Caption('Substitutos equivalentes'),
                const SizedBox(height: 8),
                if (subs.isEmpty)
                  const Text(
                    'Nenhum. Este movimento não tem equivalente no catálogo — '
                    'se o aparelho estiver ocupado, o motor vai reordenar o '
                    'treino em vez de trocar.',
                    style: TextStyle(color: kMuted, fontSize: 13.5),
                  )
                else
                  for (final s in subs.take(8))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        children: [
                          Expanded(child: Text(widget.data.nameOf(s.exercise.slug))),
                          Text('${s.score.round()}%',
                              style: const TextStyle(color: kMuted, fontSize: 13)),
                        ],
                      ),
                    ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String _loadNote(LoadScalability l) => switch (l) {
        LoadScalability.baixa =>
          'Peso corporal: dá para lastrar, mas não dá para igualar uma carga externa.',
        LoadScalability.nenhuma =>
          'Isométrico: a progressão aqui é por tempo, não por carga.',
        LoadScalability.tempo =>
          'Medido em tempo ou distância, não em carga.',
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

  static String _pattern(MovementPattern p) =>
      p.name.replaceAllMapped(RegExp(r'([A-Z])'), (m) => ' ${m[1]!.toLowerCase()}');

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

class _Tag extends StatelessWidget {
  final String text;
  final bool dim;
  const _Tag(this.text, {this.dim = false});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: dim ? kSurfaceHi : kGo.withValues(alpha: .14),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(text,
            style: TextStyle(fontSize: 12.5, color: dim ? kMuted : kGo)),
      );
}

class _Empty extends StatelessWidget {
  const _Empty();
  @override
  Widget build(BuildContext context) => const Center(
        child: Text('Nada encontrado', style: TextStyle(color: kMuted)),
      );
}
