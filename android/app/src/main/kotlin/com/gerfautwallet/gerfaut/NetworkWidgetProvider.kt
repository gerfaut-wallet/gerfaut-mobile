package com.gerfautwallet.gerfaut

import android.content.Context
import android.content.SharedPreferences
import android.os.Bundle
import android.view.View
import android.widget.RemoteViews

// The chain as Gerfaut last saw it: the block height from the latest
// sync, and how old that reading is. Nothing private transits here.
class NetworkWidgetProvider : GerfautWidgetProvider() {

    override fun render(
        context: Context,
        data: SharedPreferences,
        options: Bundle,
    ): RemoteViews {
        val height = grantedHeight(options)
        // A single cell keeps the title and the height alone; the
        // "block height" caption and the freshness line come back with
        // the second row.
        val compact = height in 1 until 100
        return RemoteViews(context.packageName, R.layout.widget_network).apply {
            opensApp(context)
            line(
                R.id.network_height,
                data.getString("network.height", null)
                    ?: context.getString(R.string.widget_placeholder),
            )
            setViewVisibility(
                R.id.network_block_label,
                if (compact) View.GONE else View.VISIBLE,
            )
            line(
                R.id.network_footer,
                if (compact) null else data.getString("network.footer", null),
            )
        }
    }
}
