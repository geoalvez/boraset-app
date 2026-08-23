/// Histórico — e a barra de calibração.
///
/// A barra não é enfeite: ela mostra ao usuário por que o app ainda diz
/// "20–30 min" em vez de "24 min". Torna a incerteza uma coisa que se resolve
/// treinando, em vez de um defeito silencioso.
library;

import 'package:flutter/material.dart';

import '../data/store.dart';
import 'theme.dart';

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
        appBar: AppBar(title: const Text('Histórico')),
        body: RefreshIndicator(
          onRefresh: () async => setState(() => _future = _load()),
          child: FutureBuilder<(List<SessionSummary>, int)>(
            future: _future,
            builder: (context, snap) {
              if (!snap.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final (sessions, timedSets) = snap.data!;
              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _Calibration(timedSets: timedSets),
                  const SizedBox(height: 22),
                  if (sessions.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(top: 40),
                      child: Center(
                        child: Text('Nenhum treino registrado ainda',
                            style: TextStyle(color: kMuted)),
                      ),
                    )
                  else ...[
                    const Caption('Treinos'),
                    const SizedBox(height: 8),
                    for (final s in sessions) _SessionTile(s),
                  ],
                ],
              );
            },
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
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: kSurface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: progress.clamp(0, 1),
              minHeight: 7,
              backgroundColor: kSurfaceHi,
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
          const SizedBox(height: 10),
          Text(body,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(fontSize: 13.5, color: kMuted)),
        ],
      ),
    );
  }
}

class _SessionTile extends StatelessWidget {
  final SessionSummary s;
  const _SessionTile(this.s);

  static String _date(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: kSurfaceHi,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(s.name, style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 3),
                  Text(
                    '${_date(s.startedAt)}'
                    '${s.duration != null ? " · ${s.duration!.inMinutes} min" : " · em andamento"}',
                    style: const TextStyle(color: kMuted, fontSize: 12.5),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('${s.setCount} séries',
                    style: const TextStyle(fontSize: 13.5)),
                if (s.volumeKg > 0)
                  Text('${s.volumeKg.round()} kg de volume',
                      style: const TextStyle(color: kMuted, fontSize: 12)),
              ],
            ),
          ],
        ),
      );
}
