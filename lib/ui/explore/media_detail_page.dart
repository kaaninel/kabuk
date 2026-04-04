/// TV series and movie detail page with full TMDB metadata.
///
/// Shows backdrop, poster, metadata, genre chips, and overview for both
/// TV series and movies. TV series include a season/episode browser that
/// lazily loads episode lists via [MediaMetadataService.getTvSeason].
///
/// Results are cached in the knowledge store using the CRUD extensions
/// from `lib/knowledge/types/tv_movie.dart`.
library;

import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kabuk/config/providers.dart';
import 'package:kabuk/config/result.dart';
import 'package:kabuk/knowledge/types/tv_movie.dart';
import 'package:kabuk/platform/shared/tmdb_client.dart';
import 'package:kabuk/services/media_metadata.dart';
import 'package:kabuk/ui/theme.dart';
import 'package:url_launcher/url_launcher.dart';

// =============================================================================
// Navigation helper
// =============================================================================

/// Pushes the [MediaDetailPage] with a slide-up transition.
///
/// [mediaType] is the [MediaType] enum value; [title] and [posterPath]
/// are shown immediately while the full detail loads from the API.
Future<void> pushMediaDetail(
  BuildContext context, {
  required int tmdbId,
  required MediaType mediaType,
  required String title,
  String? posterPath,
}) {
  return Navigator.of(context).push<void>(
    PageRouteBuilder<void>(
      pageBuilder: (context, animation, secondaryAnimation) => MediaDetailPage(
        tmdbId: tmdbId,
        mediaType: mediaType,
        title: title,
        posterPath: posterPath,
      ),
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        final tween = Tween(begin: const Offset(0, 1), end: Offset.zero)
            .chain(CurveTween(curve: Curves.easeOutCubic));
        return SlideTransition(position: animation.drive(tween), child: child);
      },
      transitionDuration: const Duration(milliseconds: 300),
      reverseTransitionDuration: const Duration(milliseconds: 250),
    ),
  );
}

// =============================================================================
// MediaDetailPage
// =============================================================================

/// Full-screen detail page for a TV series or movie from TMDB.
///
/// Shows backdrop + poster header, metadata (rating, status, year, runtime),
/// genre chips, expandable overview, and external links (IMDB/TVDB).
/// For TV series, a season/episode browser is included. For movies,
/// budget/revenue and a tagline are shown when available.
///
/// On load, the metadata result is cached in the knowledge store via the
/// CRUD extensions.
class MediaDetailPage extends ConsumerStatefulWidget {
  /// Creates a [MediaDetailPage].
  const MediaDetailPage({
    required this.tmdbId,
    required this.mediaType,
    required this.title,
    this.posterPath,
    super.key,
  });

  /// TMDB identifier.
  final int tmdbId;

  /// Whether this is a movie or TV series.
  final MediaType mediaType;

  /// Display title (shown immediately while details load).
  final String title;

  /// Optional poster path for the hero image while loading.
  final String? posterPath;

  @override
  ConsumerState<MediaDetailPage> createState() => _MediaDetailPageState();
}

class _MediaDetailPageState extends ConsumerState<MediaDetailPage> {
  bool _loading = true;
  String? _error;

  // TV series state.
  TvSeriesDetail? _tvSeries;
  int _selectedSeasonIndex = 0;
  TvSeasonDetail? _seasonDetail;
  bool _loadingSeason = false;

  // Movie state.
  MovieDetail? _movie;

  // Overview expansion.
  bool _overviewExpanded = false;

  bool get _isTv => widget.mediaType == MediaType.tvSeries;

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  @override
  void initState() {
    super.initState();
    _fetchDetail();
  }

  Future<void> _fetchDetail() async {
    final service = ref.read(mediaMetadataServiceProvider);
    if (service == null) {
      setState(() {
        _error = 'Media metadata service not configured (missing TMDB key).';
        _loading = false;
      });
      return;
    }

    if (_isTv) {
      await _fetchTvSeries(service);
    } else {
      await _fetchMovie(service);
    }
  }

  Future<void> _fetchTvSeries(MediaMetadataService service) async {
    final result = await service.getTvSeries(widget.tmdbId);
    if (!mounted) return;

    switch (result) {
      case Success(:final value):
        setState(() {
          _tvSeries = value;
          _loading = false;
        });
        unawaited(_cacheTvSeries(value));
        // Auto-select first regular season (skip specials if possible).
        if (value.seasons.isNotEmpty) {
          final firstRegular =
              value.seasons.indexWhere((s) => s.seasonNumber > 0);
          _selectedSeasonIndex = firstRegular >= 0 ? firstRegular : 0;
          unawaited(_fetchSeason(value.seasons[_selectedSeasonIndex].seasonNumber));
        }
      case Failure(:final error):
        setState(() {
          _error = 'Failed to load TV series: $error';
          _loading = false;
        });
    }
  }

  Future<void> _fetchMovie(MediaMetadataService service) async {
    final result = await service.getMovie(widget.tmdbId);
    if (!mounted) return;

    switch (result) {
      case Success(:final value):
        setState(() {
          _movie = value;
          _loading = false;
        });
        unawaited(_cacheMovie(value));
      case Failure(:final error):
        setState(() {
          _error = 'Failed to load movie: $error';
          _loading = false;
        });
    }
  }

  Future<void> _fetchSeason(int seasonNumber) async {
    final service = ref.read(mediaMetadataServiceProvider);
    if (service == null) return;

    setState(() => _loadingSeason = true);
    final result = await service.getTvSeason(widget.tmdbId, seasonNumber);
    if (!mounted) return;

    switch (result) {
      case Success(:final value):
        setState(() {
          _seasonDetail = value;
          _loadingSeason = false;
        });
      case Failure():
        setState(() => _loadingSeason = false);
    }
  }

  // ---------------------------------------------------------------------------
  // Knowledge store caching
  // ---------------------------------------------------------------------------

  Future<void> _cacheTvSeries(TvSeriesDetail detail) async {
    final store = ref.read(knowledgeStoreProvider);
    await store.createTvSeries(
      name: detail.name,
      overview: detail.overview,
      posterPath: detail.posterPath,
      backdropPath: detail.backdropPath,
      firstAirDate: detail.firstAirDate,
      lastAirDate: detail.lastAirDate,
      status: detail.status,
      numberOfSeasons: detail.numberOfSeasons,
      numberOfEpisodes: detail.numberOfEpisodes,
      genres: detail.genres,
      networks: detail.networks,
      voteAverage: detail.voteAverage,
      tmdbId: detail.id,
      tvdbId: detail.externalIds?.tvdbId,
      imdbId: detail.externalIds?.imdbId,
    );
  }

  Future<void> _cacheMovie(MovieDetail detail) async {
    final store = ref.read(knowledgeStoreProvider);
    await store.createMovie(
      name: detail.title,
      overview: detail.overview,
      posterPath: detail.posterPath,
      backdropPath: detail.backdropPath,
      releaseDate: detail.releaseDate,
      runtime: detail.runtime,
      genres: detail.genres,
      voteAverage: detail.voteAverage,
      tmdbId: detail.id,
      imdbId: detail.externalIds?.imdbId,
    );
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.kabukBackground,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _ErrorBody(
                  message: _error!,
                  onBack: () => Navigator.of(context).pop(),
                )
              : _isTv
                  ? _buildTvBody(context)
                  : _buildMovieBody(context),
    );
  }

  // ---------------------------------------------------------------------------
  // TV series body
  // ---------------------------------------------------------------------------

  Widget _buildTvBody(BuildContext context) {
    final series = _tvSeries!;
    final yearRange = _tvYearRange(series);
    final backdropUrl =
        TmdbImageHelper.url(series.backdropPath, size: MediaImageSize.large);
    final posterUrl =
        TmdbImageHelper.url(series.posterPath, size: MediaImageSize.medium);

    return CustomScrollView(
      slivers: [
        _BackdropAppBar(
          backdropUrl: backdropUrl,
          title: series.name,
          onBack: () => Navigator.of(context).pop(),
        ),
        SliverToBoxAdapter(
          child: _buildTvHeader(context, series, posterUrl, yearRange),
        ),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: KabukTheme.spacingMd),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              // Genre chips.
              if (series.genres.isNotEmpty) ...[
                _GenreChips(genres: series.genres),
                const SizedBox(height: KabukTheme.spacingMd),
              ],

              // Overview.
              if (series.overview != null && series.overview!.isNotEmpty) ...[
                _ExpandableOverview(
                  text: series.overview!,
                  expanded: _overviewExpanded,
                  onToggle: () =>
                      setState(() => _overviewExpanded = !_overviewExpanded),
                ),
                const SizedBox(height: KabukTheme.spacingLg),
              ],

              // Networks.
              if (series.networks.isNotEmpty) ...[
                _InfoRow(label: 'Networks', value: series.networks.join(', ')),
                const SizedBox(height: KabukTheme.spacingSm),
              ],

              // External links.
              _ExternalLinks(externalIds: series.externalIds),
              const SizedBox(height: KabukTheme.spacingLg),

              // Season selector + episodes.
              if (series.seasons.isNotEmpty) ...[
                const _SectionTitle(title: 'Seasons'),
                const SizedBox(height: KabukTheme.spacingSm),
                _SeasonSelector(
                  seasons: series.seasons,
                  selectedIndex: _selectedSeasonIndex,
                  onSelected: (index) {
                    setState(() => _selectedSeasonIndex = index);
                    _fetchSeason(series.seasons[index].seasonNumber);
                  },
                ),
                const SizedBox(height: KabukTheme.spacingMd),
                if (_loadingSeason)
                  const Padding(
                    padding:
                        EdgeInsets.symmetric(vertical: KabukTheme.spacingLg),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (_seasonDetail != null)
                  ..._seasonDetail!.episodes
                      .map((ep) => _EpisodeCard(episode: ep)),
              ],

              const SizedBox(height: KabukTheme.spacingXl),
            ]),
          ),
        ),
      ],
    );
  }

  Widget _buildTvHeader(
    BuildContext context,
    TvSeriesDetail series,
    String? posterUrl,
    String yearRange,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        KabukTheme.spacingMd,
        0,
        KabukTheme.spacingMd,
        KabukTheme.spacingMd,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _PosterImage(url: posterUrl, height: 180),
          const SizedBox(width: KabukTheme.spacingMd),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: KabukTheme.spacingSm),
                Text(
                  series.name,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: context.kabukTextPrimary,
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: KabukTheme.spacingXs),
                Text(
                  yearRange,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: context.kabukTextSecondary,
                      ),
                ),
                const SizedBox(height: KabukTheme.spacingSm),
                Row(
                  children: [
                    _RatingBadge(rating: series.voteAverage),
                    const SizedBox(width: KabukTheme.spacingSm),
                    if (series.status != null)
                      _StatusBadge(status: series.status!),
                  ],
                ),
                const SizedBox(height: KabukTheme.spacingSm),
                Text(
                  '${series.numberOfSeasons} season'
                  '${series.numberOfSeasons == 1 ? '' : 's'}'
                  ' · ${series.numberOfEpisodes} episode'
                  '${series.numberOfEpisodes == 1 ? '' : 's'}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: context.kabukTextSecondary,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Movie body
  // ---------------------------------------------------------------------------

  Widget _buildMovieBody(BuildContext context) {
    final movie = _movie!;
    final backdropUrl =
        TmdbImageHelper.url(movie.backdropPath, size: MediaImageSize.large);
    final posterUrl =
        TmdbImageHelper.url(movie.posterPath, size: MediaImageSize.medium);
    final year = movie.releaseDate?.year.toString() ?? '';
    final runtime = _formatRuntime(movie.runtime);

    return CustomScrollView(
      slivers: [
        _BackdropAppBar(
          backdropUrl: backdropUrl,
          title: movie.title,
          onBack: () => Navigator.of(context).pop(),
        ),
        SliverToBoxAdapter(
          child: _buildMovieHeader(context, movie, posterUrl, year, runtime),
        ),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: KabukTheme.spacingMd),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              // Genre chips.
              if (movie.genres.isNotEmpty) ...[
                _GenreChips(genres: movie.genres),
                const SizedBox(height: KabukTheme.spacingMd),
              ],

              // Tagline.
              if (movie.tagline != null && movie.tagline!.isNotEmpty) ...[
                Text(
                  movie.tagline!,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        fontStyle: FontStyle.italic,
                        color: context.kabukTextSecondary,
                      ),
                ),
                const SizedBox(height: KabukTheme.spacingMd),
              ],

              // Overview.
              if (movie.overview != null && movie.overview!.isNotEmpty) ...[
                _ExpandableOverview(
                  text: movie.overview!,
                  expanded: _overviewExpanded,
                  onToggle: () =>
                      setState(() => _overviewExpanded = !_overviewExpanded),
                ),
                const SizedBox(height: KabukTheme.spacingLg),
              ],

              // Budget / Revenue.
              if (movie.budget != null && movie.budget! > 0) ...[
                _InfoRow(
                  label: 'Budget',
                  value: _formatCurrency(movie.budget!),
                ),
                const SizedBox(height: KabukTheme.spacingXs),
              ],
              if (movie.revenue != null && movie.revenue! > 0) ...[
                _InfoRow(
                  label: 'Revenue',
                  value: _formatCurrency(movie.revenue!),
                ),
                const SizedBox(height: KabukTheme.spacingSm),
              ],

              // Find on Usenet placeholder.
              const SizedBox(height: KabukTheme.spacingSm),
              _UsenetButton(title: movie.title),
              const SizedBox(height: KabukTheme.spacingLg),

              // External links.
              _ExternalLinks(externalIds: movie.externalIds),

              const SizedBox(height: KabukTheme.spacingXl),
            ]),
          ),
        ),
      ],
    );
  }

  Widget _buildMovieHeader(
    BuildContext context,
    MovieDetail movie,
    String? posterUrl,
    String year,
    String runtime,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        KabukTheme.spacingMd,
        0,
        KabukTheme.spacingMd,
        KabukTheme.spacingMd,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _PosterImage(url: posterUrl, height: 180),
          const SizedBox(width: KabukTheme.spacingMd),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: KabukTheme.spacingSm),
                Text(
                  movie.title,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: context.kabukTextPrimary,
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: KabukTheme.spacingXs),
                Text(
                  [year, runtime].where((s) => s.isNotEmpty).join(' · '),
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: context.kabukTextSecondary,
                      ),
                ),
                const SizedBox(height: KabukTheme.spacingSm),
                Row(
                  children: [
                    _RatingBadge(rating: movie.voteAverage),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  String _tvYearRange(TvSeriesDetail series) {
    final start = series.firstAirDate?.year.toString() ?? '?';
    final end = series.status == 'Ended' || series.status == 'Canceled'
        ? (series.lastAirDate?.year.toString() ?? '?')
        : '';
    return end.isNotEmpty ? '$start–$end' : '$start–';
  }

  static String _formatRuntime(int? minutes) {
    if (minutes == null || minutes <= 0) return '';
    final h = minutes ~/ 60;
    final m = minutes % 60;
    if (h > 0 && m > 0) return '${h}h ${m}m';
    if (h > 0) return '${h}h';
    return '${m}m';
  }

  static String _formatCurrency(int amount) {
    if (amount >= 1000000000) {
      return '\$${(amount / 1000000000).toStringAsFixed(1)}B';
    } else if (amount >= 1000000) {
      return '\$${(amount / 1000000).toStringAsFixed(1)}M';
    } else if (amount >= 1000) {
      return '\$${(amount / 1000).toStringAsFixed(1)}K';
    }
    return '\$$amount';
  }
}

// =============================================================================
// Reusable private widgets
// =============================================================================

// ── Backdrop SliverAppBar ────────────────────────────────────────────────────

class _BackdropAppBar extends StatelessWidget {
  const _BackdropAppBar({
    required this.backdropUrl,
    required this.title,
    required this.onBack,
  });

  final String? backdropUrl;
  final String title;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return SliverAppBar(
      expandedHeight: 220,
      pinned: true,
      backgroundColor: context.kabukSurface,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_rounded),
        onPressed: onBack,
      ),
      flexibleSpace: FlexibleSpaceBar(
        title: Text(
          title,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            shadows: [Shadow(blurRadius: 8, color: Colors.black54)],
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        background: backdropUrl != null
            ? Stack(
                fit: StackFit.expand,
                children: [
                  CachedNetworkImage(
                    imageUrl: backdropUrl!,
                    fit: BoxFit.cover,
                    errorWidget: (_, _, _) =>
                        ColoredBox(color: context.kabukSurfaceVariant),
                  ),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.transparent, Colors.black87],
                      ),
                    ),
                  ),
                ],
              )
            : ColoredBox(color: context.kabukSurfaceVariant),
      ),
    );
  }
}

// ── Poster image ─────────────────────────────────────────────────────────────

class _PosterImage extends StatelessWidget {
  const _PosterImage({required this.url, required this.height});

  final String? url;
  final double height;

  @override
  Widget build(BuildContext context) {
    final width = height * 2 / 3;
    return ClipRRect(
      borderRadius: BorderRadius.circular(KabukTheme.radiusSm),
      child: SizedBox(
        width: width,
        height: height,
        child: url != null
            ? CachedNetworkImage(
                imageUrl: url!,
                fit: BoxFit.cover,
                errorWidget: (_, _, _) => _posterPlaceholder(context),
              )
            : _posterPlaceholder(context),
      ),
    );
  }

  Widget _posterPlaceholder(BuildContext context) {
    return ColoredBox(
      color: context.kabukSurfaceVariant,
      child: const Center(child: Icon(Icons.movie_outlined, size: 40)),
    );
  }
}

// ── Rating badge ─────────────────────────────────────────────────────────────

class _RatingBadge extends StatelessWidget {
  const _RatingBadge({required this.rating});

  final double? rating;

  @override
  Widget build(BuildContext context) {
    if (rating == null) return const SizedBox.shrink();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.star_rounded, size: 18, color: KabukTheme.warmAccent),
        const SizedBox(width: 3),
        Text(
          rating!.toStringAsFixed(1),
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: context.kabukTextPrimary,
              ),
        ),
      ],
    );
  }
}

// ── Status badge ─────────────────────────────────────────────────────────────

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final color = switch (status.toLowerCase()) {
      'returning series' => KabukTheme.success,
      'ended' || 'canceled' => KabukTheme.textTertiary,
      'released' => KabukTheme.accentGreen,
      _ => KabukTheme.blueAccent,
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(KabukTheme.radiusSm),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        status,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}

// ── Genre chips ──────────────────────────────────────────────────────────────

class _GenreChips extends StatelessWidget {
  const _GenreChips({required this.genres});

  final List<String> genres;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: KabukTheme.spacingSm,
      runSpacing: KabukTheme.spacingXs,
      children: genres.map((genre) {
        return Chip(
          label: Text(genre),
          labelStyle: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: context.kabukTextPrimary,
              ),
          backgroundColor: context.kabukSurfaceVariant,
          side: BorderSide.none,
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        );
      }).toList(),
    );
  }
}

// ── Expandable overview ──────────────────────────────────────────────────────

class _ExpandableOverview extends StatelessWidget {
  const _ExpandableOverview({
    required this.text,
    required this.expanded,
    required this.onToggle,
  });

  final String text;
  final bool expanded;
  final VoidCallback onToggle;

  static const _maxCollapsedLines = 4;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          text,
          maxLines: expanded ? null : _maxCollapsedLines,
          overflow: expanded ? null : TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: context.kabukTextPrimary,
                height: 1.5,
              ),
        ),
        if (text.length > 200)
          GestureDetector(
            onTap: onToggle,
            child: Padding(
              padding: const EdgeInsets.only(top: KabukTheme.spacingXs),
              child: Text(
                expanded ? 'Show less' : 'Show more',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: KabukTheme.accentGreen,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ),
          ),
      ],
    );
  }
}

// ── Info row ─────────────────────────────────────────────────────────────────

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 80,
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: context.kabukTextSecondary,
                  fontWeight: FontWeight.w600,
                ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: context.kabukTextPrimary,
                ),
          ),
        ),
      ],
    );
  }
}

// ── Section title ────────────────────────────────────────────────────────────

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: context.kabukTextPrimary,
            fontWeight: FontWeight.bold,
          ),
    );
  }
}

// ── Season selector ──────────────────────────────────────────────────────────

class _SeasonSelector extends StatelessWidget {
  const _SeasonSelector({
    required this.seasons,
    required this.selectedIndex,
    required this.onSelected,
  });

  final List<TvSeasonSummary> seasons;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: seasons.length,
        separatorBuilder: (_, _) =>
            const SizedBox(width: KabukTheme.spacingSm),
        itemBuilder: (context, index) {
          final season = seasons[index];
          final isSelected = index == selectedIndex;
          final label = season.name ?? 'Season ${season.seasonNumber}';

          return ChoiceChip(
            label: Text(label),
            selected: isSelected,
            onSelected: (_) => onSelected(index),
            labelStyle: TextStyle(
              fontSize: 13,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              color: isSelected
                  ? context.kabukTextPrimary
                  : context.kabukTextSecondary,
            ),
            selectedColor: KabukTheme.accentGreen.withValues(alpha: 0.2),
            backgroundColor: context.kabukSurfaceVariant,
            side: isSelected
                ? const BorderSide(color: KabukTheme.accentGreen)
                : BorderSide.none,
            visualDensity: VisualDensity.compact,
            showCheckmark: false,
          );
        },
      ),
    );
  }
}

// ── Episode card ─────────────────────────────────────────────────────────────

class _EpisodeCard extends StatelessWidget {
  const _EpisodeCard({required this.episode});

  final TvEpisode episode;

  @override
  Widget build(BuildContext context) {
    final stillUrl =
        TmdbImageHelper.url(episode.stillPath, size: MediaImageSize.small);
    final airDateStr =
        episode.airDate != null ? _formatDate(episode.airDate!) : null;
    final runtimeStr = episode.runtime != null ? '${episode.runtime}m' : null;
    final subtitle = [
      ?airDateStr,
      ?runtimeStr,
    ].join(' · ');

    return Padding(
      padding: const EdgeInsets.only(bottom: KabukTheme.spacingSm),
      child: Container(
        decoration: BoxDecoration(
          color: context.kabukCardColor,
          borderRadius: BorderRadius.circular(KabukTheme.radiusMd),
        ),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Episode still.
              ClipRRect(
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(KabukTheme.radiusMd),
                  bottomLeft: Radius.circular(KabukTheme.radiusMd),
                ),
                child: SizedBox(
                  width: 130,
                  child: stillUrl != null
                      ? CachedNetworkImage(
                          imageUrl: stillUrl,
                          fit: BoxFit.cover,
                          height: double.infinity,
                          errorWidget: (_, _, _) =>
                              _episodePlaceholder(context),
                        )
                      : _episodePlaceholder(context),
                ),
              ),

              // Episode details.
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(KabukTheme.spacingSm),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${episode.episodeCode}  ${episode.name ?? ''}',
                        style:
                            Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  color: context.kabukTextPrimary,
                                  fontWeight: FontWeight.w600,
                                ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      if (subtitle.isNotEmpty)
                        Text(
                          subtitle,
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: context.kabukTextSecondary,
                                  ),
                        ),
                      const SizedBox(height: KabukTheme.spacingXs),
                      if (episode.overview != null &&
                          episode.overview!.isNotEmpty)
                        Text(
                          episode.overview!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: context.kabukTextSecondary,
                                    height: 1.4,
                                  ),
                        ),
                    ],
                  ),
                ),
              ),

              // Usenet download placeholder.
              Padding(
                padding: const EdgeInsets.only(
                  right: KabukTheme.spacingXs,
                  top: KabukTheme.spacingXs,
                ),
                child: IconButton(
                  icon: const Icon(Icons.download_rounded, size: 22),
                  color: context.kabukTextSecondary,
                  tooltip: 'Find on Usenet',
                  onPressed: () {
                    // TODO: Wire up Usenet search for this episode.
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _episodePlaceholder(BuildContext context) {
    return ColoredBox(
      color: context.kabukSurfaceVariant,
      child: const Center(child: Icon(Icons.image_outlined, size: 28)),
    );
  }

  /// Formats a [DateTime] as `MMM d, yyyy` without the intl package.
  static String _formatDate(DateTime dt) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
  }
}

// ── External links ───────────────────────────────────────────────────────────

class _ExternalLinks extends StatelessWidget {
  const _ExternalLinks({required this.externalIds});

  final ExternalIds? externalIds;

  @override
  Widget build(BuildContext context) {
    if (externalIds == null) return const SizedBox.shrink();

    final links = <_ExternalLink>[
      if (externalIds!.imdbId != null)
        _ExternalLink(
          label: 'IMDb',
          url: 'https://www.imdb.com/title/${externalIds!.imdbId}',
        ),
      if (externalIds!.tvdbId != null)
        _ExternalLink(
          label: 'TVDB',
          url: 'https://thetvdb.com/?tab=series&id=${externalIds!.tvdbId}',
        ),
    ];

    if (links.isEmpty) return const SizedBox.shrink();

    return Wrap(
      spacing: KabukTheme.spacingSm,
      children: links.map((link) {
        return ActionChip(
          avatar: const Icon(Icons.open_in_new_rounded, size: 16),
          label: Text(link.label),
          labelStyle: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: KabukTheme.blueAccent,
              ),
          backgroundColor: context.kabukSurfaceVariant,
          side: BorderSide.none,
          visualDensity: VisualDensity.compact,
          onPressed: () async {
            final uri = Uri.tryParse(link.url);
            if (uri != null) {
              await launchUrl(uri, mode: LaunchMode.externalApplication);
            }
          },
        );
      }).toList(),
    );
  }
}

class _ExternalLink {
  const _ExternalLink({required this.label, required this.url});
  final String label;
  final String url;
}

// ── Usenet button (placeholder) ──────────────────────────────────────────────

class _UsenetButton extends StatelessWidget {
  const _UsenetButton({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: () {
          // TODO: Wire up Usenet search for this movie.
        },
        icon: const Icon(Icons.download_rounded),
        label: const Text('Find on Usenet'),
        style: OutlinedButton.styleFrom(
          foregroundColor: KabukTheme.accentGreen,
          side: const BorderSide(color: KabukTheme.accentGreen),
          padding: const EdgeInsets.symmetric(
            vertical: KabukTheme.spacingSm + 4,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(KabukTheme.radiusMd),
          ),
        ),
      ),
    );
  }
}

// ── Error body ───────────────────────────────────────────────────────────────

class _ErrorBody extends StatelessWidget {
  const _ErrorBody({required this.message, required this.onBack});

  final String message;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(KabukTheme.spacingLg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline_rounded,
              size: 48,
              color: context.kabukTextTertiary,
            ),
            const SizedBox(height: KabukTheme.spacingMd),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: context.kabukTextSecondary,
                  ),
            ),
            const SizedBox(height: KabukTheme.spacingLg),
            TextButton.icon(
              onPressed: onBack,
              icon: const Icon(Icons.arrow_back_rounded),
              label: const Text('Go back'),
            ),
          ],
        ),
      ),
    );
  }
}
