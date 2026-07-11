import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:three_style_trainer/alg_structs.dart';
import 'package:three_style_trainer/smart_cube/cube_orientation.dart';

const String SPEFFZ = "ABCDEFGHIJKLMNOPQRSTUVWX";

class Settings {
  String _cornersScheme = SPEFFZ;
  String _edgesScheme = SPEFFZ;
  CornerBuffer _cornerBuffer = CornerBuffer.UFR;
  EdgeBuffer _edgeBuffer = EdgeBuffer.UF;
  bool _showRecordingDot = true;
  // Physical holding orientation for smart-cube completion detection.
  CubeColour _cubeTopColour = CubeColour.white;
  CubeColour _cubeFrontColour = CubeColour.green;

  static final Settings _singleton = Settings._internal();

  factory Settings() {
    return _singleton;
  }

  Settings._internal();

  Future<void> initPrefs() async {
    WidgetsFlutterBinding.ensureInitialized();

    SharedPreferences prefs = await SharedPreferences.getInstance();
    String? cornersScheme = prefs.getString("corners_scheme");
    if (cornersScheme != null) {
      setCornersScheme(cornersScheme);
    }

    String? edgesScheme = prefs.getString("edges_scheme");
    if (edgesScheme != null) {
      setEdgesScheme(edgesScheme);
    }

    String? cornerBufferStr = prefs.getString("corner_buffer");
    if (cornerBufferStr != null) {
      CornerBuffer cornerBuffer = CornerBuffer.values.firstWhere(
          (e) => e.name == cornerBufferStr,
          orElse: () => CornerBuffer.UFR);
      setCornerBuffer(cornerBuffer);
    }

    String? edgeBufferStr = prefs.getString("edge_buffer");
    if (edgeBufferStr != null) {
      EdgeBuffer edgeBuffer = EdgeBuffer.values.firstWhere(
          (e) => e.name == edgeBufferStr, orElse: () => EdgeBuffer.UF);
      setEdgeBuffer(edgeBuffer);
    }

    bool? showRecordingDot = prefs.getBool("show_recording_dot");
    if (showRecordingDot != null) {
      _showRecordingDot = showRecordingDot;
    }

    _cubeTopColour =
        _parseColour(prefs.getString("cube_top_colour"), CubeColour.white);
    _cubeFrontColour =
        _parseColour(prefs.getString("cube_front_colour"), CubeColour.green);
    // Guard against an invalid persisted pair (e.g. after an enum change).
    if (!CubeOrientation.isValid(_cubeTopColour, _cubeFrontColour)) {
      _cubeTopColour = CubeColour.white;
      _cubeFrontColour = CubeColour.green;
    }
  }

  static CubeColour _parseColour(String? name, CubeColour fallback) =>
      CubeColour.values.firstWhere((c) => c.name == name, orElse: () => fallback);

  List<String> getCornersScheme() {
    List<String> cornersScheme = [];
    for (int i = 0; i < _cornersScheme.length; i++) {
      cornersScheme.add(_cornersScheme[i]);
    }
    return cornersScheme;
  }

  void setCornersScheme(String value) async {
    value = value.trim();
    if (value.isEmpty) {
      value = SPEFFZ;
    }
    _cornersScheme = value;

    SharedPreferences prefs = await SharedPreferences.getInstance();
    prefs.setString("corners_scheme", _cornersScheme);
  }

  List<String> getEdgesScheme() {
    List<String> edgesScheme = [];
    for (int i = 0; i < _edgesScheme.length; i++) {
      edgesScheme.add(_edgesScheme[i]);
    }
    return edgesScheme;
  }

  void setEdgesScheme(String value) async {
    value = value.trim();
    if (value.isEmpty) {
      value = SPEFFZ;
    }
    _edgesScheme = value;

    SharedPreferences prefs = await SharedPreferences.getInstance();
    prefs.setString("edges_scheme", _edgesScheme);
  }

  CornerBuffer getCornerBuffer() {
    return _cornerBuffer;
  }

  void setCornerBuffer(CornerBuffer cornerBuffer) async {
    _cornerBuffer = cornerBuffer;

    SharedPreferences prefs = await SharedPreferences.getInstance();
    prefs.setString("corner_buffer", _cornerBuffer.name);
  }

  EdgeBuffer getEdgeBuffer() {
    return _edgeBuffer;
  }

  void setEdgeBuffer(EdgeBuffer edgeBuffer) async {
    _edgeBuffer = edgeBuffer;

    SharedPreferences prefs = await SharedPreferences.getInstance();
    prefs.setString("edge_buffer", _edgeBuffer.name);
  }

  bool getShowRecordingDot() {
    return _showRecordingDot;
  }

  void setShowRecordingDot(bool value) async {
    _showRecordingDot = value;

    SharedPreferences prefs = await SharedPreferences.getInstance();
    prefs.setBool("show_recording_dot", value);
  }

  CubeColour getCubeTopColour() => _cubeTopColour;

  CubeColour getCubeFrontColour() => _cubeFrontColour;

  // Set the holding orientation. Front falls back to the first valid face for
  // the chosen top when the requested pair isn't a valid (adjacent) orientation.
  void setCubeOrientation(CubeColour top, CubeColour front) async {
    if (!CubeOrientation.isValid(top, front)) {
      front = CubeOrientation.frontsFor(top).first;
    }
    _cubeTopColour = top;
    _cubeFrontColour = front;

    SharedPreferences prefs = await SharedPreferences.getInstance();
    prefs.setString("cube_top_colour", top.name);
    prefs.setString("cube_front_colour", front.name);
  }

  // Preference keys carried in an export's settings section. Spans schemes and
  // buffers (this class) plus theme and the menu/alg-times choices owned by
  // other widgets.
  static const List<String> exportedPrefKeys = [
    "corners_scheme",
    "edges_scheme",
    "corner_buffer",
    "edge_buffer",
    "app_theme",
    "target_time",
    "race_time",
    "show_next_alg",
    "record_times",
    "practice_type",
    "alg_times_sort_by_avg",
    "alg_times_sort_ascending",
    "show_recording_dot",
    "cube_top_colour",
    "cube_front_colour",
  ];

  // Snapshot of the persisted settings, for export. Only keys that are actually
  // set are included; missing ones default on restore.
  Future<Map<String, Object?>> exportSettings() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    Map<String, Object?> snapshot = {};
    for (String key in exportedPrefKeys) {
      Object? value = prefs.get(key);
      if (value != null) {
        snapshot[key] = value;
      }
    }
    return snapshot;
  }

  // Overwrite the persisted settings from an imported snapshot, then reload the
  // in-memory scheme/buffer state. Only known keys are applied; unknown keys are
  // ignored and absent keys leave the existing value untouched.
  Future<void> importSettings(Map<String, Object?> snapshot) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    for (String key in exportedPrefKeys) {
      if (!snapshot.containsKey(key)) {
        continue;
      }
      Object? value = snapshot[key];
      if (value is bool) {
        await prefs.setBool(key, value);
      } else if (value is String) {
        await prefs.setString(key, value);
      } else if (value is int) {
        await prefs.setInt(key, value);
      } else if (value is double) {
        await prefs.setDouble(key, value);
      }
    }
    await initPrefs();
  }
}
