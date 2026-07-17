import 'package:flutter_test/flutter_test.dart';
import 'package:smartcube/src/driver.dart';
import 'package:smartcube/src/drivers/moyu_v10_driver.dart';

/// Name matching and MAC derivation, incl. the widened `WCU_MY3x` family that a
/// WeiLong V11 is expected to land in. No hardware exists for the V11, so these
/// pin the *safe* behavior: never fabricate a MAC off the V10 OUI for an
/// un-confirmed model.
void main() {
  final driver = MoyuV10Driver();

  CubeAdvertisement adv(String? name, {Map<int, List<int>> mfg = const {}}) =>
      CubeAdvertisement(id: 'dev', name: name, manufacturerData: mfg);

  group('name matching', () {
    test('claims the V10 name', () {
      expect(driver.matches(adv('WCU_MY32_ABCD')), isTrue);
    });

    test('claims a V11-family name (broad prefix already covers it)', () {
      expect(driver.matches(adv('WCU_MY33_ABCD')), isTrue);
      expect(driver.matches(adv('WCU_MY39_0000')), isTrue);
    });

    test('does not claim unrelated names', () {
      expect(driver.matches(adv('GAN_1234')), isFalse);
      expect(driver.matches(adv('QY-QYSC-1')), isFalse);
    });
  });

  group('deriveMac — confirmed V10', () {
    test('name-derives the V10 MAC from the CF:30:16:00 OUI', () {
      expect(MoyuV10Driver.deriveMac(adv('WCU_MY32_ABCD')),
          'CF:30:16:00:AB:CD');
    });

    test('is case-insensitive on the hex tail', () {
      expect(MoyuV10Driver.deriveMac(adv('WCU_MY32_abcd')),
          'CF:30:16:00:AB:CD');
    });

    test('needsExplicitMac is false when the name derives a MAC', () {
      expect(driver.needsExplicitMac(adv('WCU_MY32_ABCD')), isFalse);
    });
  });

  group('deriveMac — un-confirmed V11 family', () {
    // A V11 whose OUI we have not confirmed must NOT be given the V10 OUI: a
    // wrong MAC would connect straight into garbage with no manual prompt.
    test('does not name-derive a MAC for an un-confirmed model', () {
      expect(MoyuV10Driver.deriveMac(adv('WCU_MY33_ABCD')), isNull);
    });

    test('falls back to manufacturer data when present (the real MAC)', () {
      // Last 6 bytes, reversed → the true BLE MAC, regardless of model/OUI.
      final mac = MoyuV10Driver.deriveMac(adv('WCU_MY33_ABCD',
          mfg: {0x0102: const [0x00, 0x11, 0x22, 0x33, 0x44, 0x55, 0x66]}));
      expect(mac, '66:55:44:33:22:11');
    });

    test('needsExplicitMac is true without manufacturer data → manual prompt', () {
      expect(driver.needsExplicitMac(adv('WCU_MY33_ABCD')), isTrue);
    });
  });

  group('deriveMac — manufacturer-data fallback', () {
    test('reverses the last 6 bytes for a nameless device', () {
      final mac = MoyuV10Driver.deriveMac(adv(null,
          mfg: {0x0102: const [0xAA, 0xBB, 0x00, 0x11, 0x22, 0x33, 0x44, 0x55]}));
      expect(mac, '55:44:33:22:11:00');
    });

    test('is null when nothing derives a MAC', () {
      expect(MoyuV10Driver.deriveMac(adv(null)), isNull);
      expect(MoyuV10Driver.deriveMac(adv('WCU_MY33_ABCD',
          mfg: {0x0102: const [0x01, 0x02]})), // too short
          isNull);
    });
  });
}
