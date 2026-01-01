/// The batch of a sending loop (§11.1 "Reading."), in a file of its own so
/// that a sender outside the splitter — the update holder answering a
/// request (`update_holder.dart`) — uses the same number without loading
/// the splitter (S406-UPDPKG).
library;

/// Parts sent per event-loop turn (§11.1 „Reading.": „a sending loop yields
/// to the event loop after each batch, without waiting"). A transmission of
/// up to [kSendBatch] parts still leaves in one go.
///
/// Measured (S399, AOT, `smoke_burst_loss`): with sender and receiver in one
/// process, a synchronous burst of 367 parts kept the receiver from reading
/// until the burst was over — 274 of 367 lost in the kernel, 3 re-request
/// rounds, in every run. The yield is one event-loop turn, no clock.
const int kSendBatch = 32;
