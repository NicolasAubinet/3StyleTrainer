import 'aes128.dart';

/// The GAN Gen2/3 encryption scheme, shared by GAN cubes and the MoYu V10
/// (ported from csTimer `moyu32cube.js` / `gancube.js`, GPL-3.0).
///
/// A packet is transformed by AES-128 over its **first** 16-byte block and, when
/// longer than 16 bytes, its **last** 16-byte block, each XOR'd with a 16-byte
/// IV. The per-cube key and IV are derived from a base key/IV plus the cube's
/// MAC — see [GanCipher.forMac].
class GanCipher {
  final Aes128 _aes;
  final List<int> _iv;

  GanCipher(List<int> key, List<int> iv)
      : _aes = Aes128(key),
        _iv = List<int>.of(iv);

  /// Derive a per-cube cipher: `key[i] = (baseKey[i] + mac[5-i]) % 255` for the
  /// first 6 bytes (same for the IV), MAC in natural byte order.
  factory GanCipher.forMac(
      List<int> baseKey, List<int> baseIv, List<int> mac) {
    final key = List<int>.of(baseKey);
    final iv = List<int>.of(baseIv);
    for (var i = 0; i < 6; i++) {
      key[i] = (key[i] + mac[5 - i]) % 255;
      iv[i] = (iv[i] + mac[5 - i]) % 255;
    }
    return GanCipher(key, iv);
  }

  /// Decrypt a received packet (in place on a copy); returns the plaintext bytes.
  List<int> decode(List<int> data) {
    final ret = List<int>.of(data);
    if (ret.length > 16) {
      final off = ret.length - 16;
      final block = _aes.decrypt(ret.sublist(off));
      for (var i = 0; i < 16; i++) {
        ret[off + i] = block[i] ^ _iv[i];
      }
    }
    _aes.decrypt(ret);
    for (var i = 0; i < 16; i++) {
      ret[i] ^= _iv[i];
    }
    return ret;
  }

  /// Encrypt a request packet; returns the ciphertext bytes.
  List<int> encode(List<int> data) {
    final ret = List<int>.of(data);
    for (var i = 0; i < 16; i++) {
      ret[i] ^= _iv[i];
    }
    _aes.encrypt(ret);
    if (ret.length > 16) {
      final off = ret.length - 16;
      final block = ret.sublist(off);
      for (var i = 0; i < 16; i++) {
        block[i] ^= _iv[i];
      }
      _aes.encrypt(block);
      for (var i = 0; i < 16; i++) {
        ret[off + i] = block[i];
      }
    }
    return ret;
  }

  /// Parse a MAC string like `CF:30:16:00:AB:CD` into its 6 bytes. Any single
  /// separator works (two hex digits are read every 3 characters).
  static List<int> macBytes(String mac) {
    return [
      for (var i = 0; i < 6; i++) int.parse(mac.substring(i * 3, i * 3 + 2), radix: 16),
    ];
  }
}
