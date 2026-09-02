package com.gerfautwallet.gerfaut

import android.content.Context
import android.content.SharedPreferences
import android.os.Bundle
import android.view.View
import android.widget.RemoteViews

// The total of the active network's wallets, then up to four of them by
// name, and how old the figures are. The amounts arrive already masked
// as "•••••" unless the settings allow balances on widgets and the app
// is not hiding amounts: this class never sees the difference.
class BalanceWidgetProvider : GerfautWidgetProvider() {

    override fun render(
        context: Context,
        data: SharedPreferences,
        options: Bundle,
    ): RemoteViews {
        return RemoteViews(context.packageName, R.layout.widget_balance).apply {
            opensApp(context)
            line(
                R.id.balance_total,
                data.getString("balance.total", null)
                    ?: context.getString(R.string.widget_masked_placeholder),
            )
            line(R.id.balance_synced, data.getString("balance.synced", null))
            // A row stands on its name alone: masked or not, the wallets
            // are listed, and a figure the app left out reads as masked
            // rather than taking its row with it.
            val fit = fittingRows(portraitHeight(options))
            ROWS.forEachIndexed { index, (rowId, nameId, figureId) ->
                val name = data.getString("balance.row${index + 1}.name", null)
                if (name == null || index >= fit) {
                    setViewVisibility(rowId, View.GONE)
                } else {
                    setTextViewText(nameId, name)
                    setTextViewText(
                        figureId,
                        data.getString("balance.row${index + 1}.figure", null)
                            ?: context.getString(R.string.widget_masked_placeholder),
                    )
                    setViewVisibility(rowId, View.VISIBLE)
                }
            }
        }
    }

    // How many wallet rows the height takes once the title, the total
    // and the footer have theirs; all of them when it is unknown. Sized
    // against the portrait height, the one the widget is looked at in:
    // the landscape minimum left a two-by-two card more than half empty.
    private fun fittingRows(heightDp: Int): Int {
        if (heightDp <= 0) return ROWS.size
        return ((heightDp - FRAME_DP) / ROW_DP).coerceIn(0, ROWS.size)
    }

    private companion object {
        val ROWS = listOf(
            Triple(R.id.balance_row1, R.id.balance_row1_name, R.id.balance_row1_figure),
            Triple(R.id.balance_row2, R.id.balance_row2_name, R.id.balance_row2_figure),
            Triple(R.id.balance_row3, R.id.balance_row3_name, R.id.balance_row3_figure),
            Triple(R.id.balance_row4, R.id.balance_row4_name, R.id.balance_row4_figure),
        )

        // What the fixed lines and paddings of the layout add up to,
        // and what one two-line wallet row takes with its margin, in dp.
        const val FRAME_DP = 96
        const val ROW_DP = 42
    }
}
