import 'package:shared_preferences/shared_preferences.dart';
import 'package:three_style_trainer/alg_structs.dart';

const String SPEFFZ = "ABCDEFGHIJKLMNOPQRSTUVWX";

class Settings {
  String _cornersScheme = SPEFFZ;
  String _edgesScheme = SPEFFZ;
  CornerBuffer _cornerBuffer = CornerBuffer.UFR;
  EdgeBuffer _edgeBuffer = EdgeBuffer.UF;

  static final Settings _singleton = Settings._internal();

  factory Settings() {
    return _singleton;
  }

  Settings._internal();

  void initPrefs() async {
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
          (e) => e.toString() == cornerBufferStr,
          orElse: () => CornerBuffer.UFR);
      setCornerBuffer(cornerBuffer);
    }

    String? edgeBufferStr = prefs.getString("edge_buffer");
    if (edgeBufferStr != null) {
      EdgeBuffer edgeBuffer = EdgeBuffer.values.firstWhere(
          (e) => e.toString() == edgeBufferStr,
          orElse: () => EdgeBuffer.UF);
      setEdgeBuffer(edgeBuffer);
    }
  }

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
}
