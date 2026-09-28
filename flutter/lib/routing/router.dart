import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../models/app_state.dart';
import '../models/models.dart';
import '../pages/audio_player_page.dart';
import '../pages/config_page.dart';
import '../pages/detail_page.dart';
import '../pages/home_page.dart';
import '../pages/live_page.dart';
import '../pages/login_page.dart';
import '../pages/node_debug_page.dart';
import '../pages/player_page.dart';
import '../pages/search_page.dart';
import '../pages/settings_detail_page.dart';
import '../pages/website_page.dart';

/// Route paths (kept identical to the original app's GoRouter layout).
const String pathHome = '/home';
const String pathSearch = '/search';
const String pathLive = '/live';
const String pathConfig = '/config';
const String pathWebsite = '/website';
const String pathPlayer = '/player';
const String pathDetail = '/detail/:siteKey/:vodId';
const String pathAudioPlayer = '/audio-player';
const String pathNode = '/node';
const String pathSettingsDetail = '/settings-detail';
const String pathLogin = '/login';

/// Creates the app's GoRouter with a bottom-navigation shell and the
/// full-screen player/detail routes.
GoRouter createRouter(AppState appState) {
  return GoRouter(
    initialLocation: pathHome,
    debugLogDiagnostics: true,
    routes: [
      ShellRoute(
        builder: (context, state, child) => MainShell(child: child),
        routes: [
          GoRoute(
            path: pathHome,
            name: 'home',
            pageBuilder: (context, state) =>
                MaterialPage(key: state.pageKey, child: const HomePage()),
          ),
          GoRoute(
            path: pathSearch,
            name: 'search',
            pageBuilder: (context, state) =>
                MaterialPage(key: state.pageKey, child: const SearchPage()),
          ),
          GoRoute(
            path: pathLive,
            name: 'live',
            pageBuilder: (context, state) =>
                MaterialPage(key: state.pageKey, child: const LivePage()),
          ),
          GoRoute(
            path: pathConfig,
            name: 'config',
            pageBuilder: (context, state) =>
                MaterialPage(key: state.pageKey, child: const ConfigPage()),
          ),
          GoRoute(
            path: pathWebsite,
            name: 'website',
            pageBuilder: (context, state) =>
                MaterialPage(key: state.pageKey, child: const WebsitePage()),
          ),
        ],
      ),
      GoRoute(
        path: pathPlayer,
        name: 'player',
        pageBuilder: (context, state) => MaterialPage(
          key: state.pageKey,
          child: PlayerPage(vod: state.extra as Vod?),
        ),
      ),
      GoRoute(
        path: pathDetail,
        name: 'detail',
        pageBuilder: (context, state) => MaterialPage(
          key: state.pageKey,
          child: DetailPage(
            siteKey: state.pathParameters['siteKey'] ?? '',
            vodId: state.pathParameters['vodId'] ?? '',
            initialVod: state.extra as Vod?,
          ),
        ),
      ),
      GoRoute(
        path: pathAudioPlayer,
        name: 'audioPlayer',
        pageBuilder: (context, state) =>
            MaterialPage(key: state.pageKey, child: const AudioPlayerPage()),
      ),
      GoRoute(
        path: pathNode,
        name: 'node',
        pageBuilder: (context, state) =>
            MaterialPage(key: state.pageKey, child: const NodeDebugPage()),
      ),
      GoRoute(
        path: pathSettingsDetail,
        name: 'settingsDetail',
        pageBuilder: (context, state) => MaterialPage(
            key: state.pageKey, child: const SettingsDetailPage()),
      ),
      GoRoute(
        path: pathLogin,
        name: 'login',
        pageBuilder: (context, state) =>
            MaterialPage(key: state.pageKey, child: const LoginPage()),
      ),
    ],
  );
}

/// Bottom navigation shell (used by the original TV app for the 5 tabs).
class MainShell extends StatelessWidget {
  final Widget child;

  const MainShell({super.key, required this.child});

  int _indexFor(BuildContext context, String location) {
    if (location.startsWith(pathSearch)) return 1;
    if (location.startsWith(pathLive)) return 2;
    if (location.startsWith(pathConfig) ||
        location.startsWith(pathSettingsDetail)) {
      return 3;
    }
    if (location.startsWith(pathWebsite)) return 4;
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final location = GoRouter.of(context).location;
    final index = _indexFor(context, location);
    final router = GoRouter.of(context);

    void go(String target) {
      if (location == target) return;
      router.go(target);
    }

    return Scaffold(
      body: child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (i) {
          switch (i) {
            case 0:
              go(pathHome);
            case 1:
              go(pathSearch);
            case 2:
              go(pathLive);
            case 3:
              go(pathConfig);
            case 4:
              go(pathWebsite);
          }
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: '首页',
          ),
          NavigationDestination(
            icon: Icon(Icons.search_outlined),
            selectedIcon: Icon(Icons.search),
            label: '搜索',
          ),
          NavigationDestination(
            icon: Icon(Icons.live_tv_outlined),
            selectedIcon: Icon(Icons.live_tv),
            label: '直播',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: '设置',
          ),
          NavigationDestination(
            icon: Icon(Icons.web_outlined),
            selectedIcon: Icon(Icons.web),
            label: '网站',
          ),
        ],
      ),
    );
  }
}
