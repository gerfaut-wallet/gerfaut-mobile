package com.gerfautwallet.gerfaut

import android.content.Context
import android.content.SharedPreferences
import android.os.Bundle
import android.view.View
import android.widget.RemoteViews

// The bitcoin price in the currency chosen in the app, the change over
// a day when the source gives one, and the time the quote was fetched.
// No wallet data comes near this widget.
class PriceWidgetProvider : GerfautWidgetProvider() {

    override fun render(
        context: Context,
        data: SharedPreferences,
        options: Bundle,
    ): RemoteViews {
        val height = grantedHeight(options)
        return RemoteViews(context.packageName, R.layout.widget_price).apply {
            opensApp(context)
            line(
                R.id.price_figure,
                data.getString("price.figure", null)
                    ?: context.getString(R.string.widget_placeholder),
            )
            line(R.id.price_change, data.getString("price.change", null))
            line(R.id.price_as_of, data.getString("price.asOf", null))
            // A single cell has room for the figure alone; its time
            // comes back with the second row.
            setViewVisibility(
                R.id.price_footer,
                if (height in 1 until 64) View.GONE else View.VISIBLE,
            )
        }
    }
}
