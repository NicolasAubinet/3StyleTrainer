# 3-Style Trainer

A trainer for the **3-style** method of blindsolving the 3x3 Rubik's Cube. Drill
letter-pair algorithms, race the clock, and find the cases that are actually
holding your times back.

With a **Bluetooth smart cube** connected, the trainer reads your turns: the
timer starts and stops itself, each case is split into recognition and
execution, and a wrong execution is named back to you and logged.

Runs on **Windows**, **Android** and the **web**.

## Practice modes

- **Race** — drill random letter pairs for a fixed number of minutes. This is
  the mode that records your times.
- **Sets** — pick the letter/sticker sets you want and run the whole pool once
  in random order. Optionally drill each pair's inverse too, and repeat until
  every case is under your target time.
- **Slowest** — practise your weak cases, drawn either from your slowest
  averages or from your most failed ones. Take the top N, or everything slower
  than a time / failed at least N times.
- **Pairs** — the letter-pair list for a set, with no timer. With a smart cube
  connected it becomes an ordered reading drill: execute each pair in turn and
  the list follows you.

## Case types

Corners, edges, 2-flips, 2-twists and parity, plus **custom sets** — your own
named lists of algs, drillable in Sets mode.

## Smart cube support

Optional, and completely dormant until you pair a cube. Supported brands:
**MoYu**, **GAN**, **QiYi**, **GoCube / Rubik's Connected** and **Giiker**.

Once paired:

- **The timer runs itself.** Each case starts on your first turn and stops the
  instant the alg lands.
- **Recognition and execution are timed apart**, and both are recorded.
- **Errors are caught.** Execute the wrong alg and it tells you which pair you
  actually did, requeues the case, and logs the mistake.
- **Every case keeps its moves**, reconstructed from the cube (slices and wide
  moves included) so you can see where an alg went wrong.
- **Wrong hold detection.** If a case would have completed under a different
  top/front colour, the trainer says so and offers to switch.

In a browser, some cubes ask you to type in their MAC address, because Web
Bluetooth hides it and their protocol needs it to decrypt.

The Bluetooth layer lives in `packages/smartcube`, a deliberately
domain-agnostic package that turns cube bytes into move and state events and
knows nothing about 3-style.

## Stats

Recorded solves feed the **Alg stats** screen: per-case solve count, best/worst,
and an average coloured against your own distribution, with recognition and
execution columns for smart-cube solves. Filter by case type and period, sort by
any column, and open a case for its full attempt history.

Once a smart cube has logged mistakes, an **Errors** view lists them per case,
broken down by kind, each slip openable to see the moves the cube saw. Errors
also feed the *Most failed* practice source.

Every run ends on a **session summary**: totals, spread, hit-target count, the
errored cases, and a sortable table of every solve.

## Settings

- **Appearance** — three themes: Slate, Keycap, Cube Face.
- **Lettering schemes** — 24-character corner and edge schemes; SpeFFz by
  default, override with your own.
- **Buffers** — corner and edge buffer pieces.
- **Smart cube orientation** — the top and front colours you hold when solving,
  so completed cases are detected correctly whatever your grip.
- **Export / import** — your times, errors and custom sets as a JSON file.

Everything is stored locally: settings in shared preferences, times, errors and
custom sets in SQLite. Nothing is uploaded, and there is no account.

## Building from source

Requires the Flutter SDK (Dart `>=3.4.4`).

```sh
flutter pub get
flutter run -d windows          # or: -d chrome, or an Android device
```

```sh
flutter test                    # tests
flutter analyze                 # lint
flutter build windows|apk|web   # release builds
```

User-facing strings live in `lib/l10n/app_en.arb`; regenerate with
`flutter gen-l10n` after editing (a build does it too). Only English is
currently supported.

## Also by me

**[Cubench](https://play.google.com/store/apps/details?id=com.cube.nanotimer)** —
my speedcubing timer for Android.

## Feedback

Bug reports and suggestions are welcome: NanoTimerCube@gmail.com

## License

GPL-3.0. See [LICENSE](LICENSE).
