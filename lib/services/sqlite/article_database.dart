import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../../models/article_model.dart';

/// Base SQLite de Vente & Don, sur le téléphone : **la seule base** de la
/// gestion (pas de Firebase). Trois tables :
///
///  - `articles` : une colonne par champ ; les listes (photos, favoris,
///    étiquettes IA) sont stockées en JSON ;
///  - `conversations` : une par couple article + acheteur ;
///  - `messages` : les messages de chaque conversation.
///
/// Les requêtes sur les articles sont ici ; celles de la messagerie sont dans
/// `ChatService`, qui partage la même base ([db]).
class ArticleDatabase {
  ArticleDatabase._(this.db);

  /// Connexion SQLite (partagée avec la messagerie).
  final Database db;

  static const fileName = 'campusconnect_vente_don.db';
  static const table = 'articles';
  static const conversationsTable = 'conversations';
  static const messagesTable = 'messages';

  /// 1 : articles. 2 : + messagerie (conversations, messages).
  static const version = 2;

  /// Ouvre (ou crée / met à jour) la base. [factory] et [path] sont
  /// remplaçables dans les tests (`databaseFactoryFfi`, fichier temporaire).
  static Future<ArticleDatabase> open({DatabaseFactory? factory, String? path}) async {
    final f = factory ?? databaseFactory;
    final dbPath = path ?? p.join(await f.getDatabasesPath(), fileName);
    final db = await f.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: version,
        onCreate: (db, _) async {
          await _createArticles(db);
          await _createChat(db);
        },
        onUpgrade: (db, from, _) async {
          if (from < 2) await _createChat(db);
        },
      ),
    );
    return ArticleDatabase._(db);
  }

  static Future<void> _createArticles(Database db) async {
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

  static Future<void> _createChat(Database db) async {
    await db.execute('''
      CREATE TABLE $conversationsTable (
        id                 TEXT PRIMARY KEY,
        article_id         TEXT NOT NULL,
        article_title      TEXT NOT NULL,
        article_image_url  TEXT,
        seller_id          TEXT NOT NULL,
        seller_name        TEXT NOT NULL,
        buyer_id           TEXT NOT NULL,
        buyer_name         TEXT NOT NULL,
        last_message       TEXT NOT NULL DEFAULT '',
        last_sender_id     TEXT,
        updated_at         INTEGER NOT NULL,
        unread_by          TEXT NOT NULL DEFAULT '[]'
      )''');
    await db.execute('''
      CREATE TABLE $messagesTable (
        id               INTEGER PRIMARY KEY AUTOINCREMENT,
        conversation_id  TEXT NOT NULL REFERENCES $conversationsTable(id) ON DELETE CASCADE,
        sender_id        TEXT NOT NULL,
        text             TEXT NOT NULL,
        sent_at          INTEGER NOT NULL
      )''');
    await db.execute('CREATE INDEX idx_messages_conv ON $messagesTable(conversation_id, sent_at)');
  }

  Future<void> close() => db.close();

  // ---------------------------------------------------------------- lecture

  /// Tous les articles, plus récents d'abord.
  Future<List<ArticleModel>> all() async {
    final rows = await db.query(table, orderBy: 'created_at DESC');
    return [for (final r in rows) fromRow(r)];
  }

  Future<ArticleModel?> byId(String id) async {
    final rows = await db.query(table, where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : fromRow(rows.first);
  }

  // -------------------------------------------------------------- écriture

  /// Insère ou remplace un article.
  Future<void> upsert(ArticleModel a) =>
      db.insert(table, toRow(a), conflictAlgorithm: ConflictAlgorithm.replace);

  /// Applique un patch (`{'status': 'reserved'}`, `{'favoritedBy': [...]}`…)
  /// à un article existant.
  Future<void> patch(String id, Map<String, dynamic> patch) async {
    final current = await byId(id);
    if (current == null) return;
    await upsert(ArticleModel.fromMap(id, {...current.toMap(), ...patch}));
  }

  Future<void> remove(String id) => db.delete(table, where: 'id = ?', whereArgs: [id]);

  // ------------------------------------------------------------- conversion

  static Map<String, Object?> toRow(ArticleModel a) => {
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
