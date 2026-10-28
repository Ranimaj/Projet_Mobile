import 'package:campusconnect/widgets/skeleton_box.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/pump_themed.dart';

void main() {
  testWidgets('renders with the requested size in both themes', (t) async {
    for (final b in Brightness.values) {
      await pumpThemed(t, const SkeletonBox(width: 120, height: 20), brightness: b);
      expect(t.getSize(find.byType(SkeletonBox)), const Size(120, 20));
    }
  });
}
