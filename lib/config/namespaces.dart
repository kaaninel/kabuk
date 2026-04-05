/// RDF namespace constants and URI helpers for the knowledge store.
///
/// All namespace prefixes, type URIs, and predicate URIs used throughout
/// Kabuk are centralised here to avoid string duplication and typos.
library;

/// RDF namespace URI prefixes and well-known predicate/type constants.
///
/// Usage:
/// ```dart
/// store.mutate(
///   subject: NS.entity('Person', uuid),
///   predicate: NS.schemaName,
///   object: 'Alice',
/// );
/// ```
abstract final class NS {
  // ---------------------------------------------------------------------------
  // Namespace prefixes
  // ---------------------------------------------------------------------------

  /// Schema.org vocabulary.
  static const String schema = 'https://schema.org/';

  /// Kabuk-specific vocabulary.
  static const String kabuk = 'kabuk:';

  /// RDF core vocabulary.
  static const String rdf = 'http://www.w3.org/1999/02/22-rdf-syntax-ns#';

  /// RDF Schema vocabulary.
  static const String rdfs = 'http://www.w3.org/2000/01/rdf-schema#';

  /// XML Schema Datatypes.
  static const String xsd = 'http://www.w3.org/2001/XMLSchema#';

  // ---------------------------------------------------------------------------
  // Common RDF / RDFS predicates
  // ---------------------------------------------------------------------------

  /// `rdf:type` — the type predicate.
  static const String rdfType = '${rdf}type';

  /// `rdfs:label` — human-readable label.
  static const String rdfsLabel = '${rdfs}label';

  // ---------------------------------------------------------------------------
  // Schema.org types
  // ---------------------------------------------------------------------------

  /// `schema:Note` type URI.
  static const String schemaNote = '${schema}Note';

  /// `schema:Person` type URI.
  static const String schemaPerson = '${schema}Person';

  /// `schema:Event` type URI.
  static const String schemaEvent = '${schema}Event';

  /// `schema:MediaObject` type URI.
  static const String schemaMediaObject = '${schema}MediaObject';

  /// `schema:ImageObject` type URI.
  static const String schemaImageObject = '${schema}ImageObject';

  /// `schema:VideoObject` type URI.
  static const String schemaVideoObject = '${schema}VideoObject';

  /// `schema:AudioObject` type URI.
  static const String schemaAudioObject = '${schema}AudioObject';

  /// `schema:Message` type URI.
  static const String schemaMessage = '${schema}Message';

  /// `schema:Action` type URI.
  static const String schemaAction = '${schema}Action';

  /// `schema:Place` type URI.
  static const String schemaPlace = '${schema}Place';

  /// `schema:Organization` type URI.
  static const String schemaOrganization = '${schema}Organization';

  /// `schema:ContactPoint` type URI.
  static const String schemaContactPoint = '${schema}ContactPoint';

  /// `schema:Article` type URI.
  static const String schemaArticle = '${schema}Article';

  /// `schema:DataFeed` type URI.
  static const String schemaDataFeed = '${schema}DataFeed';

  /// `schema:Product` type URI.
  static const String schemaProduct = '${schema}Product';

  /// `schema:WebPage` type URI.
  static const String schemaWebPage = '${schema}WebPage';

  /// `schema:WebSite` type URI.
  static const String schemaWebSite = '${schema}WebSite';

  /// `schema:Offer` type URI.
  static const String schemaOffer = '${schema}Offer';

  /// `schema:Review` type URI.
  static const String schemaReview = '${schema}Review';

  /// `schema:AggregateRating` type URI.
  static const String schemaAggregateRating = '${schema}AggregateRating';

  /// `schema:BreadcrumbList` type URI.
  static const String schemaBreadcrumbList = '${schema}BreadcrumbList';

  /// `schema:ListItem` type URI.
  static const String schemaListItem = '${schema}ListItem';

  /// `schema:SiteNavigationElement` type URI.
  static const String schemaSiteNavigationElement = '${schema}SiteNavigationElement';

  /// `schema:PostalAddress` type URI.
  static const String schemaPostalAddress = '${schema}PostalAddress';

  /// `schema:GeoCoordinates` type URI.
  static const String schemaGeoCoordinates = '${schema}GeoCoordinates';

  /// `schema:CreativeWork` type URI.
  static const String schemaCreativeWork = '${schema}CreativeWork';

  /// `schema:CollectionPage` type URI.
  static const String schemaCollectionPage = '${schema}CollectionPage';

  /// `schema:ItemList` type URI.
  static const String schemaItemList = '${schema}ItemList';

  /// `schema:HowTo` type URI.
  static const String schemaHowTo = '${schema}HowTo';

  /// `schema:Recipe` type URI.
  static const String schemaRecipe = '${schema}Recipe';

  /// `schema:FAQPage` type URI.
  static const String schemaFAQPage = '${schema}FAQPage';

  /// `schema:Question` type URI.
  static const String schemaQuestion = '${schema}Question';

  /// `schema:Answer` type URI.
  static const String schemaAnswer = '${schema}Answer';

  // ---------------------------------------------------------------------------
  // Schema.org Movie/TV types
  // ---------------------------------------------------------------------------

  /// `schema:TVSeries` type URI.
  static const String schemaTVSeries = '${schema}TVSeries';

  /// `schema:TVSeason` type URI.
  static const String schemaTVSeason = '${schema}TVSeason';

  /// `schema:TVEpisode` type URI.
  static const String schemaTVEpisode = '${schema}TVEpisode';

  /// `schema:Movie` type URI.
  static const String schemaMovie = '${schema}Movie';

  // ---------------------------------------------------------------------------
  // Schema.org common predicates
  // ---------------------------------------------------------------------------

  /// `schema:name` — the name of the item.
  static const String schemaName = '${schema}name';

  /// `schema:description` — a description of the item.
  static const String schemaDescription = '${schema}description';

  /// `schema:text` — the textual content of a note or message.
  static const String schemaText = '${schema}text';

  /// `schema:dateCreated` — the date the item was created.
  static const String schemaDateCreated = '${schema}dateCreated';

  /// `schema:dateModified` — the date the item was last modified.
  static const String schemaDateModified = '${schema}dateModified';

  /// `schema:startDate` — the start date of an event.
  static const String schemaStartDate = '${schema}startDate';

  /// `schema:endDate` — the end date of an event.
  static const String schemaEndDate = '${schema}endDate';

  /// `schema:location` — the location of an event or place.
  static const String schemaLocation = '${schema}location';

  /// `schema:sender` — the sender of a message.
  static const String schemaSender = '${schema}sender';

  /// `schema:recipient` — the recipient of a message.
  static const String schemaRecipient = '${schema}recipient';

  /// `schema:image` — an image associated with the item.
  static const String schemaImage = '${schema}image';

  /// `schema:email` — an email address.
  static const String schemaEmail = '${schema}email';

  /// `schema:telephone` — a telephone number.
  static const String schemaTelephone = '${schema}telephone';

  /// `schema:givenName` — a person's given (first) name.
  static const String schemaGivenName = '${schema}givenName';

  /// `schema:familyName` — a person's family (last) name.
  static const String schemaFamilyName = '${schema}familyName';

  /// `schema:contentUrl` — the URL of the actual content (media files).
  static const String schemaContentUrl = '${schema}contentUrl';

  /// `schema:encodingFormat` — the MIME type of the content.
  static const String schemaEncodingFormat = '${schema}encodingFormat';

  /// `schema:contentSize` — the file size in bytes.
  static const String schemaContentSize = '${schema}contentSize';

  /// `schema:width` — the width of a media object.
  static const String schemaWidth = '${schema}width';

  /// `schema:height` — the height of a media object.
  static const String schemaHeight = '${schema}height';

  /// `schema:duration` — the duration of an audio/video object.
  static const String schemaDuration = '${schema}duration';

  /// `schema:thumbnail` — a thumbnail image for a media object.
  static const String schemaThumbnail = '${schema}thumbnail';

  /// `schema:organizer` — the organizer of an event.
  static const String schemaOrganizer = '${schema}organizer';

  /// `schema:url` — the canonical URL of the item.
  static const String schemaUrl = '${schema}url';

  /// `schema:datePublished` — the date the item was published.
  static const String schemaDatePublished = '${schema}datePublished';

  /// `schema:author` — the author of the content.
  static const String schemaAuthor = '${schema}author';

  /// `schema:identifier` — a unique identifier for the item.
  static const String schemaIdentifier = '${schema}identifier';

  /// `schema:dataFeedElement` — links a DataFeed to its elements.
  static const String schemaDataFeedElement = '${schema}dataFeedElement';

  /// `schema:price` — the price of a product/offer.
  static const String schemaPrice = '${schema}price';

  /// `schema:priceCurrency` — the currency of the price (ISO 4217).
  static const String schemaPriceCurrency = '${schema}priceCurrency';

  /// `schema:brand` — the brand of a product.
  static const String schemaBrand = '${schema}brand';

  /// `schema:sku` — the stock keeping unit of a product.
  static const String schemaSku = '${schema}sku';

  /// `schema:gtin` — the Global Trade Item Number of a product.
  static const String schemaGtin = '${schema}gtin';

  /// `schema:category` — a category for the item.
  static const String schemaCategory = '${schema}category';

  /// `schema:ratingValue` — the rating value.
  static const String schemaRatingValue = '${schema}ratingValue';

  /// `schema:reviewCount` — the count of reviews.
  static const String schemaReviewCount = '${schema}reviewCount';

  /// `schema:bestRating` — the highest rating value.
  static const String schemaBestRating = '${schema}bestRating';

  /// `schema:worstRating` — the lowest rating value.
  static const String schemaWorstRating = '${schema}worstRating';

  /// `schema:streetAddress` — street address.
  static const String schemaStreetAddress = '${schema}streetAddress';

  /// `schema:postalCode` — postal code.
  static const String schemaPostalCode = '${schema}postalCode';

  /// `schema:addressLocality` — city/locality.
  static const String schemaAddressLocality = '${schema}addressLocality';

  /// `schema:addressRegion` — state/region.
  static const String schemaAddressRegion = '${schema}addressRegion';

  /// `schema:addressCountry` — country.
  static const String schemaAddressCountry = '${schema}addressCountry';

  /// `schema:geo` — the geo coordinates.
  static const String schemaGeo = '${schema}geo';

  /// `schema:latitude` — latitude.
  static const String schemaLatitude = '${schema}latitude';

  /// `schema:longitude` — longitude.
  static const String schemaLongitude = '${schema}longitude';

  /// `schema:offers` — an offer for a product.
  static const String schemaOffers = '${schema}offers';

  /// `schema:aggregateRating` — the overall rating.
  static const String schemaAggregateRatingPred = '${schema}aggregateRating';

  /// `schema:review` — a review of the item.
  static const String schemaReviewPred = '${schema}review';

  /// `schema:reviewBody` — the body text of a review.
  static const String schemaReviewBody = '${schema}reviewBody';

  /// `schema:publisher` — the publisher of the content.
  static const String schemaPublisher = '${schema}publisher';

  /// `schema:mainEntityOfPage` — the main entity described by the page.
  static const String schemaMainEntityOfPage = '${schema}mainEntityOfPage';

  /// `schema:isPartOf` — indicates the item is part of another item.
  static const String schemaIsPartOf = '${schema}isPartOf';

  /// `schema:hasPart` — indicates the item has a part.
  static const String schemaHasPart = '${schema}hasPart';

  /// `schema:about` — the subject matter of the content.
  static const String schemaAbout = '${schema}about';

  /// `schema:mentions` — an entity mentioned in the content.
  static const String schemaMentions = '${schema}mentions';

  /// `schema:mainEntity` — the primary entity described by a creative work.
  static const String schemaMainEntity = '${schema}mainEntity';

  /// `schema:associatedMedia` — media object associated with the creative work.
  static const String schemaAssociatedMedia = '${schema}associatedMedia';

  /// `schema:keywords` — keywords or tags.
  static const String schemaKeywords = '${schema}keywords';

  /// `schema:inLanguage` — the language of the content.
  static const String schemaInLanguage = '${schema}inLanguage';

  /// `schema:position` — the position of an item in a series or list.
  static const String schemaPosition = '${schema}position';

  /// `schema:numberOfItems` — number of items in a list.
  static const String schemaNumberOfItems = '${schema}numberOfItems';

  /// `schema:itemListElement` — an element of an item list.
  static const String schemaItemListElement = '${schema}itemListElement';

  /// `schema:availability` — product availability.
  static const String schemaAvailability = '${schema}availability';

  /// `schema:condition` — product condition.
  static const String schemaItemCondition = '${schema}itemCondition';

  /// `schema:color` — color of a product.
  static const String schemaColor = '${schema}color';

  /// `schema:material` — material of a product.
  static const String schemaMaterial = '${schema}material';

  /// `schema:logo` — logo of an organization.
  static const String schemaLogo = '${schema}logo';

  /// `schema:sameAs` — URL of a reference web page indicating the item's identity.
  static const String schemaSameAs = '${schema}sameAs';

  /// `schema:jobTitle` — a person's job title.
  static const String schemaJobTitle = '${schema}jobTitle';

  /// `schema:worksFor` — organization a person works for.
  static const String schemaWorksFor = '${schema}worksFor';

  /// `schema:memberOf` — organization a person is member of.
  static const String schemaMemberOf = '${schema}memberOf';

  /// `schema:alumniOf` — educational organization a person is alumni of.
  static const String schemaAlumniOf = '${schema}alumniOf';

  // ---------------------------------------------------------------------------
  // Schema.org Movie/TV predicates
  // ---------------------------------------------------------------------------

  /// `schema:numberOfSeasons` — total number of seasons in a TV series.
  static const String schemaNumberOfSeasons = '${schema}numberOfSeasons';

  /// `schema:numberOfEpisodes` — total number of episodes.
  static const String schemaNumberOfEpisodes = '${schema}numberOfEpisodes';

  /// `schema:seasonNumber` — the season number within a series.
  static const String schemaSeasonNumber = '${schema}seasonNumber';

  /// `schema:episodeNumber` — the episode number within a season.
  static const String schemaEpisodeNumber = '${schema}episodeNumber';

  /// `schema:partOfSeries` — links a season/episode to its parent series.
  static const String schemaPartOfSeries = '${schema}partOfSeries';

  /// `schema:partOfSeason` — links an episode to its parent season.
  static const String schemaPartOfSeason = '${schema}partOfSeason';

  /// `schema:genre` — the genre of a creative work.
  static const String schemaGenre = '${schema}genre';

  /// `schema:director` — the director of a movie or episode.
  static const String schemaDirector = '${schema}director';

  /// `schema:actor` — an actor in a movie or TV series.
  static const String schemaActor = '${schema}actor';

  /// `schema:productionCompany` — the production company.
  static const String schemaProductionCompany = '${schema}productionCompany';

  /// `schema:countryOfOrigin` — the country of origin.
  static const String schemaCountryOfOrigin = '${schema}countryOfOrigin';

  // ---------------------------------------------------------------------------
  // Kabuk-specific predicates
  // ---------------------------------------------------------------------------

  /// `kabuk:tag` — a user-assigned tag on any entity.
  static const String kabukTag = '${kabuk}tag';

  /// `kabuk:folder` — the folder an entity belongs to.
  static const String kabukFolder = '${kabuk}folder';

  /// `kabuk:reminder` — a reminder timestamp associated with an entity.
  static const String kabukReminder = '${kabuk}reminder';

  /// `kabuk:conversation` — links an entity to a conversation.
  static const String kabukConversation = '${kabuk}conversation';

  /// `kabuk:read` — whether the entity has been read by the user.
  static const String kabukRead = '${kabuk}read';

  /// `kabuk:encrypted` — whether the entity's content is encrypted.
  static const String kabukEncrypted = '${kabuk}encrypted';

  /// `kabuk:participant` — a participant in a conversation.
  static const String kabukParticipant = '${kabuk}participant';

  /// `kabuk:conversationType` — the type/category of a conversation.
  static const String kabukConversationType = '${kabuk}conversationType';

  /// `kabuk:lastMessageAt` — timestamp of the last message in a conversation.
  static const String kabukLastMessageAt = '${kabuk}lastMessageAt';

  /// `kabuk:completed` — whether a task or action is completed.
  static const String kabukCompleted = '${kabuk}completed';

  /// `kabuk:priority` — the priority level of a task.
  static const String kabukPriority = '${kabuk}priority';

  /// `kabuk:dueDate` — the due date for a task.
  static const String kabukDueDate = '${kabuk}dueDate';

  /// `kabuk:agentMemory` — persistent memory stored by an agent.
  static const String kabukAgentMemory = '${kabuk}agentMemory';

  /// `kabuk:lastAccessed` — the last time an entity was accessed.
  static const String kabukLastAccessed = '${kabuk}lastAccessed';

  /// `kabuk:schemaHash` — a hash of the data schema for migration detection.
  static const String kabukSchemaHash = '${kabuk}schemaHash';

  /// `kabuk:rfwSource` — the RFW template source text for a widget.
  static const String kabukRfwSource = '${kabuk}rfwSource';

  /// `kabuk:pinOrder` — sort order for pinned items.
  static const String kabukPinOrder = '${kabuk}pinOrder';

  /// `kabuk:iconName` — Material icon name identifier.
  static const String kabukIconName = '${kabuk}iconName';

  /// `kabuk:color` — hex color string for an entity.
  static const String kabukColor = '${kabuk}color';

  /// `kabuk:feedUrl` — the source URL of a feed subscription.
  static const String kabukFeedUrl = '${kabuk}feedUrl';

  /// `kabuk:feedType` — the type of feed source (rss, reddit, atom).
  static const String kabukFeedType = '${kabuk}feedType';

  /// `kabuk:feedCategory` — a category or subreddit name for the feed.
  static const String kabukFeedCategory = '${kabuk}feedCategory';

  /// `kabuk:feedSource` — links an article back to its feed subscription.
  static const String kabukFeedSource = '${kabuk}feedSource';

  /// `kabuk:lastFetched` — the last time a feed was successfully fetched.
  static const String kabukLastFetched = '${kabuk}lastFetched';

  /// `kabuk:refreshInterval` — refresh interval in minutes for a feed.
  static const String kabukRefreshInterval = '${kabuk}refreshInterval';

  /// `kabuk:galleryImages` — JSON-encoded list of image URLs (gallery posts).
  static const String kabukGalleryImages = '${kabuk}galleryImages';

  /// `kabuk:videoUrl` — direct video URL for video posts.
  static const String kabukVideoUrl = '${kabuk}videoUrl';

  /// `kabuk:streamUrl` — resolved direct stream URL for native playback.
  static const String kabukStreamUrl = '${kabuk}streamUrl';

  /// `kabuk:nostrEventId` — Nostr event ID associated with an entity.
  static const String kabukNostrEventId = '${kabuk}nostrEventId';

  /// `kabuk:nostrPubkey` — Nostr pubkey of the author (legacy single-key).
  static const String kabukNostrPubkey = '${kabuk}nostrPubkey';

  /// `kabuk:nostrKeyEntry` — a labeled Nostr key entry for a Person.
  ///
  /// The object string is `{pubkeyHex}:{label}` where label is a
  /// user-supplied tag such as "personal", "work", or left empty for default.
  /// Multiple entries may exist per Person; each has a unique pubkey value.
  static const String kabukNostrKeyEntry = '${kabuk}nostrKeyEntry';

  /// `kabuk:nostrRelay` — preferred relay URL for an entity.
  static const String kabukNostrRelay = '${kabuk}nostrRelay';

  /// `kabuk:nostrReactionCount` — cached count of reactions on a Nostr event.
  static const String kabukNostrReactionCount = '${kabuk}nostrReactionCount';

  /// `kabuk:nostrReplyCount` — cached count of replies on a Nostr event.
  static const String kabukNostrReplyCount = '${kabuk}nostrReplyCount';

  /// `kabuk:nostrRepostCount` — cached count of reposts on a Nostr event.
  static const String kabukNostrRepostCount = '${kabuk}nostrRepostCount';

  /// `kabuk:nostrUserReacted` — whether the current user reacted to this event.
  static const String kabukNostrUserReacted = '${kabuk}nostrUserReacted';

  /// `kabuk:nostrUserReposted` — whether the current user reposted this event.
  static const String kabukNostrUserReposted = '${kabuk}nostrUserReposted';

  /// `kabuk:extractedFrom` — the source URL this entity was extracted from.
  static const String kabukExtractedFrom = '${kabuk}extractedFrom';

  /// `kabuk:sourceWebPage` — links to the WebPage entity this was found on.
  static const String kabukSourceWebPage = '${kabuk}sourceWebPage';

  /// `kabuk:semanticType` — the Schema.org type string for display purposes.
  static const String kabukSemanticType = '${kabuk}semanticType';

  /// `kabuk:confidence` — extraction confidence score (0.0-1.0).
  static const String kabukConfidence = '${kabuk}confidence';

  /// `kabuk:WebChannel` entity type — a web-based content channel.
  static const String kabukWebChannel = '${kabuk}WebChannel';

  /// `kabuk:channelDomain` — the domain of a web channel.
  static const String kabukChannelDomain = '${kabuk}channelDomain';

  /// `kabuk:channelFavicon` — favicon URL for a web channel.
  static const String kabukChannelFavicon = '${kabuk}channelFavicon';

  /// `kabuk:memberEntity` — links a channel to a member entity.
  static const String kabukMemberEntity = '${kabuk}memberEntity';

  // ---------------------------------------------------------------------------
  // Kabuk entity types
  // ---------------------------------------------------------------------------

  /// `kabuk:Conversation` entity type.
  static const String kabukConversationEntity = '${kabuk}Conversation';

  /// `kabuk:GeneratedTemplate` entity type.
  static const String kabukGeneratedTemplate = '${kabuk}GeneratedTemplate';

  /// `kabuk:Bookmark` entity type — a pinned webapp or webpage.
  static const String kabukBookmark = '${kabuk}Bookmark';

  /// `kabuk:SavedView` entity type — an AI-generated RFW view saved by the user.
  static const String kabukSavedView = '${kabuk}SavedView';

  /// `kabuk:WidgetLibrary` entity type.
  static const String kabukWidgetLibrary = '${kabuk}WidgetLibrary';

  /// `kabuk:Capability` entity type.
  static const String kabukCapability = '${kabuk}Capability';

  /// `kabuk:Preference` entity type.
  static const String kabukPreference = '${kabuk}Preference';

  /// `kabuk:FeedSubscription` entity type.
  static const String kabukFeedSubscription = '${kabuk}FeedSubscription';

  /// `kabuk:NostrNote` entity type — a Nostr text note.
  static const String kabukNostrNote = '${kabuk}NostrNote';

  /// `kabuk:SavedSearch` entity type — a persistent search query.
  static const String kabukSavedSearch = '${kabuk}SavedSearch';

  /// `kabuk:Collection` entity type — a folder/collection for organizing content.
  static const String kabukCollection = '${kabuk}Collection';

  /// `kabuk:ContentBlock` entity type — a block within a document.
  static const String kabukContentBlock = '${kabuk}ContentBlock';

  /// `kabuk:FollowedUser` entity type — a user/account the local user follows.
  static const String kabukFollowedUser = '${kabuk}FollowedUser';

  /// `kabuk:profileUrl` — the profile page URL for a followed user.
  static const String kabukProfileUrl = '${kabuk}profileUrl';

  /// `kabuk:followedAt` — ISO-8601 timestamp when the user was followed.
  static const String kabukFollowedAt = '${kabuk}followedAt';

  /// `schema:Comment` type URI — used for article/Reddit comments.
  static const String schemaCommentEntity = '${schema}Comment';

  /// `kabuk:parentArticle` — links a comment to its parent article URI.
  static const String kabukParentArticle = '${kabuk}parentArticle';

  /// `kabuk:parentComment` — links a reply to its parent comment URI.
  static const String kabukParentComment = '${kabuk}parentComment';

  /// `kabuk:score` — upvote/engagement score (integer literal).
  static const String kabukScore = '${kabuk}score';

  /// `kabuk:commentDepth` — reply nesting depth (0 = top-level).
  static const String kabukCommentDepth = '${kabuk}commentDepth';

  // ---------------------------------------------------------------------------
  // Content block predicates
  // ---------------------------------------------------------------------------

  /// `kabuk:blockType` — the type of content block (text, heading, image, etc.).
  static const String kabukBlockType = '${kabuk}blockType';

  /// `kabuk:blockOrder` — the sort order of a block within its parent document.
  static const String kabukBlockOrder = '${kabuk}blockOrder';

  /// `kabuk:parentDocument` — links a content block to its parent document.
  static const String kabukParentDocument = '${kabuk}parentDocument';

  /// `kabuk:parentCollection` — links a document or collection to its parent collection.
  static const String kabukParentCollection = '${kabuk}parentCollection';

  /// `kabuk:blockContent` — the primary text/markdown content of a block.
  static const String kabukBlockContent = '${kabuk}blockContent';

  /// `kabuk:blockMediaUri` — links a media block to its media object URI.
  static const String kabukBlockMediaUri = '${kabuk}blockMediaUri';

  /// `kabuk:blockCaption` — optional caption for a media block.
  static const String kabukBlockCaption = '${kabuk}blockCaption';

  /// `kabuk:blockLanguage` — programming language for a code block.
  static const String kabukBlockLanguage = '${kabuk}blockLanguage';

  /// `kabuk:blockChecked` — whether a checklist item is checked.
  static const String kabukBlockChecked = '${kabuk}blockChecked';

  /// `kabuk:blockLevel` — heading level (1, 2, 3) for heading blocks.
  static const String kabukBlockLevel = '${kabuk}blockLevel';

  /// `kabuk:coverImage` — URI of a cover image for a document.
  static const String kabukCoverImage = '${kabuk}coverImage';

  /// `kabuk:icon` — an emoji or icon identifier for a document/collection.
  static const String kabukIcon = '${kabuk}icon';

  /// `kabuk:pinned` — whether an item is pinned/favorited.
  static const String kabukPinned = '${kabuk}pinned';

  /// `kabuk:mediaCount` — cached count of media blocks in a document.
  static const String kabukMediaCount = '${kabuk}mediaCount';

  /// `kabuk:wordCount` — cached word count of a document.
  static const String kabukWordCount = '${kabuk}wordCount';

  // ---------------------------------------------------------------------------
  // SavedSearch predicates
  // ---------------------------------------------------------------------------

  /// `kabuk:searchQuery` — the saved search query string.
  static const String kabukSearchQuery = '${kabuk}searchQuery';

  /// `kabuk:searchSource` — where the saved search runs
  /// (nostr_hashtag, nostr_search, local).
  static const String kabukSearchSource = '${kabuk}searchSource';

  // ---------------------------------------------------------------------------
  // Usenet predicates & types
  // ---------------------------------------------------------------------------

  /// `kabuk:UsenetIndexer` entity type — a Newznab-compatible indexer.
  static const String kabukUsenetIndexer = '${kabuk}UsenetIndexer';

  /// `kabuk:UsenetProvider` entity type — an NNTP server provider.
  static const String kabukUsenetProvider = '${kabuk}UsenetProvider';

  /// `kabuk:UsenetRelease` entity type — a search result from an indexer.
  static const String kabukUsenetRelease = '${kabuk}UsenetRelease';

  /// `kabuk:NzbFile` entity type — parsed NZB metadata.
  static const String kabukNzbFile = '${kabuk}NzbFile';

  /// `kabuk:host` — hostname of a server (NNTP provider).
  static const String kabukHost = '${kabuk}host';

  /// `kabuk:port` — port number for a server connection.
  static const String kabukPort = '${kabuk}port';

  /// `kabuk:username` — username for authentication.
  static const String kabukUsername = '${kabuk}username';

  /// `kabuk:passwordRef` — Vault reference for encrypted password storage.
  static const String kabukPasswordRef = '${kabuk}passwordRef';

  /// `kabuk:connections` — number of simultaneous connections allowed.
  static const String kabukConnections = '${kabuk}connections';

  /// `kabuk:ssl` — whether the connection uses SSL/TLS.
  static const String kabukSsl = '${kabuk}ssl';

  /// `kabuk:retentionDays` — article retention period in days.
  static const String kabukRetentionDays = '${kabuk}retentionDays';

  /// `kabuk:apiKeyRef` — Vault reference for encrypted API key storage.
  static const String kabukApiKeyRef = '${kabuk}apiKeyRef';

  /// `kabuk:enabled` — whether an entity (indexer/provider) is active.
  static const String kabukEnabled = '${kabuk}enabled';

  /// `kabuk:sizeBytes` — file size in bytes.
  static const String kabukSizeBytes = '${kabuk}sizeBytes';

  /// `kabuk:usenetCategory` — Usenet content category.
  static const String kabukUsenetCategory = '${kabuk}usenetCategory';

  /// `kabuk:newsgroup` — the Usenet newsgroup name.
  static const String kabukNewsgroup = '${kabuk}newsgroup';

  /// `kabuk:nzbUrl` — URL to download the NZB file.
  static const String kabukNzbUrl = '${kabuk}nzbUrl';

  /// `kabuk:imdbId` — IMDB identifier for movie/TV content.
  static const String kabukImdbId = '${kabuk}imdbId';

  /// `kabuk:tvdbId` — TVDB identifier for TV content.
  static const String kabukTvdbId = '${kabuk}tvdbId';

  /// `kabuk:usenetAttributes` — comma-separated quality attributes (2160p, HDR, etc.).
  static const String kabukUsenetAttributes = '${kabuk}usenetAttributes';

  /// `kabuk:poster` — the Usenet poster/uploader.
  static const String kabukPoster = '${kabuk}poster';

  /// `kabuk:indexerRef` — reference to the source UsenetIndexer entity.
  static const String kabukIndexerRef = '${kabuk}indexerRef';

  /// `kabuk:releaseRef` — reference to the source UsenetRelease entity.
  static const String kabukReleaseRef = '${kabuk}releaseRef';

  /// `kabuk:totalBytes` — total size in bytes for an NZB file.
  static const String kabukTotalBytes = '${kabuk}totalBytes';

  /// `kabuk:fileCount` — number of files in an NZB.
  static const String kabukFileCount = '${kabuk}fileCount';

  /// `kabuk:segmentCount` — number of segments in an NZB.
  static const String kabukSegmentCount = '${kabuk}segmentCount';

  /// `kabuk:hasPar2` — whether the NZB contains PAR2 recovery files.
  static const String kabukHasPar2 = '${kabuk}hasPar2';

  /// `kabuk:hasRar` — whether the NZB contains RAR archives.
  static const String kabukHasRar = '${kabuk}hasRar';

  /// `kabuk:contentType` — detected MIME type of the content.
  static const String kabukContentType = '${kabuk}contentType';

  /// `kabuk:capabilities` — comma-separated capability strings.
  static const String kabukCapabilities = '${kabuk}capabilities';

  /// `kabuk:lastSync` — ISO-8601 timestamp of last synchronization.
  static const String kabukLastSync = '${kabuk}lastSync';

  // ---------------------------------------------------------------------------
  // Kabuk media (TV/Movie) predicates
  // ---------------------------------------------------------------------------

  /// `kabuk:tmdbId` — TMDB identifier for movie/TV content.
  static const String kabukTmdbId = '${kabuk}tmdbId';

  /// `kabuk:posterPath` — TMDB poster image path.
  static const String kabukPosterPath = '${kabuk}posterPath';

  /// `kabuk:backdropPath` — TMDB backdrop image path.
  static const String kabukBackdropPath = '${kabuk}backdropPath';

  /// `kabuk:voteAverage` — average user rating score.
  static const String kabukVoteAverage = '${kabuk}voteAverage';

  /// `kabuk:airDate` — original air date of a TV episode or season.
  static const String kabukAirDate = '${kabuk}airDate';

  /// `kabuk:mediaStatus` — production status (e.g. Returning Series, Ended).
  static const String kabukMediaStatus = '${kabuk}mediaStatus';

  /// `kabuk:network` — the broadcast network.
  static const String kabukNetwork = '${kabuk}network';

  /// `kabuk:runtime` — runtime in minutes.
  static const String kabukRuntime = '${kabuk}runtime';

  /// `kabuk:overview` — plot summary or synopsis.
  static const String kabukOverview = '${kabuk}overview';

  /// `kabuk:stillPath` — TMDB still image path for an episode.
  static const String kabukStillPath = '${kabuk}stillPath';

  // ---------------------------------------------------------------------------
  // Cache / expiry predicates
  // ---------------------------------------------------------------------------

  /// `kabuk:expiresAt` — ISO-8601 timestamp after which the entity should be
  /// pruned from the local knowledge store.
  ///
  /// Set automatically when an article is created:
  /// - Unread articles expire 48 hours after `schema:datePublished`.
  /// - After the user reads an article the expiry is extended to 7 days.
  /// - Bookmarked articles are excluded from pruning entirely.
  static const String kabukExpiresAt = '${kabuk}expiresAt';

  /// `kabuk:lastViewedAt` — ISO-8601 timestamp of when the user last opened
  /// the entity.  Used together with [kabukExpiresAt] to extend the lifetime
  /// of frequently-accessed articles.
  static const String kabukLastViewedAt = '${kabuk}lastViewedAt';

  /// `kabuk:browsedAt` — ISO-8601 timestamp of when the content was first
  /// browsed (fetched into the local store). Used by the content expiry
  /// service to determine whether the entity has exceeded its time-to-live.
  static const String kabukBrowsedAt = '${kabuk}browsedAt';

  /// `kabuk:saved` — boolean flag (`'true'` / `'false'`) indicating
  /// whether the user has explicitly saved this entity. Saved content is
  /// excluded from automatic expiry regardless of its age.
  static const String kabukSaved = '${kabuk}saved';

  // ---------------------------------------------------------------------------
  // Plugin predicates & types
  // ---------------------------------------------------------------------------

  /// `kabuk:Plugin` entity type — a registered content plugin.
  static const String kabukPlugin = '${kabuk}Plugin';

  /// `kabuk:pluginId` — the unique string identifier of a plugin.
  static const String kabukPluginId = '${kabuk}pluginId';

  /// `kabuk:pluginEnabled` — whether the plugin is currently enabled.
  static const String kabukPluginEnabled = '${kabuk}pluginEnabled';

  /// `kabuk:pluginConfig` — JSON-encoded configuration map for a plugin.
  static const String kabukPluginConfig = '${kabuk}pluginConfig';

  /// `kabuk:pluginInstalledAt` — ISO-8601 timestamp when the plugin was
  /// first registered in the knowledge store.
  static const String kabukPluginInstalledAt = '${kabuk}pluginInstalledAt';

  // ---------------------------------------------------------------------------
  // Kabuk streaming quality preference predicates
  // ---------------------------------------------------------------------------

  /// `kabuk:StreamingPrefs` entity type — user's streaming quality defaults.
  static const String kabukStreamingPrefs = '${kabuk}StreamingPrefs';

  /// `kabuk:preferredResolution` — preferred video resolution (2160p, 1080p, etc.).
  static const String kabukPreferredResolution = '${kabuk}preferredResolution';

  /// `kabuk:preferredCodec` — preferred video codec (x265, x264, AV1, any).
  static const String kabukPreferredCodec = '${kabuk}preferredCodec';

  /// `kabuk:preferredSource` — preferred release source (BluRay, WEB-DL, any).
  static const String kabukPreferredSource = '${kabuk}preferredSource';

  /// `kabuk:preferredAudio` — preferred audio format (Atmos, DTS-HD MA, any).
  static const String kabukPreferredAudio = '${kabuk}preferredAudio';

  /// `kabuk:preferredLanguage` — preferred content language (English, Multi, etc.).
  static const String kabukPreferredLanguage = '${kabuk}preferredLanguage';

  /// `kabuk:hdrPreference` — HDR preference (required, preferred, any, none).
  static const String kabukHdrPreference = '${kabuk}hdrPreference';

  /// `kabuk:maxFileSizeMb` — maximum file size in megabytes (0 = no limit).
  static const String kabukMaxFileSizeMb = '${kabuk}maxFileSizeMb';

  /// `kabuk:maxRetries` — maximum NZB sources to try before giving up.
  static const String kabukMaxRetries = '${kabuk}maxRetries';

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  /// Generates a Kabuk entity URI from a [type] and unique [id].
  ///
  /// ```dart
  /// final uri = NS.entity('Person', '550e8400-e29b');
  /// // => 'kabuk:Person/550e8400-e29b'
  /// ```
  static String entity(String type, String id) => '$kabuk$type/$id';
}
