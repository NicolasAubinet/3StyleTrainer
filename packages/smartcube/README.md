# smartcube

Bluetooth smart-cube connectivity for Flutter (Android / Windows / desktop, and
Web later). Scans, connects, decrypts and decodes a smart cube's BLE stream into
**timestamped move events** and **full cube-state snapshots**.

Deliberately **domain-agnostic**: it knows nothing about 3-style, letter pairs,
timing, or any trainer. It only turns cube bytes into `CubeMove` / `CubeState`.
Consumers build their own logic on top. This is what lets it live in its own
repo and be reused by other projects.

## Status

Early scaffold (Phase 1). Public interfaces are defined; the per-brand drivers,
crypto, cube-state model, and BLE transport are being ported next. See
`docs/smart-cube-integration-plan.md` (§10–11) in the parent project for the
protocol spec and port plan.

Bring-up order: cube-state model → GAN/MoYu crypto → `flutter_blue_plus`
transport → **MoYu WeiLong V10 AI** driver (`WCU_MY32`) → broaden to GAN/QiYi/…

## Architecture

```
CubeScanner ── scans BLE, auto-detects brand ──▶ SmartCube
                                                   ├─ Stream<CubeMove>
                                                   └─ Stream<CubeState>
CubeDriver (registry): GanDriver | MoyuV10Driver | QiyiDriver | …
   matches(advertisement) → build()   (each driver is PURE: bytes → events)
transport/  ── the ONLY flutter_blue_plus dependency (swappable for Web BT)
```

## License

GPL-3.0-or-later. Portions are ported to Dart from **csTimer**
(https://github.com/cs0x7f/cstimer), which is GPL-3.0. Because Dart compiles the
package into the host app, apps depending on `smartcube` are also GPL.

The GAN Gen2 driver is ported from **gan-web-bluetooth**
(https://github.com/afedotov/gan-web-bluetooth), which is MIT. Its notice is kept
in `LICENSE-gan-web-bluetooth.txt` as that licence requires; MIT code may be
redistributed under GPL-3.0.
