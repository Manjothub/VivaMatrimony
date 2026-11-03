import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../network/api_client.dart';
import '../router/app_router.dart' show rootNavigatorKey;
import '../storage/cache_service.dart';
import '../storage/secure_storage.dart';

/// Auth states that drive all routing decisions.
enum AuthStatus {
  loading,
  unauthenticated,
  onboardingRequired,
  authenticated,
}

class AuthState {
  final AuthStatus status;
  final String? userId;
  final String? email;
  final String? memberId;
  final bool onboardingCompleted;

  const AuthState({
    required this.status,
    this.userId,
    this.email,
    this.memberId,
    this.onboardingCompleted = false,
  });

  const AuthState.loading()
      : status = AuthStatus.loading,
        userId = null,
        email = null,
        memberId = null,
        onboardingCompleted = false;

  const AuthState.unauthenticated()
      : status = AuthStatus.unauthenticated,
        userId = null,
        email = null,
        memberId = null,
        onboardingCompleted = false;

  AuthState copyWith({
    AuthStatus? status,
    String? userId,
    String? email,
    String? memberId,
    bool? onboardingCompleted,
  }) =>
      AuthState(
        status: status ?? this.status,
        userId: userId ?? this.userId,
        email: email ?? this.email,
        memberId: memberId ?? this.memberId,
        onboardingCompleted: onboardingCompleted ?? this.onboardingCompleted,
      );
}

class AuthNotifier extends AsyncNotifier<AuthState> {
  // Incremented on every logout/forceUnauthenticated call.
  // Any in-flight async callback that captured an older generation will bail
  // out before writing state, preventing stale "authenticated" restorations.
  int _authGeneration = 0;

  @override
  Future<AuthState> build() async {
    final sub = Supabase.instance.client.auth.onAuthStateChange.listen(
      (data) async {
        final event = data.event;
        final session = data.session;
        final generation = ++_authGeneration;

        debugPrint('[Auth] stream event=$event session=${session?.user.id}');

        if (event == AuthChangeEvent.signedOut || session == null) {
          // Session is definitively gone. Wipe local storage so stale
          // Keystore entries don't survive an uninstall/reinstall.
          // This covers: explicit logout, token expiry, server-side revocation.
          try { await ref.read(secureStorageProvider).clearAppData(); } catch (_) {}
          try { await CacheService.invalidateAll(); } catch (_) {}
          // Idempotent: logout() already set this, but the stream fires too.
          // Route through _setUnauthenticated() so the router-refresh guard
          // also runs on this path (token expiry, server-side revocation).
          _setUnauthenticated();
          return;
        }

        if (event == AuthChangeEvent.signedIn ||
            event == AuthChangeEvent.tokenRefreshed ||
            event == AuthChangeEvent.initialSession) {
          if (event == AuthChangeEvent.signedIn) {
            await _ensureUserRow(session, generation);
            return;
          }
          final newState = await _stateFromSession(session);
          if (_isCurrentGeneration(generation)) {
            state = AsyncValue.data(newState);
          }
        }
      },
    );
    ref.onDispose(sub.cancel);

    final session = Supabase.instance.client.auth.currentSession;
    if (session == null) {
      // No session at cold start. Wait briefly for the SDK to restore a
      // persisted session before deciding to wipe storage.
      // supabase_flutter restores the session asynchronously; currentSession
      // may be null for a short window even when a valid session exists.
      // We wait for the first auth state event instead of acting immediately.
      //
      // Storage is wiped on confirmed signedOut event (see stream listener)
      // and on explicit logout(). Wiping here unconditionally caused a
      // regression: initialSession fires after build() returns null, so the
      // wipe ran on every cold start with a valid session.
      return const AuthState.unauthenticated();
    }
    final generation = ++_authGeneration;
    final initialState = await _stateFromSession(session);
    return _isCurrentGeneration(generation)
        ? initialState
        : const AuthState.unauthenticated();
  }

  // Simpler guard: just check the generation number. We no longer need to
  // verify session.user.id because _authGeneration is only incremented by
  // logout/forceUnauthenticated, which means any callback from a prior
  // "signed-in" era is stale.
  bool _isCurrentGeneration(int generation) => _authGeneration == generation;

  void _setUnauthenticated() {
    _authGeneration++;
    debugPrint('[Auth] _setUnauthenticated gen=$_authGeneration');
    state = const AsyncValue.data(AuthState.unauthenticated());
    _forceRouterRedirect();
  }

  /// Explicitly refresh GoRouter so it re-evaluates its redirect immediately.
  /// The ref.listen in routerProvider fires asynchronously and can miss the
  /// state change if the shell widget tree is mid-disposal during logout.
  /// refresh() forces a synchronous redirect re-evaluation without pushing a
  /// new route, so there is no double-navigation race.
  void _forceRouterRedirect() {
    final ctx = rootNavigatorKey.currentContext;
    if (ctx != null && ctx.mounted) {
      GoRouter.of(ctx).refresh();
      debugPrint('[Auth] GoRouter refreshed after auth flip');
    }
  }

  /// Escape hatch for the splash 8-second timeout.
  void forceUnauthenticated() {
    _setUnauthenticated();
    unawaited(Supabase.instance.client.auth
        .signOut(scope: SignOutScope.local)
        .catchError((_) {}));
  }

  Future<void> _ensureUserRow(Session session, int generation) async {
    try {
      final response = await ref.read(apiClientProvider).post('/auth/register');
      if (!_isCurrentGeneration(generation)) return;
      final data = response.data as Map<String, dynamic>?;
      final storage = ref.read(secureStorageProvider);
      if (data != null) {
        final onboardingDone = data['onboarding_completed'] as bool? ?? false;
        final memberId = data['member_id'] as String?;
        if (memberId != null) await storage.saveMemberId(memberId);
        await storage.setOnboardingCompleted(onboardingDone);
      }
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        await Supabase.instance.client.auth.signOut(scope: SignOutScope.local);
        if (_isCurrentGeneration(generation)) _setUnauthenticated();
        return;
      }
      // Non-401 (network error, 5xx) — proceed; row likely already exists.
    } catch (_) {}
    final newState = await _stateFromSession(session);
    if (_isCurrentGeneration(generation)) {
      state = AsyncValue.data(newState);
    }
  }

  Future<AuthState> _stateFromSession(Session session) async {
    final storage = ref.read(secureStorageProvider);
    final onboardingDone = await storage.isOnboardingCompleted();
    final memberId = await storage.getMemberId();
    return AuthState(
      status: onboardingDone
          ? AuthStatus.authenticated
          : AuthStatus.onboardingRequired,
      userId: session.user.id,
      email: session.user.email,
      memberId: memberId,
      onboardingCompleted: onboardingDone,
    );
  }

  Future<void> onLoginSuccess({
    required bool onboardingCompleted,
    String? memberId,
  }) async {
    final session = Supabase.instance.client.auth.currentSession;
    if (session == null) return;
    final generation = ++_authGeneration;
    final storage = ref.read(secureStorageProvider);
    if (memberId != null) await storage.saveMemberId(memberId);
    await storage.setOnboardingCompleted(onboardingCompleted);
    final newState = await _stateFromSession(session);
    if (_isCurrentGeneration(generation)) {
      state = AsyncValue.data(newState);
    }
  }

  Future<void> onOnboardingCompleted() async {
    final storage = ref.read(secureStorageProvider);
    await storage.setOnboardingCompleted(true);
    final current = state.valueOrNull;
    if (current != null) {
      state = AsyncValue.data(current.copyWith(
        status: AuthStatus.authenticated,
        onboardingCompleted: true,
      ));
    }
  }

  // Guard against concurrent logout calls (e.g. double-tap confirm button).
  bool _isLoggingOut = false;

  // Not needed anymore — kept so router code that references it compiles.
  bool isHandlingLogoutNav = false;

  Future<void> logout() async {
    if (_isLoggingOut) {
      debugPrint('[Auth] logout() ignored — already in progress');
      return;
    }
    _isLoggingOut = true;

    // Capture the token up front, before anything tears down the session: the
    // backend audit and the global revoke both need a still-valid access token.
    final accessToken =
        Supabase.instance.client.auth.currentSession?.accessToken;
    final storage = ref.read(secureStorageProvider);
    final api = ref.read(apiClientProvider);

    debugPrint('[Auth] LOGOUT START');

    try {
      // 1. Wipe cache + app local data (memberId, onboarding flag). Fast/local.
      try {
        await CacheService.invalidateAll();
        debugPrint('[Auth] cache invalidated');
      } catch (e) {
        debugPrint('[Auth] cache clear failed: $e');
      }
      try {
        await storage.clearAppData();
        debugPrint('[Auth] clearAppData done');
      } catch (e) {
        debugPrint('[Auth] clearAppData failed: $e');
      }

      // 2. Flip auth state NOW — the router redirects to /login immediately.
      //    NOT gated on the network audit or global signOut below, so logout
      //    feels instant and never strands the UI on a black screen.
      _setUnauthenticated();
      debugPrint('[Auth] LOGOUT COMPLETE (UI flipped)');

      // 3. Backend audit THEN global signOut, fire-and-forget. The audit runs
      //    first (access token still valid, captured above) and before the
      //    session is revoked. signOut(scope: global) removes the local Supabase
      //    session via its signedOut event BEFORE its own network revoke, so a
      //    cold start cannot restore the session even if the revoke fails.
      //
      //    ponytail: the audit is awaited before signOut (honors
      //    audit-before-revoke); a hung backend delays the local session
      //    teardown up to the Dio receiveTimeout (60s). Upgrade: pass a short
      //    per-request receiveTimeout on the audit so a slow backend can't
      //    delay it.
      unawaited(() async {
        if (accessToken != null) {
          try {
            debugPrint('[Auth] calling backend /auth/logout');
            await api.post(
              '/auth/logout',
              options:
                  Options(headers: {'Authorization': 'Bearer $accessToken'}),
            );
            debugPrint('[Auth] backend /auth/logout SUCCESS');
          } catch (e) {
            debugPrint('[Auth] backend /auth/logout FAILED: $e');
          }
        } else {
          debugPrint('[Auth] no access token — skipping backend call');
        }
        try {
          await Supabase.instance.client.auth
              .signOut(scope: SignOutScope.global);
          debugPrint('[Auth] Supabase.signOut() done');
        } catch (e) {
          debugPrint('[Auth] Supabase.signOut() failed: $e');
        }
      }());
    } finally {
      _isLoggingOut = false;
    }
  }
}

final authProvider = AsyncNotifierProvider<AuthNotifier, AuthState>(
  AuthNotifier.new,
);
