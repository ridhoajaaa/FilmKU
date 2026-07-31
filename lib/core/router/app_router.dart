import 'package:go_router/go_router.dart';

import '../../features/movies/presentation/screens/app_shell.dart';
import '../../features/movies/presentation/screens/detail_screen.dart';
import '../../features/movies/presentation/screens/home_screen.dart';
import '../../features/movies/presentation/screens/player_screen.dart';
import '../../features/movies/presentation/screens/search_screen.dart';
import '../../features/movies/presentation/screens/settings_screen.dart';
import '../../features/movies/presentation/screens/watchlist_screen.dart';

/// GoRouter configuration. The bottom-tab screens live inside a
/// [StatefulShellRoute.indexedStack] so each tab keeps its scroll state;
/// detail & player are root-level routes so they cover the whole screen.
final appRouter = GoRouter(
  initialLocation: '/home',
  routes: [
    StatefulShellRoute.indexedStack(
      builder: (context, state, navigationShell) =>
          AppShell(navigationShell: navigationShell),
      branches: [
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/home',
              name: 'home',
              builder: (context, state) => const HomeScreen(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/search',
              name: 'search',
              builder: (context, state) => const SearchScreen(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/watchlist',
              name: 'watchlist',
              builder: (context, state) => const WatchlistScreen(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/settings',
              name: 'settings',
              builder: (context, state) => const SettingsScreen(),
            ),
          ],
        ),
      ],
    ),
    GoRoute(
      path: '/movie/:id',
      name: 'movieDetail',
      builder: (context, state) =>
          DetailScreen(movieId: int.parse(state.pathParameters['id']!)),
    ),
    GoRoute(
      path: '/player/:id',
      name: 'player',
      builder: (context, state) =>
          PlayerScreen(movieId: int.parse(state.pathParameters['id']!)),
    ),
  ],
);
