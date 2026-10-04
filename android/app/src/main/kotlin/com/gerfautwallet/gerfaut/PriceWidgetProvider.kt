package com.gerfautwallet.gerfaut

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.graphics.Paint
import android.graphics.Typeface
import android.os.Bundle
import android.text.TextPaint
import android.util.TypedValue
import android.view.View
import android.widget.RemoteViews
import kotlin.math.ceil

// The bitcoin price in the currency chosen in the app, the change over
// a day when the source gives one, and when the quote was fetched.
// No wallet data comes near this widget.
class PriceWidgetProvider : GerfautWidgetProvider() {

    override fun render(
        context: Context,
        data: SharedPreferences,
        options: Bundle,
    ): RemoteViews {
        val height = grantedHeight(options)
        val change = data.getString("price.change", null)
        return RemoteViews(context.packageName, R.layout.widget_price).apply {
            opensApp(context)
            line(
                R.id.price_figure,
                data.getString("price.figure", null)
                    ?: context.getString(R.string.widget_placeholder),
            )
            line(R.id.price_change, change)
            line(R.id.price_as_of, asOf(context, data, change, options))
            // A single cell has room for the figure alone; its time
            // comes back with the second row.
            setViewVisibility(
                R.id.price_footer,
                if (height in 1 until 64) View.GONE else View.VISIBLE,
            )
        }
    }

    // The as-of line the app wrote, or its narrow form when the full one
    // would not fit: "as of Oct 03, 09:41" takes about 100dp, and the
    // widget at its narrowest leaves 82. Measured as widget_price.xml
    // draws it rather than against a threshold, so the text size the
    // reader chose counts. Sized against the smallest width, the
    // portrait one on a phone; an unknown width, as in the picker
    // preview, keeps the full line.
    private fun asOf(
        context: Context,
        data: SharedPreferences,
        change: String?,
        options: Bundle,
    ): String? {
        val full = data.getString("price.asOf", null) ?: return null
        val narrow = data.getString("price.asOfNarrow", null) ?: return full
        val widthDp = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, 0)
        if (widthDp <= 0) return full
        val metrics = context.resources.displayMetrics
        val paint = TextPaint(Paint.ANTI_ALIAS_FLAG).apply {
            textSize = TypedValue.applyDimension(
                TypedValue.COMPLEX_UNIT_SP,
                FOOTER_TEXT_SP,
                metrics,
            )
            typeface = Typeface.create("sans-serif", Typeface.NORMAL)
            fontFeatureSettings = "'tnum'"
        }
        var room = (widthDp - 2 * PADDING_DP) * metrics.density
        // The change sits before the time on the same line.
        if (change != null) {
            room -= ceil(paint.measureText(change)) + CHANGE_MARGIN_DP * metrics.density
        }
        return if (ceil(paint.measureText(full)) <= room) full else narrow
    }

    private companion object {
        // As widget_price.xml lays out the footer: its text size, the
        // card's side padding, the margin after the change.
        const val FOOTER_TEXT_SP = 12f
        const val PADDING_DP = 14
        const val CHANGE_MARGIN_DP = 8
    }
}
