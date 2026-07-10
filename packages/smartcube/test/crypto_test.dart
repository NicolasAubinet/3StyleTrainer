import 'package:flutter_test/flutter_test.dart';
import 'package:smartcube/src/crypto/aes128.dart';
import 'package:smartcube/src/crypto/gan_cipher.dart';

// MoYu V10 base key/iv (LZString-decompressed from moyu32cube.js KEYS via node).
const _baseKey = [21, 119, 58, 92, 103, 14, 45, 31, 23, 103, 42, 19, 155, 103, 82, 87];
const _baseIv = [17, 35, 38, 37, 134, 42, 44, 59, 85, 6, 127, 49, 126, 103, 33, 87];

void main() {
  group('Aes128', () {
    test('FIPS-197 known-answer (standard AES-128)', () {
      final key = List<int>.generate(16, (i) => i);
      final pt = [0, 0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77, //
        0x88, 0x99, 0xaa, 0xbb, 0xcc, 0xdd, 0xee, 0xff];
      const ct = [0x69, 0xc4, 0xe0, 0xd8, 0x6a, 0x7b, 0x04, 0x30, //
        0xd8, 0xcd, 0xb7, 0x80, 0x70, 0xb4, 0xc5, 0x5a];
      expect(Aes128(key).encrypt(List<int>.of(pt)), ct);
      expect(Aes128(key).decrypt(List<int>.of(ct)), pt);
    });

    test('single-block round trip against csTimer vector', () {
      final key = List<int>.generate(16, (i) => (i * 7) & 255);
      final pt = List<int>.generate(16, (i) => (i * 13 + 1) & 255);
      const ct = [77, 247, 194, 59, 149, 27, 121, 13, //
        41, 236, 122, 18, 185, 119, 136, 104];
      expect(Aes128(key).encrypt(List<int>.of(pt)), ct);
      expect(Aes128(key).decrypt(List<int>.of(ct)), pt);
    });

    test('leaves bytes past the first block untouched', () {
      final key = List<int>.generate(16, (i) => i);
      final block = List<int>.generate(20, (i) => i);
      Aes128(key).encrypt(block);
      expect(block.sublist(16), [16, 17, 18, 19]);
    });
  });

  group('GanCipher', () {
    const mac = 'CF:30:16:00:AB:CD';

    test('macBytes parses colon-separated MAC', () {
      expect(GanCipher.macBytes(mac), [207, 48, 22, 0, 171, 205]);
    });

    test('forMac derives the csTimer key/iv', () {
      // Reproduces getKeyAndIv() so we can assert against node output.
      final macB = GanCipher.macBytes(mac);
      final key = List<int>.of(_baseKey);
      final iv = List<int>.of(_baseIv);
      for (var i = 0; i < 6; i++) {
        key[i] = (key[i] + macB[5 - i]) % 255;
        iv[i] = (iv[i] + macB[5 - i]) % 255;
      }
      expect(key, [226, 35, 58, 114, 151, 221, 45, 31, 23, 103, 42, 19, 155, 103, 82, 87]);
      expect(iv, [222, 206, 38, 59, 182, 249, 44, 59, 85, 6, 127, 49, 126, 103, 33, 87]);
    });

    test('decode matches csTimer for a 20-byte packet', () {
      final cipher = [92, 208, 61, 75, 172, 41, 136, 124, 41, 183, //
        170, 101, 62, 114, 54, 134, 65, 179, 86, 153];
      final plain = [161, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19];
      final cipher0 = GanCipher.forMac(_baseKey, _baseIv, GanCipher.macBytes(mac));
      expect(cipher0.decode(cipher), plain);
    });

    test('encode is the inverse of decode', () {
      final cipher = GanCipher.forMac(_baseKey, _baseIv, GanCipher.macBytes(mac));
      final plain = [161, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19];
      expect(cipher.encode(plain), [92, 208, 61, 75, 172, 41, 136, 124, 41, 183, //
        170, 101, 62, 114, 54, 134, 65, 179, 86, 153]);
      expect(cipher.decode(cipher.encode(plain)), plain);
    });

    test('does not mutate the caller\'s buffer', () {
      final cipher = GanCipher.forMac(_baseKey, _baseIv, GanCipher.macBytes(mac));
      final plain = List<int>.filled(20, 7);
      final snapshot = List<int>.of(plain);
      cipher.encode(plain);
      expect(plain, snapshot);
    });
  });
}
