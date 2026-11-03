import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/presentation/screens/splash_screen.dart';
import '../../features/auth/presentation/screens/login_screen.dart';
import '../../features/auth/presentation/screens/register_screen.dart';
import '../../features/auth/presentation/screens/forgot_password_screen.dart';
import '../../features/auth/presentation/screens/welcome_screen.dart';
import '../../features/onboarding/presentation/screens/onboarding_basic_screen.dart';
import '../../features/onboarding/presentation/screens/onboarding_bio_screen.dart';
import '../../features/onboarding/presentation/screens/onboarding_education_screen.dart';
import '../../features/onboarding/presentation/screens/onboarding_career_screen.dart';
import '../../features/onboarding/presentation/screens/onboarding_family_screen.dart';
import '../../features/onboarding/presentation/screens/onboarding_lifestyle_screen.dart';
import '../../features/onboarding/presentation/screens/onboarding_native_place_screen.dart';
import '../../features/onboarding/presentation/screens/onboarding_preferences_screen.dart';
import '../../features/onboarding/presentation/screens/onboarding_photos_screen.dart';
import '../../features/onboarding/presentation/screens/onboarding_community_screen.dart';
import '../../features/profile/presentation/screens/who_viewed_me_screen.dart';
import '../../features/interests/presentation/screens/mutual_matches_screen.dart';
import '../../features/verification/presentation/screens/verification_select_screen.dart';
import '../../features/verification/presentation/screens/verification_reference_screen.dart';
import '../../features/verification/presentation/screens/verification_certificate_screen.dart';
import '../../features/verification/presentation/screens/verification_status_screen.dart';
import '../../features/home/presentation/screens/main_shell_screen.dart';
import '../../features/home/presentation/screens/home_screen.dart';
import '../../features/search/presentation/screens/search_screen.dart';
import '../../features/interests/presentation/screens/interests_screen.dart';
import '../../features/messaging/presentation/screens/conversations_screen.dart';
import '../../features/profile/presentation/screens/my_profile_screen.dart';
import '../../features/shortlist/presentation/screens/shortlist_screen.dart';
import '../../features/profile/presentation/screens/profile_detail_screen.dart';
import '../../features/biodata/presentation/screens/biodata_screen.dart';
import '../../features/settings/presentation/screens/settings_screen.dart';
import '../../features/settings/presentation/screens/privacy_screen.dart';
import '../../features/settings/presentation/screens/help_screen.dart';
import '../../features/settings/presentation/screens/report_screen.dart';
import '../../features/profile/presentation/screens/edit_profile_screen.dart';
import '../../features/notifications/presentation/screens/notifications_screen.dart';
import '../providers/auth_provider.dart';
import '../../shared/constants/app_constants.dart';

/// Root navigator key — used by AuthNotifier to force a synchronous
/// GoRouter.refresh() after the auth state flips to unauthenticated (logout /
/// token expiry), so the redirect always re-runs even when the ref.listen
/// bridge is missed mid-disposal. Pass this to GoRouter so it owns the root
/// Navigator.
final rootNavigatorKey = GlobalKey<NavigatorState>();

final routerProvider = Provider<GoRouter>((ref) {
  final notifier = _AuthChangeNotifier();

  ref.listen<AsyncValue<AuthState>>(authProvider, (previous, next) {
    final prevStatus = previous?.valueOrNull?.status;
    final nextStatus = next.valueOrNull?.status;
    final wasError = previous is AsyncError;
    final isError = next is AsyncError;
    if (prevStatus != nextStatus || wasError != isError) {
      notifier.notify();
    }
  });

  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: AppRoutes.splash,
    debugLogDiagnostics: true,
    refreshListenable: notifier,
    redirect: (context, state) {
      final authAsync = ref.read(authProvider);
      final auth = authAsync.valueOrNull;

      if (authAsync is AsyncError) return AppRoutes.login;

      // AsyncLoading: auth state is not yet resolved.
      // On first app start, go to splash. But if we're already past splash
      // (e.g. a background token refresh briefly emits AsyncLoading), stay
      // put — returning null prevents a flash to splash/black screen.
      if (authAsync is AsyncLoading || auth == null) {
        final loc = state.matchedLocation;
        debugPrint('[Router] AsyncLoading at loc=$loc');
        if (loc == AppRoutes.splash) return null; // already on splash, stay
        // Already on a real screen — don't interrupt with splash.
        return null;
      }

      final loc = state.matchedLocation;
      final isSplash = loc == AppRoutes.splash;
      final isOnAuthRoute = loc == AppRoutes.login ||
          loc == AppRoutes.register ||
          loc == AppRoutes.forgotPassword ||
          loc == AppRoutes.welcome;
      final isOnOnboardingRoute =
          loc.startsWith('/onboarding') || loc.startsWith('/verification');

      debugPrint('[Router] redirect loc=$loc status=${auth.status}');
      switch (auth.status) {
        case AuthStatus.loading:
          return isSplash ? null : AppRoutes.splash;
        case AuthStatus.unauthenticated:
          if (isOnAuthRoute) return null;
          return AppRoutes.login;
        case AuthStatus.onboardingRequired:
          // Allow forgot-password while onboarding state is unclear
          if (loc == AppRoutes.forgotPassword) return null;
          if (isOnOnboardingRoute) return null;
          return AppRoutes.onboardingBasic;
        case AuthStatus.authenticated:
          if (isSplash || isOnAuthRoute) return AppRoutes.home;
          return null;
      }
    },
    routes: [
      // Auth routes use instant replacement — no animation means no black
      // canvas showing through during the transition from the shell.
      GoRoute(
        path: AppRoutes.splash,
        pageBuilder: (_, s) => _instantPage(s, const SplashScreen()),
      ),
      GoRoute(
        path: AppRoutes.login,
        pageBuilder: (_, s) => _instantPage(s, const LoginScreen()),
      ),
      GoRoute(
        path: AppRoutes.register,
        pageBuilder: (_, s) => _instantPage(s, const RegisterScreen()),
      ),
      GoRoute(
        path: AppRoutes.forgotPassword,
        pageBuilder: (_, s) => _instantPage(s, const ForgotPasswordScreen()),
      ),
      GoRoute(
        path: AppRoutes.welcome,
        pageBuilder: (_, s) => _instantPage(s, const WelcomeScreen()),
      ),

      // Onboarding + verification + detail/settings routes use _instantPage
      // for the same reason as the shell: logout can be triggered from the
      // settings screen, and any default MaterialPage fade leaves a one-frame
      // black canvas when the redirect replaces the stack with /login.
      GoRoute(
        path: AppRoutes.onboardingBasic,
        pageBuilder: (_, s) =>
            _instantPage(s, OnboardingBasicScreen(isEditing: s.extra == true)),
      ),
      GoRoute(
        path: AppRoutes.onboardingBio,
        pageBuilder: (_, s) =>
            _instantPage(s, OnboardingBioScreen(isEditing: s.extra == true)),
      ),
      GoRoute(
        path: AppRoutes.onboardingEducation,
        pageBuilder: (_, s) => _instantPage(
            s, OnboardingEducationScreen(isEditing: s.extra == true)),
      ),
      GoRoute(
        path: AppRoutes.onboardingCareer,
        pageBuilder: (_, s) => _instantPage(
            s, OnboardingCareerScreen(isEditing: s.extra == true)),
      ),
      GoRoute(
        path: AppRoutes.onboardingFamily,
        pageBuilder: (_, s) => _instantPage(
            s, OnboardingFamilyScreen(isEditing: s.extra == true)),
      ),
      GoRoute(
        path: AppRoutes.onboardingLifestyle,
        pageBuilder: (_, s) => _instantPage(
            s, OnboardingLifestyleScreen(isEditing: s.extra == true)),
      ),
      GoRoute(
        path: AppRoutes.onboardingNativePlace,
        pageBuilder: (_, s) => _instantPage(
            s, OnboardingNativePlaceScreen(isEditing: s.extra == true)),
      ),
      GoRoute(
        path: AppRoutes.onboardingPreferences,
        pageBuilder: (_, s) => _instantPage(
            s, OnboardingPreferencesScreen(isEditing: s.extra == true)),
      ),
      GoRoute(
        path: AppRoutes.onboardingPhotos,
        pageBuilder: (_, s) => _instantPage(
            s, OnboardingPhotosScreen(isEditing: s.extra == true)),
      ),
      GoRoute(
        path: AppRoutes.onboardingCommunity,
        pageBuilder: (_, s) => _instantPage(
            s, OnboardingCommunityScreen(isEditing: s.extra == true)),
      ),

      // Verification
      GoRoute(
        path: AppRoutes.verificationSelect,
        pageBuilder: (_, s) => _instantPage(s, const VerificationSelectScreen()),
      ),
      GoRoute(
        path: AppRoutes.verificationReference,
        pageBuilder: (_, s) =>
            _instantPage(s, const VerificationReferenceScreen()),
      ),
      GoRoute(
        path: AppRoutes.verificationCertificate,
        pageBuilder: (_, s) =>
            _instantPage(s, const VerificationCertificateScreen()),
      ),
      GoRoute(
        path: AppRoutes.verificationStatus,
        pageBuilder: (_, s) => _instantPage(s, const VerificationStatusScreen()),
      ),

      // Main app shell — pageBuilder with zero-duration transition so the
      // shell exits instantly when the redirect replaces it with /login.
      // Using builder (MaterialPage default) causes a one-frame black canvas
      // during the shell→login swap on logout.
      StatefulShellRoute.indexedStack(
        pageBuilder: (context, state, navigationShell) => _instantPage(
          state,
          MainShellScreen(navigationShell: navigationShell),
        ),
        branches: [
          StatefulShellBranch(routes: [
            GoRoute(path: AppRoutes.home, builder: (_, __) => const HomeScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: AppRoutes.search, builder: (_, __) => const SearchScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: AppRoutes.interests, builder: (_, __) => const InterestsScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: AppRoutes.connections, builder: (_, __) => const ConversationsScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: AppRoutes.myProfile, builder: (_, __) => const MyProfileScreen()),
            GoRoute(path: AppRoutes.shortlist, builder: (_, __) => const ShortlistScreen()),
          ]),
        ],
      ),

      // Detail / settings routes
      GoRoute(path: AppRoutes.editProfile, pageBuilder: (_, s) => _instantPage(s, const EditProfileScreen())),
      GoRoute(path: AppRoutes.biodata, pageBuilder: (_, s) => _instantPage(s, const BiodataScreen())),
      GoRoute(
        path: '/profile/:userId',
        pageBuilder: (context, state) => _instantPage(
            state, ProfileDetailScreen(userId: state.pathParameters['userId']!)),
      ),
      GoRoute(path: AppRoutes.notifications, pageBuilder: (_, s) => _instantPage(s, const NotificationsScreen())),
      GoRoute(path: AppRoutes.settings, pageBuilder: (_, s) => _instantPage(s, const SettingsScreen())),
      GoRoute(path: AppRoutes.privacy, pageBuilder: (_, s) => _instantPage(s, const PrivacyScreen())),
      GoRoute(path: AppRoutes.helpSupport, pageBuilder: (_, s) => _instantPage(s, const HelpScreen())),
      GoRoute(
        path: '/report/:userId',
        pageBuilder: (context, state) => _instantPage(
            state, ReportScreen(reportedUserId: state.pathParameters['userId']!)),
      ),
      GoRoute(path: AppRoutes.whoViewedMe, pageBuilder: (_, s) => _instantPage(s, const WhoViewedMeScreen())),
      GoRoute(path: AppRoutes.mutualMatches, pageBuilder: (_, s) => _instantPage(s, const MutualMatchesScreen())),
    ],
    errorBuilder: (context, state) => Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 60, color: Colors.grey),
            const SizedBox(height: 16),
            const Text('Page not found',
                style: TextStyle(fontSize: 18)),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () => context.go(AppRoutes.home),
              child: const Text('Go Home'),
            ),
          ],
        ),
      ),
    ),
  );
});

class _AuthChangeNotifier extends ChangeNotifier {
  void notify() => notifyListeners();
}

/// Near-instant page transition (1ms) — used for auth/splash routes and the
/// shell so there is no black-canvas window when the router replaces the shell
/// with login. Duration.zero causes a one-frame black flash on Impeller/Vulkan
/// because the compositor doesn't get a frame to composite the new route before
/// the old one is removed. 1ms is imperceptible but gives the compositor time.
CustomTransitionPage<void> _instantPage(GoRouterState state, Widget child) {
  return CustomTransitionPage<void>(
    key: state.pageKey,
    child: child,
    transitionDuration: const Duration(milliseconds: 1),
    reverseTransitionDuration: const Duration(milliseconds: 1),
    transitionsBuilder: (_, __, ___, child) => child,
  );
}
