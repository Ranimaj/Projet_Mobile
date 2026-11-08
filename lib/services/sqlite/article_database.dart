import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../../models/article_model.dart';

/// État de synchronisation d'une ligne avec Firebase.
enum SyncState {
  /// Identique à Firestore (dernière lecture ou écriture réussie).
  synced,

  /// Créée ou modifiée sur le téléphone, pas encore envoyée.
  pending,

  /// Supprimée sur le téléphone, suppression pas encore envoyée : la ligne
  /// est gardée (cachée) pour qu'une lecture Firestore ne la fasse pas
  /// réapparaître.
  deleted,
}

/// Base SQLite de Vente & Don : la base **principale** des articles sur le
/// téléphone. L'app lit toujours ici ; Firebase sert à partager les articles
/// avec les autres étudiants (voir [SqliteArticleRepository]).
///
/// Une table `articles` avec une colonne par champ ; les listes (photos,
/// favoris, étiquettes IA) sont stockées en JSON.
class ArticleDatabase {
  ArticleDatabase._(this._db);

  final Database _db;

  static const fileName = 'campusconnect_vente_don.db';
  static const table = 'articles';
  static const version = 1;

  /// Ouvre (ou crée) la base. [factory] et [path] sont remplaçables dans les
  /// tests (`databaseFactoryFfi`, `inMemoryDatabasePath`).
  static Future<ArticleDatabase> open({DatabaseFactory? factory, String? path}) async {
    final f = factory ?? databaseFactory;
    final dbPath = path ?? p.join(await f.getDatabasesPath(), fileName);
    final db = await f.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(version: version, onCreate: _create),
    );
    return ArticleDatabase._(db);
  }

  static Future<void> _create(Database db, int version) async {
    await db.execute('''
      CREATE TABLE $table (
        id            TEXT PRIMARY KEY,
        owner_id      TEXT NOT NULL,
        owner_name    TEXT NOT NULL,
        title         TEXT NOT NULL,
        description   TEXT NOT NULL,
        price         REAL,
        category      TEXT NOT NULL,
        status        TEXT NOT NULL,
        image_urls    TEXT NOT NULL,
        latitude      REAL,
        longitude     REAL,
        created_at    INTEGER NOT NULL,
        updated_at    INTEGER,
        view_count    INTEGER NOT NULL DEFAULT 0,
        favorited_by  TEXT NOT NULL,
        labels        TEXT NOT NULL,
        sync_state    TEXT NOT NULL DEFAULT 'synced'
      )''');
    await db.execute('CREATE INDEX idx_articles_owner ON $table(owner_id)');
    await db.execute('CREATE INDEX idx_articles_created ON $table(created_at DESC)');
  }

  Future<void> close() => _db.close();

  // ---------------------------------------------------------------- lecture

  /// Articles visibles (sans les suppressions en attente), plus récents
  /// d'abord.
  Future<List<ArticleModel>> all() async {
    final rows = await _db.query(table,
        where: 'sync_state != ?', whereArgs: [SyncState.deleted.name], orderBy: 'created_at DESC');
    return [for (final r in rows) fromRow(r)];
  }

  Future<ArticleModel?> byId(String id) async {
    final rows = await _db.query(table,
        where: 'id = ? AND sync_state != ?', whereArgs: [id, SyncState.deleted.name], limit: 1);
    return rows.isEmpty ? null : fromRow(rows.first);
  }

  /// État de synchronisation d'une ligne (null si absente).
  Future<SyncState?> syncStateOf(String id) async {
    final rows = await _db.query(table, columns: ['sync_state'], where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return null;
    return SyncState.values.byName(rows.first['sync_state'] as String);
  }

  /// Ids des lignes pas encore envoyées à Firebase (créations, modifications
  /// ou suppressions).
  Future<Set<String>> unsyncedIds() async {
    final rows = await _db.query(table,
        columns: ['id'], where: 'sync_state != ?', whereArgs: [SyncState.synced.name]);
    return {for (final r in rows) r['id'] as String};
  }

  // -------------------------------------------------------------- écriture

  /// Insère ou remplace un article.
  Future<void> upsert(ArticleModel a, {SyncState state = SyncState.synced}) =>
      _db.insert(table, toRow(a, state), conflictAlgorithm: ConflictAlgorithm.replace);

  /// Applique un patch au format Firestore (`{'status': 'reserved'}`,
  /// `{'favoritedBy': [...]}`…) à un article existant.
  Future<void> patch(String id, Map<String, dynamic> patch, {SyncState state = SyncState.synced}) async {
    final rows = await _db.query(table, where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return;
    final current = fromRow(rows.first);
    final merged = ArticleModel.fromMap(id, {...current.toMap(), ...patch});
    await upsert(merged, state: state);
  }

  /// Marque la ligne comme envoyée à Firebase (sans toucher une suppression
  /// en attente).
  Future<void> markSynced(String id) => _db.update(table, {'sync_state': SyncState.synced.name},
      where: 'id = ? AND sync_state = ?', whereArgs: [id, SyncState.pending.name]);

  /// Marque l'article supprimé (en attente) ou l'efface tout de suite.
  Future<void> remove(String id, {bool pending = false}) async {
    if (pending) {
      await _db.update(table, {'sync_state': SyncState.deleted.name}, where: 'id = ?', whereArgs: [id]);
    } else {
      await _db.delete(table, where: 'id = ?', whereArgs: [id]);
    }
  }

  /// Remplace le contenu par les articles lus sur Firebase, sauf les lignes
  /// dont l'id est dans [keepLocal] (modifications pas encore envoyées) :
  /// le téléphone garde sa version tant que la synchro n'est pas faite.
  /// Les autres lignes non synchronisées sont considérées comme envoyées.
  Future<void> replaceWithRemote(List<ArticleModel> remote, {Set<String> keepLocal = const {}}) {
    return _db.transaction((txn) async {
      if (keepLocal.isEmpty) {
        await txn.delete(table);
      } else {
        final marks = List.filled(keepLocal.length, '?').join(',');
        await txn.delete(table, where: 'id NOT IN ($marks)', whereArgs: keepLocal.toList());
      }
      final batch = txn.batch();
      for (final a in remote) {
        if (keepLocal.contains(a.id)) continue;
        batch.insert(table, toRow(a, SyncState.synced), conflictAlgorithm: ConflictAlgorithm.replace);
      }
      await batch.commit(noResult: true);
    });
  }

  // ------------------------------------------------------------- conversion

  static Map<String, Object?> toRow(ArticleModel a, SyncState state) => {
        'id': a.id,
        'owner_id': a.ownerId,
        'owner_name': a.ownerName,
        'title': a.title,
        'description': a.description,
        'price': a.price,
        'category': a.category,
        'status': a.status.name,
        'image_urls': jsonEncode(a.imageUrls),
        'latitude': a.latitude,
        'longitude': a.longitude,
        'created_at': a.createdAt.millisecondsSinceEpoch,
        'updated_at': a.updatedAt?.millisecondsSinceEpoch,
        'view_count': a.viewCount,
        'favorited_by': jsonEncode(a.favoritedBy),
        'labels': jsonEncode(a.labels),
        'sync_state': state.name,
      };

  static ArticleModel fromRow(Map<String, Object?> r) {
    List<String> list(String col) => List<String>.from(jsonDecode(r[col] as String? ?? '[]') as List);
    DateTime? date(String col) =>
        r[col] == null ? null : DateTime.fromMillisecondsSinceEpoch(r[col] as int);
    return ArticleModel(
      id: r['id'] as String,
      ownerId: r['owner_id'] as String,
      ownerName: r['owner_name'] as String,
      title: r['title'] as String,
      description: r['description'] as String,
      price: (r['price'] as num?)?.toDouble(),
      category: r['category'] as String,
      status: ArticleStatus.values.firstWhere((s) => s.name == r['status'],
          orElse: () => ArticleStatus.available),
      imageUrls: list('image_urls'),
      latitude: (r['latitude'] as num?)?.toDouble(),
      longitude: (r['longitude'] as num?)?.toDouble(),
      createdAt: date('created_at')!,
      updatedAt: date('updated_at'),
      viewCount: (r['view_count'] as num?)?.toInt() ?? 0,
      favoritedBy: list('favorited_by'),
      labels: list('labels'),
    );
  }
}
