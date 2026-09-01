package com.gerfautwallet.gerfaut

import android.content.Context
import android.content.SharedPreferences
import android.os.Bundle
import android.view.View
import android.widget.RemoteViews

// The chain as Gerfaut last saw it: the block height from the latest
// sync, and the fee rates the backend recommends right now. The fee
// block disappears whole when the app wrote no rates — a network with
// no fee market, or a source that did not answer. Nothing private
// transits here.
class NetworkWidgetProvider : GerfautWidgetProvider() {

    override fun render(
        context: Context,
        data: SharedPreferences,
        options: Bundle,
    ): RemoteViews {
        val height = grantedHeight(options)
        // A single cell keeps the height alone; fees and the freshness
        // line come back with the second row.
        val compact = height in 1 until 100
        return RemoteViews(context.packageName, R.layout.widget_network).apply {
            opensApp(context)
            line(
                R.id.network_height,
                data.getString("network.height", null)
                    ?: context.getString(R.string.widget_placeholder),
            )
            val nextBlock = data.getString("network.nextBlock", null)
            line(R.id.network_next_block, nextBlock)
            line(R.id.network_hour, data.getString("network.hour", null))
            setViewVisibility(
                R.id.network_fees,
                if (nextBlock == null || compact) View.GONE else View.VISIBLE,
            )
            line(
                R.id.network_footer,
                if (compact) null else data.getString("network.footer", null),
            )
        }
    }
}
