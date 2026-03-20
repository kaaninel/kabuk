/// Shared widgets and models used across settings sub-pages.
///
/// Contains [ServiceProviderConfig], [SettingsSectionHeader],
/// [SettingsTile], provider notifier, and helper dialogs.
library;

import 'package:flutter/material.dart';
import 'package:kabuk/ui/theme.dart';

// ---------------------------------------------------------------------------
// Service Provider model
// ---------------------------------------------------------------------------

/// A configurable external service provider.
class ServiceProviderConfig {
  /// Creates a [ServiceProviderConfig].
  const ServiceProviderConfig({
    required this.id,
    required this.name,
    required this.icon,
    required this.color,
    this.apiKey,
    this.baseUrl,
    this.username,
    this.enabled = false,
    this.description = '',
  });

  /// Unique identifier.
  final String id;

  /// Display name.
  final String name;

  /// Icon for display.
  final IconData icon;

  /// Accent color.
  final Color color;

  /// Optional API key / token.
  final String? apiKey;

  /// Optional base URL override.
  final String? baseUrl;

  /// Optional username.
  final String? username;

  /// Whether integration is active.
  final bool enabled;

  /// Description of the service.
  final String description;

  /// Creates a copy with updated fields.
  ServiceProviderConfig copyWith({
    String? apiKey,
    String? baseUrl,
    String? username,
    bool? enabled,
  }) {
    return ServiceProviderConfig(
      id: id,
      name: name,
      icon: icon,
      color: color,
      apiKey: apiKey ?? this.apiKey,
      baseUrl: baseUrl ?? this.baseUrl,
      username: username ?? this.username,
      enabled: enabled ?? this.enabled,
      description: description,
    );
  }
}

/// Default supported service providers.
final defaultProviders = <ServiceProviderConfig>[
  const ServiceProviderConfig(
    id: 'reddit',
    name: 'Reddit',
    icon: Icons.forum_rounded,
    color: KabukTheme.redditOrange,
    description: 'Reddit API for browsing feeds, saving posts, and searching.',
    baseUrl: 'https://oauth.reddit.com',
  ),
  const ServiceProviderConfig(
    id: '4chan',
    name: '4chan',
    icon: Icons.image_rounded,
    color: Color(0xFF648034),
    description: '4chan API for reading boards and threads. No auth required.',
    baseUrl: 'https://a.4cdn.org',
  ),
  const ServiceProviderConfig(
    id: 'hackernews',
    name: 'Hacker News',
    icon: Icons.newspaper_rounded,
    color: Color(0xFFFF6600),
    description: 'HN API for top stories, discussions, and user profiles.',
    baseUrl: 'https://hacker-news.firebaseio.com/v0',
  ),
  const ServiceProviderConfig(
    id: 'github',
    name: 'GitHub',
    icon: Icons.code_rounded,
    color: Color(0xFF8B5CF6),
    description: 'GitHub API for repositories, issues, and notifications.',
    baseUrl: 'https://api.github.com',
  ),
  const ServiceProviderConfig(
    id: 'rss',
    name: 'RSS Feeds',
    icon: Icons.rss_feed_rounded,
    color: Color(0xFFEF6C00),
    description: 'Subscribe to RSS/Atom feeds for news and blog updates.',
  ),
  const ServiceProviderConfig(
    id: 'youtube',
    name: 'YouTube',
    icon: Icons.play_circle_rounded,
    color: Color(0xFFFF0000),
    description: 'YouTube Data API for channels, playlists, and search.',
    baseUrl: 'https://www.googleapis.com/youtube/v3',
  ),
];

// Service provider state is persisted via [serviceProvidersProvider]
// defined in lib/config/providers.dart.

// ---------------------------------------------------------------------------
// Shared settings widgets
// ---------------------------------------------------------------------------

/// Section header with icon and title.
class SettingsSectionHeader extends StatelessWidget {
  /// Creates a [SettingsSectionHeader].
  const SettingsSectionHeader({
    super.key,
    required this.icon,
    required this.title,
    required this.color,
  });

  /// Section icon.
  final IconData icon;

  /// Section title.
  final String title;

  /// Accent color.
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 6),
        Text(
          title.toUpperCase(),
          style: TextStyle(
            color: color,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
          ),
        ),
      ],
    );
  }
}

/// A single settings row that navigates to a detail page.
class SettingsTile extends StatelessWidget {
  /// Creates a [SettingsTile].
  const SettingsTile({
    super.key,
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    this.trailing,
    this.onTap,
    this.compact = false,
  });

  /// Tile icon.
  final IconData icon;

  /// Icon accent color.
  final Color iconColor;

  /// Title text.
  final String title;

  /// Subtitle text.
  final String subtitle;

  /// Optional trailing widget.
  final Widget? trailing;

  /// Tap callback.
  final VoidCallback? onTap;

  /// Whether to use compact spacing.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.only(bottom: compact ? 2 : 4),
      decoration: BoxDecoration(
        color: context.kabukCardColor,
        borderRadius: BorderRadius.circular(KabukTheme.radiusSm),
        border: Border.all(color: context.kabukDivider, width: 0.5),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(KabukTheme.radiusSm),
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: KabukTheme.spacingMd,
              vertical: compact ? 10 : 14,
            ),
            child: Row(
              children: [
                Container(
                  width: compact ? 28 : 32,
                  height: compact ? 28 : 32,
                  decoration: BoxDecoration(
                    color: iconColor.withAlpha(18),
                    borderRadius: BorderRadius.circular(compact ? 6 : 8),
                  ),
                  child: Icon(icon, size: compact ? 15 : 17, color: iconColor),
                ),
                const SizedBox(width: KabukTheme.spacingSm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          color: context.kabukTextPrimary,
                          fontSize: compact ? 13 : 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        subtitle,
                        style: TextStyle(
                          color: context.kabukTextSecondary,
                          fontSize: compact ? 11 : 12,
                        ),
                      ),
                    ],
                  ),
                ),
                ?trailing,
                const SizedBox(width: 4),
                Icon(
                  Icons.chevron_right_rounded,
                  size: compact ? 18 : 20,
                  color: context.kabukTextTertiary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Coming soon dialog
// ---------------------------------------------------------------------------

/// Shows a styled dialog for features that are not yet implemented.
void showComingSoonDialog(
  BuildContext context, {
  required String title,
  required IconData icon,
  required String description,
}) {
  showDialog<void>(
    context: context,
    builder: (_) => AlertDialog(
      backgroundColor: context.kabukSurface,
      icon: Icon(icon, size: 32, color: KabukTheme.primaryGreen),
      title: Text(title),
      content: Text(
        description,
        style: TextStyle(
          color: context.kabukTextSecondary,
          fontSize: 14,
          height: 1.5,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('OK'),
        ),
      ],
    ),
  );
}
