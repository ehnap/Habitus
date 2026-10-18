import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

const subsonicVersion = '1.16.1';
const subsonicClient = 'Habitus';

String newSalt([Random? random]) {
  final source = random ?? Random.secure();
  final bytes = List<int>.generate(12, (_) => source.nextInt(256));
  return bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
}

String subsonicToken(String password, String salt) {
  return md5.convert(utf8.encode('$password$salt')).toString();
}
