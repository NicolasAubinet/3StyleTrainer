/// AES-128 single-block cipher (ECB), ported to Dart from csTimer's `sha256.js`
/// (`AES128`, cs0x7f/cstimer, GPL-3.0). Validated against the FIPS-197
/// known-answer vector, so it is standard AES-128.
///
/// [encrypt]/[decrypt] operate **in place on the first 16 bytes** of the passed
/// list and return it; a longer list is left untouched past byte 16 (this is
/// what the GAN/MoYu two-block scheme relies on).
class Aes128 {
  static const List<int> _sbox = [
    99, 124, 119, 123, 242, 107, 111, 197, 48, 1, 103, 43, 254, 215, 171, 118, //
    202, 130, 201, 125, 250, 89, 71, 240, 173, 212, 162, 175, 156, 164, 114, 192,
    183, 253, 147, 38, 54, 63, 247, 204, 52, 165, 229, 241, 113, 216, 49, 21,
    4, 199, 35, 195, 24, 150, 5, 154, 7, 18, 128, 226, 235, 39, 178, 117,
    9, 131, 44, 26, 27, 110, 90, 160, 82, 59, 214, 179, 41, 227, 47, 132,
    83, 209, 0, 237, 32, 252, 177, 91, 106, 203, 190, 57, 74, 76, 88, 207,
    208, 239, 170, 251, 67, 77, 51, 133, 69, 249, 2, 127, 80, 60, 159, 168,
    81, 163, 64, 143, 146, 157, 56, 245, 188, 182, 218, 33, 16, 255, 243, 210,
    205, 12, 19, 236, 95, 151, 68, 23, 196, 167, 126, 61, 100, 93, 25, 115,
    96, 129, 79, 220, 34, 42, 144, 136, 70, 238, 184, 20, 222, 94, 11, 219,
    224, 50, 58, 10, 73, 6, 36, 92, 194, 211, 172, 98, 145, 149, 228, 121,
    231, 200, 55, 109, 141, 213, 78, 169, 108, 86, 244, 234, 101, 122, 174, 8,
    186, 120, 37, 46, 28, 166, 180, 198, 232, 221, 116, 31, 75, 189, 139, 138,
    112, 62, 181, 102, 72, 3, 246, 14, 97, 53, 87, 185, 134, 193, 29, 158,
    225, 248, 152, 17, 105, 217, 142, 148, 155, 30, 135, 233, 206, 85, 40, 223,
    140, 161, 137, 13, 191, 230, 66, 104, 65, 153, 45, 15, 176, 84, 187, 22,
  ];

  static const List<int> _shiftTabI = [
    0, 13, 10, 7, 4, 1, 14, 11, 8, 5, 2, 15, 12, 9, 6, 3, //
  ];

  static final List<int> _sboxI = _buildSboxI();
  static final List<int> _xtime = _buildXtime();

  static List<int> _buildSboxI() {
    final s = List<int>.filled(256, 0);
    for (var i = 0; i < 256; i++) {
      s[_sbox[i]] = i;
    }
    return s;
  }

  static List<int> _buildXtime() {
    final x = List<int>.filled(256, 0);
    for (var i = 0; i < 128; i++) {
      x[i] = i << 1;
      x[128 + i] = (i << 1) ^ 0x1b;
    }
    return x;
  }

  final List<int> _key; // 176-byte expanded key schedule.

  Aes128(List<int> key) : _key = _expandKey(key);

  static List<int> _expandKey(List<int> key) {
    final ex = List<int>.filled(176, 0);
    for (var i = 0; i < 16; i++) {
      ex[i] = key[i];
    }
    var rcon = 1;
    for (var i = 16; i < 176; i += 4) {
      var tmp = ex.sublist(i - 4, i);
      if (i % 16 == 0) {
        tmp = [_sbox[tmp[1]] ^ rcon, _sbox[tmp[2]], _sbox[tmp[3]], _sbox[tmp[0]]];
        rcon = _xtime[rcon];
      }
      for (var j = 0; j < 4; j++) {
        ex[i + j] = ex[i + j - 16] ^ tmp[j];
      }
    }
    return ex;
  }

  void _addRoundKey(List<int> state, int off) {
    for (var i = 0; i < 16; i++) {
      state[i] ^= _key[off + i];
    }
  }

  void _shiftSubAdd(List<int> state, int off) {
    final s0 = state.sublist(0, 16);
    for (var i = 0; i < 16; i++) {
      state[i] = _sboxI[s0[_shiftTabI[i]]] ^ _key[off + i];
    }
  }

  void _shiftSubAddI(List<int> state, int off) {
    final s0 = state.sublist(0, 16);
    for (var i = 0; i < 16; i++) {
      state[_shiftTabI[i]] = _sbox[s0[i] ^ _key[off + i]];
    }
  }

  void _mixColumns(List<int> state) {
    for (var i = 12; i >= 0; i -= 4) {
      final s0 = state[i], s1 = state[i + 1], s2 = state[i + 2], s3 = state[i + 3];
      final h = s0 ^ s1 ^ s2 ^ s3;
      state[i] ^= h ^ _xtime[s0 ^ s1];
      state[i + 1] ^= h ^ _xtime[s1 ^ s2];
      state[i + 2] ^= h ^ _xtime[s2 ^ s3];
      state[i + 3] ^= h ^ _xtime[s3 ^ s0];
    }
  }

  void _mixColumnsInv(List<int> state) {
    for (var i = 0; i < 16; i += 4) {
      final s0 = state[i], s1 = state[i + 1], s2 = state[i + 2], s3 = state[i + 3];
      final h = s0 ^ s1 ^ s2 ^ s3;
      final xh = _xtime[h];
      final h1 = _xtime[_xtime[xh ^ s0 ^ s2]] ^ h;
      final h2 = _xtime[_xtime[xh ^ s1 ^ s3]] ^ h;
      state[i] ^= h1 ^ _xtime[s0 ^ s1];
      state[i + 1] ^= h2 ^ _xtime[s1 ^ s2];
      state[i + 2] ^= h1 ^ _xtime[s2 ^ s3];
      state[i + 3] ^= h2 ^ _xtime[s3 ^ s0];
    }
  }

  /// Decrypt the first 16 bytes of [block] in place; returns [block].
  List<int> decrypt(List<int> block) {
    _addRoundKey(block, 160);
    for (var i = 144; i >= 16; i -= 16) {
      _shiftSubAdd(block, i);
      _mixColumnsInv(block);
    }
    _shiftSubAdd(block, 0);
    return block;
  }

  /// Encrypt the first 16 bytes of [block] in place; returns [block].
  List<int> encrypt(List<int> block) {
    _shiftSubAddI(block, 0);
    for (var i = 16; i < 160; i += 16) {
      _mixColumns(block);
      _shiftSubAddI(block, i);
    }
    _addRoundKey(block, 160);
    return block;
  }
}
