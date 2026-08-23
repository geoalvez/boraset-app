/// Persistência local. Offline primeiro; sincronização vem depois.
///
/// O que este arquivo existe para fazer, além de salvar:
/// **fechar o laço da estimativa de tempo.** Sem histórico, o motor só sabe
/// o prior populacional e o app fica preso em "20–30 min" para sempre. Cada
/// série registrada aqui empurra a confiança para `calibrating` e depois
/// para `personalized`.
///
/// O schema tem `synced_at` desde o primeiro dia. Adicionar sincronização
/// depois é fácil; adicionar a coluna depois de mil usuários, não.
library;

import 'package:boraset_domain/boraset_domain.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

class LoggedSet {
  final String sessionId, slotId, exerciseSlug;
  final int setIndex;
  final double? loadKg;
  final int? reps;
  final int? seconds;
  final bool warmup;

  const LoggedSet({
    required this.sessionId,
    required this.slotId,
    required this.exerciseSlug,
    required this.setIndex,
    this.loadKg,
    this.reps,
    this.seconds,
    this.warmup = false,
  });
}

class SessionSummary {
  final String id, name;
  final DateTime startedAt;
  final DateTime? finishedAt;
  final int setCount;
  final double volumeKg;

  const SessionSummary({
    required this.id,
    required this.name,
    required this.startedAt,
    this.finishedAt,
    required this.setCount,
    required this.volumeKg,
  });

  Duration? get duration => finishedAt?.difference(startedAt);
}

/// O que o usuário escolheu para o próprio programa.
class ProgramSetup {
  final String splitId;
  final Goal goal;
  final Level level;

  /// Vazio = "assume que a academia tem tudo". É o padrão honesto: pedir o
  /// inventário do ferro antes do primeiro treino afugenta o usuário.
  final Set<Equipment> equipment;

  /// false na primeira abertura — a UI oferece configurar, sem obrigar.
  final bool configured;

  const ProgramSetup({
    required this.splitId,
    required this.goal,
    required this.level,
    required this.equipment,
    this.configured = false,
  });

  TrainingSplit get split =>
      splitsFor(Level.avancado).firstWhere((s) => s.id == splitId,
          orElse: () => abc3);
}

class WorkoutStore {
  final Database db;
  WorkoutStore(this.db);

  static const _version = 1;

  static Future<WorkoutStore> open({String? path, DatabaseFactory? factory}) async {
    final f = factory ?? databaseFactory;
    final dir = path ?? p.join(await f.getDatabasesPath(), 'boraset.db');
    final db = await f.openDatabase(
      dir,
      options: OpenDatabaseOptions(
        version: _version,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: _create,
      ),
    );
    return WorkoutStore(db);
  }

  static Future<void> _create(Database db, int _) async {
    await db.execute('''
      CREATE TABLE sessions (
        id          TEXT PRIMARY KEY,
        name        TEXT NOT NULL,
        started_at  INTEGER NOT NULL,
        finished_at INTEGER,
        budget_sec  INTEGER,
        synced_at   INTEGER
      )''');
    await db.execute('''
      CREATE TABLE set_records (
        id            INTEGER PRIMARY KEY AUTOINCREMENT,
        session_id    TEXT NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
        slot_id       TEXT NOT NULL,
        exercise_slug TEXT NOT NULL,
        set_index     INTEGER NOT NULL,
        load_kg       REAL,
        reps          INTEGER,
        seconds       INTEGER,
        warmup        INTEGER NOT NULL DEFAULT 0,
        logged_at     INTEGER NOT NULL,
        synced_at     INTEGER
      )''');
    // O índice que importa: "quanto ESTE usuário demora NESTE exercício".
    await db.execute(
        'CREATE INDEX idx_sets_exercise ON set_records(exercise_slug, logged_at DESC)');
    await db.execute('''
      CREATE TABLE prefs (
        key   TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )''');
  }

  // --- sessões --------------------------------------------------------------

  Future<void> startSession(String id, String name, {Duration? budget}) =>
      db.insert(
        'sessions',
        {
          'id': id,
          'name': name,
          'started_at': DateTime.now().millisecondsSinceEpoch,
          'budget_sec': budget?.inSeconds,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

  Future<void> finishSession(String id) => db.update(
        'sessions',
        {'finished_at': DateTime.now().millisecondsSinceEpoch},
        where: 'id = ?',
        whereArgs: [id],
      );

  Future<void> logSet(LoggedSet s) => db.insert('set_records', {
        'session_id': s.sessionId,
        'slot_id': s.slotId,
        'exercise_slug': s.exerciseSlug,
        'set_index': s.setIndex,
        'load_kg': s.loadKg,
        'reps': s.reps,
        'seconds': s.seconds,
        'warmup': s.warmup ? 1 : 0,
        'logged_at': DateTime.now().millisecondsSinceEpoch,
      });

  Future<List<SessionSummary>> recentSessions({int limit = 30}) async {
    final rows = await db.rawQuery('''
      SELECT s.id, s.name, s.started_at, s.finished_at,
             COUNT(r.id)                     AS sets,
             COALESCE(SUM(r.load_kg * r.reps), 0) AS volume
      FROM sessions s
      LEFT JOIN set_records r ON r.session_id = s.id AND r.warmup = 0
      GROUP BY s.id
      -- rowid desempata: started_at tem resolucao de milissegundo e duas
      -- sessoes abertas rapido caem no mesmo valor. Mesmo motivo do id DESC
      -- em _mostRecentSessionWith; sem isso a ordem do historico e indefinida.
      ORDER BY s.started_at DESC, s.rowid DESC
      LIMIT ?''', [limit]);
    return [
      for (final r in rows)
        SessionSummary(
          id: r['id'] as String,
          name: r['name'] as String,
          startedAt: DateTime.fromMillisecondsSinceEpoch(r['started_at'] as int),
          finishedAt: r['finished_at'] == null
              ? null
              : DateTime.fromMillisecondsSinceEpoch(r['finished_at'] as int),
          setCount: (r['sets'] as num).toInt(),
          volumeKg: (r['volume'] as num).toDouble(),
        ),
    ];
  }

  /// Qual foi a última sessão em que este exercício apareceu.
  ///
  /// O desempate por `id` não é decoração: `logged_at` tem resolução de
  /// milissegundo, e duas sessões registradas rápido caem no mesmo valor.
  /// Sem o `id DESC`, o SQLite pode devolver a sessão ANTIGA — e aí o app
  /// sugere a carga errada para quem treinou duas vezes no mesmo dia.
  Future<String?> _mostRecentSessionWith(String exerciseSlug) async {
    final r = await db.rawQuery(
        'SELECT session_id FROM set_records WHERE exercise_slug = ? '
        'ORDER BY logged_at DESC, id DESC LIMIT 1',
        [exerciseSlug]);
    return r.isEmpty ? null : r.first['session_id'] as String;
  }

  /// A última carga usada em cada série deste exercício.
  ///
  /// Devolve por índice de série porque Pirâmide, Drop-Set e Strip-Set mudam
  /// a carga a cada série — "a carga do supino" não existe.
  Future<Map<int, double>> lastLoadsFor(String exerciseSlug) async {
    final sid = await _mostRecentSessionWith(exerciseSlug);
    if (sid == null) return const {};
    final rows = await db.query(
      'set_records',
      columns: ['set_index', 'load_kg'],
      where: 'exercise_slug = ? AND session_id = ? AND load_kg IS NOT NULL',
      whereArgs: [exerciseSlug, sid],
    );
    return {
      for (final r in rows) (r['set_index'] as int): (r['load_kg'] as num).toDouble(),
    };
  }

  Future<List<SetRecord>> lastSessionOf(String exerciseSlug) async {
    final sid = await _mostRecentSessionWith(exerciseSlug);
    if (sid == null) return const [];
    final rows = await db.query(
      'set_records',
      where: 'exercise_slug = ? AND session_id = ?',
      whereArgs: [exerciseSlug, sid],
      orderBy: 'set_index',
    );
    return [
      for (final r in rows)
        SetRecord(
          index: r['set_index'] as int,
          loadKg: (r['load_kg'] as num?)?.toDouble(),
          reps: r['reps'] as int?,
          elapsed: r['seconds'] == null
              ? null
              : Duration(seconds: r['seconds'] as int),
          warmup: (r['warmup'] as int) == 1,
        ),
    ];
  }

  // --- configuração do programa --------------------------------------------

  /// O que o usuário escolheu: divisão, objetivo, nível e o ferro que a
  /// academia dele tem. É o que o gerador consome.
  Future<void> saveSetup({
    required String splitId,
    required Goal goal,
    required Level level,
    required Set<Equipment> equipment,
  }) async {
    await setPref('split', splitId);
    await setPref('goal', goal.name);
    await setPref('level', level.name);
    await setPref('equipment', equipment.map((e) => e.name).join(','));
  }

  Future<ProgramSetup> setup() async {
    final rows = await db.query('prefs');
    final m = {for (final r in rows) r['key'] as String: r['value'] as String};
    T pick<T extends Enum>(List<T> values, String? name, T fallback) =>
        values.where((v) => v.name == name).firstOrNull ?? fallback;
    final eq = (m['equipment'] ?? '').split(',').where((s) => s.isNotEmpty);
    return ProgramSetup(
      splitId: m['split'] ?? 'abc-3',
      goal: pick(Goal.values, m['goal'], Goal.hipertrofia),
      level: pick(Level.values, m['level'], Level.intermediario),
      equipment: {
        for (final e in eq) ...Equipment.values.where((v) => v.name == e),
      },
      configured: m.containsKey('split'),
    );
  }

  // --- perfil ---------------------------------------------------------------

  Future<void> setPref(String key, String value) => db.insert(
        'prefs',
        {'key': key, 'value': value},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

  Future<Set<String>> _prefSet(String key) async {
    final r = await db.query('prefs', where: 'key = ?', whereArgs: [key]);
    if (r.isEmpty) return {};
    final raw = r.first['value'] as String;
    return raw.isEmpty ? {} : raw.split(',').toSet();
  }

  Future<void> avoid(String slug) async =>
      setPref('avoided', {...await _prefSet('avoided'), slug}.join(','));

  /// Monta o perfil que o motor consome.
  ///
  /// `observedSetSeconds` é o que tira o app do modo "faixa": com 12 séries
  /// registradas a confiança sobe para `calibrating`, com 40 para
  /// `personalized`. Uma pessoa leva 40 s por série, outra 70 — e é isso
  /// que a estimativa passa a saber.
  Future<UserProfile> profile({Level level = Level.intermediario}) async {
    final rows = await db.rawQuery('''
      SELECT exercise_slug, AVG(seconds) AS avg_s, COUNT(*) AS n
      FROM set_records
      WHERE seconds IS NOT NULL AND warmup = 0
      GROUP BY exercise_slug''');
    final transitions = await db.rawQuery(
        'SELECT AVG(seconds) AS avg_s FROM set_records WHERE seconds IS NOT NULL');
    return UserProfile(
      avoided: await _prefSet('avoided'),
      preferred: await _prefSet('preferred'),
      level: level,
      observedSetSeconds: {
        for (final r in rows)
          r['exercise_slug'] as String: (r['avg_s'] as num).toDouble(),
      },
      observedTransitionSeconds: transitions.isEmpty || transitions.first['avg_s'] == null
          ? null
          : (transitions.first['avg_s'] as num).toDouble(),
    );
  }

  /// Quantas séries com tempo já foram registradas — é o que move a
  /// confiança da estimativa. Serve para a UI dizer o quanto falta calibrar.
  Future<int> timedSetCount() async {
    final r = await db.rawQuery(
        'SELECT COUNT(*) AS n FROM set_records WHERE seconds IS NOT NULL AND warmup = 0');
    return (r.first['n'] as num).toInt();
  }

  Future<void> close() => db.close();
}
