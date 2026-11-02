package pl.portfel.portfel

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.graphics.Color
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

/** Widżet: wartość majątku, zmiana od poprzedniego notowania i wynik łączny. Dane zapisuje aplikacja. */
class PortfelWidget : HomeWidgetProvider() {
    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray, widgetData: SharedPreferences) {
        for (id in appWidgetIds) {
            val v = RemoteViews(context.packageName, R.layout.portfel_widget)
            v.setTextViewText(R.id.w_value, widgetData.getString("w_value", "—"))
            val change = widgetData.getString("w_change", "") ?: ""
            v.setTextViewText(R.id.w_change, change)
            v.setTextColor(R.id.w_change, if (change.startsWith("-") || change.startsWith("−")) Color.parseColor("#F07A6A") else Color.parseColor("#4CC98A"))
            v.setTextViewText(R.id.w_result, widgetData.getString("w_result", ""))
            v.setTextViewText(R.id.w_date, widgetData.getString("w_date", ""))
            v.setOnClickPendingIntent(R.id.w_root, HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java))
            appWidgetManager.updateAppWidget(id, v)
        }
    }
}
