/// Histórico — e a barra de calibração.
///
/// A barra não é enfeite: ela mostra ao usuário por que o app ainda diz
/// "20–30 min" em vez de "24 min". Torna a incerteza uma coisa que se resolve
/// treinando, em vez de um defeito silencioso.
library;

import 'package:flutter/material.dart';

import '../data/store.dart';
import 'theme.dart';
import 'widgets.dart';

class HistoryScreen extends StatefulWidget {
  final WorkoutStore store;
  const HistoryScreen({super.key, required this.store});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  late Future<(List<SessionSummary>, int)> _future = _load();

  Future<(List<SessionSummary>, int)> _load() async =>
      (await widget.store.recentSessions(), await widget.store.timedSetCount());

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          bottom: false,
          child: FutureBuilder<(List<SessionSummary>, int)>(
            future: _future,
            builder: (context, snap) {
              if (!snap.hasData) {
                return const Center(
                    child: SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2)));
              }
              final (sessions, timedSets) = snap.data!;
              final volume =
                  sessions.fold<double>(0, (a, s) => a + s.volumeKg);
              return RefreshIndicator(
                color: kGo,
                backgroundColor: kSurfaceHi,
                onRefresh: () async => setState(() => _future = _load()),
                child: ListView(
                  padding: const EdgeInsets.only(bottom: 28),
                  children: [
                    const BsHeader('Histórico'),
                    if (sessions.isNotEmpty)
                      Padding(
                        padding:
                            const EdgeInsetsDirectional.fromSTEB(20, 0, 20, 18),
                        child: Row(
                          children: [
                            _Stat('${sessions.length}', 'treinos'),
                            const SizedBox(width: 10),
                            _Stat(
                                '${sessions.fold<int>(0, (a, s) => a + s.setCount)}',
                                'séries'),
                            const SizedBox(width: 10),
                            _Stat(
                                volume >= 1000
                                    ? '${(volume / 1000).toStringAsFixed(1)}t'
                                    : '${volume.round()}kg',
                                'volume'),
                          ],
                        ),
                      ),
                    Padding(
                      padding:
                          const EdgeInsetsDirectional.fromSTEB(20, 0, 20, 22),
                      child: _Calibration(timedSets: timedSets),
                    ),
                    if (sessions.isEmpty)
                      const Padding(
                        padding: EdgeInsets.only(top: 30),
                        child: Center(
                          child: Text('Nenhum treino registrado ainda',
                              style: TextStyle(color: kFaint, fontSize: 14)),
                        ),
                      )
                    else ...[
                      const Padding(
                        padding: EdgeInsetsDirectional.fromSTEB(20, 0, 20, 10),
                        child: Caption('Treinos'),
                      ),
                      const Divider(),
                      for (final s in sessions) _SessionRow(s),
                    ],
                  ],
                ),
              );
            },
          ),
        ),
      );
}

class _Stat extends StatelessWidget {
  final String value, label;
  const _Stat(this.value, this.label);

  @override
  Widget build(BuildContext context) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            color: kSurface,
            borderRadius: BorderRadius.circular(kRadiusSm),
            border: Border.all(color: kLine),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(value,
                  style: const TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.5,
                    fontFeatures: kTabular,
                  )),
              const SizedBox(height: 2),
              Caption(label),
            ],
          ),
        ),
      );
}

/// O quanto o app já conhece o seu ritmo.
class _Calibration extends StatelessWidget {
  final int timedSets;
  const _Calibration({required this.timedSets});

  // Os mesmos limiares do HistoricalDurationModel.
  static const _calibrating = 12;
  static const _personalized = 40;

  (String, String, double, Color) get _state {
    if (timedSets < _calibrating) {
      return (
        'Aprendendo o seu ritmo',
        'Faltam ${_calibrating - timedSets} séries para o tempo restante deixar '
            'de ser uma faixa e virar um número.',
        timedSets / _calibrating,
        kWarn,
      );
    }
    if (timedSets < _personalized) {
      return (
        'Calibrando',
        'Já dá para estimar. Faltam ${_personalized - timedSets} séries para a '
            'estimativa ficar realmente ajustada a você.',
        timedSets / _personalized,
        kGo,
      );
    }
    return (
      'Estimativa personalizada',
      'O app conhece o seu ritmo em $timedSets séries. O tempo restante já sai '
          'com margem estreita.',
      1,
      kGo,
    );
  }

  @override
  Widget build(BuildContext context) {
    final (title, body, progress, color) = _state;
    return BsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(title,
                    style: Theme.of(context).textTheme.titleMedium),
              ),
              Text('$timedSets',
                  style: const TextStyle(
                      color: kFaint, fontSize: 13, fontFeatures: kTabular)),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: progress.clamp(0, 1),
              minHeight: 5,
              backgroundColor: kSurfaceHi,
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
          const SizedBox(height: 11),
          Text(body,
              style: const TextStyle(color: kFaint, fontSize: 12.5, height: 1.45)),
        ],
      ),
    );
  }
}

class _SessionRow extends StatelessWidget {
  final SessionSummary s;
  const _SessionRow(this.s);

  static const _months = [
    'jan', 'fev', 'mar', 'abr', 'mai', 'jun',
    'jul', 'ago', 'set', 'out', 'nov', 'dez',
  ];
  static String _date(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')} ${_months[d.month - 1]}';

  @override
  Widget build(BuildContext context) => BsRow(
        title: s.name,
        subtitle: '${_date(s.startedAt)}'
            '${s.duration != null ? " · ${s.duration!.inMinutes} min" : " · em andamento"}',
        trailing: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text('${s.setCount} séries',
                style: const TextStyle(fontSize: 13, fontFeatures: kTabular)),
            if (s.volumeKg > 0) ...[
              const SizedBox(height: 2),
              Text('${s.volumeKg.round()} kg',
                  style: const TextStyle(
                      color: kFaint, fontSize: 11.5, fontFeatures: kTabular)),
            ],
          ],
        ),
      );
}
