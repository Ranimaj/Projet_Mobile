import 'package:campusconnect/core/utils/firestore_codec.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Timestamp survit à un aller-retour encode/decode (file hors-ligne)', () {
    final ts = Timestamp.fromDate(DateTime(2026, 10, 1, 9, 30));
    final encoded = FirestoreCodec.encodeMap({
      'createdAt': ts,
      'nested': {'at': ts},
      'tags': ['a', 'b'],
    });
    expect(encoded['createdAt'], isA<Map>());

    final decoded = FirestoreCodec.decodeMap(encoded);
    expect(decoded['createdAt'], ts);
    expect((decoded['nested'] as Map)['at'], ts);
    expect(decoded['tags'], ['a', 'b']);
  });

  test('un payload sans Timestamp (carte étudiante) reste identique', () {
    final payload = {'uid': 'u1', 'file': 'card.jpg', 'submittedAt': '2026-10-01T09:30:00Z'};
    expect(FirestoreCodec.decodeMap(FirestoreCodec.encodeMap(payload)), payload);
  });
}
