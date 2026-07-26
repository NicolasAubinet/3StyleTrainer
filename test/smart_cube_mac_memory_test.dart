import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:three_style_trainer/settings.dart';

// Only web ever asks for a MAC, and asking twice for the same cube would be a
// bug: the answer is saved under the cube's advertised name.
void main() {
  test('a saved MAC is loaded back on the next launch', () async {
    SharedPreferences.setMockInitialValues({
      'smart_cube_macs': '{"WCU_MY32_5288":"CF:30:16:02:52:88"}',
    });
    await Settings().initPrefs();

    expect(Settings().getSmartCubeMac('WCU_MY32_5288'), 'CF:30:16:02:52:88');
    expect(Settings().getSmartCubeMac('WCU_MY32_ABCD'), isNull);
  });

  test('a typed MAC is written under the cube name', () async {
    SharedPreferences.setMockInitialValues({});
    await Settings().initPrefs();

    Settings().setSmartCubeMac('GAN_1234', 'AA:BB:CC:DD:EE:FF');
    expect(Settings().getSmartCubeMac('GAN_1234'), 'AA:BB:CC:DD:EE:FF');

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('smart_cube_macs'), contains('AA:BB:CC:DD:EE:FF'));
  });

  test('unreadable saved MACs do not block startup', () async {
    SharedPreferences.setMockInitialValues({'smart_cube_macs': 'not json'});
    await Settings().initPrefs();

    expect(Settings().getSmartCubeMac('WCU_MY32_5288'), isNull);
  });
}
