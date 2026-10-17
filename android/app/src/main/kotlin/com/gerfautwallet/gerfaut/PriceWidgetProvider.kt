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
// a day when the source gives one, when the quote was fetched, and the
// credit its source asks for ("Powered by CoinGecko").
// No wallet data comes near this widget.
class PriceWidgetProvider : GerfautWidgetProvider() {

    override fun render(
        context: Context,
        data: SharedPreferences,
        options: Bundle,
    ): RemoteViews {
        val height = grantedHeight(options)
        val change = data.getString("price.change", null)
        val credit = data.getString("price.credit", null)
        val fit = room(context, height, credit, options)
        return RemoteViews(context.packageName, R.layout.widget_price).apply {
            opensApp(context)
            line(
                context,
                R.id.price_figure,
                data.getString("price.figure", null)
                    ?: context.getString(R.string.widget_placeholder),
            )
            line(context, R.id.price_change, change)
            line(context, R.id.price_as_of, asOf(context, data, change, options))
            line(context, R.id.price_credit, credit)
            setViewVisibility(R.id.price_title, if (fit.title) View.VISIBLE else View.GONE)
            setViewVisibility(R.id.price_footer, if (fit.footer) View.VISIBLE else View.GONE)
        }
    }

    private class Room(val title: Boolean, val footer: Boolean)

    // Which of the title and the time line fit beside the figure. With
    // no credit, a single cell has room for the title and the figure,
    // and the time comes back with the second row. A credit stays
    // whatever the size, as its source asks wherever its price shows:
    // the title gives way first, then the time. Heights as
    // widget_price.xml draws its lines, at the text size the reader
    // chose; an unknown height, as in the picker preview, keeps them all.
    private fun room(context: Context, height: Int, credit: String?, options: Bundle): Room {
        if (credit == null) return Room(title = true, footer = height !in 1 until 64)
        if (height <= 0) return Room(title = true, footer = true)
        val small = lineDp(context, SMALL_TEXT_SP)
        val creditLines = if (fitsOneLine(context, credit, options)) 1 else 2
        var used = lineDp(context, FIGURE_TEXT_SP) + creditLines * small + 2 * LINE_GAP_DP
        val inside = height - 2 * PADDING_V_DP
        val footer = used + LINE_GAP_DP + small <= inside
        if (footer) used += LINE_GAP_DP + small
        return Room(title = used + small <= inside, footer = footer)
    }

    // The height of one line of text at [sp], in dp, padding of the font
    // included, as a TextView sizes itself.
    private fun lineDp(context: Context, sp: Float): Float {
        val metrics = context.resources.displayMetrics
        val paint = TextPaint(Paint.ANTI_ALIAS_FLAG).apply {
            textSize = TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_SP, sp, metrics)
        }
        val font = paint.fontMetrics
        return ceil(font.bottom - font.top) / metrics.density
    }

    // Whether [text] fits on one line of the credit at its narrowest;
    // an unknown width, as in the picker preview, says it does.
    private fun fitsOneLine(context: Context, text: String, options: Bundle): Boolean {
        val widthDp = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, 0)
        if (widthDp <= 0) return true
        val metrics = context.resources.displayMetrics
        val paint = TextPaint(Paint.ANTI_ALIAS_FLAG).apply {
            textSize = TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_SP, SMALL_TEXT_SP, metrics)
            typeface = Typeface.create("sans-serif", Typeface.NORMAL)
        }
        return ceil(paint.measureText(text)) <= (widthDp - 2 * PADDING_DP) * metrics.density
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
                SMALL_TEXT_SP,
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
        // As widget_price.xml lays out its lines: the size of the
        // title, the footer and the credit, the size of the figure at
        // its largest, the gap above each line under the title, the
        // card's side and top padding, the margin after the change.
        const val SMALL_TEXT_SP = 12f
        const val FIGURE_TEXT_SP = 22f
        const val LINE_GAP_DP = 2f
        const val PADDING_DP = 14
        const val PADDING_V_DP = 12
        const val CHANGE_MARGIN_DP = 8
    }
}
