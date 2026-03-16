/// Empty feed state — onboarding widget guiding users to the OmniBar.
///
/// Shown when the user has no feed subscriptions. Points them to the
/// OmniBar search bar at the top for subscribing to content sources.
library;

import 'package:flutter/material.dart';

import 'package:kabuk/ui/theme.dart';

/// Shown when user has no feed subscriptions — guides them to the OmniBar.
class EmptyFeedState extends StatelessWidget {
  /// Creates an [EmptyFeedState].
  const EmptyFeedState({super.key, this.onSearchTap});

  /// Called when the user taps the "Open search bar" button.
  final VoidCallback? onSearchTap;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(KabukTheme.spacingXl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Hero icon.
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    KabukTheme.accentGreen.withAlpha(30),
                    KabukTheme.purpleAccent.withAlpha(20),
                  ],
                ),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Icon(
                Icons.explore_rounded,
                size: 48,
                color: KabukTheme.accentGreen.withAlpha(200),
              ),
            ),
            const SizedBox(height: KabukTheme.spacingLg),

            Text(
              'Your feed is empty',
              style: Theme.of(context).textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: KabukTheme.spacingSm),
            const Text(
              'Tap the search bar above to subscribe to\n'
              'Reddit, RSS feeds, or Nostr topics.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: KabukTheme.textSecondary,
                fontSize: 14,
                height: 1.5,
              ),
            ),
            const SizedBox(height: KabukTheme.spacingLg),

            // Call to action — tap to open OmniBar search.
            Semantics(
              label: 'Find content to subscribe',
              button: true,
              excludeSemantics: true,
              child: GestureDetector(
                onTap: onSearchTap,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 14,
                  ),
                  decoration: BoxDecoration(
                    color: KabukTheme.accentGreen.withAlpha(20),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: KabukTheme.accentGreen.withAlpha(50),
                    ),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.search_rounded,
                        size: 22,
                        color: KabukTheme.accentGreen,
                        semanticLabel: '',
                      ),
                      SizedBox(width: 12),
                      Text(
                        'Find content to subscribe',
                        style: TextStyle(
                          color: KabukTheme.accentGreen,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: KabukTheme.spacingXl),

            // How-to hints.
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: KabukTheme.surface,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.lightbulb_outline_rounded,
                        size: 16,
                        color: KabukTheme.warmAccent.withAlpha(180),
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'What you can do',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: KabukTheme.textPrimary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const _HintRow(
                    icon: Icons.reddit,
                    color: Color(0xFFFF4500),
                    title: 'Type  r/subreddit',
                    subtitle: 'Subscribe to any Reddit community',
                  ),
                  const SizedBox(height: 12),
                  const _HintRow(
                    icon: Icons.tag_rounded,
                    color: KabukTheme.purpleAccent,
                    title: 'Type  #topic',
                    subtitle: 'Follow hashtags on Nostr',
                  ),
                  const SizedBox(height: 12),
                  const _HintRow(
                    icon: Icons.link_rounded,
                    color: KabukTheme.blueAccent,
                    title: 'Paste a URL',
                    subtitle: 'Add any RSS or Atom feed',
                  ),
                  const SizedBox(height: 12),
                  const _HintRow(
                    icon: Icons.search_rounded,
                    color: KabukTheme.accentGreen,
                    title: 'Search anything',
                    subtitle: 'Discover content across your feeds & Nostr',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A single hint row in the empty state.
class _HintRow extends StatelessWidget {
  const _HintRow({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: color.withAlpha(20),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 16, color: color),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
              Text(
                subtitle,
                style: const TextStyle(
                  fontSize: 12,
                  color: KabukTheme.textTertiary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
