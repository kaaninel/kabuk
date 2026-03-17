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
