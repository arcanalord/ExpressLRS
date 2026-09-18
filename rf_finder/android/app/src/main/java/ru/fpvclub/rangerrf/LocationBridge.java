package ru.fpvclub.rangerrf;

import android.Manifest;
import android.app.Activity;
import android.content.Context;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.location.Location;
import android.location.LocationListener;
import android.location.LocationManager;
import android.net.Uri;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.webkit.JavascriptInterface;
import android.webkit.WebView;

import org.json.JSONObject;

import java.util.List;
import java.util.Locale;

public final class LocationBridge {
    private static final int REQUEST_LOCATION = 2401;
    private static final long FIX_TIMEOUT_MS = 9000;

    private final Activity activity;
    private final WebView webView;
    private final LocationManager locationManager;
    private final Handler main = new Handler(Looper.getMainLooper());
    private LocationListener activeListener;
    private Runnable timeoutRunnable;

    LocationBridge(Activity activity, WebView webView) {
        this.activity = activity;
        this.webView = webView;
        this.locationManager = (LocationManager) activity.getSystemService(Context.LOCATION_SERVICE);
    }

    @JavascriptInterface
    public void requestFix() {
        main.post(this::requestFixOnMain);
    }

    @JavascriptInterface
    public void openMap(double lat, double lon) {
        main.post(() -> {
            try {
                String q = String.format(Locale.US, "geo:%.7f,%.7f?q=%.7f,%.7f(RF%%20target)", lat, lon, lat, lon);
                Intent i = new Intent(Intent.ACTION_VIEW, Uri.parse(q));
                activity.startActivity(i);
            } catch (Exception first) {
                try {
                    String url = String.format(Locale.US, "https://www.openstreetmap.org/?mlat=%.7f&mlon=%.7f#map=18/%.7f/%.7f", lat, lon, lat, lon);
                    activity.startActivity(new Intent(Intent.ACTION_VIEW, Uri.parse(url)));
                } catch (Exception ignored) {}
            }
        });
    }

    @JavascriptInterface
    public String capability() {
        try {
            JSONObject o = new JSONObject();
            o.put("fineGranted", activity.checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED);
            o.put("coarseGranted", activity.checkSelfPermission(Manifest.permission.ACCESS_COARSE_LOCATION) == PackageManager.PERMISSION_GRANTED);
            o.put("gpsEnabled", locationManager != null && locationManager.isProviderEnabled(LocationManager.GPS_PROVIDER));
            o.put("networkEnabled", locationManager != null && locationManager.isProviderEnabled(LocationManager.NETWORK_PROVIDER));
            return o.toString();
        } catch (Exception e) {
            return "{}";
        }
    }

    void injectUi() {
        main.post(() -> {
            if (webView == null) return;
            String js = "(function(){if(document.getElementById('rf-fusion3-feature'))return;" +
                    "function load(id,src,next){var s=document.createElement('script');s.id=id;s.src=src;s.onload=next||null;document.body.appendChild(s);}" +
                    "load('rf-measurements','file:///android_asset/measurements.js',function(){" +
                    "load('rf-fusion-sim','file:///android_asset/fusion-sim.js',function(){" +
                    "load('rf-fusion3-feature','file:///android_asset/fusion3.js');});});})();";
            webView.evaluateJavascript(js, null);
        });
    }

    void onRequestPermissionsResult(int requestCode, int[] grantResults) {
        if (requestCode != REQUEST_LOCATION) return;
        boolean granted = false;
        if (grantResults != null) {
            for (int r : grantResults) if (r == PackageManager.PERMISSION_GRANTED) granted = true;
        }
        if (granted) requestFixOnMain();
        else pushError("Разрешение геолокации не выдано");
    }

    void destroy() {
        main.post(this::cancelActiveRequest);
    }

    private boolean hasLocationPermission() {
        return activity.checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED ||
                activity.checkSelfPermission(Manifest.permission.ACCESS_COARSE_LOCATION) == PackageManager.PERMISSION_GRANTED;
    }

    private void requestFixOnMain() {
        if (locationManager == null) {
            pushError("Служба геолокации недоступна");
            return;
        }
        if (!hasLocationPermission()) {
            activity.requestPermissions(new String[]{
                    Manifest.permission.ACCESS_FINE_LOCATION,
                    Manifest.permission.ACCESS_COARSE_LOCATION
            }, REQUEST_LOCATION);
            return;
        }

        cancelActiveRequest();
        Location cached = bestLastKnown();
        String provider = null;
        try {
            if (locationManager.isProviderEnabled(LocationManager.GPS_PROVIDER)) provider = LocationManager.GPS_PROVIDER;
            else if (locationManager.isProviderEnabled(LocationManager.NETWORK_PROVIDER)) provider = LocationManager.NETWORK_PROVIDER;
        } catch (Exception ignored) {}

        if (provider == null) {
            if (cached != null) pushLocation(cached, true);
            else pushError("Включи геолокацию/GPS");
            return;
        }

        activeListener = new LocationListener() {
            @Override public void onLocationChanged(Location location) {
                if (location == null) return;
                pushLocation(location, false);
                cancelActiveRequest();
            }
            @Override public void onProviderEnabled(String provider) {}
            @Override public void onProviderDisabled(String provider) {}
            @Override public void onStatusChanged(String provider, int status, Bundle extras) {}
        };

        try {
            locationManager.requestLocationUpdates(provider, 0L, 0f, activeListener, Looper.getMainLooper());
        } catch (SecurityException e) {
            pushError("Нет разрешения геолокации");
            cancelActiveRequest();
            return;
        } catch (Exception e) {
            if (cached != null) pushLocation(cached, true);
            else pushError("Не удалось получить координаты: " + e.getMessage());
            cancelActiveRequest();
            return;
        }

        final Location fallback = cached;
        timeoutRunnable = () -> {
            if (fallback != null) pushLocation(fallback, true);
            else pushError("GPS fix не получен за 9 с");
            cancelActiveRequest();
        };
        main.postDelayed(timeoutRunnable, FIX_TIMEOUT_MS);
    }

    private Location bestLastKnown() {
        if (!hasLocationPermission() || locationManager == null) return null;
        Location best = null;
        try {
            List<String> providers = locationManager.getProviders(true);
            for (String provider : providers) {
                Location l = locationManager.getLastKnownLocation(provider);
                if (l == null) continue;
                if (best == null) best = l;
                else {
                    boolean fresher = l.getTime() > best.getTime();
                    boolean muchMoreAccurate = l.hasAccuracy() && (!best.hasAccuracy() || l.getAccuracy() + 15f < best.getAccuracy());
                    if (muchMoreAccurate || (fresher && (!best.hasAccuracy() || !l.hasAccuracy() || l.getAccuracy() <= best.getAccuracy() * 1.5f))) best = l;
                }
            }
        } catch (SecurityException ignored) {}
        return best;
    }

    private void cancelActiveRequest() {
        if (timeoutRunnable != null) {
            main.removeCallbacks(timeoutRunnable);
            timeoutRunnable = null;
        }
        if (activeListener != null && locationManager != null) {
            try { locationManager.removeUpdates(activeListener); } catch (Exception ignored) {}
            activeListener = null;
        }
    }

    private void pushLocation(Location l, boolean cached) {
        try {
            JSONObject o = new JSONObject();
            o.put("ok", true);
            o.put("lat", l.getLatitude());
            o.put("lon", l.getLongitude());
            o.put("accuracyM", l.hasAccuracy() ? l.getAccuracy() : JSONObject.NULL);
            o.put("altitudeM", l.hasAltitude() ? l.getAltitude() : JSONObject.NULL);
            o.put("provider", l.getProvider());
            o.put("timeMs", l.getTime());
            o.put("cached", cached);
            eval("window.onLocationFix && window.onLocationFix(" + o.toString() + ")");
        } catch (Exception e) {
            pushError("Ошибка координат");
        }
    }

    private void pushError(String message) {
        eval("window.onLocationError && window.onLocationError(" + JSONObject.quote(message) + ")");
    }

    private void eval(String js) {
        main.post(() -> {
            if (webView != null) webView.evaluateJavascript(js, null);
        });
    }
}
