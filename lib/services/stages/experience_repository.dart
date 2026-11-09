import '../../core/constants/app_constants.dart';
import '../../models/stage_records.dart';
import '../local_store.dart';
import 'db_changes.dart';

/// Formations et expériences d'un étudiant (CRUD).
class ExperienceRepository {
  ExperienceRepository(this._store, this._changes);

  final LocalStore _store;
  final DbChanges _changes;
  static const _experiences = AppConstants.stageExperiencesCollection;

  List<Experience> forUser(String userId) => [
        for (final d in _store.where(_experiences, (e) => e['userId'] == userId)) Experience.fromMap(d.id, d.data),
      ]..sort((a, b) => a.title.compareTo(b.title));

  Future<void> save({
    String? id,
    required String userId,
    required ExperienceKind kind,
    required String title,
    required String organization,
    String period = '',
    String description = '',
  }) async {
    await _store.set(_experiences, id ?? LocalStore.newId(), {
      'userId': userId,
      'kind': kind.name,
      'title': title.trim(),
      'organization': organization.trim(),
      'period': period.trim(),
      'description': description.trim(),
    });
    _changes.bump();
  }

  Future<void> delete(String id) async {
    await _store.delete(_experiences, id);
    _changes.bump();
  }
}
