import 'package:flutter_test/flutter_test.dart';
import 'package:smartcube/src/driver.dart';
import 'package:smartcube/src/drivers/moyu_v10_driver.dart';

/// Name matching and MAC derivation. The V11 (hardware-confirmed 2026-07-22)
/// advertises the *same* `WCU_MY32` name as the V10 but a `CF:30:16:02` OUI,
/// so real-MAC sources (manufacturer data, then a MAC-shaped device id) must
/// win over name-derivation — a name-derived V10 OUI on a V11 yields a wrong
/// cipher key and garbage decode.
void main() {
  final driver = MoyuV10Driver();

  CubeAdvertisement adv(String? name,
          {String id = 'dev', Map<int, List<int>> mfg = const {}}) =>
      CubeAdvertisement(id: id, name: name, manufacturerData: mfg);

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

  group('deriveMac — real-MAC sources win', () {
    test('manufacturer data beats the name-derived V10 OUI (the V11 case)', () {
      // A V11 advertises WCU_MY32_* but lives on CF:30:16:02 — the real MAC
      // from manufacturer data must win or the cipher key is wrong.
      final mac = MoyuV10Driver.deriveMac(adv('WCU_MY32_5288',
          mfg: {0x0102: const [0x88, 0x52, 0x16, 0x30, 0xCF, 0x88, 0x52, 0x02, 0x16, 0x30, 0xCF]}));
      expect(mac, 'CF:30:16:02:52:88');
    });

    test('a MAC-shaped device id beats the name (Windows/Android/Linux)', () {
      expect(MoyuV10Driver.deriveMac(adv('WCU_MY32_5288', id: 'cf:30:16:02:52:88')),
          'CF:30:16:02:52:88');
    });
  });

  group('deriveMac — name fallback (web-style opaque id, no mfr data)', () {
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

  group('modelName — V10 vs V11 told apart by OUI', () {
    test('V11 OUI labels as V11', () {
      expect(driver.modelName(adv('WCU_MY32_5288', id: 'CF:30:16:02:52:88')),
          'MoYu WeiLong V11');
    });

    test('V10 OUI labels as V10', () {
      expect(driver.modelName(adv('WCU_MY32_ABCD', id: 'CF:30:16:00:AB:CD')),
          'MoYu WeiLong V10');
    });

    test('no derivable MAC stays ambiguous', () {
      expect(driver.modelName(adv('WCU_MY33_ABCD')), 'MoYu WeiLong V10/V11');
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
