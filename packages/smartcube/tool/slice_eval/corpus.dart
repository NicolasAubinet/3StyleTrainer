/// Realistic blind-solving sequences. Hand-written 3-style commutators /
/// conjugates and a few well-known perms — NOT tuned to any one solver's sheet.

class CorpusGroup {
  final String name;
  final List<String> algs;
  const CorpusGroup(this.name, this.algs);
}

const corpus = <CorpusGroup>[
  CorpusGroup('corners (slice-free)', [
    "R U' R' D2 R U R' D2",
    "D' R U R' D R U' R'",
    "R' D' R U R' D R U'",
    "U R U' L' U R' U' L",
    "R U R' D R U' R' D'",
    "L U' L' D L U L' D'",
    "F R U' R' U' R U R' F'",
    "R U R' F' R U R' U' R' F R2 U' R'",
    "D R' U' R D' R' U R",
    "U' L' U R U' L U R'",
    "R D R' U R D' R' U'",
    "L' U L D' L' U' L D",
    "R' U' R D2 R' U R D2",
    "F' L F R' F' L' F R",
    "R B' R' U R B R' U'",
    "U2 R U R' U2 R U' R'",
    // The owner's H-parity counterexample: starts R U D' but the U D' is a
    // genuine two-handed outer pair, not an E slice.
    "R U D' R' F' R U R' U' R' F R2 U' R' U' R D R'",
  ]),
  CorpusGroup('edges (slice-heavy)', [
    "M' U R U' M U R' U'",
    "M2 U R U' M2 U R' U'",
    "U R U' M' U R' U' M",
    "M' U' R U M U' R' U",
    "R U R' M2 R U' R' M2",
    "M U R' U' M' U R U'",
    "M2 U' L U M2 U' L' U",
    "M' U2 M U2",
    "M2 U M2 U2 M2 U M2",
    "M2 U M U2 M' U M2",
    "U M' U2 M U'",
    "D M' U2 M D'",
    "M' U M U M' U2 M U2",
    "R M' U R' U' M R U R'",
    "L' M U2 M' L",
    "M2 D M2 D' M2 D M2 D'",
  ]),
  CorpusGroup('E / S slices', [
    "E R U R' E' R U' R'",
    "E' L U L' E L U' L'",
    "S R U R' S' R U' R'",
    "S' U R U' S U R' U'",
    "E U R U' E' U R' U'",
    "S2 R U R' S2 R U' R'",
  ]),
  CorpusGroup('wide moves', [
    "Rw U R' U' Rw' F R F'",
    "Rw U2 R' U' R U' Rw'",
    "Uw R U R' U' Uw'",
    "Fw R U R' U' Fw'",
    "Rw' U' R U' R' U2 Rw",
    "Lw U L' U' Lw' F L F'",
  ]),
  // Real blind edge algs with wides, from blddb (github.com/nbwzx/blddb,
  // GPL-3.0) — the most-used human algs, usage-weighted, rotations excluded
  // (a rotation emits nothing, so no parse of the stream can contain it).
  // The last two are the §31k owner algs; both appear in blddb verbatim.
  CorpusGroup('blind wides (blddb)', [
    "R U' R' U M' U' R U r'",
    "r U' R' U M U' R U R'",
    "r U R' U' M U R U' R'",
    "l D l' S' l D' l' S",
    "l' U L U' M U L' U' L",
    "l' U R E' R2 E R U' l",
    "u' R' E' R2 E R' u",
    "u' R E R2 E' R u",
    "u L E L2 E' L u'",
    "U' r' E' r2 E' r' U",
    "U r' S r2 S r' U'",
    "r U' r' S' r U r' S",
    "S r U' r' S' r U r'",
    "D' l D l' S' l D' l' S D",
    "u L' E' L2 E L' u'",
    "E R E' R' U' R E R' u",
  ]),
  // The hard case: adjacent opposite-face outer pairs, which the synthesizer
  // executes as ONE two-handed motion most of the time — timing-identical to a
  // slice, but not a slice.
  CorpusGroup('adversarial: simultaneous outer pairs', [
    "R U D' R'",
    "R U D' R' U' D",
    "F U D' F' U D",
    "R L' U R' L",
    "U D' R U' D",
    "R U D' R' U D",
    "L R' U L' R",
    "U D' F U' D",
  ]),
  // Timing twins of the group above: these ARE slices.
  CorpusGroup('adversarial: real slices (twins)', [
    "R E R'",
    "R E R' E'",
    "M U R U' M'",
    "E R U R' E'",
    "M' R U R' M",
    "E' R U R' E",
  ]),
  CorpusGroup('non-rotation-neutral (M2 method style)', [
    "U M2 U'",
    "R U M2 U' R'",
    "D M2 D'",
    "U' M2 U",
    "R U R' M2",
  ]),
];

List<String> allAlgs() => [for (final g in corpus) ...g.algs];
