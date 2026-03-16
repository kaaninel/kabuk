/// Chat view — messaging-app-style entry point for the Chat tab.
///
/// This is a thin wrapper that delegates to [ConversationList],
/// which shows all conversations in a WhatsApp-style list.
/// Tapping a conversation pushes [ConversationDetail].
library;

import 'package:flutter/material.dart';
import 'package:kabuk/ui/chat/conversation_list.dart';

/// Chat view — the Chat tab in the bottom navigation.
///
/// Displays the messaging-style conversation list. Users interact
/// with contacts and agents by tapping into individual conversations.
class ChatView extends StatelessWidget {
  /// Creates a [ChatView].
  const ChatView({super.key});

  @override
  Widget build(BuildContext context) => const ConversationList();
}
