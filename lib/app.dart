/// Root application widget for Kabuk.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kabuk/config/providers.dart';
import 'package:kabuk/ui/onboarding/onboarding_view.dart';
import 'package:kabuk/ui/shell.dart';
import 'package:kabuk/ui/theme.dart';
import 'package:path_provider/path_provider.dart';

/// Whether the user has completed the onboarding flow.
///
/// Checks for the existence of a global flag file
/// (`onboarding_complete`) in the app documents directory.
/// This is independent of any per-profile database.
final onboardingCompleteProvider =
    StateNotifierProvider<OnboardingCompleteNotifier, bool>(
      OnboardingCompleteNotifier.new,
    );

/// Notifier backing [onboardingCompleteProvider].
///
/// Performs an async file check on build to detect onboarding completion.
class OnboardingCompleteNotifier extends StateNotifier<bool> {
  /// Creates an [OnboardingCompleteNotifier].
  OnboardingCompleteNotifier(this._ref) : super(false) {
    _loadFromFile();
  }

  final Ref _ref;

  Future<void> _loadFromFile() async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final file = File('${appDir.path}/onboarding_complete');
      if (file.existsSync()) {
        state = true;
      } else {
        // Legacy migration: if identities already exist the user has
        // previously completed onboarding under the old DB-backed flag.
        final auth = _ref.read(authServiceProvider);
        if (await auth.hasIdentity) {
          state = true;
          await file.writeAsString('1');
        }
      }
    } on Object {
      // Silently ignore errors — default to not-completed.
    }
  }

  /// Marks onboarding as complete and persists the flag.
  void complete() {
    state = true;
    _persistFlag();
  }

  Future<void> _persistFlag() async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final file = File('${appDir.path}/onboarding_complete');
      await file.writeAsString('1');
    } on Object {
      // Best effort.
    }
  }
}

/// Root application widget.
///
/// Configures [MaterialApp] with the Kabuk dark theme.
/// Shows [OnboardingView] on first launch, then [KabukShell].
class KabukApp extends ConsumerWidget {
  /// Creates the [KabukApp].
  const KabukApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final onboardingDone = ref.watch(onboardingCompleteProvider);

    return MaterialApp(
      title: 'Kabuk',
      debugShowCheckedModeBanner: false,
      theme: KabukTheme.darkTheme,
      home: onboardingDone
          ? const KabukShell()
          : OnboardingView(
              onComplete: () {
                ref.read(onboardingCompleteProvider.notifier).complete();
              },
            ),
    );
  }
}
