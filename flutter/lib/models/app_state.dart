import 'package:flutter/material.dart';

/// Global app state: theme, display mode, initialization flags.
class AppState extends ChangeNotifier {
  ThemeMode _themeMode = ThemeMode.system;
  DisplayMode _displayMode = DisplayMode.grid;
  bool _isInitialized = false;
  bool _isFirstLaunch = true;

  ThemeMode get themeMode => _themeMode;
  DisplayMode get displayMode => _displayMode;
  bool get isInitialized => _isInitialized;
  bool get isFirstLaunch => _isFirstLaunch;

  AppState() {
    _loadDefaults();
  }

  void _loadDefaults() {
    _isInitialized = true;
    _isFirstLaunch = true;
    notifyListeners();
  }

  void setThemeMode(ThemeMode mode) {
    _themeMode = mode;
    notifyListeners();
  }

  void setDisplayMode(DisplayMode mode) {
    _displayMode = mode;
    notifyListeners();
  }

  void setInitialized(bool value) {
    _isInitialized = value;
    notifyListeners();
  }

  void setFirstLaunch(bool value) {
    _isFirstLaunch = value;
    notifyListeners();
  }
}
