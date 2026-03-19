/// Native reader view for AI-extracted web content.
///
/// Displays web content that has been processed by the reader mode service
/// and stored as Article + ContentBlocks in the knowledge base. Renders
/// text, images, videos, code blocks, and quotes as native Flutter widgets
/// with clean, readable typography.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:kabuk/config/providers.dart';
import 'package:kabuk/knowledge/types/article.dart';
import 'package:kabuk/knowledge/types/content_block.dart';
import 'package:kabuk/ui/explore/article_detail_page.dart' show openUrlSmart;
import 'package:kabuk/ui/explore/quick_peek_sheet.dart';
import 'package:kabuk/ui/shared/error_retry.dart';
import 'package:kabuk/ui/shared/feed_image.dart';
import 'package:kabuk/ui/shared/kabuk_markdown.dart';
import 'package:kabuk/ui/shared/time_format.dart';
import 'package:kabuk/ui/shared/video_thumbnail.dart';
import 'package:kabuk/ui/theme.dart';

// =============================================================================
// Data model
// =============================================================================

/// Holds the loaded article metadata and its ordered content blocks.
class ReaderContent {
  /// Creates a [ReaderContent].
  const ReaderContent({this.article, this.blocks = const []});

  /// The article entity from the knowledge store, or `null` if not found.
  final ArticleData? article;

  /// Ordered content blocks that make up the article body.
  final List<ContentBlockData> blocks;
}

// =============================================================================
// Provider
// =============================================================================

/// Loads article data and its content blocks for the reader view.
///
/// The [String] parameter is the article URI in the knowledge store.
final readerContentProvider =
    FutureProvider.family<ReaderContent, String>((ref, articleUri) async {
  final store = ref.read(knowledgeStoreProvider);
  final article = await store.getArticleData(articleUri);
  final blocks = await store.listDocumentBlocks(articleUri);
  return ReaderContent(article: article, blocks: blocks);
});

// =============================================================================
// ReaderView
// =============================================================================

/// Full-screen native reader view for AI-extracted web content.
///
/// Takes an article URI and renders its content blocks — text, images,
/// videos, code, quotes, and callouts — as native Flutter widgets with
/// clean, readable typography optimized for long-form reading.
class ReaderView extends ConsumerStatefulWidget {
  /// Creates a [ReaderView].
  const ReaderView({required this.articleUri, this.url, super.key});

  /// URI of the article in the knowledge store.
  final String articleUri;

  /// Original URL (for display and sharing).
  final String? url;

  @override
  ConsumerState<ReaderView> createState() => _ReaderViewState();
}

class _ReaderViewState extends ConsumerState<ReaderView> {
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _openOriginal(String url) {
    QuickPeekSheet.show(context, url: url, title: 'Original');
  }

  @override
  Widget build(BuildContext context) {
    final asyncContent = ref.watch(readerContentProvider(widget.articleUri));

    return Scaffold(
      backgroundColor: KabukTheme.background,
      body: asyncContent.when(
        loading: () => const _ReaderSkeleton(),
        error: (err, _) => ErrorRetryWidget.fromError(
          err,
          onRetry: () => ref.invalidate(readerContentProvider(widget.articleUri)),
        ),
        data: (content) {
          if (content.article == null) {
            return const ErrorRetryWidget(
              message: 'Article not found in the knowledge store.',
              icon: Icons.article_outlined,
            );
          }
          return _ReaderBody(
            article: content.article!,
            blocks: content.blocks,
            scrollController: _scrollController,
            externalUrl: widget.url ?? content.article!.url,
            onOpenOriginal: _openOriginal,
          );
        },
      ),
    );
  }
}

// =============================================================================
// Reader body
// =============================================================================

/// Renders the complete reader layout: app bar, article header, content
/// blocks, and bottom action bar.
class _ReaderBody extends StatelessWidget {
  const _ReaderBody({
    required this.article,
    required this.blocks,
    required this.scrollController,
    required this.onOpenOriginal,
    this.externalUrl,
  });

  /// Article metadata.
  final ArticleData article;

  /// Ordered content blocks.
  final List<ContentBlockData> blocks;

  /// Scroll controller for the main content.
  final ScrollController scrollController;

  /// Original source URL.
  final String? externalUrl;

  /// Callback to open the source URL.
  final void Function(String url) onOpenOriginal;

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      controller: scrollController,
      slivers: [
        // ── App bar ──────────────────────────────────────────────────────
        _ReaderAppBar(
          title: article.name ?? 'Reader',
          externalUrl: externalUrl,
          onOpenOriginal: onOpenOriginal,
        ),

        // ── Article header ───────────────────────────────────────────────
        SliverToBoxAdapter(
          child: _ArticleHeader(article: article),
        ),

        // ── Hero image ───────────────────────────────────────────────────
        if (FeedImage.isValidImageUrl(article.image))
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                KabukTheme.spacingMd,
                KabukTheme.spacingSm,
                KabukTheme.spacingMd,
                KabukTheme.spacingMd,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(KabukTheme.radiusMd),
                child: FeedImage(
                  imageUrl: article.image!,
                  height: 220,
                  borderRadius: BorderRadius.circular(KabukTheme.radiusMd),
                ),
              ),
            ),
          ),

        // ── Content blocks ───────────────────────────────────────────────
        if (blocks.isEmpty)
          // Fallback: render article description as markdown when no blocks.
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: KabukTheme.spacingMd,
              ),
              child: article.description != null
                  ? KabukMarkdown(data: article.description!)
                  : const Center(
                      child: Padding(
                        padding: EdgeInsets.all(KabukTheme.spacingXl),
                        child: Text(
                          'No content blocks available.',
                          style: TextStyle(
                            color: KabukTheme.textTertiary,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ),
            ),
          )
        else
          SliverList.builder(
            itemCount: blocks.length,
            itemBuilder: (context, index) => _ContentBlockRenderer(
              block: blocks[index],
            ),
          ),

        // ── Bottom spacing ───────────────────────────────────────────────
        const SliverToBoxAdapter(child: SizedBox(height: KabukTheme.spacingMd)),

        // ── Bottom bar ───────────────────────────────────────────────────
        SliverToBoxAdapter(
          child: _ReaderBottomBar(
            url: externalUrl,
            onOpenOriginal: onOpenOriginal,
          ),
        ),

        // ── Safe area padding ────────────────────────────────────────────
        const SliverToBoxAdapter(
          child: SizedBox(
            height: KabukTheme.spacingLg,
          ),
        ),
      ],
    );
  }
}

// =============================================================================
// App bar
// =============================================================================

/// Collapsing app bar with back button, truncated title, and "View original".
class _ReaderAppBar extends StatelessWidget {
  const _ReaderAppBar({
    required this.title,
    required this.onOpenOriginal,
    this.externalUrl,
  });

  /// Article title (truncated in the app bar).
  final String title;

  /// Source URL.
  final String? externalUrl;

  /// Callback to open the source URL.
  final void Function(String url) onOpenOriginal;

  @override
  Widget build(BuildContext context) {
    return SliverAppBar(
      pinned: true,
      backgroundColor: KabukTheme.background,
      surfaceTintColor: Colors.transparent,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_rounded),
        color: KabukTheme.textPrimary,
        onPressed: () => Navigator.of(context).pop(),
      ),
      title: Text(
        title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: KabukTheme.textPrimary,
        ),
      ),
      actions: [
        if (externalUrl != null)
          IconButton(
            icon: const Icon(Icons.open_in_new_rounded, size: 20),
            color: KabukTheme.textSecondary,
            tooltip: 'View original',
            onPressed: () => onOpenOriginal(externalUrl!),
          ),
      ],
      systemOverlayStyle: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
      ),
    );
  }
}

// =============================================================================
// Article header
// =============================================================================

/// Renders the article title, author, publication date, and source info.
class _ArticleHeader extends StatelessWidget {
  const _ArticleHeader({required this.article});

  /// The article whose metadata to display.
  final ArticleData article;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        KabukTheme.spacingMd,
        KabukTheme.spacingSm,
        KabukTheme.spacingMd,
        KabukTheme.spacingXs,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Title ────────────────────────────────────────────────────
          if (article.name != null)
            Text(
              article.name!,
              style: const TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w800,
                height: 1.25,
                letterSpacing: -0.5,
                color: KabukTheme.textPrimary,
              ),
            ),

          const SizedBox(height: KabukTheme.spacingSm),

          // ── Meta row: author · date · source ─────────────────────────
          Wrap(
            spacing: 6,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (article.author != null) ...[
                _MetaChip(
                  icon: Icons.person_outline_rounded,
                  label: article.author!,
                ),
                const _MetaDot(),
              ],
              if (article.datePublished != null) ...[
                _MetaChip(
                  icon: Icons.schedule_rounded,
                  label: timeAgoFromDateTime(article.datePublished!),
                ),
              ],
              if (article.feedSource != null) ...[
                const _MetaDot(),
                _MetaChip(
                  icon: Icons.rss_feed_rounded,
                  label: article.feedSource!,
                ),
              ],
            ],
          ),

          const SizedBox(height: KabukTheme.spacingMd),
          const Divider(color: KabukTheme.divider, height: 1),
        ],
      ),
    );
  }
}

/// Small metadata label with an icon.
class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.icon, required this.label});

  /// Leading icon.
  final IconData icon;

  /// Text content.
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: KabukTheme.textTertiary),
        const SizedBox(width: 3),
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            color: KabukTheme.textSecondary,
          ),
        ),
      ],
    );
  }
}

/// Dot separator between metadata chips.
class _MetaDot extends StatelessWidget {
  const _MetaDot();

  @override
  Widget build(BuildContext context) {
    return const Text(
      '·',
      style: TextStyle(fontSize: 12, color: KabukTheme.textTertiary),
    );
  }
}

// =============================================================================
// Content block renderer
// =============================================================================

/// Renders a single [ContentBlockData] as the appropriate native widget.
///
/// Delegates to specialized builders based on [ContentBlockData.type].
class _ContentBlockRenderer extends StatelessWidget {
  const _ContentBlockRenderer({required this.block});

  /// The content block to render.
  final ContentBlockData block;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: _paddingForBlock(block.type),
      child: switch (block.type) {
        BlockType.text => _buildText(context),
        BlockType.heading => _buildHeading(context),
        BlockType.image => _buildImage(context),
        BlockType.video => _buildVideo(context),
        BlockType.audio => _buildAudio(context),
        BlockType.code => _buildCode(context),
        BlockType.quote => _buildQuote(context),
        BlockType.divider => _buildDivider(),
        BlockType.checklist => _buildChecklist(context),
        BlockType.callout => _buildCallout(context),
      },
    );
  }

  /// Returns horizontal and vertical padding appropriate for each block type.
  EdgeInsets _paddingForBlock(BlockType type) => switch (type) {
    BlockType.divider => const EdgeInsets.symmetric(
      horizontal: KabukTheme.spacingMd,
      vertical: KabukTheme.spacingSm,
    ),
    BlockType.image || BlockType.video => const EdgeInsets.symmetric(
      horizontal: KabukTheme.spacingMd,
      vertical: KabukTheme.spacingSm,
    ),
    _ => const EdgeInsets.symmetric(
      horizontal: KabukTheme.spacingMd,
      vertical: KabukTheme.spacingXs,
    ),
  };

  // ── Text ─────────────────────────────────────────────────────────────────

  Widget _buildText(BuildContext context) {
    final content = block.content;
    if (content == null || content.trim().isEmpty) {
      return const SizedBox.shrink();
    }
    return KabukMarkdown(
      data: content,
      onTapLink: (text, href, _) {
        if (href == null) return;
        openUrlSmart(context, href, title: text.isNotEmpty ? text : null);
      },
    );
  }

  // ── Heading ──────────────────────────────────────────────────────────────

  Widget _buildHeading(BuildContext context) {
    final content = block.content ?? '';
    if (content.trim().isEmpty) return const SizedBox.shrink();

    final level = block.level ?? 2;
    final style = switch (level) {
      1 => const TextStyle(
        fontSize: 24,
        fontWeight: FontWeight.w800,
        height: 1.3,
        letterSpacing: -0.3,
        color: KabukTheme.textPrimary,
      ),
      2 => const TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        height: 1.3,
        color: KabukTheme.textPrimary,
      ),
      _ => const TextStyle(
        fontSize: 17,
        fontWeight: FontWeight.w600,
        height: 1.3,
        color: KabukTheme.textPrimary,
      ),
    };

    return Padding(
      padding: EdgeInsets.only(top: level == 1 ? KabukTheme.spacingMd : KabukTheme.spacingSm),
      child: Text(content, style: style),
    );
  }

  // ── Image ────────────────────────────────────────────────────────────────

  Widget _buildImage(BuildContext context) {
    final url = block.mediaUri;
    if (url == null || !FeedImage.isValidImageUrl(url)) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(KabukTheme.radiusMd),
          child: FeedImage(
            imageUrl: url,
            borderRadius: BorderRadius.circular(KabukTheme.radiusMd),
          ),
        ),
        if (block.caption != null && block.caption!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: KabukTheme.spacingXs),
            child: Text(
              block.caption!,
              style: const TextStyle(
                fontSize: 12,
                color: KabukTheme.textTertiary,
                fontStyle: FontStyle.italic,
                height: 1.4,
              ),
            ),
          ),
      ],
    );
  }

  // ── Video ────────────────────────────────────────────────────────────────

  Widget _buildVideo(BuildContext context) {
    final url = block.mediaUri;
    if (url == null || url.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        VideoThumbnail(
          videoUrl: url,
          thumbnailUrl: block.mediaUri,
          height: 220,
          borderRadius: BorderRadius.circular(KabukTheme.radiusMd),
        ),
        if (block.caption != null && block.caption!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: KabukTheme.spacingXs),
            child: Text(
              block.caption!,
              style: const TextStyle(
                fontSize: 12,
                color: KabukTheme.textTertiary,
                fontStyle: FontStyle.italic,
                height: 1.4,
              ),
            ),
          ),
      ],
    );
  }

  // ── Audio ────────────────────────────────────────────────────────────────

  Widget _buildAudio(BuildContext context) {
    // Render as a styled placeholder — full audio playback is out of scope.
    return Container(
      padding: const EdgeInsets.all(KabukTheme.spacingMd),
      decoration: BoxDecoration(
        color: KabukTheme.surfaceVariant,
        borderRadius: BorderRadius.circular(KabukTheme.radiusMd),
        border: Border.all(color: KabukTheme.divider, width: 0.5),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.audiotrack_rounded,
            color: KabukTheme.accentGreen,
            size: 24,
          ),
          const SizedBox(width: KabukTheme.spacingSm),
          Expanded(
            child: Text(
              block.caption ?? block.mediaUri ?? 'Audio',
              style: const TextStyle(
                fontSize: 14,
                color: KabukTheme.textSecondary,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  // ── Code ─────────────────────────────────────────────────────────────────

  Widget _buildCode(BuildContext context) {
    final content = block.content ?? '';
    if (content.trim().isEmpty) return const SizedBox.shrink();

    final language = block.language;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Language badge.
        if (language != null && language.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: KabukTheme.spacingXs),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: KabukTheme.surfaceVariant,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                language.toUpperCase(),
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: KabukTheme.textTertiary,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ),
        // Code container.
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(KabukTheme.spacingSm + 4),
          decoration: BoxDecoration(
            color: KabukTheme.surfaceVariant,
            borderRadius: BorderRadius.circular(KabukTheme.radiusSm),
            border: Border.all(color: KabukTheme.divider, width: 0.5),
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SelectableText(
              content,
              style: const TextStyle(
                fontFamily: 'SF Mono',
                fontSize: 13,
                height: 1.5,
                color: KabukTheme.textPrimary,
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ── Quote ────────────────────────────────────────────────────────────────

  Widget _buildQuote(BuildContext context) {
    final content = block.content ?? '';
    if (content.trim().isEmpty) return const SizedBox.shrink();

    return Container(
      decoration: BoxDecoration(
        border: const Border(
          left: BorderSide(color: KabukTheme.accentGreen, width: 3),
        ),
        color: KabukTheme.primaryGreen.withAlpha(12),
      ),
      padding: const EdgeInsets.fromLTRB(
        KabukTheme.spacingMd,
        KabukTheme.spacingSm,
        KabukTheme.spacingSm,
        KabukTheme.spacingSm,
      ),
      child: KabukMarkdown(
        data: content,
        onTapLink: (text, href, _) {
          if (href == null) return;
          openUrlSmart(context, href, title: text.isNotEmpty ? text : null);
        },
      ),
    );
  }

  // ── Divider ──────────────────────────────────────────────────────────────

  Widget _buildDivider() {
    return const Divider(color: KabukTheme.divider, height: 1);
  }

  // ── Checklist ────────────────────────────────────────────────────────────

  Widget _buildChecklist(BuildContext context) {
    final content = block.content ?? '';
    final isChecked = block.checked ?? false;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(
            isChecked
                ? Icons.check_box_rounded
                : Icons.check_box_outline_blank_rounded,
            size: 20,
            color: isChecked
                ? KabukTheme.accentGreen
                : KabukTheme.textTertiary,
          ),
        ),
        const SizedBox(width: KabukTheme.spacingSm),
        Expanded(
          child: Text(
            content,
            style: TextStyle(
              fontSize: 15,
              height: 1.6,
              color: isChecked
                  ? KabukTheme.textTertiary
                  : KabukTheme.textPrimary,
              decoration:
                  isChecked ? TextDecoration.lineThrough : TextDecoration.none,
            ),
          ),
        ),
      ],
    );
  }

  // ── Callout ──────────────────────────────────────────────────────────────

  Widget _buildCallout(BuildContext context) {
    final content = block.content ?? '';
    if (content.trim().isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(KabukTheme.spacingMd),
      decoration: BoxDecoration(
        color: KabukTheme.blueAccent.withAlpha(18),
        borderRadius: BorderRadius.circular(KabukTheme.radiusMd),
        border: Border.all(
          color: KabukTheme.blueAccent.withAlpha(60),
          width: 0.5,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 2),
            child: Icon(
              Icons.info_outline_rounded,
              size: 18,
              color: KabukTheme.blueAccent,
            ),
          ),
          const SizedBox(width: KabukTheme.spacingSm),
          Expanded(
            child: KabukMarkdown(
              data: content,
              onTapLink: (text, href, _) {
                if (href == null) return;
                openUrlSmart(
                  context,
                  href,
                  title: text.isNotEmpty ? text : null,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// Bottom bar
// =============================================================================

/// Action bar at the bottom of the reader view with source link, share,
/// and bookmark buttons.
class _ReaderBottomBar extends StatelessWidget {
  const _ReaderBottomBar({
    required this.onOpenOriginal,
    this.url,
  });

  /// Source URL.
  final String? url;

  /// Callback to open the source URL.
  final void Function(String url) onOpenOriginal;

  @override
  Widget build(BuildContext context) {
    if (url == null) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: KabukTheme.spacingMd),
      padding: const EdgeInsets.symmetric(
        horizontal: KabukTheme.spacingMd,
        vertical: KabukTheme.spacingSm + 2,
      ),
      decoration: BoxDecoration(
        color: KabukTheme.surfaceElevated,
        borderRadius: BorderRadius.circular(KabukTheme.radiusMd),
        border: Border.all(color: KabukTheme.divider, width: 0.5),
      ),
      child: Row(
        children: [
          // "View original" link.
          Expanded(
            child: GestureDetector(
              onTap: () => onOpenOriginal(url!),
              child: Row(
                children: [
                  const Icon(
                    Icons.open_in_new_rounded,
                    size: 14,
                    color: KabukTheme.blueAccent,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _truncateUrl(url!),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        color: KabukTheme.blueAccent,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(width: KabukTheme.spacingSm),

          // Share button.
          IconButton(
            icon: const Icon(Icons.share_outlined, size: 20),
            color: KabukTheme.textSecondary,
            tooltip: 'Share',
            onPressed: () {
              Clipboard.setData(ClipboardData(text: url!));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Link copied to clipboard'),
                  duration: Duration(seconds: 2),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  /// Strips scheme and common prefixes to show a compact domain + path.
  static String _truncateUrl(String url) {
    var display = url
        .replaceFirst(RegExp(r'^https?://'), '')
        .replaceFirst('www.', '');
    if (display.length > 50) {
      display = '${display.substring(0, 47)}...';
    }
    return display;
  }
}

// =============================================================================
// Loading skeleton
// =============================================================================

/// Shimmer loading skeleton shown while the reader content loads.
class _ReaderSkeleton extends StatelessWidget {
  const _ReaderSkeleton();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: KabukTheme.background,
      appBar: AppBar(
        backgroundColor: KabukTheme.background,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          color: KabukTheme.textPrimary,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: const Padding(
        padding: EdgeInsets.symmetric(horizontal: KabukTheme.spacingMd),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(height: KabukTheme.spacingMd),
            // Title placeholder.
            _SkeletonBox(width: double.infinity, height: 28),
            SizedBox(height: KabukTheme.spacingSm),
            _SkeletonBox(width: 220, height: 28),
            SizedBox(height: KabukTheme.spacingMd),
            // Meta row placeholder.
            _SkeletonBox(width: 180, height: 14),
            SizedBox(height: KabukTheme.spacingLg),
            // Image placeholder.
            _SkeletonBox(width: double.infinity, height: 200),
            SizedBox(height: KabukTheme.spacingLg),
            // Text line placeholders.
            _SkeletonBox(width: double.infinity, height: 14),
            SizedBox(height: KabukTheme.spacingSm),
            _SkeletonBox(width: double.infinity, height: 14),
            SizedBox(height: KabukTheme.spacingSm),
            _SkeletonBox(width: 260, height: 14),
            SizedBox(height: KabukTheme.spacingMd),
            _SkeletonBox(width: double.infinity, height: 14),
            SizedBox(height: KabukTheme.spacingSm),
            _SkeletonBox(width: double.infinity, height: 14),
            SizedBox(height: KabukTheme.spacingSm),
            _SkeletonBox(width: 180, height: 14),
          ],
        ),
      ),
    );
  }
}

/// Rounded rectangle shimmer placeholder block.
class _SkeletonBox extends StatelessWidget {
  const _SkeletonBox({required this.width, required this.height});

  /// Width of the placeholder. Use [double.infinity] for full-width.
  final double width;

  /// Height of the placeholder.
  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: KabukTheme.surfaceVariant,
        borderRadius: BorderRadius.circular(KabukTheme.radiusSm),
      ),
    );
  }
}
