import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pharos_flutter/main.dart';
import 'package:pharos_flutter/services/pharos_vision_service.dart';
import 'package:pharos_flutter/services/model_settings.dart';

void main() {
  testWidgets('PharosApp builds smoke test', (WidgetTester tester) async {
    final PharosVisionService visionService = PharosVisionService();
    final ModelSettingsService settingsService = ModelSettingsService();

    // Build our app and trigger a frame.
    await tester.pumpWidget(PharosApp(
      visionService: visionService,
      settingsService: settingsService,
    ));

    // Verify that the app initializes
    expect(find.byType(Scaffold), findsWidgets);
  });
}
