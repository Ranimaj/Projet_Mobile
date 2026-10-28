import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:campusconnect/core/theme/contrast.dart';

void main() {
  test('black on white is 21:1',
      () => expect(contrastRatio(Colors.black, Colors.white), closeTo(21, 0.01)));
  test('identical colours are 1:1',
      () => expect(contrastRatio(Colors.red, Colors.red), closeTo(1, 0.001)));
}
