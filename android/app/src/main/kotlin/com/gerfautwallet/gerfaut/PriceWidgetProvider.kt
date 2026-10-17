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
        val change = data.getString("price.change", null)
        val credit = data.getString("price.credit", null)
        val text = WidgetText(context)
        val inside = innerWidthDp(options)
        val height = grantedHeight(options)
        // What the credit may take, with the figure at its smallest
        // beside it: nothing pushes either under the edge.
        val creditRoom = if (height <= 0) null else PriceWidgetFit.creditRoomDp(
            heightDp = height,
            figureMinDp = text.lineDpAtPx(text.px(PriceWidgetFit.FIGURE_MIN_DP, dp = true)),
        )
        val creditSize = credit?.let { text.creditSize(it, inside, creditRoom) }
        val fit = PriceWidgetFit.lines(
            heightDp = height,
            figureDp = text.lineDp(PriceWidgetFit.FIGURE_TEXT_SP),
            smallDp = text.lineDp(PriceWidgetFit.SMALL_TEXT_SP),
            creditDp = creditSize?.heightDp,
        )
        return RemoteViews(context.packageName, R.layout.widget_price).apply {
            opensApp(context)
            line(
                context,
                R.id.price_figure,
                data.getString("price.figure", null)
                    ?: context.getString(R.string.widget_placeholder),
            )
            line(context, R.id.price_change, change)
            line(context, R.id.price_as_of, asOf(text, data, change, inside))
            line(context, R.id.price_credit, credit)
            if (creditSize != null) {
                setTextViewTextSize(R.id.price_credit, TypedValue.COMPLEX_UNIT_PX, creditSize.px)
                setInt(R.id.price_credit, "setMaxLines", creditSize.lines)
            }
            setViewVisibility(R.id.price_title, if (fit.title) View.VISIBLE else View.GONE)
            setViewVisibility(R.id.price_footer, if (fit.footer) View.VISIBLE else View.GONE)
        }
    }

    // The width the card leaves its lines, in dp, at the smallest the
    // launcher may draw it, the portrait width on a phone; null when it
    // has not said, as in the picker preview.
    private fun innerWidthDp(options: Bundle): Float? {
        val widthDp = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, 0)
        return if (widthDp <= 0) null else (widthDp - 2 * PriceWidgetFit.PADDING_DP).toFloat()
    }

    // The as-of line the app wrote, or its narrow form when the full one
    // would not fit: "as of Oct 03, 09:41" takes about 100dp, and the
    // widget at its narrowest leaves 82. Measured as widget_price.xml
    // draws it rather than against a threshold, so the text size the
    // reader chose counts; an unknown width keeps the full line.
    private fun asOf(
        text: WidgetText,
        data: SharedPreferences,
        change: String?,
        inside: Float?,
    ): String? {
        val full = data.getString("price.asOf", null) ?: return null
        val narrow = data.getString("price.asOfNarrow", null) ?: return full
        if (inside == null) return full
        // The change sits before the time on the same line.
        val room = inside - (change?.let {
            text.widthDp(it, PriceWidgetFit.SMALL_TEXT_SP, tabular = true) +
                PriceWidgetFit.CHANGE_MARGIN_DP
        } ?: 0f)
        return if (text.fits(full, PriceWidgetFit.SMALL_TEXT_SP, dp = false, room, tabular = true)) full else narrow
    }
}

// How the widget's text measures, at the text size the reader chose:
// one paint for every line widget_price.xml draws in the system face.
private class WidgetText(context: Context) {
    private val metrics = context.resources.displayMetrics

    private fun paint(size: Float, dp: Boolean, tabular: Boolean) =
        TextPaint(Paint.ANTI_ALIAS_FLAG).apply {
            textSize = TypedValue.applyDimension(
                if (dp) TypedValue.COMPLEX_UNIT_DIP else TypedValue.COMPLEX_UNIT_SP,
                size,
                metrics,
            )
            typeface = Typeface.create("sans-serif", Typeface.NORMAL)
            if (tabular) fontFeatureSettings = "'tnum'"
        }

    // The height of one line at [sp], in dp, the font's padding
    // included, as a TextView sizes itself.
    fun lineDp(sp: Float): Float = lineDpAtPx(px(sp, dp = false))

    fun lineDpAtPx(px: Float): Float {
        val font = TextPaint(Paint.ANTI_ALIAS_FLAG).apply { textSize = px }.fontMetrics
        return ceil(font.bottom - font.top) / metrics.density
    }

    fun px(size: Float, dp: Boolean) = TypedValue.applyDimension(
        if (dp) TypedValue.COMPLEX_UNIT_DIP else TypedValue.COMPLEX_UNIT_SP,
        size,
        metrics,
    )

    class CreditSize(val px: Float, val lines: Int, val heightDp: Float)

    // The credit's size and lines, [widthDp] wide and [heightDp] high
    // at most: 12sp, the size of the lines beside it, on one line when
    // it holds there; else as large as one line allows; else two lines,
    // at the size where its longest word holds. Never below 10dp, the
    // least the CoinGecko terms allow, and never a size that cuts the
    // source's name. An unknown width or height keeps 12sp.
    fun creditSize(text: String, widthDp: Float?, heightDp: Float?): CreditSize {
        val full = px(PriceWidgetFit.SMALL_TEXT_SP, dp = false)
        val least = minOf(full, px(PriceWidgetFit.CREDIT_MIN_DP, dp = true))
        fun sized(size: Float, lines: Int) = CreditSize(size, lines, lines * lineDpAtPx(size))
        // The largest size, down to the least, whose lines hold in the height.
        fun within(size: Float, lines: Int): CreditSize {
            var fitted = size
            while (heightDp != null && fitted > least && lines * lineDpAtPx(fitted) > heightDp) {
                fitted = maxOf(least, fitted - metrics.density / 2)
            }
            return sized(fitted, lines)
        }
        if (widthDp == null) return within(full, 1)
        val room = widthDp * metrics.density
        val measure = paint(PriceWidgetFit.SMALL_TEXT_SP, dp = false, tabular = false)
        val wide = measure.measureText(text)
        if (wide <= room) return within(full, 1)
        val oneLine = full * room / wide
        if (oneLine >= least) return within(oneLine, 1)
        val word = text.split(" ").maxOf { measure.measureText(it) }
        return within(maxOf(least, minOf(full, full * room / word)), 2)
    }

    fun widthDp(text: String, size: Float, dp: Boolean = false, tabular: Boolean = false): Float =
        ceil(paint(size, dp, tabular).measureText(text)) / metrics.density

    fun fits(text: String, size: Float, dp: Boolean, roomDp: Float, tabular: Boolean = false) =
        widthDp(text, size, dp, tabular) <= roomDp
}

// Which lines of the price widget fit at a height, kept apart from
// Android so a test can hold it to real launcher sizes.
internal object PriceWidgetFit {
    // As widget_price.xml lays out its lines: the size of the title,
    // the footer and the credit, the size of the figure at its largest
    // and at its smallest, the smallest the credit shrinks to (dp: the
    // reader's text size already counted), the gap above each line
    // under the title, the card's side and vertical padding, the margin
    // after the change.
    const val SMALL_TEXT_SP = 12f
    const val FIGURE_TEXT_SP = 22f
    const val FIGURE_MIN_DP = 10f
    const val CREDIT_MIN_DP = 10f
    const val LINE_GAP_DP = 2f
    const val PADDING_DP = 14
    const val PADDING_V_DP = 12
    const val CHANGE_MARGIN_DP = 8f

    class Lines(val title: Boolean, val footer: Boolean)

    // With no credit, a single cell has room for the title and the
    // figure, and the time comes back with the second row. A credit
    // stays whatever the size, as its source asks wherever its price
    // shows, and so does the figure, which shrinks rather than be cut
    // (widget_price.xml gives it the height left). Beside the figure at
    // its largest and the credit, the time takes the room first and the
    // title what is left: short of room, the title gives way first,
    // then the time. An unknown height, as in the picker preview, keeps
    // every line.
    fun lines(heightDp: Int, figureDp: Float, smallDp: Float, creditDp: Float?): Lines {
        if (heightDp <= 0) return Lines(title = true, footer = true)
        if (creditDp == null) return Lines(title = true, footer = heightDp >= 64)
        val inside = heightDp - 2 * PADDING_V_DP
        var used = LINE_GAP_DP + figureDp + LINE_GAP_DP + creditDp
        val footer = used + LINE_GAP_DP + smallDp <= inside
        if (footer) used += LINE_GAP_DP + smallDp
        return Lines(title = used + smallDp <= inside, footer = footer)
    }

    // The height the credit may take beside the figure at its smallest,
    // the other lines given way: the most it can have without pushing
    // anything under the edge.
    fun creditRoomDp(heightDp: Int, figureMinDp: Float): Float =
        heightDp - 2 * PADDING_V_DP - LINE_GAP_DP - figureMinDp - LINE_GAP_DP

    // The height left to the figure once the lines shown take theirs:
    // widget_price.xml gives it all of it, and it shrinks to fit.
    fun figureRoomDp(heightDp: Int, lines: Lines, smallDp: Float, creditDp: Float?): Float {
        var room = heightDp - 2f * PADDING_V_DP - LINE_GAP_DP
        if (lines.title) room -= smallDp
        if (lines.footer) room -= LINE_GAP_DP + smallDp
        if (creditDp != null) room -= LINE_GAP_DP + creditDp
        return room
    }
}
