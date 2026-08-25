import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

/// Host-side driver for the web integration tests.
///
/// Writes `test_driver/integration_response_data.json` and any screenshots
/// captured via `IntegrationTestWidgetsFlutterBinding.takeScreenshot(...)`
/// into `test_driver/`. Run with:
///
///   flutter drive \
///     --driver=test_driver/integration_test.dart \
///     --target=integration_test/chat_e2e.dart \
///     -d web-server \
///     --dart-define=API_BASE_URL=http://localhost:8000/api/v1 \
///     --dart-define=TENANT_SLUG=algeria
Future<void> main() async {
  await integrationDriver(
    onScreenshot: (String screenshotName, List<int> screenshotBytes,
        [Map<String, Object?>? args]) async {
      final File image = File('test_driver/$screenshotName.png');
      image.writeAsBytesSync(screenshotBytes);
      // Returning true tells the framework the screenshot was consumed.
      return true;
    },
  );
}
