/// Reusable page widget for onboarding [PageView] pages.
///
/// Provides a consistent layout with an icon area, title, description,
/// and optional child content for each onboarding step.
library;

import 'package:flutter/material.dart';
import 'package:kabuk/ui/theme.dart';

/// A single page within the onboarding [PageView].
///
/// Displays a centered layout with an [icon], [title], [description],
/// and an optional [child] widget below the description.
class OnboardingPage extends StatelessWidget {
  /// Creates an [OnboardingPage].
  const OnboardingPage({
    required this.icon,
    required this.title,
    required this.description,
    this.child,
    super.key,
  });

  /// The large icon displayed at the top of the page.
  final IconData icon;

  /// The page title shown below the icon.
  final String title;

  /// The descriptive text shown below the title.
  final String description;

  /// Optional additional content below the description.
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: KabukTheme.spacingLg),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Icon area.
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              color: KabukTheme.primaryGreen.withAlpha(30),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 56, color: KabukTheme.accentGreen),
          ),
          const SizedBox(height: KabukTheme.spacingXl),

          // Title.
          Text(
            title,
            style: const TextStyle(
              color: KabukTheme.textPrimary,
              fontSize: 28,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: KabukTheme.spacingMd),

          // Description.
          Text(
            description,
            style: const TextStyle(
              color: KabukTheme.textSecondary,
              fontSize: 16,
              height: 1.5,
            ),
            textAlign: TextAlign.center,
          ),

          // Optional child.
          if (child != null) ...[
            const SizedBox(height: KabukTheme.spacingLg),
            child!,
          ],
        ],
      ),
    );
  }
}
