# Cleona Chat -- User Manual

Version 3.1.125 | July 2026

---

## Table of Contents

1. [What is Cleona Chat?](#1-what-is-cleona-chat)
2. [Getting Started](#2-getting-started)
3. [Contacts](#3-contacts)
4. [Messaging](#4-messaging)
5. [Groups](#5-groups)
6. [Public Channels](#6-public-channels)
7. [Calls](#7-calls)
8. [Calendar](#8-calendar)
9. [Polls](#9-polls)
10. [Multiple Identities](#10-multiple-identities)
11. [Multi-Device](#11-multi-device)
12. [Recovery](#12-recovery)
13. [Settings](#13-settings)
14. [Security](#14-security)
15. [Software Updates](#15-software-updates)
16. [FAQ](#16-faq)

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

**Available on Android, iOS, macOS, Linux, and Windows.** The same experience
across all five platforms.

---

## 2. Getting Started

### Installing the App

- **Android:** Download the APK from the Cleona website or GitHub Releases and
  install it. You may need to allow installation from unknown sources in your phone
  settings (this is normal for apps distributed outside the Play Store).
- **iOS:** Install via TestFlight. Open the TestFlight invitation link on your
  iPhone and tap "Install." TestFlight is Apple's official way to distribute beta
  apps.
- **macOS:** Download the DMG from the Cleona website or GitHub Releases. Open the
  DMG and drag Cleona to your Applications folder. On first launch, macOS may ask
  you to confirm that you want to open an app from an identified developer.
- **Linux (Ubuntu/Debian):** Download the .deb package and install with
  `sudo dpkg -i cleona-chat_VERSION_amd64.deb`. Launch from your application menu
  or run `cleona-chat` in a terminal.
- **Linux (Fedora/openSUSE):** Download the .rpm package and install with
  `sudo dnf install cleona-chat-VERSION.x86_64.rpm`.
- **Linux (any distro -- AppImage):** Download the .AppImage file, make it
  executable (`chmod +x cleona-chat-*.AppImage`), and double-click to run. No
  installation needed.
- **Windows:** Download and run the installer from the Cleona website or GitHub
  Releases.

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
their contact QR code (from the identity detail page), and the other scans it. The
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

Made a mistake? You can edit your own messages within 15 minutes of sending
them. Use the three-dot menu on the message and choose "Edit." Edits are
visible to the recipient (the message updates in place).

You can delete your own messages at any time -- there is no time limit for
deletion. Use the three-dot menu and choose "Delete." Deletions remove the
message from both sides.

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

- **Owner** -- The person who created the group. Can manage members, change group
  settings, promote others to admin, and remove members. The owner can transfer
  ownership to another member.
- **Admin** -- Can manage messages, remove members, and help keep order.
- **Member** -- Can read and send messages.

### Inviting Members

The group owner or admin can add new members at any time from the group info screen.

### Leaving a Group

Open the group info (tap the group name at the top of the chat) and choose "Leave
Group." You will stop receiving messages from this group. If you are the last owner,
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

### System Channels

Cleona includes two built-in system channels:

- **Bug Log:** When Cleona detects an error, it asks whether you want to
  send an anonymized crash report. These reports appear in the Bug Log
  channel where the community can review them. No personal data is
  transmitted -- only technical error descriptions. You can also manually
  submit a log report (with a preview dialog and explicit consent).
- **Feature Requests:** Users can submit feature requests and vote on
  existing proposals. Proposals are sorted by vote count.

Both system channels have a 25 MB size limit and are moderated by the jury
system.

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

## 8. Calendar

Cleona includes a built-in calendar that is encrypted and fully peer-to-peer --
no cloud service involved.

### Views

The calendar offers five views: Day, Week, Month, Year, and a Tasks view. Switch
between them using the tabs at the top of the calendar screen.

### Creating Events

Tap on a time slot or use the add button to create a new event. You can set a
title, date, time, location, and notes. Events are stored encrypted on your device.

### Recurring Events

Events can repeat on a daily, weekly, monthly, or yearly schedule. You can
customize the pattern (e.g. every second Tuesday, every first of the month) and
set an end date or a number of repetitions.

### Inviting Contacts

When creating or editing an event, you can invite your Cleona contacts. They
receive an encrypted calendar invite and can respond with Accept, Decline, or
Tentative. Updates to the event are automatically sent to all invitees.

### Free/Busy Sharing

You can share your availability with contacts without revealing event details.
There are three privacy levels: full details, time blocks only, or hidden. You
can set a default and override it per contact.

### Reminders

Events can have reminders that trigger a system notification before the event
starts. You can snooze reminders if needed.

### External Calendar Sync

Cleona can sync with external calendar services:

- **CalDAV** -- Connect to any CalDAV-compatible server (Nextcloud, Radicale,
  etc.).
- **Google Calendar** -- Sync via Google Calendar API with secure OAuth2
  authentication.
- **Local CalDAV server** -- Cleona can run a local CalDAV server on your device,
  allowing desktop calendar apps (Thunderbird, Outlook, Apple Calendar, Evolution)
  to sync with your Cleona calendar.
- **Android system calendar** -- Events from Cleona can be pushed to your
  Android device's built-in calendar app.
- **ICS files** -- Import and export events in standard iCalendar format.

### PDF Export

You can print or export any calendar view (Day, Week, Month, Year) as a PDF
document.

---

## 9. Polls

You can create polls in any chat or group to gather opinions or plan events.

### Poll Types

Cleona supports five types of polls:

- **Single Choice** -- Participants pick one option.
- **Multiple Choice** -- Participants can select several options.
- **Date Poll** -- Find a date that works for everyone. Each participant marks
  dates as available, maybe, or unavailable.
- **Scale** -- Rate something on a numeric scale (e.g. 1 to 5).
- **Free Text** -- Participants write their own answer.

### Creating a Poll

Open a chat and tap the poll icon (or use the attachment menu). Choose the poll
type, add your question and options, then send. The poll appears as a message in
the chat.

### Voting

Tap on a poll to cast your vote. You can change your vote or revoke it at any
time.

### Anonymous Voting

Polls can be configured for anonymous voting. When enabled, votes are
cryptographically anonymous -- no one, not even the poll creator, can see who
voted for what. The vote count is still visible.

### Date Poll to Calendar

When a date poll is complete, the winning date can be converted directly into a
calendar event with one tap.

---

## 10. Multiple Identities

### Why Multiple Identities?

You might want to keep your work life and personal life separate, or have a
dedicated identity for a community you are part of. Cleona lets you create
multiple identities under the same app, all derived from your single seed phrase.

### Creating a New Identity

Go to the identity list (accessible from the home screen menu or by tapping the
plus sign next to your identity tabs) and create a new identity. Give it a display
name and it is ready to use. Each identity has its own contacts, conversations,
and profile.

### Switching Between Identities

Tap the identity tab in the top bar to switch. The switch is instant -- no
reloading, no waiting.

### You Never Miss a Message

All your identities are active at the same time. Even if you are currently viewing
one identity, messages for your other identities are still received and stored.
You will see notifications for all of them.

### Identity Detail Page

Tap on the currently active identity tab to open its detail page. Here you can:

- View your QR code for sharing with contacts.
- Change your profile picture.
- Add a profile description.
- Change your display name.
- Pick a visual theme (skin) for this identity.
- Delete the identity if you no longer need it.

### Deleting an Identity

When you delete an identity, your contacts are notified. The identity and all
associated data are removed from your device. This action cannot be undone.

---

## 11. Multi-Device

### Using Cleona on Multiple Devices

You can use the same identity on up to 5 devices simultaneously. One device acts
as the primary (it holds the seed phrase), and additional devices are linked to it.

### Linking a New Device

1. Open Settings on your primary device.
2. Go to "Linked Devices."
3. Choose "Link New Device."
4. On the new device, install Cleona and choose "Link to Existing Device" during
   setup.
5. Scan the pairing QR code shown on your primary device, or use the pairing link.

The linked device receives a delegation certificate from the primary device.
Messages sent from a linked device are cryptographically signed with a delegated
key, so contacts can verify that the message genuinely comes from your identity.

### How It Works

- The primary device holds your seed phrase and master keys.
- Linked devices receive derived signing keys and a delegation certificate -- they
  never receive the seed phrase itself.
- All devices share the same identity and contacts. Messages arrive on all devices.
- Delegation certificates are automatically renewed before they expire.

### Device Management

Open Settings and go to "Linked Devices" to see all your linked devices, their
status, and when they were last active. You can revoke a linked device at any time
if it is lost or stolen.

### Emergency Key Rotation

If you suspect a device has been compromised, you can trigger an emergency key
rotation. This generates new keys and requires confirmation from a quorum of your
other devices (a majority must approve). This prevents a single stolen device from
rotating keys on its own.

---

## 12. Recovery

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

## 13. Settings

### Notifications and Ringtones

Configure notification sounds for incoming messages and calls. Choose from 6
ringtones for calls. On Android, you can also toggle vibration.

### Skins and Themes

Cleona comes with 10 visual themes (called skins): Teal, Ocean, Sunset, Forest,
Amethyst, Fire, Storm, Slate, Gold, and Contrast. The Contrast skin meets WCAG AAA
accessibility standards for maximum readability.

Each identity can have its own skin. You can also switch between light, dark, and
system theme modes.

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
media files to an external location via SMB, SFTP, FTPS, or HTTP. Media files
are tiered automatically:

- First 30 days: originals stay on your device.
- After 30 days: a thumbnail stays, the original is archived.
- After 90 days: only a small thumbnail remains on your device.
- After 1 year: only a placeholder remains; the original is safe in the archive.

You can tap any archived media to retrieve it from the archive (when connected
to your home network). Important media can be pinned so it is never archived.

### Voice Message Transcription

When enabled, voice messages you send are automatically transcribed to text before
being sent. The transcription happens entirely on your device using the open-source
Whisper model -- no audio is sent to any external service. The recipient sees both
the voice message and the text.

### Linked Devices

Manage your linked devices from this settings section. See the Multi-Device chapter
for details.

---

## 14. Security

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

### Anti-Censorship

If your network blocks the standard connection method (UDP), Cleona automatically
switches to an alternative transport (TLS) that is harder to detect and block. This
happens transparently -- you do not need to configure anything.

### Secure Key Storage

On supported platforms, Cleona stores your encryption keys in the operating
system's secure keyring (Android Keystore, iOS Keychain, macOS Keychain). This
provides hardware-backed protection for your keys where available.

### Database Encryption

All your data stored on your device (messages, contacts, settings) is encrypted.
Even if someone gets access to your device's file system, they cannot read your
Cleona data without your encryption keys, which are derived from your seed.

### Closed Network

Cleona operates as a closed network. Every network packet is authenticated, which
means only legitimate Cleona devices can participate. This prevents outsiders from
injecting fake messages or eavesdropping on network traffic.

---

## 15. Software Updates

### How Do I Get Updates?

Cleona can be updated through multiple channels. The goal is to ensure you
can receive updates even if individual distribution channels are blocked or
unavailable:

1. **App Store / Play Store:** If you installed Cleona from an app store,
   updates arrive through the store as usual.
2. **GitHub Releases:** The project's GitHub page provides signed
   installation packages for all platforms.
3. **In-Network Updates:** If another Cleona user on your network already
   has the latest version, Cleona can download the update directly over the
   P2P network -- no external server required. The new version is split into
   error-correcting fragments and distributed across multiple nodes. Your
   device collects enough fragments to reconstruct the update. Authenticity
   is verified via the developer's Ed25519 signature.
4. **Invite Links:** You can create invite links that contain everything a
   new user needs to install Cleona and connect to the network.
5. **Physical Transfer:** In environments without internet, you can share
   Cleona via USB drive or local network.

### Update Notifications

When a new update is available, Cleona shows a notification on the home
screen. If the update is also available via the network (in-network update),
you can choose to download it directly from the network.

### Binary Distribution

By default, your device helps distribute updates to other users on the
network. If you prefer not to participate, you can disable this in Settings
under "Network." Storage used for update fragments is limited (5 MB on
mobile, 20 MB on desktop) and cleaned up regularly.

### Signature Verification

Every update is cryptographically signed. Cleona verifies the signature
automatically before installing any update. This ensures that only updates
from the official developer are accepted -- even when the update was
obtained via the P2P network.

---

## 16. FAQ

**Can I use Cleona without internet?**

No, you need a network connection to send and receive messages. However, if you go
offline temporarily, messages sent to you are stored across the network and
delivered when you reconnect -- for up to 7 days. On a local network (e.g. the
same Wi-Fi), you can communicate even without internet access.

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

Cleona is developed transparently. The source code is available for review on
GitHub.

---

**Can I use Cleona on multiple devices?**

Yes. You can link up to 5 devices to the same identity. One device is the primary
(it holds the seed phrase), and additional devices are linked via a secure pairing
process. All devices share the same identity, contacts, and conversations. See the
Multi-Device chapter for details.

---

**How does Cleona find other users without a server?**

When you are on the same local network, Cleona discovers other users automatically
via network broadcasts (IPv4 and IPv6). For users on different networks, Cleona
uses the contact information embedded in QR codes, NFC exchanges, or cleona://
links to establish an initial connection. Once connected, your device learns about
the network and can route messages efficiently.

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
- **Multi-device.** Link up to 5 devices to the same identity.
- **Calendar and polls.** Built-in encrypted calendar and poll features.
- **Offline delivery.** Messages wait for you, stored across the network.

Everything else -- sending text, sharing photos, making calls, creating groups --
works much like you would expect from any modern messenger.

---

**Does Cleona work abroad?**

Yes. As long as you have an internet connection, Cleona works anywhere in the
world. Since there is no central server, the service cannot be blocked for specific
countries. Cleona also has an anti-censorship fallback: if the standard connection
(UDP) is blocked, Cleona automatically switches to an alternative transport (TLS)
that is harder to detect and block.

---

**Is Cleona free?**

Yes. Cleona is free and ad-free. Since there is no central server, there are no
server costs to cover. You can find a "Donate" option in the app to voluntarily
support development.

---

**My message shows a clock icon -- what does that mean?**

It means the message has not been delivered yet. The recipient is probably offline.
Once the message is delivered, the icon changes. Messages are kept for up to 7 days
for delivery.

---

**Can I switch from WhatsApp to Cleona?**

Yes, but you cannot transfer your WhatsApp chats. Cleona and WhatsApp are
fundamentally different systems. You need to add your contacts individually in
Cleona. The easiest way is to share your cleona:// link in a WhatsApp group and
ask others to add you.

---

**How do I get updates if the app store is blocked?**

Cleona can receive updates directly over the P2P network without relying on
any app store, website, or download server. If another user on the network
has the latest version, your device can download the update from them.
Authenticity is verified via the developer's digital signature. Alternatively,
a contact can share the app via an invite link or USB drive. See the Software
Updates chapter for details.

---

*Cleona Chat -- Private by design, decentralized by nature.*
