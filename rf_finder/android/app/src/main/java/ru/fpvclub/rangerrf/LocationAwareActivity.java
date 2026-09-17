package ru.fpvclub.rangerrf;

import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.webkit.WebView;

import java.lang.reflect.Field;

public class LocationAwareActivity extends MainActivity {
    private final Handler locationHandler = new Handler(Looper.getMainLooper());
    private LocationBridge locationBridge;

    @Override protected void onCreate(Bundle state) {
        super.onCreate(state);
        try {
            Field f = MainActivity.class.getDeclaredField("webView");
            f.setAccessible(true);
            WebView view = (WebView) f.get(this);
            if (view != null) {
                locationBridge = new LocationBridge(this, view);
                view.addJavascriptInterface(locationBridge, "AndroidLocation");
                // MainActivity owns the WebViewClient. Retry injection while its local page finishes loading.
                locationHandler.postDelayed(locationBridge::injectUi, 350);
                locationHandler.postDelayed(locationBridge::injectUi, 900);
                locationHandler.postDelayed(locationBridge::injectUi, 1800);
            }
        } catch (Exception ignored) {
            locationBridge = null;
        }
    }

    @Override public void onRequestPermissionsResult(int requestCode, String[] permissions, int[] grantResults) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults);
        if (locationBridge != null) locationBridge.onRequestPermissionsResult(requestCode, grantResults);
    }

    @Override protected void onDestroy() {
        if (locationBridge != null) locationBridge.destroy();
        locationHandler.removeCallbacksAndMessages(null);
        super.onDestroy();
    }
}
