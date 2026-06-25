import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String kLockPasswordHashKey = 'lock_password_hash';

Future<String> _hash(String password) async {
  final digest = await Sha256().hash(utf8.encode(password));
  return digest.bytes
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join();
}

/// Returns the stored password hash, or null when no password is set.
Future<String?> getLockPasswordHash() async {
  final prefs = await SharedPreferences.getInstance();
  final hash = prefs.getString(kLockPasswordHashKey);
  return (hash == null || hash.isEmpty) ? null : hash;
}

Future<void> setLockPassword(String password) async {
  final hash = await _hash(password);
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(kLockPasswordHashKey, hash);
}

Future<void> clearLockPassword() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.remove(kLockPasswordHashKey);
}

Future<bool> verifyLockPassword(String password) async {
  final stored = await getLockPasswordHash();
  if (stored == null) return false;
  return stored == await _hash(password);
}
