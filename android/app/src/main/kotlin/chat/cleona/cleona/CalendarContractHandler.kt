package chat.cleona.cleona

import android.Manifest
import android.app.Activity
import android.content.ContentUris
import android.content.ContentValues
import android.content.Context
import android.content.pm.PackageManager
import android.provider.CalendarContract
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.TimeZone

/**
 * Bridge that mirrors Cleona calendar events into the Android system
 * calendar provider (CalendarContract). One Cleona-local calendar per
 * identity, with [ACCOUNT_TYPE_LOCAL] so the events never leave the
 * device — no Google account required.
 *
 * Lifecycle:
 *   - [ensureCalendar] returns the calendarId for the identity, creating
 *     a fresh local calendar row on the first call.
 *   - [upsertEvent] / [deleteEvent] push changes in. Events keep their
 *     Cleona eventId in the SYNC_DATA1 column so future upserts can
 *     locate them without keeping a separate map.
 *   - [deleteCalendar] removes everything Cleona ever wrote for that
 *     identity in one call (the Android provider cascades events
 *     automatically when the calendar row is deleted).
 *
 * Permissions: the caller is responsible for prompting the user for
 * READ_CALENDAR / WRITE_CALENDAR. [checkPermissions] returns whether
 * both are currently granted.
 */
class CalendarContractHandler(
    private val context: Context,
    private val activity: Activity?
) : MethodChannel.MethodCallHandler {

    companion object {
        const val CHANNEL_NAME = "chat.cleona/calendar_contract"
        const val PERMISSION_REQUEST_CODE = 2042
        private const val ACCOUNT_NAME_PREFIX = "Cleona "
        private const val ACCOUNT_TYPE = CalendarContract.ACCOUNT_TYPE_LOCAL

        // We stash Cleona's own eventId in SYNC_DATA1 so a PUT (upsert)
        // from the Dart side can find the row without keeping a
        // parallel lookup table. SYNC_DATA{1..10} are reserved by
        // Android for exactly this kind of opaque sync metadata.
        private const val SYNC_DATA_EVENT_ID = CalendarContract.Events.SYNC_DATA1
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "checkPermissions" -> result.success(checkPermissions())
                "requestPermissions" -> {
                    requestPermissions()
                    result.success(null)
                }
                "ensureCalendar" -> {
                    val shortId = call.argument<String>("shortId")
                        ?: return result.error("ARG", "missing shortId", null)
                    val displayName = call.argument<String>("displayName")
                        ?: shortId
                    if (!checkPermissions()) {
                        return result.error("PERM", "calendar permission not granted", null)
                    }
                    result.success(ensureCalendar(shortId, displayName))
                }
                "upsertEvent" -> {
                    val calendarId = (call.argument<Number>("calendarId")
                        ?: return result.error("ARG", "missing calendarId", null)).toLong()
                    val eventId = call.argument<String>("eventId")
                        ?: return result.error("ARG", "missing eventId", null)
                    val title = call.argument<String>("title") ?: ""
                    val startMs = (call.argument<Number>("startMs")
                        ?: return result.error("ARG", "missing startMs", null)).toLong()
                    val endMs = (call.argument<Number>("endMs")
                        ?: return result.error("ARG", "missing endMs", null)).toLong()
                    val description = call.argument<String>("description")
                    val location = call.argument<String>("location")
                    val rrule = call.argument<String>("rrule")
                    val allDay = call.argument<Boolean>("allDay") ?: false
                    val timeZone = call.argument<String>("timeZone") ?: "UTC"
                    if (!checkPermissions()) {
                        return result.error("PERM", "calendar permission not granted", null)
                    }
                    val ok = upsertEvent(
                        calendarId, eventId, title, startMs, endMs,
                        description, location, rrule, allDay, timeZone
                    )
                    result.success(ok)
                }
                "deleteEvent" -> {
                    val calendarId = (call.argument<Number>("calendarId")
                        ?: return result.error("ARG", "missing calendarId", null)).toLong()
                    val eventId = call.argument<String>("eventId")
                        ?: return result.error("ARG", "missing eventId", null)
                    if (!checkPermissions()) {
                        return result.error("PERM", "calendar permission not granted", null)
                    }
                    result.success(deleteEvent(calendarId, eventId))
                }
                "listEvents" -> {
                    val calendarId = (call.argument<Number>("calendarId")
                        ?: return result.error("ARG", "missing calendarId", null)).toLong()
                    if (!checkPermissions()) {
                        return result.error("PERM", "calendar permission not granted", null)
                    }
                    result.success(listEvents(calendarId))
                }
                "deleteCalendar" -> {
                    val shortId = call.argument<String>("shortId")
                        ?: return result.error("ARG", "missing shortId", null)
                    if (!checkPermissions()) {
                        return result.error("PERM", "calendar permission not granted", null)
                    }
                    result.success(deleteCalendar(shortId))
                }
                else -> result.notImplemented()
            }
        } catch (e: Exception) {
            result.error("EXC", e.message, e.stackTraceToString())
        }
    }

    // ── Permissions ─────────────────────────────────────────────────

    private fun checkPermissions(): Boolean {
        val read = ContextCompat.checkSelfPermission(
            context, Manifest.permission.READ_CALENDAR
        ) == PackageManager.PERMISSION_GRANTED
        val write = ContextCompat.checkSelfPermission(
            context, Manifest.permission.WRITE_CALENDAR
        ) == PackageManager.PERMISSION_GRANTED
        return read && write
    }

    private fun requestPermissions() {
        val act = activity ?: return
        ActivityCompat.requestPermissions(
            act,
            arrayOf(
                Manifest.permission.READ_CALENDAR,
                Manifest.permission.WRITE_CALENDAR
            ),
            PERMISSION_REQUEST_CODE
        )
    }

    // ── Calendar lifecycle ──────────────────────────────────────────

    private fun accountNameFor(shortId: String): String = ACCOUNT_NAME_PREFIX + shortId

    /**
     * Return the calendarId for the identity, creating the row if missing.
     */
    private fun ensureCalendar(shortId: String, displayName: String): Long {
        val existing = findCalendarId(shortId)
        if (existing != null) return existing

        val values = ContentValues().apply {
            put(CalendarContract.Calendars.ACCOUNT_NAME, accountNameFor(shortId))
            put(CalendarContract.Calendars.ACCOUNT_TYPE, ACCOUNT_TYPE)
            put(CalendarContract.Calendars.NAME, "cleona-$shortId")
            put(CalendarContract.Calendars.CALENDAR_DISPLAY_NAME, "Cleona: $displayName")
            put(CalendarContract.Calendars.CALENDAR_COLOR, 0xFF4CAF50.toInt())
            put(
                CalendarContract.Calendars.CALENDAR_ACCESS_LEVEL,
                CalendarContract.Calendars.CAL_ACCESS_OWNER
            )
            put(CalendarContract.Calendars.OWNER_ACCOUNT, accountNameFor(shortId))
            put(CalendarContract.Calendars.VISIBLE, 1)
            put(CalendarContract.Calendars.SYNC_EVENTS, 1)
            put(
                CalendarContract.Calendars.CALENDAR_TIME_ZONE,
                TimeZone.getDefault().id
            )
        }

        // The provider requires ACCOUNT_NAME + ACCOUNT_TYPE + CALLER_IS_SYNCADAPTER
        // to insert a row with ACCOUNT_TYPE_LOCAL.
        val uri = CalendarContract.Calendars.CONTENT_URI.buildUpon()
            .appendQueryParameter(CalendarContract.CALLER_IS_SYNCADAPTER, "true")
            .appendQueryParameter(
                CalendarContract.Calendars.ACCOUNT_NAME, accountNameFor(shortId)
            )
            .appendQueryParameter(CalendarContract.Calendars.ACCOUNT_TYPE, ACCOUNT_TYPE)
            .build()

        val inserted = context.contentResolver.insert(uri, values)
            ?: throw RuntimeException("insert() returned null for calendar $shortId")
        return ContentUris.parseId(inserted)
    }

    private fun findCalendarId(shortId: String): Long? {
        val projection = arrayOf(CalendarContract.Calendars._ID)
        val selection =
            "${CalendarContract.Calendars.ACCOUNT_TYPE}=? AND ${CalendarContract.Calendars.ACCOUNT_NAME}=?"
        val args = arrayOf(ACCOUNT_TYPE, accountNameFor(shortId))
        context.contentResolver.query(
            CalendarContract.Calendars.CONTENT_URI,
            projection, selection, args, null
        )?.use { c ->
            if (c.moveToFirst()) return c.getLong(0)
        }
        return null
    }

    /**
     * Remove all rows (events + calendar) tied to the identity.
     */
    private fun deleteCalendar(shortId: String): Boolean {
        val calendarId = findCalendarId(shortId) ?: return false
        val uri = ContentUris.withAppendedId(
            CalendarContract.Calendars.CONTENT_URI, calendarId
        ).buildUpon()
            .appendQueryParameter(CalendarContract.CALLER_IS_SYNCADAPTER, "true")
            .appendQueryParameter(
                CalendarContract.Calendars.ACCOUNT_NAME, accountNameFor(shortId)
            )
            .appendQueryParameter(CalendarContract.Calendars.ACCOUNT_TYPE, ACCOUNT_TYPE)
            .build()
        val deleted = context.contentResolver.delete(uri, null, null)
        return deleted > 0
    }

    // ── Events ──────────────────────────────────────────────────────

    private fun findEventRowId(calendarId: Long, eventId: String): Long? {
        val projection = arrayOf(CalendarContract.Events._ID)
        val selection =
            "${CalendarContract.Events.CALENDAR_ID}=? AND $SYNC_DATA_EVENT_ID=?"
        val args = arrayOf(calendarId.toString(), eventId)
        context.contentResolver.query(
            CalendarContract.Events.CONTENT_URI,
            projection, selection, args, null
        )?.use { c ->
            if (c.moveToFirst()) return c.getLong(0)
        }
        return null
    }

    private fun upsertEvent(
        calendarId: Long,
        eventId: String,
        title: String,
        startMs: Long,
        endMs: Long,
        description: String?,
        location: String?,
        rrule: String?,
        allDay: Boolean,
        timeZone: String
    ): Boolean {
        val values = ContentValues().apply {
            put(CalendarContract.Events.CALENDAR_ID, calendarId)
            put(CalendarContract.Events.TITLE, title)
            put(CalendarContract.Events.DTSTART, startMs)
            // RRULE events must set DURATION and leave DTEND null; others
            // use DTEND. The provider rejects anything else.
            if (rrule != null && rrule.isNotEmpty()) {
                val durationMs = endMs - startMs
                val seconds = (durationMs / 1000).coerceAtLeast(0)
                put(CalendarContract.Events.DURATION, "PT${seconds}S")
                putNull(CalendarContract.Events.DTEND)
                put(CalendarContract.Events.RRULE, rrule)
            } else {
                put(CalendarContract.Events.DTEND, endMs)
                putNull(CalendarContract.Events.DURATION)
                putNull(CalendarContract.Events.RRULE)
            }
            put(CalendarContract.Events.ALL_DAY, if (allDay) 1 else 0)
            put(CalendarContract.Events.EVENT_TIMEZONE, timeZone)
            if (description != null) put(CalendarContract.Events.DESCRIPTION, description)
            if (location != null) put(CalendarContract.Events.EVENT_LOCATION, location)
            put(SYNC_DATA_EVENT_ID, eventId)
        }

        val existing = findEventRowId(calendarId, eventId)
        // Writes to SYNC_DATA1 — and deletes on ACCOUNT_TYPE_LOCAL rows —
        // are only accepted by the provider when the request is marked
        // as CALLER_IS_SYNCADAPTER. Without this flag the provider throws
        // `IllegalArgumentException: Only sync adapters may write to
        // sync_data1`, which silently failed the upsert during the first
        // on-device test.
        val shortId = findShortIdByCalendarId(calendarId) ?: return false
        val syncAdapterEventsUri = CalendarContract.Events.CONTENT_URI.buildUpon()
            .appendQueryParameter(CalendarContract.CALLER_IS_SYNCADAPTER, "true")
            .appendQueryParameter(
                CalendarContract.Events.ACCOUNT_NAME, accountNameFor(shortId)
            )
            .appendQueryParameter(CalendarContract.Events.ACCOUNT_TYPE, ACCOUNT_TYPE)
            .build()
        return if (existing != null) {
            val uri = ContentUris.withAppendedId(syncAdapterEventsUri, existing)
            context.contentResolver.update(uri, values, null, null) > 0
        } else {
            context.contentResolver.insert(syncAdapterEventsUri, values) != null
        }
    }

    private fun deleteEvent(calendarId: Long, eventId: String): Boolean {
        val rowId = findEventRowId(calendarId, eventId) ?: return false
        val shortId = findShortIdByCalendarId(calendarId) ?: return false
        val syncAdapterEventsUri = CalendarContract.Events.CONTENT_URI.buildUpon()
            .appendQueryParameter(CalendarContract.CALLER_IS_SYNCADAPTER, "true")
            .appendQueryParameter(
                CalendarContract.Events.ACCOUNT_NAME, accountNameFor(shortId)
            )
            .appendQueryParameter(CalendarContract.Events.ACCOUNT_TYPE, ACCOUNT_TYPE)
            .build()
        val uri = ContentUris.withAppendedId(syncAdapterEventsUri, rowId)
        return context.contentResolver.delete(uri, null, null) > 0
    }

    /**
     * Reverse-lookup the identity short-id that owns a given calendarId.
     * Needed because upserts and deletes have to pass ACCOUNT_NAME /
     * ACCOUNT_TYPE as query parameters to bypass the sync-adapter check.
     */
    private fun findShortIdByCalendarId(calendarId: Long): String? {
        val projection = arrayOf(CalendarContract.Calendars.ACCOUNT_NAME)
        val selection = "${CalendarContract.Calendars._ID}=?"
        val args = arrayOf(calendarId.toString())
        context.contentResolver.query(
            CalendarContract.Calendars.CONTENT_URI,
            projection, selection, args, null
        )?.use { c ->
            if (c.moveToFirst()) {
                val accountName = c.getString(0) ?: return null
                if (accountName.startsWith(ACCOUNT_NAME_PREFIX)) {
                    return accountName.substring(ACCOUNT_NAME_PREFIX.length)
                }
            }
        }
        return null
    }

    /**
     * Return a list of {eventId, title, startMs, endMs} dictionaries for
     * the calendar, so the Dart side can diff against its own state.
     */
    private fun listEvents(calendarId: Long): List<Map<String, Any?>> {
        val projection = arrayOf(
            CalendarContract.Events._ID,
            SYNC_DATA_EVENT_ID,
            CalendarContract.Events.TITLE,
            CalendarContract.Events.DTSTART,
            CalendarContract.Events.DTEND,
            CalendarContract.Events.ALL_DAY,
            CalendarContract.Events.RRULE,
        )
        val selection = "${CalendarContract.Events.CALENDAR_ID}=?"
        val args = arrayOf(calendarId.toString())
        val out = mutableListOf<Map<String, Any?>>()
        context.contentResolver.query(
            CalendarContract.Events.CONTENT_URI,
            projection, selection, args, null
        )?.use { c ->
            while (c.moveToNext()) {
                out.add(
                    mapOf(
                        "rowId" to c.getLong(0),
                        "eventId" to (c.getString(1) ?: ""),
                        "title" to (c.getString(2) ?: ""),
                        "startMs" to c.getLong(3),
                        "endMs" to (if (c.isNull(4)) null else c.getLong(4)),
                        "allDay" to (c.getInt(5) != 0),
                        "rrule" to c.getString(6),
                    )
                )
            }
        }
        return out
    }
}
