package ru.fpvclub.rangerrf;

import android.os.Bundle;
import android.webkit.WebView;

public class LocationAwareActivity extends MainActivity {
    private LocationBridge locationBridge;

    @Override protected void configureWebView(WebView view) {
        locationBridge = new LocationBridge(this, view);
        view.addJavascriptInterface(locationBridge, "AndroidLocation");
    }

    @Override protected void onWebUiReady() {
        if (locationBridge != null) locationBridge.injectUi();
    }

    @Override protected void onCreate(Bundle state) {
        super.onCreate(state);
    }

    @Override public void onRequestPermissionsResult(int requestCode, String[] permissions, int[] grantResults) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults);
        if (locationBridge != null) locationBridge.onRequestPermissionsResult(requestCode, grantResults);
    }

    @Override protected void onDestroy() {
        if (locationBridge != null) locationBridge.destroy();
        super.onDestroy();
    }
}
