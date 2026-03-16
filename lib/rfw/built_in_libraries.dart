/// Built-in RFW widget libraries shipped with Kabuk.
///
/// These libraries provide the base set of widgets that agents
/// can reference out of the box: core layouts, notes, contacts,
/// media, calendar, and dashboard.
library;

import 'package:kabuk/rfw/models.dart';

/// Returns all built-in widget libraries.
List<RfwLibrary> builtInLibraries() => [
  _coreLibrary(),
  _notesLibrary(),
  _contactsLibrary(),
  _dashboardLibrary(),
  _mediaLibrary(),
  _calendarLibrary(),
  _chatLibrary(),
];

// =============================================================================
// kabuk:core — base layouts and utility widgets
// =============================================================================

RfwLibrary _coreLibrary() => const RfwLibrary(
  name: 'kabuk:core',
  version: '1.0.0',
  author: 'Kabuk Project',
  description: 'Base widgets and layouts for Kabuk UI.',
  widgets: {
    'Card': RfwWidgetDef(
      name: 'Card',
      description: 'Material card with title, subtitle, and body.',
      rfwSource: '''
import core.widgets;
import core.material;

widget Root = Container(
  padding: [12.0, 12.0, 12.0, 12.0],
  decoration: { color: 0xFF1E1E1E, borderRadius: [12.0, 12.0, 12.0, 12.0] },
  child: Column(
    crossAxisAlignment: "start",
    children: [
      Text(text: data.title, style: { fontSize: 16.0, fontWeight: "bold", color: 0xFFE0E0E0 }),
      SizedBox(height: 4.0),
      Text(text: data.subtitle, style: { fontSize: 13.0, color: 0xFF9E9E9E }),
      SizedBox(height: 8.0),
      Text(text: data.body, style: { fontSize: 14.0, color: 0xFFE0E0E0 }),
    ],
  ),
);
''',
      dataContract: {'title': 'string', 'subtitle': 'string', 'body': 'string'},
      events: ['onTap'],
    ),
    'ListTile': RfwWidgetDef(
      name: 'ListTile',
      description: 'Standard list tile with title and subtitle.',
      rfwSource: '''
import core.widgets;

widget Root = Padding(
  padding: [8.0, 12.0, 8.0, 12.0],
  child: Column(
    crossAxisAlignment: "start",
    children: [
      Text(text: data.title, style: { fontSize: 14.0, color: 0xFFE0E0E0 }),
      SizedBox(height: 2.0),
      Text(text: data.subtitle, style: { fontSize: 12.0, color: 0xFF9E9E9E }),
    ],
  ),
);
''',
      dataContract: {'title': 'string', 'subtitle': 'string'},
      events: ['onTap'],
    ),
    'EmptyState': RfwWidgetDef(
      name: 'EmptyState',
      description: 'Placeholder shown when no data is available.',
      rfwSource: '''
import core.widgets;

widget Root = Center(
  child: Column(
    mainAxisSize: "min",
    children: [
      Text(text: data.message, style: { fontSize: 16.0, color: 0xFF9E9E9E }),
    ],
  ),
);
''',
      dataContract: {'message': 'string'},
    ),
    'ErrorState': RfwWidgetDef(
      name: 'ErrorState',
      description: 'Error display with message.',
      rfwSource: '''
import core.widgets;

widget Root = Container(
  padding: [12.0, 12.0, 12.0, 12.0],
  decoration: { color: 0x20CF6679, borderRadius: [8.0, 8.0, 8.0, 8.0] },
  child: Text(text: data.message, style: { fontSize: 14.0, color: 0xFFCF6679 }),
);
''',
      dataContract: {'message': 'string'},
      events: ['onRetry'],
    ),
    'LoadingState': RfwWidgetDef(
      name: 'LoadingState',
      description: 'Centered loading indicator with optional message.',
      rfwSource: '''
import core.widgets;

widget Root = Center(
  child: Column(
    mainAxisSize: "min",
    children: [
      SizedBox(
        width: 32.0,
        height: 32.0,
        child: Container(
          decoration: { color: 0xFF26A69A, borderRadius: [16.0, 16.0, 16.0, 16.0] },
        ),
      ),
      SizedBox(height: 12.0),
      Text(text: data.message, style: { fontSize: 14.0, color: 0xFF9E9E9E }),
    ],
  ),
);
''',
      dataContract: {'message': 'string'},
    ),
    'Grid': RfwWidgetDef(
      name: 'Grid',
      description: 'Simple two-column layout using Rows.',
      rfwSource: '''
import core.widgets;

widget Root = Container(
  padding: [12.0, 12.0, 12.0, 12.0],
  child: Column(
    crossAxisAlignment: "start",
    children: [
      Text(text: data.title, style: { fontSize: 16.0, fontWeight: "bold", color: 0xFFE0E0E0 }),
      SizedBox(height: 8.0),
      Row(
        children: [
          Expanded(
            child: Container(
              padding: [8.0, 8.0, 8.0, 8.0],
              decoration: { color: 0xFF1E1E1E, borderRadius: [8.0, 8.0, 8.0, 8.0] },
              child: Text(text: "Item 1", style: { fontSize: 13.0, color: 0xFF9E9E9E }),
            ),
          ),
          SizedBox(width: 8.0),
          Expanded(
            child: Container(
              padding: [8.0, 8.0, 8.0, 8.0],
              decoration: { color: 0xFF1E1E1E, borderRadius: [8.0, 8.0, 8.0, 8.0] },
              child: Text(text: "Item 2", style: { fontSize: 13.0, color: 0xFF9E9E9E }),
            ),
          ),
        ],
      ),
    ],
  ),
);
''',
      dataContract: {'title': 'string'},
    ),
  },
);

// =============================================================================
// kabuk:notes — note display widgets
// =============================================================================

RfwLibrary _notesLibrary() => const RfwLibrary(
  name: 'kabuk:notes',
  version: '1.0.0',
  author: 'Kabuk Project',
  description: 'Note display and preview widgets.',
  dependencies: ['kabuk:core'],
  schemaTypes: ['https://schema.org/Note'],
  widgets: {
    'NoteCard': RfwWidgetDef(
      name: 'NoteCard',
      description: 'Compact preview card for a note.',
      rfwSource: '''
import core.widgets;

widget Root = Container(
  padding: [12.0, 12.0, 12.0, 12.0],
  decoration: { color: 0xFF1E1E1E, borderRadius: [12.0, 12.0, 12.0, 12.0], border: { color: 0xFF333333, width: 0.5 } },
  child: Column(
    crossAxisAlignment: "start",
    children: [
      Text(text: data.name, style: { fontSize: 15.0, fontWeight: "bold", color: 0xFFE0E0E0 }),
      SizedBox(height: 4.0),
      Text(text: data.text, maxLines: 3, style: { fontSize: 13.0, color: 0xFF9E9E9E }),
      SizedBox(height: 8.0),
      Text(text: data.dateCreated, style: { fontSize: 11.0, color: 0xFF666666 }),
    ],
  ),
);
''',
      dataContract: {
        'name': 'string',
        'text': 'string',
        'dateCreated': 'string',
      },
      events: ['onTap', 'onDelete'],
    ),
    'NoteDetail': RfwWidgetDef(
      name: 'NoteDetail',
      description: 'Full note view with all details.',
      rfwSource: '''
import core.widgets;

widget Root = Padding(
  padding: [16.0, 16.0, 16.0, 16.0],
  child: Column(
    crossAxisAlignment: "start",
    children: [
      Text(text: data.name, style: { fontSize: 20.0, fontWeight: "bold", color: 0xFFE0E0E0 }),
      SizedBox(height: 8.0),
      Text(text: data.dateCreated, style: { fontSize: 12.0, color: 0xFF666666 }),
      SizedBox(height: 16.0),
      Text(text: data.text, style: { fontSize: 14.0, color: 0xFFE0E0E0, height: 1.5 }),
    ],
  ),
);
''',
      dataContract: {
        'name': 'string',
        'text': 'string',
        'dateCreated': 'string',
      },
      events: ['onEdit', 'onDelete'],
    ),
  },
);

// =============================================================================
// kabuk:contacts — contact display widgets
// =============================================================================

RfwLibrary _contactsLibrary() => const RfwLibrary(
  name: 'kabuk:contacts',
  version: '1.0.0',
  author: 'Kabuk Project',
  description: 'Contact display widgets.',
  dependencies: ['kabuk:core'],
  schemaTypes: ['https://schema.org/Person'],
  widgets: {
    'ContactCard': RfwWidgetDef(
      name: 'ContactCard',
      description: 'Contact info card with name and details.',
      rfwSource: '''
import core.widgets;

widget Root = Container(
  padding: [12.0, 12.0, 12.0, 12.0],
  decoration: { color: 0xFF1E1E1E, borderRadius: [12.0, 12.0, 12.0, 12.0] },
  child: Row(
    children: [
      Container(
        width: 40.0,
        height: 40.0,
        decoration: { color: 0x4000897B, borderRadius: [20.0, 20.0, 20.0, 20.0] },
        child: Center(
          child: Text(text: data.initial, style: { fontSize: 16.0, color: 0xFF26A69A }),
        ),
      ),
      SizedBox(width: 12.0),
      Column(
        crossAxisAlignment: "start",
        children: [
          Text(text: data.name, style: { fontSize: 15.0, fontWeight: "bold", color: 0xFFE0E0E0 }),
          SizedBox(height: 2.0),
          Text(text: data.email, style: { fontSize: 13.0, color: 0xFF9E9E9E }),
        ],
      ),
    ],
  ),
);
''',
      dataContract: {'name': 'string', 'email': 'string', 'initial': 'string'},
      events: ['onTap'],
    ),
  },
);

// =============================================================================
// kabuk:dashboard — explore view widgets
// =============================================================================

// =============================================================================
// kabuk:media — media display widgets
// =============================================================================

RfwLibrary _mediaLibrary() => const RfwLibrary(
  name: 'kabuk:media',
  version: '1.0.0',
  author: 'Kabuk Project',
  description: 'Media display widgets.',
  dependencies: ['kabuk:core'],
  schemaTypes: [
    'https://schema.org/ImageObject',
    'https://schema.org/VideoObject',
    'https://schema.org/AudioObject',
  ],
  widgets: {
    'ImageCard': RfwWidgetDef(
      name: 'ImageCard',
      description: 'Image thumbnail card with metadata.',
      rfwSource: '''
import core.widgets;

widget Root = Container(
  padding: [12.0, 12.0, 12.0, 12.0],
  decoration: { color: 0xFF1E1E1E, borderRadius: [12.0, 12.0, 12.0, 12.0], border: { color: 0xFF333333, width: 0.5 } },
  child: Column(
    crossAxisAlignment: "start",
    children: [
      Container(
        height: 120.0,
        decoration: { color: 0xFF333333, borderRadius: [8.0, 8.0, 8.0, 8.0] },
        child: Center(
          child: Text(text: data.format, style: { fontSize: 20.0, color: 0xFF9E9E9E }),
        ),
      ),
      SizedBox(height: 8.0),
      Text(text: data.name, style: { fontSize: 15.0, fontWeight: "bold", color: 0xFFE0E0E0 }),
      SizedBox(height: 4.0),
      Row(
        children: [
          Text(text: data.format, style: { fontSize: 12.0, color: 0xFF9E9E9E }),
          SizedBox(width: 8.0),
          Text(text: data.size, style: { fontSize: 12.0, color: 0xFF666666 }),
        ],
      ),
    ],
  ),
);
''',
      dataContract: {'name': 'string', 'format': 'string', 'size': 'string'},
      events: ['onTap'],
    ),
    'VideoCard': RfwWidgetDef(
      name: 'VideoCard',
      description: 'Video preview card with play indicator and duration.',
      rfwSource: '''
import core.widgets;

widget Root = Container(
  padding: [12.0, 12.0, 12.0, 12.0],
  decoration: { color: 0xFF1E1E1E, borderRadius: [12.0, 12.0, 12.0, 12.0], border: { color: 0xFF333333, width: 0.5 } },
  child: Column(
    crossAxisAlignment: "start",
    children: [
      Container(
        height: 120.0,
        decoration: { color: 0xFF333333, borderRadius: [8.0, 8.0, 8.0, 8.0] },
        child: Center(
          child: Container(
            width: 48.0,
            height: 48.0,
            decoration: { color: 0x4000897B, borderRadius: [24.0, 24.0, 24.0, 24.0] },
            child: Center(
              child: Text(text: "▶", style: { fontSize: 24.0, color: 0xFF26A69A }),
            ),
          ),
        ),
      ),
      SizedBox(height: 8.0),
      Text(text: data.name, style: { fontSize: 15.0, fontWeight: "bold", color: 0xFFE0E0E0 }),
      SizedBox(height: 4.0),
      Row(
        children: [
          Text(text: data.format, style: { fontSize: 12.0, color: 0xFF9E9E9E }),
          SizedBox(width: 8.0),
          Text(text: data.duration, style: { fontSize: 12.0, color: 0xFF26A69A }),
          SizedBox(width: 8.0),
          Text(text: data.size, style: { fontSize: 12.0, color: 0xFF666666 }),
        ],
      ),
    ],
  ),
);
''',
      dataContract: {
        'name': 'string',
        'format': 'string',
        'duration': 'string',
        'size': 'string',
      },
      events: ['onTap', 'onPlay'],
    ),
    'AudioCard': RfwWidgetDef(
      name: 'AudioCard',
      description: 'Compact audio item with icon, name, and duration.',
      rfwSource: '''
import core.widgets;

widget Root = Container(
  padding: [10.0, 12.0, 10.0, 12.0],
  decoration: { color: 0xFF1E1E1E, borderRadius: [8.0, 8.0, 8.0, 8.0], border: { color: 0xFF333333, width: 0.5 } },
  child: Row(
    children: [
      Container(
        width: 36.0,
        height: 36.0,
        decoration: { color: 0x4000897B, borderRadius: [18.0, 18.0, 18.0, 18.0] },
        child: Center(
          child: Text(text: "♪", style: { fontSize: 16.0, color: 0xFF26A69A }),
        ),
      ),
      SizedBox(width: 12.0),
      Expanded(
        child: Column(
          crossAxisAlignment: "start",
          children: [
            Text(text: data.name, style: { fontSize: 14.0, fontWeight: "bold", color: 0xFFE0E0E0 }),
            SizedBox(height: 2.0),
            Text(text: data.format, style: { fontSize: 12.0, color: 0xFF9E9E9E }),
          ],
        ),
      ),
      Text(text: data.duration, style: { fontSize: 13.0, color: 0xFF26A69A }),
    ],
  ),
);
''',
      dataContract: {
        'name': 'string',
        'duration': 'string',
        'format': 'string',
      },
      events: ['onTap', 'onPlay'],
    ),
    'Gallery': RfwWidgetDef(
      name: 'Gallery',
      description: 'Vertical list of media items with name, type, and size.',
      rfwSource: '''
import core.widgets;

widget Root = Container(
  padding: [12.0, 12.0, 12.0, 12.0],
  decoration: { color: 0xFF1E1E1E, borderRadius: [12.0, 12.0, 12.0, 12.0] },
  child: Column(
    crossAxisAlignment: "start",
    children: [
      Text(text: data.title, style: { fontSize: 16.0, fontWeight: "bold", color: 0xFFE0E0E0 }),
      SizedBox(height: 4.0),
      Text(text: data.count, style: { fontSize: 12.0, color: 0xFF9E9E9E }),
    ],
  ),
);
''',
      dataContract: {'title': 'string', 'count': 'string'},
      events: ['onTap'],
    ),
  },
);

// =============================================================================
// kabuk:calendar — event display widgets
// =============================================================================

RfwLibrary _calendarLibrary() => const RfwLibrary(
  name: 'kabuk:calendar',
  version: '1.0.0',
  author: 'Kabuk Project',
  description: 'Calendar and event display widgets.',
  dependencies: ['kabuk:core'],
  schemaTypes: ['https://schema.org/Event'],
  widgets: {
    'EventCard': RfwWidgetDef(
      name: 'EventCard',
      description:
          'Event card showing name, dates, and location with green accent.',
      rfwSource: '''
import core.widgets;

widget Root = Container(
  padding: [12.0, 12.0, 12.0, 12.0],
  decoration: { color: 0xFF1E1E1E, borderRadius: [12.0, 12.0, 12.0, 12.0], border: { color: 0xFF333333, width: 0.5 } },
  child: Row(
    children: [
      Container(
        width: 4.0,
        height: 60.0,
        decoration: { color: 0xFF26A69A, borderRadius: [2.0, 2.0, 2.0, 2.0] },
      ),
      SizedBox(width: 12.0),
      Expanded(
        child: Column(
          crossAxisAlignment: "start",
          children: [
            Text(text: data.name, style: { fontSize: 15.0, fontWeight: "bold", color: 0xFFE0E0E0 }),
            SizedBox(height: 4.0),
            Row(
              children: [
                Text(text: data.startDate, style: { fontSize: 12.0, color: 0xFF26A69A }),
                Text(text: " — ", style: { fontSize: 12.0, color: 0xFF666666 }),
                Text(text: data.endDate, style: { fontSize: 12.0, color: 0xFF26A69A }),
              ],
            ),
            SizedBox(height: 2.0),
            Text(text: data.location, style: { fontSize: 12.0, color: 0xFF9E9E9E }),
          ],
        ),
      ),
    ],
  ),
);
''',
      dataContract: {
        'name': 'string',
        'startDate': 'string',
        'endDate': 'string',
        'location': 'string',
      },
      events: ['onTap'],
    ),
    'EventList': RfwWidgetDef(
      name: 'EventList',
      description: 'Vertical list of events with title and count.',
      rfwSource: '''
import core.widgets;

widget Root = Container(
  padding: [12.0, 12.0, 12.0, 12.0],
  decoration: { color: 0xFF1E1E1E, borderRadius: [12.0, 12.0, 12.0, 12.0] },
  child: Column(
    crossAxisAlignment: "start",
    children: [
      Text(text: data.title, style: { fontSize: 16.0, fontWeight: "bold", color: 0xFFE0E0E0 }),
      SizedBox(height: 4.0),
      Text(text: data.count, style: { fontSize: 12.0, color: 0xFF9E9E9E }),
    ],
  ),
);
''',
      dataContract: {'title': 'string', 'count': 'string'},
      events: ['onTap'],
    ),
  },
);

// =============================================================================
// kabuk:chat — conversation and message widgets
// =============================================================================

RfwLibrary _chatLibrary() => const RfwLibrary(
  name: 'kabuk:chat',
  version: '1.0.0',
  author: 'Kabuk Project',
  description: 'Chat and conversation display widgets.',
  dependencies: ['kabuk:core'],
  schemaTypes: [
    'https://schema.org/Message',
    'https://schema.org/Conversation',
  ],
  widgets: {
    'MessageBubble': RfwWidgetDef(
      name: 'MessageBubble',
      description: 'A simplified message display with sender, text, and time.',
      rfwSource: '''
import core.widgets;

widget Root = Container(
  padding: [10.0, 12.0, 10.0, 12.0],
  decoration: { color: 0xFF1E1E1E, borderRadius: [12.0, 12.0, 12.0, 12.0] },
  child: Column(
    crossAxisAlignment: "start",
    children: [
      Row(
        children: [
          Container(
            width: 28.0,
            height: 28.0,
            decoration: { color: 0x4000897B, borderRadius: [14.0, 14.0, 14.0, 14.0] },
            child: Center(
              child: Text(text: data.sender, maxLines: 1, style: { fontSize: 11.0, color: 0xFF26A69A }),
            ),
          ),
          SizedBox(width: 8.0),
          Text(text: data.sender, style: { fontSize: 13.0, fontWeight: "bold", color: 0xFFE0E0E0 }),
          Spacer(),
          Text(text: data.time, style: { fontSize: 11.0, color: 0xFF666666 }),
        ],
      ),
      SizedBox(height: 6.0),
      Padding(
        padding: [36.0, 0.0, 0.0, 0.0],
        child: Text(text: data.text, style: { fontSize: 14.0, color: 0xFFE0E0E0 }),
      ),
    ],
  ),
);
''',
      dataContract: {'sender': 'string', 'text': 'string', 'time': 'string'},
      events: ['onTap'],
    ),
    'ConversationList': RfwWidgetDef(
      name: 'ConversationList',
      description: 'List of conversations with title and last message time.',
      rfwSource: '''
import core.widgets;

widget Root = Container(
  padding: [12.0, 12.0, 12.0, 12.0],
  decoration: { color: 0xFF1E1E1E, borderRadius: [12.0, 12.0, 12.0, 12.0] },
  child: Column(
    crossAxisAlignment: "start",
    children: [
      Text(text: data.title, style: { fontSize: 16.0, fontWeight: "bold", color: 0xFFE0E0E0 }),
      SizedBox(height: 4.0),
      Text(text: data.count, style: { fontSize: 12.0, color: 0xFF9E9E9E }),
    ],
  ),
);
''',
      dataContract: {'title': 'string', 'count': 'string'},
      events: ['onTap'],
    ),
  },
);

// =============================================================================
// kabuk:dashboard — explore view widgets
// =============================================================================

RfwLibrary _dashboardLibrary() => const RfwLibrary(
  name: 'kabuk:dashboard',
  version: '1.0.0',
  author: 'Kabuk Project',
  description: 'Dashboard and stats widgets for the Explore view.',
  dependencies: ['kabuk:core'],
  widgets: {
    'StatWidget': RfwWidgetDef(
      name: 'StatWidget',
      description: 'Number/stat display with label.',
      rfwSource: '''
import core.widgets;

widget Root = Container(
  padding: [16.0, 16.0, 16.0, 16.0],
  decoration: { color: 0xFF1E1E1E, borderRadius: [12.0, 12.0, 12.0, 12.0] },
  child: Column(
    children: [
      Text(text: data.value, style: { fontSize: 28.0, fontWeight: "bold", color: 0xFF26A69A }),
      SizedBox(height: 4.0),
      Text(text: data.label, style: { fontSize: 13.0, color: 0xFF9E9E9E }),
    ],
  ),
);
''',
      dataContract: {'value': 'string', 'label': 'string'},
    ),
    'QuickAction': RfwWidgetDef(
      name: 'QuickAction',
      description: 'Action button with label.',
      rfwSource: '''
import core.widgets;

widget Root = GestureDetector(
  onTap: event "onTap" {},
  child: Container(
    padding: [12.0, 16.0, 12.0, 16.0],
    decoration: { color: 0x2000897B, borderRadius: [12.0, 12.0, 12.0, 12.0] },
    child: Center(
      child: Text(text: data.label, style: { fontSize: 14.0, color: 0xFF26A69A, fontWeight: "bold" }),
    ),
  ),
);
''',
      dataContract: {'label': 'string'},
      events: ['onTap'],
    ),
  },
);
