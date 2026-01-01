# Cleona Chat -- User Manual

Version 4.2 | As of November 2026

---

## Table of contents

1. [What is Cleona Chat?](#1-what-is-cleona-chat)
2. [Getting started](#2-getting-started)
3. [Contacts](#3-contacts)
4. [Messages](#4-messages)
5. [Groups](#5-groups)
6. [Public channels](#6-public-channels)
7. [Calls](#7-calls)
8. [Calendar](#8-calendar)
9. [Polls](#9-polls)
10. [Multiple identities](#10-multiple-identities)
11. [Several devices](#11-several-devices)
12. [Recovery](#12-recovery)
13. [Settings](#13-settings)
14. [Security](#14-security)
15. [Software updates](#15-software-updates)
16. [Frequently asked questions](#16-frequently-asked-questions)

---

## 1. What is Cleona Chat?

### Your messenger, your data

Cleona Chat is a messenger that works entirely without a central server.
Your messages travel from your device to your counterpart's device --
with no detour through a company headquarters, no cloud, no data center.
Where another device happens to help along the way, it only forwards
encrypted packets. No company can read, store, or pass on your messages,
simply because no company sits in between.

### No account, no phone number

With Cleona you need neither a phone number nor an email address to sign
up. Your identity consists of a cryptographic key pair that is generated
automatically on your device the first time you start it. This means:
nobody can track you down via your phone number or email address, unless
you share your contact details yourself.

### Future-proof encryption

Cleona uses so-called post-quantum encryption. This means: even future
quantum computers would not be able to crack your messages. You do not
have to understand the details -- what matters is only that your
communication is protected as well as the current state of the art
allows.

### How does it work without a server?

The network of Cleona consists only of the devices of its users. Every
device is a node, no node is more important than another, and each one
knows only its neighbors. Four things make this network special:

- **No fixed point.** There is no server address in the app, and the
  network does not depend on any single node. There is nothing anyone
  could switch off to switch off Cleona.
- **Instant.** Your message sets off the moment you send it. It waits
  for no clock and for nothing else.
- **Cover traffic on the side.** Your device constantly sends small
  cover packets, so that from the outside no one can tell when you
  are really writing. No message depends on it -- the cover traffic just
  runs alongside.
- **Codes instead of names.** Whoever forwards a message sees only a
  code that changes every day. Normally, none of them knows sender and
  recipient at the same time; the exceptions are listed in chapter 14.

**Three routes, all at once.** When you send a message, Cleona does not
try one route after another, but all suitable ones at the same time. As
soon as your counterpart confirms receipt, the others are aborted.

1. **In the same network:** If you are in the same Wi-Fi, the message
   goes straight across.
2. **Over the fixed neighbors:** On the internet, your device hands the
   message to its fixed neighbor. That one forwards it to your
   counterpart's fixed neighbors (up to three at once), and one of them
   delivers it.
3. **Mailbox:** If your counterpart is offline, Cleona deposits the
   message encrypted at three neighbors. It stays there for up to 7
   days. When your counterpart comes back online, they pick it up.

**How do you get into the network?** There is no server address in the
app. You get your entry point from your first contact: their invitation
contains the addresses through which your device finds its first
neighbors. In the same Wi-Fi, Cleona devices also find each other on
their own. From then on, your device gets to know more neighbors with
every neighbor it meets.

### Platforms

Cleona is available for Android, iOS, macOS, Linux and Windows. On
computers and on Android, messages and calls arrive within seconds. On
the iPhone this holds while the app is open. When it is not open, iOS
only wakes it briefly now and then; iOS decides when. Cleona then
collects everything kept for you and shows a notification with a number
on the app icon. Calls do not reach an iPhone whose app is not open.
This is a rule of Apple, not a fault in Cleona.

---

## 2. Getting started

### Install the app

**Android:**
1. Download the APK file from the Cleona website or from GitHub Releases.
2. Open the file on your phone. If necessary, allow installation from
   unknown sources (Android asks you automatically).
3. Tap "Install" and wait until the installation is complete.

**iOS:**
1. Open the TestFlight invitation link on your iPhone.
2. Tap "Install". TestFlight is Apple's official way of distributing
   beta apps.
3. After installation you will find Cleona on your home screen.

**macOS:**
1. Download the DMG file from the Cleona website or from GitHub Releases.
2. Open the DMG and drag Cleona into your Applications folder.
3. On first launch, macOS may ask whether you want to open an app from
   an identified developer -- confirm this.

**Linux (Ubuntu/Debian):**
1. Download the .deb file from the Cleona website or from GitHub Releases.
2. Install with a double-click or in the terminal: `sudo dpkg -i cleona-chat-beta_VERSION_amd64.deb`
3. Start Cleona from the application menu or in the terminal with `cleona-chat-beta`.

**Linux (Fedora/openSUSE):**
1. Download the .rpm file from the Cleona website or from GitHub Releases.
2. Install with: `sudo dnf install cleona-chat-beta-VERSION-1.x86_64.rpm`
3. Start Cleona from the application menu or in the terminal with `cleona-chat-beta`.

**Linux (all distributions -- AppImage):**
1. Download the .AppImage file from the Cleona website or from GitHub Releases.
2. Make the file executable: right-click, properties, executable, or in
   the terminal: `chmod +x cleona-chat-beta-VERSION-x86_64.AppImage`
3. Start with a double-click or in the terminal: `./cleona-chat-beta-VERSION-x86_64.AppImage`

The package names apply to the beta, which is currently the only
published version; they are called `cleona-chat-beta`.

**Windows:**
1. Download the installer from the Cleona website or from GitHub Releases.
2. Run the installation file and follow the instructions.
3. Start Cleona from the Start menu or the desktop shortcut.

### Create an identity

On first launch, Cleona automatically creates a new identity for you.
You can give yourself a display name -- that is the name your contacts
see. This name can be changed at any time.

### Write down the seed phrase -- the most important thing of all

After creating your identity, Cleona shows you 24 words. That is your
**seed phrase** -- your personal recovery key.

**Write these 24 words down on paper and keep them safe.**

Why is this so important?

- If your phone breaks, gets lost, or is stolen, you can restore your
  entire identity on a new device with these 24 words.
- Without the seed phrase there is no way back. There is no "forgot
  password" button and no support that could give you back your account
  -- because there is no account on a server at all. Even your contacts
  cannot restore your identity, no matter how many of them. A second
  device with the same identity comes with a later version (see
  chapter 11).
- Never pass the seed phrase on to others. Whoever knows these words can
  impersonate you.

You can find the 24 words later in the settings under "Backup" ->
"Show recovery phrase", in case you want to read them off again. On
Android you confirm this with your screen lock.

### Add your first contact

To chat with someone, you first have to add that person as a contact.
There are several ways to do this -- all of them are explained in the
next section.

---

## 3. Contacts

### Your invitation

Contacts in Cleona come about only through an invitation. Your
invitation is there from the first start -- even without internet and
before your device has even found a neighbor. You find it on your
identity detail page (tap your own name in the top bar).

The invitation comes in two forms that contain exactly the same thing:

- as a **QR code**, when your counterpart is standing next to you, and
- as a **text line**, which you send by email, SMS, or through another
  messenger.

The invitation contains no phone number and no name from a directory. It
contains your public keys and the addresses through which your
counterpart reaches you and your neighbors. For someone who has freshly
installed Cleona, your invitation is therefore also the entry point into
the network.

### Scan QR code (recommended)

When you meet in person:

1. You show your counterpart the QR code of your invitation.
2. Your counterpart taps the plus button, selects "Scan QR code", and
   holds the camera up to your screen. This also works with a computer's
   webcam.
3. The request goes to you and is **accepted automatically** -- because
   you just showed the code yourself.

A QR code is valid only once: the first valid request is accepted, after
that the invitation is used up. The QR code is the safest method,
because while doing it you know exactly with whom you are exchanging the
contact.

### NFC (hold phones together)

When both devices support NFC:

1. Open the add-contact function on both.
2. Hold your phones back to back against each other.
3. The invitation is transferred and accepted automatically.

NFC, like the QR code, offers a high level of security, because the
exchange only works when you are physically standing next to each other.

### Send the text line

When you cannot meet:

1. Open your invitation and copy the text line.
2. Send it to the person who is supposed to add you -- by email, SMS, or
   through another messenger.
3. The other person pastes the line in Cleona in the add-contact dialog.
4. The request appears under **"Requests"** on your side. Here it is
   **not** accepted automatically: you decide yourself, because you
   cannot know who else read the line on the way.

### Accept contact requests

An incoming request does not yet create a contact. It poses a question
to you and appears in the **"Requests"** tab. There you see the name and
the verification level and can choose:

- **Accept** -- only now does the person become your contact.
- **Decline** -- the request is discarded.
- **Block** -- the person cannot send you further requests.

### Never use as a fixed neighbor

In a contact's menu you find the switch **"Never use as a fixed
neighbor"** (default: off). When it is on, this contact does not forward
messages for you and therefore also does not learn when you send or
receive messages. This is intended for the case that danger threatens
you from your own surroundings.

From unknowns (neither a contact nor a member of a shared group),
Cleona lets nothing through besides such a request -- no message, no
call, no file. And even the request only gets through if the
sender has first solved a small computational task. That makes mass spam
expensive.

### Verification levels

Cleona shows you how securely a contact's identity is confirmed:

| Level | Meaning |
|-------|-----------|
| Not verified | You are connected, but nothing confirms that the right person is really behind it. |
| Seen | The key exchange was successful; you can communicate encrypted. |
| Verified | You met in person and connected via camera scan or NFC. |
| Trusted | You have explicitly marked this contact as trustworthy. |

"Verified" exists only for an in-person exchange. An invitation that
came through a chat or by email never reaches this level -- even if it
contains the same data.

If a contact's keys change without notice, Cleona resets them to "Not
verified". That protects you from someone impersonating your contact
unnoticed.

---

## 4. Messages

### Send and receive text

Simply type your message into the input field at the bottom and press
Enter or the send button. Your message is encrypted automatically before
it leaves your device.

Incoming messages appear in the chat history.

### What the marks on your message mean

| Mark | Meaning |
|---------|-----------|
| Clock | The message has been created, but no route has carried it yet. |
| One check | The message is on its way. This also applies while it is waiting in the mailbox for your counterpart. |
| Two checks | Delivered: your counterpart's device has confirmed receipt. |
| Warning sign | For 14 days, no route carried the message. Tap it to resend it. |

**Offline is not an error.** If your counterpart is not reachable, the
message stays at one check until it is picked up -- it is not lost. If
your device itself has no connection, the message stays at the clock
and sets off on its own as soon as a route is there again. The warning
sign appears only when it has found no route for 14 days; then you can
resend it.

This also holds for an iPhone whose app is not open: the message waits
in the post box until iOS briefly wakes the app or until the other
person opens it. That can take longer than on other devices.

Two checks only exist when the recipient confirms receipt themselves.
This receipt is encrypted and signed -- no one along the way can forge
it to fake a delivery to you.

### Send images, videos, and files

You have several options:

- **Paperclip icon** in the input field: tap it to select a file, an
  image, or a video from your gallery or your file system.
- **Drag and drop** (desktop): simply drag a file into the chat window.
- **Paste from the clipboard** (desktop): copy an image and paste it in
  the chat.

Small files (under 256 KB) travel directly inside the message. Larger
files are split into pieces and given error correction, so that
individual lost pieces do not matter. If you are both online, they are
streamed over a neighbor; otherwise they are deposited at devices that
are constantly reachable, until your counterpart picks them up.

From 256 KB, Cleona asks you per file before it is sent: a large file
cannot take the route of your messages. Its content stays encrypted,
and your counterpart does not learn your internet address. But from
the outside the transfer is visible as an event, and a foreign device
that forwards or keeps it sees who uploads and who fetches it. Your
consent applies only to this one file.

### Voice messages

1. Press and hold the microphone button in the input field.
2. Speak your message.
3. Release the button to send the message.

If speech recognition is activated on your device (see settings), your
voice message is automatically transcribed to text. Your counterpart
then sees both the recording and the transcribed text.

### Reply to messages (quote)

To reply to a specific message:

1. Open the three-dot menu next to the message.
2. Select "Reply".
3. A banner with the quoted message appears above the input field.
4. Write your reply and send it.

The quoted message is shown in your reply, so that the reference is
clear.

### Edit and delete messages

- **Edit:** three-dot menu of the message, then "Edit". Change the text
  and send it again. Your counterpart sees that the message was edited.
  Editing is possible within 15 minutes of sending.
- **Delete:** three-dot menu of the message, then "Delete". The message
  is removed from your side and your counterpart's. You can delete your
  own messages at any time -- there is no time window for deleting.

### Emoji reactions

Instead of writing a reply, you can react to a message with an emoji:

1. Open the three-dot menu or press and hold the message.
2. Choose an emoji from the quick selection, or open the emoji picker
   for the full selection.
3. Your reaction appears under the message.

### Copy text

Via the three-dot menu of a message you can copy the message text to the
clipboard.

### Search messages

At the top of the chat window you find the search function. Enter a
search term, and Cleona shows you all hits in the current chat. With the
arrow keys you can jump back and forth between the hits.

On the start page there is additionally a cross-tab search filter, with
which you can search all conversations for a term.

### Link preview

When you send a link, Cleona automatically generates a preview (title,
description, preview image). This preview is created by your device and
sent along -- your counterpart does not have to establish a connection
to the linked website for it.

What a tap on a received link does, you set in the settings under
"Open links": "Normally", "Prefer a private window" (where the device
cannot open a private window, the link opens normally), or "Ask every
time".

---

## 5. Groups

### Create a group

1. Switch to the "Groups" tab.
2. Tap the plus button.
3. Give the group a name.
4. Select the contacts you want to invite.
5. Tap "Create".

The invited contacts receive a notification and can join the group.

### How group messages are protected

In a group with up to 16 members, Cleona sends each message to each
member individually -- encrypted only for that member, just as if you
had written a separate message to each one. The checks on a group
message show the status of the member for whom it has progressed the
least.

If the group grows beyond 16 members, it uses a shared key. It changes
every day and is redrawn when a member leaves or is removed; a new
member reads only from their joining onwards. There, the checks no
longer show the status of each member, but that the message is
deposited in the network. If the group drops to 12 or fewer members,
it returns to individual sending.

### Images in groups and channels

In the settings of a group or a channel, you use "Always load images"
to set whether images are loaded immediately or only when you tap one.

### Invite members

Even after creation, you can invite further contacts:

1. Open the group info (three-dot menu in the group overview or top bar
   in the group chat).
2. Tap "Invite".
3. Select the contacts you want to add.

### Roles

Every group has three roles:

- **Owner:** has full control. Can add and remove members, appoint
  admins, and manage the group. The owner can also transfer their
  status to another member.
- **Admin:** can remove members and help with management.
- **Member:** can read and write messages.

### Leave a group

1. Open the three-dot menu in the group overview.
2. Select "Leave".
3. Confirm your decision.

When you leave a group, your previous messages remain visible to the
other members.

---

## 6. Public channels

### What are channels?

Channels are public discussion forums within the Cleona network. In
contrast to groups, anyone can read along here without having to be
invited. Only the owner and admins can publish posts -- subscribers read
along.

### Find and join channels

1. Switch to the "Channels" tab.
2. Open the "Search" tab.
3. Search the available channels by name or topic.
4. Tap a channel and then "Subscribe".

Channels can be filtered by language. Some channels are marked as "Not
safe for minors" -- these are only visible if you have confirmed in your
profile that you are over 18.

### Create your own channel

1. Switch to the "Channels" tab.
2. Tap the plus button.
3. Enter a channel name (must be unique across the entire network).
4. Choose the language and whether the channel should be public or
   private.
5. Optional: add a description and an image.
6. Tap "Create".

For public channels you can set whether the content is classified as
"Not safe for minors".

### Report content

If you notice inappropriate content in a public channel, you can report
it. Cleona uses a decentralized moderation system: reports are evaluated
by randomly selected members of the network (a kind of "jury"). If a
violation is found, the channel receives a warning. For repeated
violations it is downgraded in the search index or blocked.

### System channels

Cleona has two built-in system channels:

- **Bug Log:** When Cleona detects an error, it asks you whether you
  want to send an error report; beforehand you see exactly what will
  be published. These reports land in the Bug Log channel, where they
  can be viewed by the community. A report carries no name and no
  content of your conversations, but a pseudonym. In the beta it
  additionally states your identifier (User ID), so that the developers
  can ask follow-up questions. You can also send a log report manually
  (with a preview dialog and explicit consent).
- **Feature Requests:** Here users can submit feature wishes and vote
  on existing proposals. The proposals are sorted by votes.

Every computer keeps up to 25 MB per system channel, every phone up to
5 MB; when that is full, the oldest goes first -- never anything you
yourself have already seen.

---
## 7. Calls

### Start a voice call

1. Open the chat with the contact you want to call.
2. Tap the phone symbol in the top bar.
3. Wait until your counterpart accepts the call.

During the call you see a timeline, the call duration, and have access
to mute and speaker.

To hang up, tap the red hang-up button.

If you see "Not reachable", the other person's device cannot be reached
right now, for example an iPhone whose app is not open. Send a message
instead.

### Start a video call

1. Open the chat with the contact.
2. Tap the camera symbol in the top bar.
3. Your video image appears in a small window, your counterpart's image
   in the large area.

You can switch between the front and rear camera during the call.

### Incoming calls

When someone calls you, a notification window appears with the caller's
name. You can:

- **Accept** -- the call begins.
- **Decline** -- the caller is notified.

If you are currently in a call, a new call does not ring; instead you
get a "Missed call" message. The same applies to a group call you have
not accepted -- the message then stands in the group chat.

If someone calls one of your identities that is currently not shown,
it rings anyway; the call screen names which of your identities is
being called.

On the iPhone it only rings while the app is open. Whoever calls you
while it is not open sees "Not reachable" after 10 seconds. As soon as
you open the app, you find a missed-call message.

### Group calls

You can also hold group calls in which several people participate at the
same time. The call is organized over an intelligent forwarding tree, so
that not every participant has to be directly connected to every other.
All calls are encrypted throughout.

Every group member can start a group call. Two participants who are not
contacts of each other never see the other's internet address: their
audio and video run via a participant who is a contact of both. If
there is no such participant, the two are not connected, and the tile
says "No common contact in the call". If a forwarding is busy, the
audio stays and the video drops for this pair.

### Encryption for calls

All calls are encrypted with one-time keys that exist only for the
duration of the call. After hanging up, these keys are deleted
immediately. No one can decrypt a past call afterwards.

Honestly: calls run, wherever possible, directly between the devices,
because even a small delay is disturbing when speaking. Unlike with
messages, your internet provider can therefore see, during a call, which
internet address you are connected to. What you say, it does not see.

During a call, your contact sees your internet address too. If you do
not want that with a contact, switch off "Allow calls" in their menu
(default: on). If you switch it off later, an address they have already
seen remains known to them.

---

## 8. Calendar

Cleona contains a built-in calendar that works encrypted and completely
decentralized -- without a cloud service.

### Views

The calendar offers five views: day, week, month, year, and a tasks
view. Switch between them via the tabs at the top of the calendar
screen.

### Create appointments

Tap a time slot or use the add button to create a new appointment. You
can enter title, date, time, location, and notes. Appointments are
stored encrypted on your device.

### Recurring appointments

Appointments can repeat daily, weekly, monthly, or yearly. You can
adjust the pattern (e.g. every second Tuesday, the first of every month)
and set an end date or a number of repetitions.

### Invite contacts

When creating or editing an appointment, you can invite your Cleona
contacts. They receive an encrypted calendar invitation and can respond
with yes, no, or maybe. Changes to the appointment are sent
automatically to all invitees.

### Free/busy display

You can share your availability with contacts without revealing
appointment details. There are three privacy levels: full details, time
blocks only, or hidden. You can set a default and override it per
contact.

### Reminders

Appointments can have reminders that trigger a system notification
before the appointment starts. You can snooze reminders if needed.

### External calendar sync

Cleona can synchronize with external calendar services:

- **CalDAV** -- connect to any CalDAV-compatible server (Nextcloud,
  Radicale, etc.).
- **Google Calendar** -- synchronization via the Google Calendar API
  with secure OAuth2 authentication.
- **Local CalDAV server** -- Cleona can start a local CalDAV server on
  your device, so that desktop calendar apps (Thunderbird, Outlook,
  Apple Calendar, Evolution) can sync with your Cleona calendar.
- **Android system calendar** -- appointments from Cleona can be
  transferred to the built-in calendar app of your Android device.
- **ICS files** -- import and export appointments in the standard
  iCalendar format.

### PDF export

You can print or export any calendar view (day, week, month, year) as a
PDF document.

---

## 9. Polls

You can create polls in any chat or group to gather opinions or plan
dates.

### Poll types

Cleona supports five kinds of polls:

- **Single choice** -- participants choose one option.
- **Multiple choice** -- participants can choose several options.
- **Date poll** -- find a date that suits everyone. Each participant
  marks dates as available, maybe, or not available.
- **Scale** -- rate something on a numerical scale (e.g. 1 to 5).
- **Free text** -- participants write their own answer.

### Create a poll

Open a chat and tap the poll symbol (or use the attachment menu). Choose
the poll type, phrase your question and the options, and send the poll.
It appears as a message in the chat.

### Vote

Tap a poll to cast your vote. You can change or withdraw your vote at
any time.

### Anonymous voting

Polls can be configured for anonymous voting. When activated, votes are
cryptographically anonymous -- no one, not even the poll creator, can
see who voted for what. The vote count remains visible nonetheless.

### Date poll to calendar

When a date poll is finished, the winning date can be turned into a
calendar entry with one tap.

---
## 10. Multiple identities

### Why multiple identities?

Imagine you want to separate your professional life and your private life
-- similar to two different phone numbers, but without a second phone.
In Cleona you can use multiple identities on one device. Each identity
has its own name, its own profile picture, its own contacts, and its own
conversations.

### Create a new identity

1. In the top bar you see your current identity as a tab.
2. Tap the plus sign (+) to the right of your identity tabs.
3. Enter a name for the new identity.
4. Done -- the new identity is active immediately.

### Switch between identities

Simply tap the identity tab in the top bar. The switch is immediate --
no waiting time, no reloading.

### All run at the same time

An important point: all your identities are active at the same time.
Even if you are currently shown as "Work", your "Private" identity
continues to receive messages. You miss nothing, no matter which
identity you have currently selected.

### Identity detail page

When you tap the tab of your currently active identity, the detail page
opens. Here you can:

- Show your QR code for contacts.
- Change or remove your profile picture.
- Add a profile description.
- Change your display name.
- Choose a design (skin) for this identity.
- Delete the identity, if you no longer need it.

### Delete an identity

When you delete an identity, your contacts are notified about it. The
identity and all associated data are removed from your device. This
process is not reversible.

---

## 11. Several devices

### One identity, one device -- for now

Today, an identity runs on one device. A second device for the same
identity comes with a later version; in the settings under "Devices" ->
"Manage devices", "Pair another device" therefore still says "Not
available yet".

When it comes, this applies: all devices are equal, there is no main
device. You set up a further device with your 24 words, and one of your
existing devices agrees. At most 5 devices.

If you enter your 24 words on a new device today, you move: the
identity is restored to the new device, and your previous device then
removes it from itself (see chapter 12).

On several devices you can today use different identities (chapter 10).

### Rotate identity keys

If you suspect that someone has got at your keys, you can generate new
keys under "Manage devices" -> "Rotate identity keys". Your contacts
are notified, your open invitations are revoked. Important: after that,
the 24 words alone only produce the old keys. Therefore create a new
recovery package directly afterwards; you can then restore only
together with this package.

---

## 12. Recovery

### Use the seed phrase

When you lose your device or set up a new one:

1. Install Cleona on the new device.
2. Select "Restore" on start.
3. Enter your 24 words.
4. Cleona generates all your identities from them -- with the same keys
   as before. To your contacts you are the same person.

### What comes back -- and what does not

Your identity is in the 24 words, your contacts and your history are
not. What comes back is your access to the network via the **recovery
package**: your device deposits a small, encrypted packet in the
network. Only your 24 words can find and open it. It states what your
new device needs to reach your contacts again, and what was lying in
the network for you in the meantime. No contact has to be online for
this.

A restoration does not bring back your previous chat history.

The recovery package lives for 7 days and is renewed by your device as
long as it runs; in the settings you see until when it is valid. If
none of your devices ran for more than 7 days, it has expired. The 24
words still restore your identity then, but you have to re-invite your
contacts; what was lying in the network for you in the meantime is
lost.

### Restoring means moving

If your previous device later finds that the identity was restored
elsewhere, it removes it from itself -- along with its history.
Therefore: whoever has your 24 words can take your identity off your
device this way. Until all contacts are back, the app reminds you; with
"Finish and renew keys" you end the restoration yourself.

### What no one can restore

This is important, and we therefore state it clearly:

- **No one but you can restore your identity.** Not the developer, not
  a support, and not your contacts either -- no matter how many there
  are. There is no master key and no part of your key that would be
  deposited with others.
- **If you have lost the 24 words and have no device left, your
  identity is lost.** Then the only option is to create a new one and
  re-invite your contacts.

The best protection: write the 24 words down on paper and keep them
safe.

---
## 13. Settings

You reach the settings via the gear symbol in the top right corner.

### Notifications and ringtones

- Choose from six different ringtones for incoming calls.
- Set a message sound.
- On Android devices you can additionally activate or deactivate
  vibration.
- **"Mute everything"** lets no message ring, vibrate, or announce
  itself on this device anymore -- for all identities. Calls keep
  ringing.
- **"Quiet hours"** you set per identity with from/until. During this
  time, no message of this identity rings, vibrates, or announces
  itself; the messages still arrive.
- **"Notifications without content"** (default: off) shows only that a
  message, invitation, or reminder has arrived -- without sender, name,
  and text. Calls keep showing the name.
- Whatever arrives all at once after startup, Cleona announces in a
  batch notification ("5 new messages in 2 conversations"); everything
  later individually. A tap on a message notification opens the
  conversation, even in another identity.

### Designs (skins)

Cleona offers ten different designs: Teal, Ocean, Sunset, Forest,
Amethyst, Fire, Storm, Slate, Gold, and Contrast. The Contrast design
meets the highest accessibility level (WCAG AAA) and is particularly
easy to read with limited vision.

Each identity can have its own design. You change the design in the
identity detail page (tap the active identity tab).

Additionally, you can switch between light, dark, and the system theme
in the settings under "Appearance".

### Change language

Cleona is available in 34 languages, including languages with
right-to-left script (e.g. Arabic, Hebrew). Change the language in the
settings under "Language".

### Media archiving

If you have a network storage (NAS) or a shared folder at home, Cleona
can automatically offload your media there. SMB, SFTP, FTPS, and WebDAV
are supported.

This is how the tiered storage works:
- The first 30 days: everything stays on your device.
- After 30 days: a preview image stays on the device, the original is
  archived.
- After 90 days: only a small preview image stays on the device.
- After one year: only a placeholder remains, the original lies safely
  in the archive.

You can tap an archived medium at any time to fetch it back --
provided you are connected to your home network. Particularly important
media can be pinned so that they are never offloaded.

Under "Storage Budget" you set how many MB of media stay on the device
(default: 100 MB on the phone, 2 GB on the computer). When it is full,
the oldest medium that is not pinned is archived first. An original is
deleted only when it is safely in the archive -- text messages are
always retained.

### Transcription for voice messages

When activated, your voice messages are converted to text locally on
your device (with the open-source model Whisper). The transcribed text
is sent together with the recording to your counterpart. The
transcription happens entirely on your device -- no data goes to
external services.

Which model (tiny, base, small) is downloaded, you set once for the
device; the language (automatic or fixed) per identity.

### Auto-download

You can set from which size media should be downloaded automatically.
This way you can, for example, have images load automatically but
decide manually on large videos.

### Devices

Under "Devices" -> "Manage devices" you see this device. Pairing a
further device comes with a later version (chapter 11).

### Network

Cleona needs no network settings to work. There are three network
switches:

- **Port forwarding on the router** (default: on). Cleona asks your own
  router to open a door for Cleona. If that works, your device is
  better reachable for others and helps the network. Cleona only talks
  to your router, not to the internet.
- **Public address entries** (default: on). If your device still has
  too few neighbors, it looks up further entry points in a public
  directory (Nostr), and if it is itself well reachable, it enters
  itself there. The entry contains an address, no name and no contact.
  If you switch it off, your device finds neighbors only via
  invitations, the local network, and the neighbors it already knows.
- **Fewer cover packets in the Wi-Fi** (default: off). In the Wi-Fi
  or on a cable you can switch off the empty cover packets. But
  then it is again visible when you are writing. There is no such
  switch on mobile data -- there Cleona sends only one cover
  packet per minute anyway.

The cover traffic as a whole cannot be switched off. That is
intentional: only if it always runs does the activity of your device
say nothing about whether you are currently writing.

Above the three switches stands the **Data-saving mode**: on mobile
data, Cleona suggests it, but never switches it on itself. It saves
data, but as a result your device is easier to recognize from the
outside.

Below that you set the **"Cache for other people’s media"**: your
device keeps encrypted parts of other people's media for up to 7 days,
so that they reach their recipients (default: 100 MB on the phone,
1 GB on the computer). A smaller size frees the space immediately --
the oldest parts first.

---

## 14. Security

### What does post-quantum encryption mean?

Today's encryption is based on mathematical problems that are extremely
hard to solve for normal computers. Quantum computers could solve some
of these problems quickly in the future. Post-quantum encryption uses
additional methods that withstand quantum computers too.

Cleona combines both approaches: classical encryption for reliability
and post-quantum methods for future-proofing. This way you are
protected against today's and future threats at the same time.

A separate key is generated for each individual message. Even if an
attacker cracked the key of one message, they could not read any other
message with it.

### Why no server is safer

With conventional messengers, your messages run through the provider's
servers. Even if they may be encrypted there: the provider has access
to metadata (who communicates with whom, when, how often, from where)
and may have to hand these out on a court order.

With Cleona there is no such central point. There is no place where all
metadata converge, and no directory in which one could look up who you
are or whom you know.

### Who sees that you are writing with someone?

Encryption protects **what** you write. Just as important is that no
single observer learns **with whom** and **when** you write. Cleona
ensures that as follows:

- **On the internet never directly.** If your device sent a message
  directly to your counterpart's internet address, your provider could
  see with whom you are writing. That is why a message on the internet
  always goes via your fixed neighbors: yours and your counterpart's.
- **Neighbors you trust.** Your fixed neighbors are, wherever possible,
  devices of your own contacts -- up to three that are currently
  reachable from the outside. If one drops out, another contact moves
  up. A contact cannot be bought with servers; an arbitrary node in the
  network can. If you do not yet have a reachable contact, Cleona takes
  another neighbor. Your invitation never names any of your contacts,
  so that no one learns the address of a friend via them.
- **Codes instead of names.** The neighbors see no names and no
  identifiers, only a code. It applies to exactly the two of you, in
  one direction, for one day -- the next day it is a different one.
  Your neighbor knows where the packet comes from, but not where it
  goes in the end. Your counterpart's neighbor knows where it goes, but
  not where it came from. Normally, no one along the way sees both ends.
- **The cover traffic.** Your device constantly sends, at irregular
  intervals, cover packets to its neighbors. They are just as
  large as real packets, go over the same port, and are
  indistinguishable from them from the outside. Whether a human is
  currently writing or the device is just running cannot be told from
  it. Your messages never wait for the cover traffic -- they start
  immediately, it just runs alongside.

**What the cover traffic costs:** in the Wi-Fi about 13 MB per day.
On mobile data, Cleona sends only one cover packet per minute,
that is about 1.7 MB per day. The reason for the throttling on mobile
data is not the data volume, but the battery: every packet wakes up
the radio modem.

**What Cleona cannot hide** -- honestly:

- No **single** observer sees who is writing with whom -- neither your
  provider nor the nodes along the way. Whoever, however, monitors
  **both ends at the same time**, for example a state that watches your
  connection and your counterpart's or sets up both neighbors, can
  correlate over time: packet out at your side, shortly after a packet
  in at your counterpart's. Repeated often enough, that yields a
  connection.
- The cover traffic makes this correlation harder, but does not
  prevent it. It hides individual messages, not the volume: whoever
  sends a lot increases the total traffic of their device.
- A contact who is your fixed neighbor learns **when** and **how much**
  you send and receive -- not with whom and not what. If the danger
  comes from your own surroundings, you can exempt every contact from
  it (see chapter 3, "Never use as a fixed neighbor").
- If two new users have only the same one neighbor, their message runs
  over exactly this node, and it sees both ends. As soon as one of the
  two has further neighbors, that is over.
- Your invitation contains your internet addresses. Whoever has the
  text line sees where you are online -- give it only to people you
  trust with that.
- A neighbor that forwards sees that two codes exchange packets -- not
  who is behind them, and not what is inside.
- A signal of a running call can, when the first neighbor is
  momentarily not answering, go via a node that sees both ends; it
  learns that the two of you are calling together.
- A large file you have consented to is seen by the computer that
  forwards or keeps it, at both ends (see chapter 4).
- For calls, the protection against the provider does not apply, and
  your contact sees your internet address (see chapter 7).

### What happens when your counterpart is offline?

1. Cleona starts all suitable routes at the same time: in the same Wi-Fi
   directly, on the internet via two neighbors -- and additionally the
   mailbox.
2. For the mailbox, Cleona deposits the encrypted message at three
   neighbors. As soon as two have confirmed receipt, it counts as
   deposited.
3. Cleona preferably chooses neighbors for this at which your
   counterpart also looks -- first the neighbor that their invitation
   names.
4. The message waits there for up to 7 days. When your counterpart
   returns, they pick it up and confirm receipt to you. Only then do
   you see two checks.

Only your counterpart can empty the mailbox: picking up and deleting
works only with a key that only they have, and deletion happens only
after they have confirmed receipt. The neighbors see only encrypted
packets under a value that changes every day.

### Strangers do not get through

From someone who is neither your contact nor a member of a shared
group, Cleona accepts exactly two
things: the request for your public keys, as long as one of your
invitations is still open, and a contact request. The request must
carry a valid invitation from you, and the sender must have solved a
computational task beforehand. Everything else -- messages, calls,
files -- is discarded before it even reaches the app. Whoever only has
your printed business card therefore cannot simply call you. A member
of a shared group reaches you only in that group -- with group messages
and group calls, never individually.

### Anti-censorship

Cleona is built so that it is hard to block:

- **No server, no fixed address.** There is no address in the app that
  one could block, and the network does not depend on any single node.
- **No fixed port.** Every device chooses a random port on first start.
  There is no known port number by which one could recognize Cleona
  traffic.
- **Like random data.** The connection setup between two devices is
  coded so that it is indistinguishable from random data.
- **Many entry points.** Every invitation, every neighbor, and every
  device in the same Wi-Fi is a possible route back into the network.

### Secure key storage

On supported platforms, Cleona stores your encryption keys in the
operating system's secure keyring (Android Keystore, iOS Keychain,
macOS Keychain). Where available, that offers hardware-backed
protection for your keys.

### Database encryption

Your messages and conversations lie in an encrypted database -- a
separate one for each identity, each with its own key. Not only the
database itself is encrypted, but also its temporary files; nothing is
written to disk unencrypted, not even briefly. Settings, contacts, and
media are also stored encrypted.

The keys are derived from your 24 words and exist only on your device.
Even someone who gets their hands on your device and reads out the data
finds only unreadable data without these keys.

It becomes unencrypted only where you yourself take content out of
Cleona:
- when you save a file from a chat onto your device,
- when you put an image into your pictures with the screenshot button,
- when you share something to another app,
- when you set up media archiving (chapter 13): the archived originals
  lie unencrypted on your network storage at home, so that you can
  open them there even without Cleona,
- when you mirror appointments to the Android system calendar: there,
  other apps with calendar access can read them.

What has left this way is not deleted with the message and does not
expire with it.

### Protection on the screen

On Android, Windows, and macOS, Cleona does not allow screen recording
by other apps. If you need an image, use the screenshot button in the
top bar: it puts the image into your pictures -- unencrypted. In a
conversation in which forwarding is not allowed, there is no
screenshot.

---

## 15. Software updates

### How do I get updates?

Cleona can be updated via various routes. The goal is that you can
receive updates even when individual distribution channels fail or are
blocked:

1. **App Store / Play Store:** As soon as Cleona appears there and you
   installed it via a store, you receive updates via the store as
   usual. On the iPhone, updates come via TestFlight.
2. **GitHub Releases:** On the project's GitHub page you find signed
   installation packages for all platforms.
3. **Updates over the network:** Cleona can fetch an update directly
   over the network -- without a download server. The new version is
   split into error-corrected pieces that spread in the network; a part
   of them even travels along in the cover traffic. Your device
   collects enough pieces and assembles the update. What is transferred
   is usually only the change -- a few MB instead of the whole app.
   This applies to Linux, Windows, and Android; under macOS you
   download new versions from the website or from GitHub.
4. **Invitation links:** You can create invitation links that contain
   everything a new user needs to install Cleona and connect to the
   network.
5. **Physical transfer:** In environments without internet you can pass
   Cleona on to others via USB stick or in the local network.

### How an update runs

1. Cleona collects the pieces of a new update automatically in the
   background and assembles them.
2. Only when the update is **complete** and its **signature has been
   verified** does Cleona offer it to you. You are thus never offered a
   half or unverified update.
3. When you tap "Install", the installation starts without further
   asking. On Android, the system additionally shows its installation
   dialog.

Older versions are not offered -- an update always only goes forward.
If a version is so old that it can no longer cooperate with the
network, Cleona indicates that clearly and asks you to update.

### Signature verification

Every update is signed twice: with a classical and a post-quantum
method. Cleona verifies both signatures automatically. This ensures
that only updates from the official developer are accepted -- even if
the update came over the network from foreign devices. An update is
never created automatically from development, but only when the
developer signs it by hand.

---
## 16. Frequently asked questions

### "Can I use Cleona without internet?"

Cleona needs a network connection, but not necessarily the internet:
in the same Wi-Fi, Cleona devices find each other on their own and can
write with each other entirely without internet access. You do not have
to be online at the same time as your counterpart: if they are offline,
the message waits up to 7 days in the mailbox at three neighbors, until
they pick it up.

### "What if I lose my seed phrase?"

As long as one device with your identity is still running, nothing is
lost -- you simply keep writing there. On the device on which you
created the identity, you can usually read off the 24 words again
(see chapter 2). Do not rely on it: a reinstallation clears this copy
away, and on Android removing or changing the screen lock destroys it
too. If you have neither the words nor a device, there is
no way back -- not via your contacts, the developer, or anyone else.
That is why it is so important to keep the 24 words safe.

### "Can someone read along on my messages?"

No. Every message is encrypted with a one-time key that applies only to
this one message. Only you and your counterpart can decrypt the
message. There is no central server, no master key, and no access for
the developer. Even if a device forwards the message on the transport
route, it sees only encrypted mush and a code. Your neighbor knows that
the packet comes from you, but not to whom it is going; your
counterpart's neighbor knows to whom it is going, but not from whom.

### "Why don't I need a phone number?"

Because your identity is purely cryptographic. Instead of a phone
number or email address that is linked to your real name, a key pair
that was generated on your device identifies you. You add contacts via
QR code, NFC, or the text line of your invitation -- not via a phone
book. That means more privacy, because your messenger account is not
bound to your real identity.

### "How do I find people on Cleona?"

Cleona deliberately has no contact search by phone number or name --
that would be a privacy problem. Instead, you exchange invitations
directly: via QR code, NFC, or as a text line via another route. That
is like exchanging business cards instead of looking up in a phone
book.

### "Does Cleona also work abroad?"

Yes. As long as you have an internet connection, Cleona works
everywhere in the world. Since there is no central server and no fixed
address, the service cannot simply be switched off for particular
countries. How Cleona makes blocking harder is described in the
"Security" chapter under "Anti-censorship". A country that blocks every
unknown traffic at the border can, however, also stop Cleona.

### "Is Cleona free?"

Yes. Cleona is free to use and without advertising. Since there is no
central server, no server costs accrue for operation either. In the
settings under "Support Cleona" -> "Donate" you can support the
development voluntarily.

### "My message has only one check -- what does that mean?"

The message is on its way, but your counterpart has not yet confirmed
receipt -- mostly because they are currently offline. That is not an
error: the message waits up to 7 days in the mailbox. As soon as they
pick it up, you see two checks. A clock means that no route has carried
the message yet -- it sets off on its own as soon as one is there; a
warning sign means that it has found no route for 14 days and that you
can resend it.

### "Why do messages arrive late on my iPhone?"

iOS does not let apps run permanently in the background. Cleona is only
woken briefly now and then; iOS decides when. It then collects
everything. As soon as you open the app, Cleona collects what was kept
for you.

### "Can I switch from WhatsApp to Cleona?"

Yes, but you cannot transfer your WhatsApp chats. Cleona and WhatsApp
are fundamentally different systems. You have to add your contacts
individually in Cleona. The easiest way is to send the text line of
your invitation to your contacts. Every request that arrives this way
you confirm yourself under "Requests".

### "Can I use Cleona on several devices at the same time?"

Not yet. A second device for the same identity comes with a later
version (chapter 11). On several devices you can today use different
identities.

### "How do I get updates when the app store is blocked?"

Cleona can fetch updates directly over the network, without depending
on an app store, a website, or a download server. If another device in
the network has the latest version, your device can load the update
from there. Authenticity is verified by a digital signature of the
developer. Alternatively, a contact can pass the app on to you via an
invitation link or USB stick. More on this in the "Software updates"
chapter.

---

## Help and contact

If you have questions or run into a problem, you find current
information on the Cleona website and on GitHub. Since Cleona is a
decentralized project, there is no classic customer support -- but an
active community that gladly helps.

---

*This manual describes Cleona Chat version 4.2. Individual functions
may change or be extended in newer versions.*