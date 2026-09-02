package com.gerfautwallet.gerfaut

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.os.Bundle
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetPlugin
import es.antonborri.home_widget.HomeWidgetProvider

// The shared frame of the three Gerfaut widgets. The app composes flat
// strings under stable keys (lib/src/home_widgets.dart names them all);
// a provider only reads them back and lays them out. A key the app left
// out hides its line: the widget never invents a value, and nothing but
// what the app chose to say ever reaches the launcher.
abstract class GerfautWidgetProvider : HomeWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        for (id in appWidgetIds) {
            appWidgetManager.updateAppWidget(
                id,
                render(context, widgetData, appWidgetManager.getAppWidgetOptions(id)),
            )
        }
    }

    // A resize renders again at the new size, so the lines that fit are
    // the ones shown rather than a clipped stack.
    override fun onAppWidgetOptionsChanged(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        newOptions: Bundle,
    ) {
        appWidgetManager.updateAppWidget(
            appWidgetId,
            render(context, HomeWidgetPlugin.getData(context), newOptions),
        )
    }

    protected abstract fun render(
        context: Context,
        data: SharedPreferences,
        options: Bundle,
    ): RemoteViews

    // A tap anywhere on a widget opens the app, nothing narrower.
    protected fun RemoteViews.opensApp(context: Context) {
        setOnClickPendingIntent(
            R.id.widget_root,
            HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java),
        )
    }

    // Shows a line when the app said something, hides it when not.
    protected fun RemoteViews.line(viewId: Int, value: String?) {
        if (value == null) {
            setViewVisibility(viewId, View.GONE)
        } else {
            setTextViewText(viewId, value)
            setViewVisibility(viewId, View.VISIBLE)
        }
    }

    // The smallest height the launcher may draw this instance at, in
    // dp; zero when it has not said, as in the picker preview. Sizing
    // against the smallest keeps every orientation whole.
    protected fun grantedHeight(options: Bundle): Int =
        options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT, 0)

    // The height the instance gets with the phone upright, in dp; zero
    // when unknown. On a phone the smallest height is the landscape one,
    // and a list sized for it stands mostly empty the rest of the time.
    protected fun portraitHeight(options: Bundle): Int =
        options.getInt(AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT, 0)
}
