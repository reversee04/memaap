import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'screens/login_screen.dart';
import 'screens/register_screen.dart';
import 'screens/home_screen.dart';
import 'screens/confirm_request_screen.dart';
import 'screens/tracking_screen.dart';
import 'screens/timeline_screen.dart';
import 'screens/hospitals_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/responder_dashboard.dart';
import 'widgets/bottom_nav_bar.dart';

final _rootNavigatorKey = GlobalKey<NavigatorState>();
final _shellNavigatorHomeKey = GlobalKey<NavigatorState>(debugLabel: 'shellHome');
final _shellNavigatorHospitalsKey = GlobalKey<NavigatorState>(debugLabel: 'shellHospitals');
final _shellNavigatorTrackingKey = GlobalKey<NavigatorState>(debugLabel: 'shellTracking');
final _shellNavigatorProfileKey = GlobalKey<NavigatorState>(debugLabel: 'shellProfile');

final goRouter = GoRouter(
  initialLocation: '/login',
  navigatorKey: _rootNavigatorKey,
  routes: [
    GoRoute(
      path: '/login',
      builder: (context, state) => const LoginScreen(),
    ),
    GoRoute(
      path: '/register',
      builder: (context, state) => const RegisterScreen(),
    ),
    GoRoute(
      path: '/responder',
      builder: (context, state) => const ResponderDashboard(),
    ),
    StatefulShellRoute.indexedStack(
      builder: (context, state, navigationShell) {
        return BottomNavBar(navigationShell: navigationShell);
      },
      branches: [
        StatefulShellBranch(
          navigatorKey: _shellNavigatorHomeKey,
          routes: [
            GoRoute(
              path: '/home',
              builder: (context, state) => const HomeScreen(),
              routes: [
                GoRoute(
                  path: 'confirm',
                  builder: (context, state) => const ConfirmRequestScreen(),
                ),
              ],
            ),
          ],
        ),
        StatefulShellBranch(
          navigatorKey: _shellNavigatorHospitalsKey,
          routes: [
            GoRoute(
              path: '/hospitals',
              builder: (context, state) => const HospitalsScreen(),
            ),
          ],
        ),
        StatefulShellBranch(
          navigatorKey: _shellNavigatorTrackingKey,
          routes: [
            GoRoute(
              path: '/tracking',
              builder: (context, state) => TrackingScreen(requestId: state.extra != null ? (state.extra as Map)['requestId'] ?? '' : ''),
              routes: [
                GoRoute(
                  path: 'timeline',
                  builder: (context, state) => const TimelineScreen(),
                ),
              ],
            ),
          ],
        ),
        StatefulShellBranch(
          navigatorKey: _shellNavigatorProfileKey,
          routes: [
            GoRoute(
              path: '/profile',
              builder: (context, state) => const ProfileScreen(),
            ),
          ],
        ),
      ],
    ),
  ],
);
