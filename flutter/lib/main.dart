import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'models/app_state.dart';
import 'routing/router.dart';
import 'services/audio_service.dart';
import 'services/config_service.dart';
import 'services/database_service.dart';
import 'services/node_service.dart';
import 'services/pan_service.dart';
import 'services/player_service.dart';
import 'services/website_api.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const TVSApp());
}

class TVSApp extends StatefulWidget {
  const TVSApp({super.key});

  @override
  State<TVSApp> createState() => _TVSAppState();
}

class _TVSAppState extends State<TVSApp> {
  late final AppState _appState;
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    _appState = AppState();
    _router = createRouter(_appState);
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: _appState),
        ChangeNotifierProvider(create: (_) => NodeService()),
        ChangeNotifierProvider(create: (_) => ConfigService()),
        ChangeNotifierProvider(create: (_) => DatabaseService()),
        ChangeNotifierProvider(create: (_) => PanService()),
        ChangeNotifierProvider(create: (_) => PlayerService()),
        ChangeNotifierProvider(create: (_) => AudioService()),
        ChangeNotifierProvider(create: (_) => WebsiteApiService()),
      ],
      child: Consumer<AppState>(
        builder: (context, appState, child) {
          return MaterialApp.router(
            title: 'TVS',
            debugShowCheckedModeBanner: false,
            theme: _buildLightTheme(),
            darkTheme: _buildDarkTheme(),
            themeMode: appState.themeMode,
            routerConfig: _router,
          );
        },
      ),
    );
  }

  ThemeData _buildDarkTheme() {
    return ThemeData(
      brightness: Brightness.dark,
      primaryColor: const Color(0xFF58A6FF),
      scaffoldBackgroundColor: const Color(0xFF0D1117),
      cardColor: const Color(0xFF161B22),
      dividerColor: Colors.white12,
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: Colors.white.withOpacity(0.3),
        trackColor: Colors.white.withOpacity(0.05),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFF161B22),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: Color(0xFF1C2128),
      ),
      dialogTheme: const DialogTheme(
        backgroundColor: Color(0xFF1C2128),
        titleTextStyle: TextStyle(color: Colors.white, fontSize: 18),
        contentTextStyle: TextStyle(color: Colors.white70, fontSize: 14),
      ),
      textTheme: const TextTheme(
        bodyLarge: TextStyle(color: Colors.white),
        bodyMedium: TextStyle(color: Colors.white70),
        titleLarge: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        titleMedium:
            TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        titleSmall: TextStyle(color: Colors.white70, fontWeight: FontWeight.w500),
      ),
      iconTheme: const IconThemeData(color: Colors.white70),
      useMaterial3: true,
    );
  }

  ThemeData _buildLightTheme() {
    return ThemeData(
      brightness: Brightness.light,
      primaryColor: const Color(0xFF2563EB),
      scaffoldBackgroundColor: const Color(0xFFF6F8FA),
      cardColor: Colors.white,
      dividerColor: Colors.black12,
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0,
      ),
      useMaterial3: true,
    );
  }
}
