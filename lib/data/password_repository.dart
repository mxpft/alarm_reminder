import 'package:hive/hive.dart';
import '../models/password_entry.dart';

class PasswordRepository {
  static const String boxName = 'passwords';

  late final Box<PasswordEntry> _box;

  Future<void> open() async {
    _box = await Hive.openBox<PasswordEntry>(boxName);
  }

  Box<PasswordEntry> get box => _box;

  List<PasswordEntry> getAll() => _box.values.toList();

  Future<void> save(PasswordEntry entry) => _box.put(entry.id, entry);

  Future<void> delete(String id) => _box.delete(id);

  int get count => _box.length;

  static String generateId() {
    final ts = DateTime.now().microsecondsSinceEpoch;
    final rand = (DateTime.now().millisecondsSinceEpoch * 2654435761) & 0xffffffff;
    return '${ts}_$rand';
  }
}
