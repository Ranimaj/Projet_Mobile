import 'package:flutter/foundation.dart';

/// Signale aux écrans qu'une écriture a eu lieu pour qu'ils relisent SQLite.
class DbChanges extends ChangeNotifier {
  void bump() => notifyListeners();
}
