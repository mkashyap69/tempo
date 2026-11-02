package dev.tempo.tempo

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.net.Uri
import android.text.SpannableString
import android.text.Spanned
import android.text.style.ForegroundColorSpan
import android.widget.RemoteViews
import androidx.core.content.ContextCompat
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

/**
 * Home-screen widgets (design 12). Small = Recovery; medium = Recovery,
 * Strain and Sleep. Values come from Flutter via home_widget
 * (lib/src/core/home_widgets.dart). Older than 2 h: dim and say when.
 */
abstract class TempoWidget(
    private val layout: Int,
    private val metrics: List<Pair<String, Int>>,
    private val rootUri: String,
) : HomeWidgetProvider() {

    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray, widgetData: SharedPreferences) {
        for (id in appWidgetIds) {
            val views = RemoteViews(context.packageName, layout)
            val updated = widgetData.getString("updated_at", null)?.toLongOrNull()
            val ageMs = if (updated == null) Long.MAX_VALUE else System.currentTimeMillis() - updated
            val stale = ageMs > 2 * 60 * 60 * 1000
            for ((prefix, ticks) in metrics) bind(context, views, widgetData, prefix, ticks, stale, ageMs)
            views.setOnClickPendingIntent(R.id.widget_root, launch(context, rootUri))
            // Medium: each column opens its own detail screen. (View ids are
            // global, so only layouts with several columns bind them.)
            if (metrics.size > 1) for ((prefix, _) in metrics) {
                val col = context.resources.getIdentifier("${prefix}_col", "id", context.packageName)
                if (col != 0) views.setOnClickPendingIntent(col, launch(context, uriFor(prefix)))
            }
            val note = context.resources.getIdentifier("header_note", "id", context.packageName)
            if (note != 0) views.setTextViewText(note, headerNote(updated))
            extra(context, views, widgetData, stale)
            appWidgetManager.updateAppWidget(id, views)
        }
    }

    /** "12 min ago" under the lockup; the Day widget shows the date instead. */
    protected open fun headerNote(updated: Long?): String {
        if (updated == null) return ""
        val m = (System.currentTimeMillis() - updated) / 60_000
        return when {
            m < 1 -> "now"
            m < 60 -> "$m min ago"
            else -> "${m / 60} h ago"
        }
    }

    /** Anything else a layout shows, bound before the update is sent. */
    protected open fun extra(context: Context, views: RemoteViews, d: SharedPreferences, stale: Boolean) {}

    protected fun launch(context: Context, uri: String) =
        HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java, Uri.parse(uri))

    private fun uriFor(prefix: String) = when (prefix) {
        "rec" -> "tempo://recovery"
        "strain" -> "tempo://strain"
        else -> "tempo://sleep"
    }

    private fun bind(context: Context, views: RemoteViews, d: SharedPreferences, prefix: String, ticks: Int, stale: Boolean, ageMs: Long) {
        fun c(res: Int) = ContextCompat.getColor(context, res)
        fun id(name: String) = context.resources.getIdentifier("${prefix}_$name", "id", context.packageName)
        val value = d.getString("${prefix}_value", null) ?: "—"
        val unit = if (prefix == "rec") d.getString("rec_unit", "") ?: "" else if (prefix == "sleep" && value != "—") "%" else ""
        var state = d.getString("${prefix}_state", null) ?: "Open Tempo"
        val accent = when (prefix) {
            "rec" -> when (d.getString("rec_level", "none")) {
                "high" -> c(R.color.widget_high)
                "mid" -> c(R.color.widget_mid)
                "low" -> c(R.color.widget_low)
                else -> c(R.color.widget_text2)
            }
            "strain" -> c(R.color.widget_strain)
            else -> c(R.color.widget_sleep)
        }
        if (stale && ageMs != Long.MAX_VALUE) {
            val hours = ageMs / 3_600_000
            state = when (prefix) { "strain" -> "Open to sync"; "rec" -> "Last night"; else -> "$hours h ago" }
        }
        views.setTextViewText(id("value"), value + unit)
        views.setTextViewText(id("state"), state)
        views.setTextColor(id("value"), c(if (stale) R.color.widget_text2 else R.color.widget_text1))
        views.setTextColor(id("state"), if (stale) c(R.color.widget_text2) else accent)
        val pct = if (stale && prefix == "strain") 0 else readInt(d, "${prefix}_fill").coerceIn(0, 100)
        // Recovery has a ring per level; only the current one shows.
        if (prefix == "rec") {
            val level = d.getString("rec_level", "none")
            for (l in listOf("high", "mid", "low")) {
                val ring = context.resources.getIdentifier("rec_ring_$l", "id", context.packageName)
                if (ring == 0) continue
                val on = l == level || (l == "high" && level !in listOf("high", "mid", "low"))
                views.setViewVisibility(ring, if (on) android.view.View.VISIBLE else android.view.View.GONE)
                views.setProgressBar(ring, 100, pct, false)
            }
        } else {
            val ring = id("ring")
            if (ring != 0) views.setProgressBar(ring, 100, pct, false)
        }
        // Older layouts' tick bars, if a launcher still holds one.
        val lit = Math.round(pct / 100.0 * ticks).toInt()
        for (i in 0 until ticks) {
            val tick = id("t$i")
            if (tick != 0) views.setInt(tick, "setBackgroundColor", if (i < lit) (if (stale) c(R.color.widget_text3) else accent) else c(R.color.widget_track))
        }
    }

    protected fun readInt(d: SharedPreferences, key: String): Int = try {
        d.getInt(key, 0)
    } catch (e: ClassCastException) {
        d.getLong(key, 0L).toInt()
    }
}

class TempoSmallWidget : TempoWidget(R.layout.tempo_widget_small, listOf("rec" to 0), "tempo://recovery")

class TempoMediumWidget : TempoWidget(R.layout.tempo_widget_medium, listOf("rec" to 0, "strain" to 0, "sleep" to 0), "tempo://today")

/**
 * Day (4×3): today's call with its lead coloured, the three numbers, strain
 * against its target band, steps against the goal, today's session and
 * tonight's bedtime. Values from dayWidgetData in home_widgets.dart.
 */
class TempoDayWidget : TempoWidget(R.layout.tempo_widget_day, listOf("rec" to 0, "strain" to 0, "sleep" to 0), "tempo://today") {
    override fun headerNote(updated: Long?): String =
        java.text.SimpleDateFormat("EEE d MMM", java.util.Locale.getDefault()).format(java.util.Date())

    override fun extra(context: Context, views: RemoteViews, d: SharedPreferences, stale: Boolean) {
        fun c(res: Int) = ContextCompat.getColor(context, res)
        val lead = if (stale) "Open Tempo" else d.getString("call_lead", null) ?: "Open Tempo"
        val rest = if (stale) " to update today." else d.getString("call_rest", null) ?: " to update today."
        val tone = when (if (stale) "muted" else d.getString("call_tone", "muted")) {
            "good" -> c(R.color.widget_high)
            "mid" -> c(R.color.widget_mid)
            "low" -> c(R.color.widget_low)
            "plain" -> c(R.color.widget_text1)
            else -> c(R.color.widget_text2)
        }
        val call = SpannableString(lead + rest)
        call.setSpan(ForegroundColorSpan(tone), 0, lead.length, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
        views.setTextViewText(R.id.day_call, call)

        val strain = d.getString("strain_value", null) ?: "—"
        val target = d.getString("strain_state", null) ?: ""
        views.setTextViewText(R.id.day_strain_text, if (stale) "Open to sync" else "$strain · $target")
        // Secondary progress shades up to the top of the target band.
        views.setProgressBar(R.id.day_strain_bar, 100, if (stale) 0 else readInt(d, "strain_fill"), false)
        views.setInt(R.id.day_strain_bar, "setSecondaryProgress", readInt(d, "strain_hi"))

        val steps = d.getString("steps_value", null) ?: "—"
        val goal = d.getString("steps_goal", null) ?: ""
        views.setTextViewText(R.id.day_steps_text, if (stale) "—" else "$steps of $goal")
        views.setProgressBar(R.id.day_steps_bar, 100, if (stale) 0 else readInt(d, "steps_fill"), false)

        views.setTextViewText(R.id.day_session, d.getString("session_title", null) ?: "—")
        val bed = d.getString("bed_time", null)
        val need = d.getString("sleep_need", null)
        views.setTextViewText(R.id.day_bed, if (bed == null) "—" else if (need == null) bed else "$bed · $need")
        views.setOnClickPendingIntent(R.id.day_session, launch(context, "tempo://coach"))
    }
}

/**
 * Tempo Coach: today's session, its status (Planned 18:00, Done, Not seen
 * yet…) and Start, which opens the guided workout. Tap elsewhere: Coach.
 */
class TempoSessionWidget : HomeWidgetProvider() {
    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray, widgetData: SharedPreferences) {
        fun c(res: Int) = ContextCompat.getColor(context, res)
        val updated = widgetData.getString("updated_at", null)?.toLongOrNull()
        val stale = updated == null || System.currentTimeMillis() - updated > 12 * 60 * 60 * 1000
        for (id in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.tempo_widget_session)
            val rest = widgetData.getString("session_level", "rest") == "rest"
            views.setTextViewText(R.id.session_title, widgetData.getString("session_title", null) ?: "Open Tempo")
            views.setTextViewText(R.id.session_detail, if (stale) "Open Tempo to update today’s plan" else widgetData.getString("session_detail", "") ?: "")
            views.setTextViewText(R.id.session_status, if (stale) "" else widgetData.getString("session_status", "") ?: "")
            views.setTextColor(R.id.session_status, when (widgetData.getString("session_level", "")) {
                "done" -> c(R.color.widget_high)
                "missed" -> c(R.color.widget_low)
                "late" -> c(R.color.widget_mid)
                else -> c(R.color.widget_text2)
            })
            views.setViewVisibility(R.id.session_start, if (rest || stale) android.view.View.GONE else android.view.View.VISIBLE)
            views.setOnClickPendingIntent(R.id.widget_root, HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java, Uri.parse("tempo://coach")))
            views.setOnClickPendingIntent(R.id.session_start, HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java, Uri.parse("tempo://start")))
            appWidgetManager.updateAppWidget(id, views)
        }
    }
}
