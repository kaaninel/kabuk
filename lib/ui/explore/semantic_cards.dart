/// Card widgets for displaying semantic entities in the explore feed.
///
/// Each entity type (Person, Product, Place, Organization) gets a
/// compact card optimized for the feed view. Cards show the most
/// relevant information for each type at a glance.
library;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:kabuk/config/providers.dart';
import 'package:kabuk/knowledge/types/article.dart';
import 'package:kabuk/knowledge/types/organization.dart';
import 'package:kabuk/knowledge/types/person.dart';
import 'package:kabuk/knowledge/types/place.dart';
import 'package:kabuk/knowledge/types/product.dart';
import 'package:kabuk/ui/explore/article_card.dart';
import 'package:kabuk/ui/theme.dart';

// =============================================================================
// Data providers
// =============================================================================

/// Loads [ArticleData] from the knowledge store by URI.
final articleDataProvider =
    FutureProvider.family<ArticleData?, String>((ref, uri) async {
  final store = ref.read(knowledgeStoreProvider);
  return store.getArticleData(uri);
});

/// Loads [PersonData] from the knowledge store by URI.
final personDataProvider =
    FutureProvider.family<PersonData?, String>((ref, uri) async {
  final store = ref.read(knowledgeStoreProvider);
  return store.getPersonData(uri);
});

/// Loads [ProductData] from the knowledge store by URI.
final productDataProvider =
    FutureProvider.family<ProductData?, String>((ref, uri) async {
  final store = ref.read(knowledgeStoreProvider);
  return store.getProductData(uri);
});

/// Loads [PlaceData] from the knowledge store by URI.
final placeDataProvider =
    FutureProvider.family<PlaceData?, String>((ref, uri) async {
  final store = ref.read(knowledgeStoreProvider);
  return store.getPlaceData(uri);
});

/// Loads [OrganizationData] from the knowledge store by URI.
final organizationDataProvider =
    FutureProvider.family<OrganizationData?, String>((ref, uri) async {
  final store = ref.read(knowledgeStoreProvider);
  return store.getOrganizationData(uri);
});

// =============================================================================
// SemanticEntityCard — dispatcher
// =============================================================================

/// A card that renders any semantic entity type.
///
/// Loads entity data from the knowledge store and dispatches to the
/// appropriate type-specific card (PersonCard, ProductCard, etc.).
class SemanticEntityCard extends ConsumerWidget {
  /// Creates a [SemanticEntityCard].
  const SemanticEntityCard({
    required this.entityUri,
    required this.entityType,
    super.key,
  });

  /// The knowledge-store URI of the entity.
  final String entityUri;

  /// The Schema.org type (e.g. "Person", "Product", "Place", "Organization").
  final String entityType;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return switch (entityType) {
      'Article' || 'WebPage' => _ArticleEntityCard(uri: entityUri),
      'Person' => PersonCard(uri: entityUri),
      'Product' => ProductCard(uri: entityUri),
      'Place' => PlaceCard(uri: entityUri),
      'Organization' => OrganizationCard(uri: entityUri),
      _ => _UnknownEntityCard(uri: entityUri, type: entityType),
    };
  }
}

class _ArticleEntityCard extends ConsumerWidget {
  const _ArticleEntityCard({required this.uri});

  final String uri;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncData = ref.watch(articleDataProvider(uri));
    return asyncData.when(
      data: (article) {
        if (article == null) return const SizedBox.shrink();
        return ArticleCard(article: article);
      },
      loading: () => const _LoadingCard(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}

/// Simple shimmer-like loading placeholder.
class _LoadingCard extends StatelessWidget {
  const _LoadingCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 120,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: context.kabukCardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.kabukDivider),
      ),
      child: Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: context.kabukTextTertiary,
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// PersonCard
// =============================================================================

/// Displays a Person entity with avatar, name, description, and contact info.
class PersonCard extends ConsumerWidget {
  /// Creates a [PersonCard].
  const PersonCard({required this.uri, super.key});

  /// The knowledge-store URI of the person.
  final String uri;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncPerson = ref.watch(personDataProvider(uri));

    return asyncPerson.when(
      loading: () => const _CardShimmer(
        icon: Icons.person_rounded,
        accentColor: KabukTheme.purpleAccent,
      ),
      error: (_, _) => const SizedBox.shrink(),
      data: (person) {
        if (person == null) return const SizedBox.shrink();
        final isLowConfidence =
            person.confidence != null && person.confidence! < 0.6;
        return _EntityCardShell(
          accentColor: KabukTheme.purpleAccent,
          lowConfidence: isLowConfidence,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Circular avatar.
                CircleAvatar(
                  radius: 24,
                  backgroundColor: KabukTheme.purpleAccent.withAlpha(38),
                  child: const Icon(
                    Icons.person_rounded,
                    size: 24,
                    color: KabukTheme.purpleAccent,
                  ),
                ),
                const SizedBox(width: 12),
                // Text content.
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        person.name ??
                            person.givenName ??
                            person.familyName ??
                            'Unknown Person',
                        style: TextStyle(
                          color: context.kabukTextPrimary,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (person.description != null) ...[
                        const SizedBox(height: 3),
                        Text(
                          person.description!,
                          style: TextStyle(
                            color: context.kabukTextSecondary,
                            fontSize: 13,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                      if (person.email != null) ...[
                        const SizedBox(height: 6),
                        _InfoChip(
                          icon: Icons.email_outlined,
                          label: person.email!,
                          color: context.kabukTextTertiary,
                        ),
                      ],
                      if (person.telephone != null) ...[
                        const SizedBox(height: 4),
                        _InfoChip(
                          icon: Icons.phone_outlined,
                          label: person.telephone!,
                          color: context.kabukTextTertiary,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// =============================================================================
// ProductCard
// =============================================================================

/// Displays a Product entity with image, name, price, rating, and brand.
class ProductCard extends ConsumerWidget {
  /// Creates a [ProductCard].
  const ProductCard({required this.uri, super.key});

  /// The knowledge-store URI of the product.
  final String uri;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncProduct = ref.watch(productDataProvider(uri));

    return asyncProduct.when(
      loading: () => const _CardShimmer(
        icon: Icons.shopping_bag_rounded,
        accentColor: KabukTheme.accentGreen,
      ),
      error: (_, _) => const SizedBox.shrink(),
      data: (product) {
        if (product == null) return const SizedBox.shrink();
        final hasImage = product.image != null && product.image!.isNotEmpty;
        final isLowConfidence =
            product.confidence != null && product.confidence! < 0.6;
        return _EntityCardShell(
          accentColor: KabukTheme.accentGreen,
          lowConfidence: isLowConfidence,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Product image.
                if (hasImage)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: SizedBox(
                      width: 100,
                      height: 100,
                      child: CachedNetworkImage(
                        imageUrl: product.image!,
                        fit: BoxFit.cover,
                        placeholder: (_, _) =>
                            Container(color: context.kabukSurface),
                        errorWidget: (_, _, _) => Container(
                          color: context.kabukSurface,
                          child: Icon(
                            Icons.shopping_bag_rounded,
                            color: context.kabukTextTertiary,
                          ),
                        ),
                      ),
                    ),
                  )
                else
                  Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                      color: KabukTheme.accentGreen.withAlpha(25),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.shopping_bag_rounded,
                      size: 36,
                      color: KabukTheme.accentGreen,
                    ),
                  ),
                const SizedBox(width: 12),
                // Product details.
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        product.name ?? 'Product',
                        style: TextStyle(
                          color: context.kabukTextPrimary,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (product.brand != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          product.brand!,
                          style: TextStyle(
                            color: context.kabukTextSecondary,
                            fontSize: 12,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                      if (product.price != null) ...[
                        const SizedBox(height: 6),
                        Text(
                          _formatPrice(product.price!, product.priceCurrency),
                          style: const TextStyle(
                            color: KabukTheme.accentGreen,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                      if (product.ratingValue != null) ...[
                        const SizedBox(height: 4),
                        _StarRating(
                          rating: product.ratingValue!,
                          reviewCount: product.reviewCount,
                        ),
                      ],
                      if (product.availability != null) ...[
                        const SizedBox(height: 6),
                        _AvailabilityBadge(
                          availability: product.availability!,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Formats a price string with optional currency prefix.
  static String _formatPrice(String price, String? currency) {
    final symbol = switch (currency?.toUpperCase()) {
      'USD' => '\$',
      'EUR' => '€',
      'GBP' => '£',
      'JPY' || 'CNY' => '¥',
      'TRY' => '₺',
      'KRW' => '₩',
      final c? => '$c ',
      null => '',
    };
    return '$symbol$price';
  }
}

// =============================================================================
// PlaceCard
// =============================================================================

/// Displays a Place entity with name, address, and coordinates.
class PlaceCard extends ConsumerWidget {
  /// Creates a [PlaceCard].
  const PlaceCard({required this.uri, super.key});

  /// The knowledge-store URI of the place.
  final String uri;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncPlace = ref.watch(placeDataProvider(uri));

    return asyncPlace.when(
      loading: () => const _CardShimmer(
        icon: Icons.place_rounded,
        accentColor: KabukTheme.warmAccent,
      ),
      error: (_, _) => const SizedBox.shrink(),
      data: (place) {
        if (place == null) return const SizedBox.shrink();
        final address = place.formattedAddress;
        final isLowConfidence =
            place.confidence != null && place.confidence! < 0.6;
        return _EntityCardShell(
          accentColor: KabukTheme.warmAccent,
          lowConfidence: isLowConfidence,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Map pin icon.
                CircleAvatar(
                  radius: 22,
                  backgroundColor: KabukTheme.warmAccent.withAlpha(38),
                  child: const Icon(
                    Icons.place_rounded,
                    size: 22,
                    color: KabukTheme.warmAccent,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        place.name ?? 'Unknown Place',
                        style: TextStyle(
                          color: context.kabukTextPrimary,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (address != null) ...[
                        const SizedBox(height: 3),
                        Text(
                          address,
                          style: TextStyle(
                            color: context.kabukTextSecondary,
                            fontSize: 13,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                      if (place.telephone != null) ...[
                        const SizedBox(height: 6),
                        _InfoChip(
                          icon: Icons.phone_outlined,
                          label: place.telephone!,
                          color: context.kabukTextTertiary,
                        ),
                      ],
                      if (place.latitude != null &&
                          place.longitude != null &&
                          // Hide zero coordinates — indicates missing data.
                          (place.latitude != 0.0 ||
                              place.longitude != 0.0)) ...[
                        const SizedBox(height: 4),
                        Text(
                          '${place.latitude!.toStringAsFixed(4)}, '
                          '${place.longitude!.toStringAsFixed(4)}',
                          style: TextStyle(
                            color: context.kabukTextTertiary,
                            fontSize: 11,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// =============================================================================
// OrganizationCard
// =============================================================================

/// Displays an Organization entity with logo, name, description, and contacts.
class OrganizationCard extends ConsumerWidget {
  /// Creates an [OrganizationCard].
  const OrganizationCard({required this.uri, super.key});

  /// The knowledge-store URI of the organization.
  final String uri;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncOrg = ref.watch(organizationDataProvider(uri));

    return asyncOrg.when(
      loading: () => const _CardShimmer(
        icon: Icons.business_rounded,
        accentColor: KabukTheme.blueAccent,
      ),
      error: (_, _) => const SizedBox.shrink(),
      data: (org) {
        if (org == null) return const SizedBox.shrink();
        final logoUrl = org.logo ?? org.image;
        final hasLogo = logoUrl != null && logoUrl.isNotEmpty;
        final isLowConfidence =
            org.confidence != null && org.confidence! < 0.6;
        return _EntityCardShell(
          accentColor: KabukTheme.blueAccent,
          lowConfidence: isLowConfidence,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Logo / avatar.
                if (hasLogo)
                  ClipOval(
                    child: SizedBox(
                      width: 40,
                      height: 40,
                      child: CachedNetworkImage(
                        imageUrl: logoUrl,
                        fit: BoxFit.cover,
                        placeholder: (_, _) => Container(
                          color: KabukTheme.blueAccent.withAlpha(25),
                        ),
                        errorWidget: (_, _, _) => CircleAvatar(
                          radius: 20,
                          backgroundColor: KabukTheme.blueAccent.withAlpha(38),
                          child: const Icon(
                            Icons.business_rounded,
                            size: 20,
                            color: KabukTheme.blueAccent,
                          ),
                        ),
                      ),
                    ),
                  )
                else
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: KabukTheme.blueAccent.withAlpha(38),
                    child: const Icon(
                      Icons.business_rounded,
                      size: 20,
                      color: KabukTheme.blueAccent,
                    ),
                  ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        org.name ?? 'Organization',
                        style: TextStyle(
                          color: context.kabukTextPrimary,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (org.description != null) ...[
                        const SizedBox(height: 3),
                        Text(
                          org.description!,
                          style: TextStyle(
                            color: context.kabukTextSecondary,
                            fontSize: 13,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                      if (org.url != null) ...[
                        const SizedBox(height: 6),
                        _InfoChip(
                          icon: Icons.language_rounded,
                          label: _displayUrl(org.url!),
                          color: KabukTheme.blueAccent,
                        ),
                      ],
                      if (org.email != null) ...[
                        const SizedBox(height: 4),
                        _InfoChip(
                          icon: Icons.email_outlined,
                          label: org.email!,
                          color: context.kabukTextTertiary,
                        ),
                      ],
                      if (org.telephone != null) ...[
                        const SizedBox(height: 4),
                        _InfoChip(
                          icon: Icons.phone_outlined,
                          label: org.telephone!,
                          color: context.kabukTextTertiary,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Strips protocol and trailing slash for a cleaner display URL.
  static String _displayUrl(String url) {
    return url
        .replaceFirst(RegExp(r'^https?://'), '')
        .replaceFirst(RegExp(r'/$'), '');
  }
}

// =============================================================================
// Shared private widgets
// =============================================================================

/// Standard card container used by all entity cards.
class _EntityCardShell extends StatelessWidget {
  const _EntityCardShell({
    required this.accentColor,
    required this.child,
    this.lowConfidence = false,
  });

  final Color accentColor;
  final Widget child;

  /// When `true`, the card is rendered at reduced opacity with a subtle
  /// "?" indicator to signal uncertain extraction confidence.
  final bool lowConfidence;

  @override
  Widget build(BuildContext context) {
    Widget card = Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: context.kabukCardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.kabukDivider),
        boxShadow: const [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 4,
            offset: Offset(0, 1),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Accent bar at top.
              Container(height: 3, color: accentColor.withAlpha(180)),
              child,
            ],
          ),
          if (lowConfidence)
            Positioned(
              top: 7,
              right: 8,
              child: Icon(
                Icons.help_outline_rounded,
                size: 14,
                color: context.kabukTextTertiary.withAlpha(150),
              ),
            ),
        ],
      ),
    );

    if (lowConfidence) {
      card = Opacity(opacity: 0.7, child: card);
    }

    return card;
  }
}

/// Compact icon + label row used for contact details (email, phone, URL).
class _InfoChip extends StatelessWidget {
  const _InfoChip({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            label,
            style: TextStyle(color: color, fontSize: 12),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

/// Star rating display with optional review count.
class _StarRating extends StatelessWidget {
  const _StarRating({required this.rating, this.reviewCount});

  final double rating;
  final int? reviewCount;

  @override
  Widget build(BuildContext context) {
    final fullStars = rating.floor();
    final hasHalf = (rating - fullStars) >= 0.5;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < fullStars && i < 5; i++)
          const Icon(Icons.star_rounded, size: 14, color: KabukTheme.warmAccent),
        if (hasHalf && fullStars < 5)
          const Icon(Icons.star_half_rounded, size: 14, color: KabukTheme.warmAccent),
        for (var i = fullStars + (hasHalf ? 1 : 0); i < 5; i++)
          Icon(Icons.star_outline_rounded, size: 14, color: context.kabukTextTertiary),
        const SizedBox(width: 4),
        Text(
          rating.toStringAsFixed(1),
          style: TextStyle(
            color: context.kabukTextSecondary,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
        if (reviewCount != null) ...[
          const SizedBox(width: 2),
          Text(
            '($reviewCount)',
            style: TextStyle(color: context.kabukTextTertiary, fontSize: 11),
          ),
        ],
      ],
    );
  }
}

/// Availability status badge.
class _AvailabilityBadge extends StatelessWidget {
  const _AvailabilityBadge({required this.availability});

  final String availability;

  @override
  Widget build(BuildContext context) {
    final isInStock = availability.toLowerCase().contains('instock') ||
        availability.toLowerCase().contains('in stock');
    final label = isInStock ? 'In Stock' : _cleanAvailability(availability);
    final color = isInStock ? KabukTheme.accentGreen : context.kabukTextTertiary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withAlpha(25),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w500),
      ),
    );
  }

  /// Strips Schema.org URL prefix from availability values.
  static String _cleanAvailability(String raw) {
    return raw
        .replaceFirst('https://schema.org/', '')
        .replaceFirst('http://schema.org/', '')
        .replaceAllMapped(
          RegExp(r'([a-z])([A-Z])'),
          (m) => '${m[1]} ${m[2]}',
        );
  }
}

/// Loading placeholder for entity cards.
class _CardShimmer extends StatelessWidget {
  const _CardShimmer({required this.icon, required this.accentColor});

  final IconData icon;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.kabukCardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.kabukDivider),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: accentColor.withAlpha(25),
            child: Icon(icon, size: 18, color: accentColor.withAlpha(100)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  height: 12,
                  width: 120,
                  decoration: BoxDecoration(
                    color: context.kabukSurface,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  height: 10,
                  width: 80,
                  decoration: BoxDecoration(
                    color: context.kabukSurface,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Fallback card for unrecognized entity types.
class _UnknownEntityCard extends StatelessWidget {
  const _UnknownEntityCard({required this.uri, required this.type});

  final String uri;
  final String type;

  @override
  Widget build(BuildContext context) {
    return _EntityCardShell(
      accentColor: context.kabukTextTertiary,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Icon(Icons.data_object_rounded, size: 20, color: context.kabukTextTertiary),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '$type entity',
                style: TextStyle(
                  color: context.kabukTextSecondary,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
