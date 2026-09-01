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
            val fit = fittingRows(grantedHeight(options))
            ROWS.forEachIndexed { index, (rowId, nameId, figureId) ->
                val name = data.getString("balance.row${index + 1}.name", null)
                val figure = data.getString("balance.row${index + 1}.figure", null)
                if (name == null || figure == null || index >= fit) {
                    setViewVisibility(rowId, View.GONE)
                } else {
                    setTextViewText(nameId, name)
                    setTextViewText(figureId, figure)
                    setViewVisibility(rowId, View.VISIBLE)
                }
            }
        }
    }

    // How many wallet rows the granted height takes once the title, the
    // total and the footer have theirs; all of them when it is unknown.
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
        // and what one wallet row takes, in dp.
        const val FRAME_DP = 92
        const val ROW_DP = 18
    }
}
