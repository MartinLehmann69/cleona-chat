# Cleona Chat -- User Manual

Welcome to Cleona Chat. This manual explains everything you need to know to get
started and make the most of the app.

---

## Table of Contents

1. [What is Cleona Chat?](#1-what-is-cleona-chat)
2. [Getting Started](#2-getting-started)
3. [Contacts](#3-contacts)
4. [Messaging](#4-messaging)
5. [Groups](#5-groups)
6. [Public Channels](#6-public-channels)
7. [Calls](#7-calls)
8. [Multiple Identities](#8-multiple-identities)
9. [Recovery](#9-recovery)
10. [Settings](#10-settings)
11. [Security](#11-security)
12. [FAQ](#12-faq)

---

## 1. What is Cleona Chat?

Cleona Chat is a messenger that works without any central server. When you send a
message, it travels directly from your device to the recipient -- no company in the
middle, no cloud, no data center.

**Your messages belong to you.** There is no server that stores your conversations.
No one can read them, not even the developer. Everything is encrypted on your
device before it leaves, and only the intended recipient can decrypt it.

**No phone number or email required.** Your identity is created entirely on your
device using modern cryptography. You do not need to hand over any personal
information to use Cleona. No phone number, no email address, no name -- unless
you choose to set one.

**Built for the future.** Cleona uses post-quantum encryption, which means your
messages are protected even against the theoretical threat of future quantum
computers. Most messengers do not offer this yet.

**Available on Android, Linux, and Windows.** The same experience across all three
platforms.

---

## 2. Getting Started

### Installing the App

- **Android:** Download the APK from the Cleona website and install it. You may
  need to allow installation from unknown sources in your phone settings (this is
  normal for apps distributed outside the Play Store).
- **Linux (Ubuntu/Debian):** Download the .deb package and install with
  `sudo dpkg -i cleona-chat_VERSION_amd64.deb`. Launch from your application menu
  or run `cleona-chat` in a terminal.
- **Linux (Fedora/openSUSE):** Download the .rpm package and install with
  `sudo dnf install cleona-chat-VERSION.x86_64.rpm`.
- **Linux (any distro — AppImage):** Download the .AppImage file, make it
  executable (`chmod +x cleona-chat-*.AppImage`), and double-click to run. No
  installation needed.
- **Windows:** Download and run the installer.

### First Launch

When you open Cleona for the first time, a fresh identity is created automatically.
This only takes a moment. You will see your new display name (which you can change
at any time) and you are ready to chat.

There is no sign-up form, no verification code, no waiting.

### Write Down Your Seed Phrase

This is the single most important step. Go to Settings and look for your seed
phrase. It is a list of 24 words.

**Write these words down on paper and keep them safe.** This seed phrase is your
master key. If you ever lose your phone, switch devices, or need to reinstall,
these 24 words are all you need to restore your entire account -- your identity,
your contacts, your message history.

Do not store the seed phrase in a screenshot, a note on the same device, or in a
cloud service. Paper in a safe place is the best option.

If you lose your seed phrase and your device, recovery becomes much harder (though
not impossible -- see the Recovery section).

### Adding Your First Contact

You need at least one contact to start chatting. There are several ways to add
someone -- see the next section for all the details.

---

## 3. Contacts

### Adding a Contact

There are four ways to add a contact in Cleona:

**QR Code** -- The easiest method when you are in the same room. One person opens
their contact QR code (from the Contacts screen), and the other scans it. The
connection is established immediately. This also gives you the highest verification
level because you met in person.

**NFC Tap** -- If both phones support NFC, simply hold them together. The contact
exchange happens automatically. Like QR, this counts as in-person verification.

**Link** -- Share a `cleona://` link via email, SMS, or any other messenger. The
other person pastes this link into the Add Contact dialog in Cleona. This works
even when you are not on the same network. The link contains enough information
for the two devices to find each other.

**Manual Entry** -- You can also enter a contact's node ID directly (a long hex
string). This is mainly a technical fallback.

After adding a contact, a contact request is sent. The other person can accept or
decline. Once both sides have accepted, you can start chatting.

### Verification Levels

You may notice small indicators next to your contacts' names. These show how
confident you can be that the person is who they claim to be:

- **Level 1 -- Unverified:** You added this contact via a link or ID, but have not
  met in person. The connection is still fully encrypted, but you have not personally
  confirmed their identity.
- **Level 2 -- Seen:** A key exchange has been completed successfully. You are
  communicating, but identity has not been verified face to face.
- **Level 3 -- Verified:** You exchanged contacts in person via QR code or NFC.
  You know this person is who they say they are.
- **Level 4 -- Trusted:** You have explicitly marked this contact as trusted.
  This is reserved for people you know very well.

Higher verification levels do not change how encryption works -- all messages are
always fully encrypted regardless of level. The levels help you judge whether a
contact is genuinely who they claim to be.

### Renaming a Contact

You can give any contact a local nickname. This name is only visible to you -- it
does not change anything for the other person. If the contact changes their own
display name later, you will see a notification and can choose whether to adopt
the new name or keep your local nickname.

---

## 4. Messaging

### Sending and Receiving Text

Type your message in the input field at the bottom and press Enter (or the send
button). Messages are delivered directly between devices. You will see delivery
confirmations: a checkmark means the message reached the recipient's device.

If the recipient is offline, your message is stored securely across the network
and delivered as soon as they come back online. Messages are kept for up to 7 days.

### Sending Images, Videos, and Files

Tap the paperclip icon (or attachment button) to pick a file from your device. You
can send images, videos, audio files, documents -- any file type.

On desktop, you can also **drag and drop** files directly into the chat window, or
**paste** images and files from the clipboard.

Small files are sent inline with the message. Larger files use a two-stage
transfer: the metadata arrives first, then the full file is transferred directly.

### Voice Messages

Press and hold the microphone button to record a voice message. Release to send.
Voice messages are automatically transcribed to text on your device (if the
transcription feature is enabled in settings), so the recipient can read the
message even when they cannot listen to audio.

### Replying to Messages

To reply to a specific message, use the three-dot menu on the message and select
"Reply." Your reply will include a quote of the original message so both sides
can see what you are referring to.

### Editing and Deleting Messages

Made a mistake? You can edit or delete your own messages within 15 minutes of
sending them. Use the three-dot menu on the message and choose "Edit" or "Delete."

Edits are visible to the recipient (the message updates in place). Deletions
remove the message from both sides.

### Emoji Reactions

You can react to any message with an emoji. Long-press (or use the three-dot menu
on) a message to see the reaction picker. Quick reactions are shown at the top,
and you can browse or search for any emoji.

Reactions are encrypted just like regular messages.

### Link Previews

When you send a message containing a URL, Cleona generates a link preview on your
device showing the page title, description, and thumbnail. The recipient sees this
preview without their device ever connecting to the linked website -- protecting
their privacy.

When you tap a link, you can choose to open it in your regular browser, in an
incognito/private window, or to be asked each time.

### Searching Messages

Use the search function in a chat to find specific messages. Results are highlighted
and you can jump between matches using the navigation arrows.

You can also use the search/filter bar on the home screen to search across all your
conversations.

### Read Receipts and Typing Indicators

You can see when the other person has read your message and when they are currently
typing. These features work in both one-on-one chats and groups.

---

## 5. Groups

### Creating a Group

Tap the floating action button (the round button, usually in the bottom-right
corner) on the home screen and choose "New Group." Give the group a name and select
the contacts you want to invite.

### Roles

Groups have three roles:

- **Admin** -- The person who created the group. Can manage members, change group
  settings, promote others to moderator, and remove members.
- **Moderator** -- Can manage messages and help keep order. Cannot change core
  group settings.
- **Member** -- Can read and send messages.

### Inviting Members

The group admin can add new members at any time from the group info screen.

### Leaving a Group

Open the group info (tap the group name at the top of the chat) and choose "Leave
Group." You will stop receiving messages from this group. If you are the last admin,
consider promoting someone else first.

---

## 6. Public Channels

Channels are different from groups. They are one-way broadcasts: the owner and
admins can post, and everyone else reads. Think of them like a news feed or
announcement board.

### Finding and Joining Channels

Open the Channels tab and switch to the "Search" view. You will see a list of
public channels available on the network. You can filter by language. Tap a
channel to see its description, then subscribe to start receiving posts.

Some channels are marked as adult content. You will only see these if you have
confirmed your age in your identity settings.

### Creating Your Own Channel

Tap the floating action button and choose "New Channel." Set a name (must be unique
across the network), pick a language, and decide whether it should be public or
private. For public channels, you can toggle the adult-content flag.

### Reporting Content

If you see content that violates community standards, you can report it. Reports
are handled by a decentralized jury system -- a randomly selected group of peers
reviews the report and decides on action. There is no central authority making
these decisions.

---

## 7. Calls

### Voice Calls

Open a chat with a contact and tap the phone icon. The call is direct, peer-to-peer,
and encrypted -- no server relays your voice. Call quality adapts automatically to
your connection.

When someone calls you, you will hear a ringtone and see the incoming call screen
with options to accept or decline.

### Video Calls

Tap the video icon instead of the phone icon to start a video call. Video calls
support picture-in-picture mode so you can keep chatting or using your phone while
on a call.

On Android, Cleona uses your device camera directly. Video quality adjusts
automatically based on your network conditions.

### Group Calls

You can start a group call from within a group chat. Group calls use an efficient
relay tree so that not every participant needs to connect to every other
participant directly. Audio from all participants is mixed, and you can see
video from multiple people.

Group calls are encrypted with keys that rotate during the call for added security.

### Ringtones

You can choose from 6 different ringtones in Settings. Message notification sounds
and vibration (on Android) can also be configured there.

---

## 8. Multiple Identities

### Why Multiple Identities?

You might want to keep your work life and personal life separate, or have a
dedicated identity for a community you are part of. Cleona lets you create
multiple identities under the same app, all derived from your single seed phrase.

### Creating a New Identity

Go to the identity list (accessible from the home screen menu) and tap "Create
Identity." Give it a display name and it is ready to use. Each identity has its
own contacts, conversations, and profile.

### Switching Between Identities

Tap your current identity name or avatar to see the identity list, then tap the
one you want to switch to. The switch is instant.

### You Never Miss a Message

All your identities are active at the same time. Even if you are currently viewing
one identity, messages for your other identities are still received and stored.
You will see notifications for all of them.

---

## 9. Recovery

### Seed Phrase Recovery

If you lose your device or need to reinstall, enter your 24-word seed phrase
during setup (choose "Restore" instead of creating a new identity). Cleona will:

1. Recreate your identity with the exact same keys.
2. Broadcast a restore request to your contacts.
3. Your contacts automatically respond with your contact list, group memberships,
   and message history.

One single contact being online is enough to restore your account. The more
contacts that are online, the more complete your history will be. Messages arrive
in stages: contacts and group structures first, then recent messages, then full
history.

### Guardian Recovery (Shamir Secret Sharing)

For extra safety, you can split your seed phrase among 5 trusted people (called
guardians). Each guardian receives a fragment that is meaningless on its own. Any
3 of the 5 fragments can reconstruct your full seed phrase.

This means even if 2 guardians are unavailable or lose their fragment, you can
still recover. And no single guardian (or even two working together) can access
your account.

### Why Your Contacts Are Your Backup

In Cleona, your contacts serve as a distributed backup of your data. Each contact
stores information about your conversations with them. When you restore, they send
this information back to you. There is no cloud backup because there is no cloud.
Your social network IS your backup network.

---

## 10. Settings

### Notifications and Ringtones

Configure notification sounds for incoming messages and calls. Choose from 6
ringtones for calls. On Android, you can also toggle vibration.

### Skins and Themes

Cleona comes with 9 visual themes (called skins). Some are light, some are dark,
and there is a high-contrast option that meets WCAG AAA accessibility standards.

Pick the one that suits your eyes and taste from Settings.

### Language

Cleona is available in 33 languages, including right-to-left languages like Arabic
and Hebrew. Change the language in Settings -- the entire interface updates
immediately.

### Storage Limit

You can set how much storage Cleona is allowed to use on your device (between
100 MB and 2 GB, depending on your platform). When the limit is reached, older
media files are cleaned up automatically. Text messages are not affected.

### Auto-Download

Configure which types of media (images, videos, audio, documents) are downloaded
automatically and set size thresholds for each type. Large files will show a
download button instead of downloading automatically.

### Download Directory

Choose where downloaded and received files are saved on your device.

### Media Archiving

If you have a NAS or network share, you can configure automatic archiving of
media files to an external location via SMB, SFTP, FTPS, or HTTP. This lets
you keep a backup of all shared media outside of the app.

### Voice Message Transcription

When enabled, voice messages you send are automatically transcribed to text before
being sent. The transcription happens entirely on your device -- no audio is sent
to any external service. The recipient sees both the voice message and the text.

---

## 11. Security

### What is Post-Quantum Encryption?

Regular encryption (used by most messengers today) could theoretically be broken
by powerful quantum computers in the future. Post-quantum encryption uses
mathematical problems that even quantum computers cannot solve efficiently.

Cleona uses a hybrid approach: it combines classical encryption (X25519) with
post-quantum encryption (ML-KEM-768). This means your messages are protected by
both layers. Even if one is somehow broken, the other still keeps you safe.

Every single message uses a fresh set of encryption keys. There is no "session"
that could be compromised -- each message is independently secured.

### Why No Server is More Secure

In traditional messengers, a server sees who talks to whom, when, and how often,
even if it cannot read the content. Metadata can reveal a lot about your life.

Cleona has no server. Messages travel directly between devices (or through other
Cleona users acting as relays, but relays cannot read the content either). There
is no central point that collects metadata, no single point of failure, and no
single target for hackers or government requests.

### What Happens When You Are Offline?

When you are offline, people can still send you messages. Here is what happens:

1. The sender's device tries to reach you directly first.
2. If that fails, it routes the message through other Cleona users who are online
   (relays). The relays cannot read your messages -- they just pass along encrypted
   data.
3. If you are completely unreachable, the message is stored on mutual contacts'
   devices (people you both know) and on the network using an error-correction
   technique that spreads small pieces across multiple devices.
4. When you come back online, all waiting messages are delivered. Messages are kept
   for up to 7 days.

You do not need to do anything -- this all happens automatically.

### Database Encryption

All your data stored on your device (messages, contacts, settings) is encrypted.
Even if someone gets access to your device's file system, they cannot read your
Cleona data without your encryption keys, which are derived from your seed.

### Closed Network

Cleona operates as a closed network. Every network packet is authenticated, which
means only legitimate Cleona devices can participate. This prevents outsiders from
injecting fake messages or eavesdropping on network traffic.

---

## 12. FAQ

**Can I use Cleona without internet?**

No, you need a network connection to send and receive messages. However, if you go
offline temporarily, messages sent to you are stored across the network and
delivered when you reconnect -- for up to 7 days. You will not lose messages just
because you were on a plane or had no signal for a while.

---

**What if I lose my seed phrase?**

If you have set up guardian recovery (Shamir Secret Sharing), any 3 of your 5
guardians can help you reconstruct the seed phrase. If you have not set up
guardians, recovery is still possible as long as you have at least one device
where Cleona is still installed and running -- you can view your seed phrase in
the settings.

The best approach: write down your seed phrase on paper and store it somewhere safe.
Consider setting up guardian recovery for additional peace of mind.

---

**Can anyone read my messages?**

No. Not the developer, not a server operator (there is none), not your internet
provider, not anyone who relays your messages. Every message is encrypted on your
device with keys that only you and the intended recipient possess. The encryption
is end-to-end and post-quantum secure.

---

**Why don't I need a phone number?**

Because your identity is purely cryptographic. When you first launch Cleona, a
unique key pair is generated on your device. This key pair IS your identity. You
prove who you are by signing messages with your private key, not by receiving an
SMS code. This means you cannot be tracked by your phone number, and you do not
need to give up any personal information.

---

**Is Cleona open source?**

Cleona is developed transparently. The source code is available for review.

---

**Can I use Cleona on multiple devices?**

Currently, each device runs its own instance. You can use the same seed phrase to
restore your identity on a new device, but simultaneous multi-device usage (like
WhatsApp Web) is not yet available. Your multiple identities all run on one device
simultaneously, though.

---

**How does Cleona find other users without a server?**

When you are on the same local network, Cleona discovers other users automatically
via network broadcasts. For users on different networks, Cleona uses the contact
information embedded in QR codes, NFC exchanges, or cleona:// links to establish
an initial connection. Once connected, your device learns about the network and
can route messages efficiently.

---

**What happens if I delete a contact?**

The contact is removed from your list and you will no longer receive messages from
them. If you are both in the same group, you can still see their group messages.
Deleted contacts cannot be accidentally re-imported through restore or network
sync -- you would need to explicitly add them again via a new QR scan or link.

---

**How much data does Cleona use?**

Cleona is designed to be efficient with bandwidth. Text messages are tiny (a few
kilobytes). Media files depend on their size, of course. There is no background
polling or unnecessary traffic -- the network protocol is designed to minimize
data usage.

---

**What does the network stats screen show?**

This is a diagnostic screen (accessible from settings) that shows you how your
device is connected to the network: how many peers you can see, routing
information, and connection quality. You generally do not need this screen, but
it can be helpful if you are troubleshooting connection issues.

---

**I switched from WhatsApp/Signal. What is different?**

The biggest differences:
- **No server.** Your messages do not pass through any company's infrastructure.
- **No phone number.** Your identity is a cryptographic key, not tied to your SIM.
- **Seed phrase.** Instead of SMS verification, you have 24 words that control
  your identity. Guard them well.
- **Contacts must be added explicitly.** There is no contact list upload from your
  phone book. You add people by scanning QR codes, tapping NFC, or sharing links.
- **Multiple identities.** You can have separate personas in one app.
- **Offline delivery.** Messages wait for you, stored across the network.

Everything else -- sending text, sharing photos, making calls, creating groups --
works much like you would expect from any modern messenger.

---

*Cleona Chat -- Private by design, decentralized by nature.*
