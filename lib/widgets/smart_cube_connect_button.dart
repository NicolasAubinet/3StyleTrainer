import 'dart:async';

import 'package:flutter/material.dart';
import 'package:smartcube/smartcube.dart';

import '../smart_cube_manager.dart';
import '../l10n/app_localizations.dart';
import '../theme/app_palette.dart';
import '../theme/theme_scope.dart';
import 'copyable_value.dart';

/// App-bar button reflecting the smart-cube connection: a subtle Bluetooth icon
/// when idle, and the battery % when connected. Tap opens the connect sheet.
class SmartCubeConnectButton extends StatelessWidget {
  const SmartCubeConnectButton({super.key});

  @override
  Widget build(BuildContext context) {
    final mgr = SmartCubeManager();
    final p = context.palette;
    final l10n = AppLocalizations.of(context)!;
    return ValueListenableBuilder<CubeConnection>(
      valueListenable: mgr.connection,
      builder: (context, conn, _) {
        final connected = conn == CubeConnection.ready;
        final reconnecting = conn == CubeConnection.reconnecting ||
            conn == CubeConnection.lost;
        final connecting = conn == CubeConnection.connecting || reconnecting;
        final icon = connected
            ? Icons.bluetooth_connected
            : connecting
                ? Icons.bluetooth_searching
                : Icons.bluetooth;
        final color = connected
            ? p.good
            : reconnecting
                ? p.pop
                : p.appBarFg;
        return Tooltip(
          message: l10n.smartCube,
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () => showSmartCubeConnectSheet(context),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, color: color, size: 22),
                  if (connected)
                    ValueListenableBuilder<int?>(
                      valueListenable: mgr.battery,
                      builder: (context, batt, _) => batt == null
                          ? const SizedBox.shrink()
                          : Padding(
                              padding: const EdgeInsets.only(left: 4),
                              child: Text('$batt%',
                                  style: TextStyle(
                                      color: color,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600)),
                            ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

Future<void> showSmartCubeConnectSheet(BuildContext context) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: context.palette.surfaceOpaque,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
    ),
    builder: (_) => const _SmartCubeConnectSheet(),
  );
}

class _SmartCubeConnectSheet extends StatefulWidget {
  const _SmartCubeConnectSheet();

  @override
  State<_SmartCubeConnectSheet> createState() => _SmartCubeConnectSheetState();
}

class _SmartCubeConnectSheetState extends State<_SmartCubeConnectSheet> {
  final SmartCubeManager _mgr = SmartCubeManager();
  final Map<String, DiscoveredCube> _found = {};
  StreamSubscription<DiscoveredCube>? _scanSub;
  bool _connecting = false;
  bool _closing = false;
  String? _error;

  CubeConnection get _conn => _mgr.connection.value;
  bool get _ready => _conn == CubeConnection.ready;
  bool get _reconnecting =>
      _conn == CubeConnection.reconnecting || _conn == CubeConnection.lost;

  @override
  void initState() {
    super.initState();
    _mgr.connection.addListener(_onConnectionChanged);
    // The manager dials the known cube on its own while reconnecting; scanning
    // over that would only race it.
    if (!_ready && !_reconnecting) _startScan();
  }

  // The cube can connect on a path this sheet never started — the reconnect
  // loop landing while we scan — so follow the manager, not just our own taps.
  void _onConnectionChanged() {
    if (!mounted || _closing) return;
    if (_ready) {
      _stopScan();
      _connecting = false;
      _error = null;
    } else if (!_reconnecting && !_connecting && _scanSub == null) {
      // The cube dropped for good under us: back to looking for one.
      _startScan();
    }
    setState(() {});
  }

  void _startScan() {
    _scanSub = _mgr.scan().listen(
      (d) => setState(() => _found[d.id] = d),
      onError: (Object e) => setState(() => _error = '$e'),
    );
  }

  Future<void> _stopScan() async {
    await _scanSub?.cancel();
    _scanSub = null;
    await _mgr.stopScan();
  }

  @override
  void dispose() {
    _mgr.connection.removeListener(_onConnectionChanged);
    _stopScan();
    super.dispose();
  }

  Future<void> _connect(DiscoveredCube d) async {
    String? mac;
    if (d.needsMac) {
      mac = await _promptMac();
      if (mac == null) return;
    }
    setState(() {
      _connecting = true;
      _error = null;
    });
    await _stopScan();
    try {
      await _mgr.connect(d, macAddress: mac);
      if (mounted) {
        final messenger = ScaffoldMessenger.of(context);
        final msg = AppLocalizations.of(context)!.smartCubeConnectedToast;
        Navigator.pop(context);
        messenger.showSnackBar(SnackBar(
          content: Text(msg),
          duration: const Duration(milliseconds: 1500),
        ));
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _connecting = false;
          _error = '${AppLocalizations.of(context)!.smartCubeConnectFailed}: $e';
        });
        _startScan();
      }
    }
  }

  Future<String?> _promptMac() {
    final l10n = AppLocalizations.of(context)!;
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.smartCubeMacTitle),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(hintText: l10n.smartCubeMacHint),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(l10n.smartCubeConnect)),
        ],
      ),
    ).then((_) =>
        controller.text.trim().isEmpty ? null : controller.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final p = context.palette;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _ready
                  ? l10n.smartCubeConnected
                  : _reconnecting
                      ? l10n.smartCube
                      : l10n.smartCubeConnectTitle,
              style: TextStyle(
                  color: p.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 16),
            if (_ready)
              _connectedBody(l10n, p)
            else if (_reconnecting)
              _reconnectingBody(l10n, p)
            else if (_connecting)
              _busy(l10n.smartCubeConnecting, p)
            else
              _scanBody(l10n, p),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: TextStyle(color: p.bad, fontSize: 13)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _busy(String label, AppPalette p) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(
                width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
            const SizedBox(width: 12),
            Text(label, style: TextStyle(color: p.textMuted)),
          ],
        ),
      );

  Widget _reconnectingBody(AppLocalizations l10n, AppPalette p) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _busy(l10n.smartCubeReconnecting, p),
        Text(l10n.smartCubeReconnectingHint,
            textAlign: TextAlign.center,
            style: TextStyle(color: p.textFaint, fontSize: 13)),
        const SizedBox(height: 20),
        _disconnectButton(l10n),
      ],
    );
  }

  Widget _disconnectButton(AppLocalizations l10n) => OutlinedButton.icon(
        onPressed: () async {
          // Hold the current body while we dismiss: the manager drops to
          // `disconnected` at once, and the sheet must not flash the scan view.
          setState(() => _closing = true);
          Navigator.pop(context);
          await _mgr.disconnect();
        },
        icon: const Icon(Icons.bluetooth_disabled),
        label: Text(l10n.smartCubeDisconnect),
      );

  Widget _scanBody(AppLocalizations l10n, AppPalette p) {
    if (_found.isEmpty) {
      return Column(
        children: [
          _busy(l10n.smartCubeScanning, p),
          Text(l10n.smartCubeNoneFound,
              textAlign: TextAlign.center,
              style: TextStyle(color: p.textFaint, fontSize: 13)),
        ],
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final d in _found.values)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.view_in_ar, color: p.accent),
            title: Text(d.modelName ?? d.brand.name,
                style: TextStyle(color: p.textPrimary)),
            subtitle: Text(d.name.isEmpty ? d.id : d.name,
                style: TextStyle(color: p.textFaint, fontSize: 12)),
            trailing: Icon(Icons.chevron_right, color: p.textFaint),
            onTap: () => _connect(d),
          ),
      ],
    );
  }

  Widget _connectedBody(AppLocalizations l10n, AppPalette p) {
    final mac = _mgr.macAddress;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(Icons.bluetooth_connected, color: p.good),
            const SizedBox(width: 10),
            Expanded(
              child: Text(_mgr.cubeName.value ?? l10n.smartCube,
                  style: TextStyle(color: p.textPrimary, fontSize: 15)),
            ),
            ValueListenableBuilder<int?>(
              valueListenable: _mgr.battery,
              builder: (context, batt, _) => Text(
                batt == null ? '' : '${l10n.smartCubeBattery}: $batt%',
                style: TextStyle(color: p.textMuted, fontSize: 13),
              ),
            ),
          ],
        ),
        if (mac != null) ...[
          const SizedBox(height: 6),
          CopyableValue(label: l10n.smartCubeMac, value: mac),
        ],
        const SizedBox(height: 20),
        _disconnectButton(l10n),
      ],
    );
  }
}
