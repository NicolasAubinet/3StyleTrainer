import 'package:shared_preferences/shared_preferences.dart';

const String SPEFFZ = "ABCDEFGHIJKLMNOPQRSTUVWX";

class Settings {
  String _cornersScheme = SPEFFZ;
  String _edgesScheme = SPEFFZ;

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
}
