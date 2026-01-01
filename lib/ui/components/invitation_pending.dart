import 'package:cleona/core/channels/system_channels.dart';
import 'package:cleona/core/service/service_interface.dart';
import 'package:cleona/core/service/service_types.dart';

/// Whether the list entry of [conv] is marked "invitation" (S407 G-2,
/// §16.2.2 "Joining is an explicit act of the invitee").
///
/// A group: as long as this device has not joined it — the state the join
/// banner in the chat follows as well. A channel has no join step (the
/// invitation is the subscription): marked while the invitation is its only
/// news — no message yet and the invitation still unread
/// (`_announceInvitation` counts it as one unread item).
bool invitationPending(Conversation conv, ICleonaService service) {
  if (conv.isGroup) return service.groups[conv.id]?.joined == false;
  if (conv.isChannel) {
    return conv.messages.isEmpty &&
        conv.unreadCount > 0 &&
        !SystemChannels.isSystemChannel(conv.id);
  }
  return false;
}
