package ru.fpvclub.rangerrf;

import android.app.Activity;
import android.app.PendingIntent;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.hardware.Sensor;
import android.hardware.SensorEvent;
import android.hardware.SensorEventListener;
import android.hardware.SensorManager;
import android.hardware.usb.UsbDevice;
import android.hardware.usb.UsbDeviceConnection;
import android.hardware.usb.UsbManager;
import android.os.Build;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.os.SystemClock;
import android.view.Surface;
import android.view.WindowManager;
import android.webkit.JavascriptInterface;
import android.webkit.WebChromeClient;
import android.webkit.WebView;
import android.webkit.WebViewClient;

import com.hoho.android.usbserial.driver.UsbSerialDriver;
import com.hoho.android.usbserial.driver.UsbSerialPort;
import com.hoho.android.usbserial.driver.UsbSerialProber;
import com.hoho.android.usbserial.util.SerialInputOutputManager;

import org.json.JSONObject;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.util.List;
import java.util.Locale;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

public class MainActivity extends Activity implements SerialInputOutputManager.Listener, SensorEventListener {
    private static final String ACTION_USB_PERMISSION = "ru.fpvclub.rangerrf.USB_PERMISSION";
    private static final int BAUD = 115200;
    private static final int WRITE_TIMEOUT_MS = 1500;

    private final Handler main = new Handler(Looper.getMainLooper());
    private final StringBuilder lineBuffer = new StringBuilder();
    private final ExecutorService uartWriter = Executors.newSingleThreadExecutor();

    private UsbManager usbManager;
    private SensorManager sensorManager;
    private Sensor rotationSensor;
    private final float[] rotationMatrix = new float[9];
    private final float[] remappedMatrix = new float[9];
    private final float[] orientation = new float[3];
    protected WebView webView;
    private UsbSerialPort serialPort;
    private SerialInputOutputManager ioManager;
    private UsbDevice connectedDevice;
    private String connectedDriver = "USB serial";
    private boolean receiverRegistered;
    private volatile long rxBytes = 0;
    private volatile long txBytes = 0;
    private volatile long rxLines = 0;
    private volatile long connectedAtMs = 0;
    private volatile long lastRxAtMs = 0;
    private volatile long lastHeadingAtMs = 0;
    private volatile int compassAccuracy = SensorManager.SENSOR_STATUS_UNRELIABLE;
    private volatile float lastHeadingDeg = Float.NaN;

    private final BroadcastReceiver receiver = new BroadcastReceiver() {
        @Override public void onReceive(Context context, Intent intent) {
            final String action = intent.getAction();
            if (ACTION_USB_PERMISSION.equals(action)) {
                UsbDevice d = getUsbDevice(intent);
                if (d != null && usbManager.hasPermission(d)) openDevice(d);
                else pushStatus("Разрешение USB не выдано", "error");
            } else if (UsbManager.ACTION_USB_DEVICE_ATTACHED.equals(action)) {
                main.postDelayed(MainActivity.this::connectUsb, 250);
            } else if (UsbManager.ACTION_USB_DEVICE_DETACHED.equals(action)) {
                UsbDevice d = getUsbDevice(intent);
                if (d != null && connectedDevice != null && d.getDeviceId() == connectedDevice.getDeviceId()) {
                    disconnectUsb("USB отключён");
                }
            }
        }
    };

    @Override protected void onCreate(Bundle state) {
        super.onCreate(state);
        getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
        usbManager = (UsbManager)getSystemService(Context.USB_SERVICE);
        sensorManager = (SensorManager)getSystemService(Context.SENSOR_SERVICE);
        rotationSensor = sensorManager.getDefaultSensor(Sensor.TYPE_ROTATION_VECTOR);

        webView = new WebView(this);
        webView.getSettings().setJavaScriptEnabled(true);
        webView.getSettings().setDomStorageEnabled(true);
        webView.getSettings().setAllowFileAccess(true);
        webView.setWebChromeClient(new WebChromeClient());
        configureWebView(webView);
        webView.setWebViewClient(new WebViewClient() {
            @Override public void onPageFinished(WebView view, String url) {
                pushStatus("USB-мост готов", "idle");
                pushSensorState();
                onWebUiReady();
                main.postDelayed(MainActivity.this::connectUsb, 250);
            }
        });
        webView.addJavascriptInterface(new JsBridge(), "AndroidSerial");
        setContentView(webView);
        registerUsbReceiver();
        webView.loadUrl("file:///android_asset/index.html");
    }

    /** Extension hook for optional app features. Called before the local page is loaded. */
    protected void configureWebView(WebView view) {}

    /** Extension hook for optional app features. Called after the local page finishes loading. */
    protected void onWebUiReady() {}

    @Override protected void onResume() {
        super.onResume();
        if (rotationSensor != null) sensorManager.registerListener(this, rotationSensor, SensorManager.SENSOR_DELAY_UI);
        pushSensorState();
    }

    @Override protected void onPause() {
        if (sensorManager != null) sensorManager.unregisterListener(this);
        super.onPause();
    }

    @Override public void onSensorChanged(SensorEvent event) {
        if (event.sensor.getType() != Sensor.TYPE_ROTATION_VECTOR) return;
        SensorManager.getRotationMatrixFromVector(rotationMatrix, event.values);
        int rotation = getWindowManager().getDefaultDisplay().getRotation();
        int axisX = SensorManager.AXIS_X, axisY = SensorManager.AXIS_Y;
        if (rotation == Surface.ROTATION_90) { axisX = SensorManager.AXIS_Y; axisY = SensorManager.AXIS_MINUS_X; }
        else if (rotation == Surface.ROTATION_180) { axisX = SensorManager.AXIS_MINUS_X; axisY = SensorManager.AXIS_MINUS_Y; }
        else if (rotation == Surface.ROTATION_270) { axisX = SensorManager.AXIS_MINUS_Y; axisY = SensorManager.AXIS_X; }
        SensorManager.remapCoordinateSystem(rotationMatrix, axisX, axisY, remappedMatrix);
        SensorManager.getOrientation(remappedMatrix, orientation);
        float deg = (float)Math.toDegrees(orientation[0]);
        if (deg < 0) deg += 360f;
        lastHeadingDeg = deg;
        lastHeadingAtMs = System.currentTimeMillis();
        long sensorMs = event.timestamp / 1000000L;
        eval("window.onHeading && window.onHeading(" + String.format(Locale.US, "%.1f", deg) + "," + sensorMs + ")");
    }

    @Override public void onAccuracyChanged(Sensor sensor, int accuracy) {
        if (sensor != null && sensor.getType() == Sensor.TYPE_ROTATION_VECTOR) {
            compassAccuracy = accuracy;
            pushSensorState();
        }
    }

    private void pushSensorState() {
        String state;
        switch (compassAccuracy) {
            case SensorManager.SENSOR_STATUS_ACCURACY_HIGH: state = "HIGH"; break;
            case SensorManager.SENSOR_STATUS_ACCURACY_MEDIUM: state = "MEDIUM"; break;
            case SensorManager.SENSOR_STATUS_ACCURACY_LOW: state = "LOW"; break;
            default: state = "UNRELIABLE"; break;
        }
        boolean available = rotationSensor != null;
        eval("window.onCompassState && window.onCompassState(" + available + "," + JSONObject.quote(state) + ")");
    }

    @Override protected void onDestroy() {
        disconnectUsb(null);
        uartWriter.shutdownNow();
        if (receiverRegistered) unregisterReceiver(receiver);
        if (webView != null) webView.destroy();
        super.onDestroy();
    }

    private void registerUsbReceiver() {
        IntentFilter f = new IntentFilter();
        f.addAction(ACTION_USB_PERMISSION);
        f.addAction(UsbManager.ACTION_USB_DEVICE_ATTACHED);
        f.addAction(UsbManager.ACTION_USB_DEVICE_DETACHED);
        if (Build.VERSION.SDK_INT >= 33) registerReceiver(receiver, f, Context.RECEIVER_EXPORTED);
        else registerReceiver(receiver, f);
        receiverRegistered = true;
    }

    private UsbSerialDriver findDriverForDevice(UsbDevice device) {
        List<UsbSerialDriver> drivers = UsbSerialProber.getDefaultProber().findAllDrivers(usbManager);
        for (UsbSerialDriver d : drivers) if (d.getDevice().getDeviceId() == device.getDeviceId()) return d;
        return null;
    }

    private UsbSerialDriver findBestDriver() {
        List<UsbSerialDriver> drivers = UsbSerialProber.getDefaultProber().findAllDrivers(usbManager);
        if (drivers.isEmpty()) return null;
        for (UsbSerialDriver d : drivers) {
            int vid = d.getDevice().getVendorId();
            if (vid == 0x10C4 || vid == 0x1A86 || vid == 0x0403 || vid == 0x067B) return d;
        }
        return drivers.get(0);
    }

    private void connectUsb() {
        if (serialPort != null) {
            pushStatus(deviceLabel() + " • 115200 • подключено", "ok");
            return;
        }
        UsbSerialDriver driver = findBestDriver();
        if (driver == null) {
            pushStatus("USB-UART не найден. Подключи CP210x / CH340 / FTDI / CDC через OTG", "idle");
            return;
        }
        UsbDevice d = driver.getDevice();
        if (!usbManager.hasPermission(d)) {
            Intent i = new Intent(ACTION_USB_PERMISSION).setPackage(getPackageName());
            int flags = PendingIntent.FLAG_UPDATE_CURRENT;
            if (Build.VERSION.SDK_INT >= 31) flags |= PendingIntent.FLAG_MUTABLE;
            PendingIntent pi = PendingIntent.getBroadcast(this, 0, i, flags);
            usbManager.requestPermission(d, pi);
            pushStatus(usbLabel(d, driver) + " • запрос разрешения…", "idle");
            return;
        }
        openDevice(d);
    }

    private void openDevice(UsbDevice d) {
        disconnectUsb(null);
        UsbSerialDriver driver = findDriverForDevice(d);
        if (driver == null || driver.getPorts().isEmpty()) {
            pushStatus(String.format(Locale.US, "Неподдерживаемый USB %04X:%04X", d.getVendorId(), d.getProductId()), "error");
            return;
        }
        UsbDeviceConnection c = usbManager.openDevice(d);
        if (c == null) { pushStatus("Не удалось открыть USB", "error"); return; }
        try {
            UsbSerialPort p = driver.getPorts().get(0);
            p.open(c);
            p.setParameters(BAUD, 8, UsbSerialPort.STOPBITS_1, UsbSerialPort.PARITY_NONE);
            try { p.setDTR(false); } catch (Exception ignored) {}
            try { p.setRTS(false); } catch (Exception ignored) {}

            serialPort = p;
            connectedDevice = d;
            connectedDriver = driver.getClass().getSimpleName().replace("SerialDriver", "");
            ioManager = new SerialInputOutputManager(p, this);
            ioManager.start();
            rxBytes = txBytes = rxLines = 0;
            connectedAtMs = System.currentTimeMillis();
            lastRxAtMs = 0;

            pushStatus(deviceLabel() + " • 115200 • подключено", "ok");
            enqueueWrite("I");
        } catch (Exception e) {
            try { c.close(); } catch (Exception ignored) {}
            serialPort = null;
            connectedDevice = null;
            pushStatus("USB ошибка: " + e.getMessage(), "error");
        }
    }

    private void disconnectUsb(String message) {
        SerialInputOutputManager io = ioManager;
        ioManager = null;
        if (io != null) io.stop();
        UsbSerialPort p = serialPort;
        serialPort = null;
        connectedDevice = null;
        connectedDriver = "USB serial";
        connectedAtMs = 0;
        lastRxAtMs = 0;
        if (p != null) try { p.close(); } catch (Exception ignored) {}
        if (message != null) pushStatus(message, "idle");
    }

    private synchronized void writeLine(String line) throws IOException {
        if (serialPort == null) throw new IOException("USB не подключён");
        String clean = line == null ? "" : line.trim();
        if (clean.isEmpty()) return;
        byte[] bytes = (clean + "\n").getBytes(StandardCharsets.US_ASCII);
        serialPort.write(bytes, WRITE_TIMEOUT_MS);
        txBytes += bytes.length;
        pushTx(clean);
    }

    private void enqueueWrite(String line) {
        uartWriter.execute(() -> {
            try { writeLine(line); }
            catch (Exception e) { pushStatus("UART запись: " + e.getMessage(), "error"); }
        });
    }

    @Override public void onNewData(byte[] data) {
        rxBytes += data.length;
        lastRxAtMs = System.currentTimeMillis();
        String chunk = new String(data, StandardCharsets.US_ASCII);
        synchronized (lineBuffer) {
            lineBuffer.append(chunk);
            int nl;
            while ((nl = lineBuffer.indexOf("\n")) >= 0) {
                String line = lineBuffer.substring(0, nl).replace("\r", "").trim();
                lineBuffer.delete(0, nl + 1);
                if (!line.isEmpty()) { ++rxLines; pushLine(line, SystemClock.elapsedRealtime()); }
            }
            if (lineBuffer.length() > 8192) lineBuffer.delete(0, lineBuffer.length() - 4096);
        }
    }

    @Override public void onRunError(Exception e) {
        main.post(() -> disconnectUsb("USB/UART ошибка: " + e.getMessage()));
    }

    private void pushLine(String line, long monoMs) { eval("window.onSerialLine && window.onSerialLine(" + JSONObject.quote(line) + "," + monoMs + ")"); }
    private void pushTx(String line) { eval("window.onSerialTx && window.onSerialTx(" + JSONObject.quote(line) + ")"); }
    private void pushStatus(String text, String state) { eval("window.onNativeStatus && window.onNativeStatus(" + JSONObject.quote(text) + "," + JSONObject.quote(state) + ")"); }
    private void eval(String js) { main.post(() -> { if (webView != null) webView.evaluateJavascript(js, null); }); }

    private String deviceLabel() {
        if (connectedDevice == null) return connectedDriver;
        return usbLabel(connectedDevice, null).replace("USB ", connectedDriver + " ");
    }

    private String usbLabel(UsbDevice d, UsbSerialDriver driver) {
        String name = driver == null ? "USB" : driver.getClass().getSimpleName().replace("SerialDriver", "");
        return String.format(Locale.US, "%s %04X:%04X", name, d.getVendorId(), d.getProductId());
    }

    private UsbDevice getUsbDevice(Intent intent) {
        if (Build.VERSION.SDK_INT >= 33) return intent.getParcelableExtra(UsbManager.EXTRA_DEVICE, UsbDevice.class);
        //noinspection deprecation
        return intent.getParcelableExtra(UsbManager.EXTRA_DEVICE);
    }

    public final class JsBridge {
        @JavascriptInterface public void connect() { main.post(MainActivity.this::connectUsb); }
        @JavascriptInterface public void disconnect() { main.post(() -> disconnectUsb("USB отключён")); }
        @JavascriptInterface public boolean isConnected() { return serialPort != null; }
        @JavascriptInterface public String transport() { return connectedDriver; }
        @JavascriptInterface public void send(String line) { enqueueWrite(line); }
        @JavascriptInterface public String diagnostics() {
            try {
                JSONObject o = new JSONObject();
                o.put("connected", serialPort != null);
                o.put("driver", connectedDriver);
                o.put("baud", BAUD);
                o.put("rxBytes", rxBytes);
                o.put("txBytes", txBytes);
                o.put("rxLines", rxLines);
                o.put("connectedAtMs", connectedAtMs);
                o.put("lastRxAtMs", lastRxAtMs);
                o.put("lastRxAgeMs", lastRxAtMs == 0 ? -1 : Math.max(0, System.currentTimeMillis() - lastRxAtMs));
                o.put("rotationVectorAvailable", rotationSensor != null);
                o.put("compassAccuracy", compassAccuracy);
                o.put("lastHeadingDeg", Float.isNaN(lastHeadingDeg) ? JSONObject.NULL : lastHeadingDeg);
                o.put("lastHeadingAgeMs", lastHeadingAtMs == 0 ? -1 : Math.max(0, System.currentTimeMillis() - lastHeadingAtMs));
                if (connectedDevice != null) {
                    o.put("vid", connectedDevice.getVendorId());
                    o.put("pid", connectedDevice.getProductId());
                }
                return o.toString();
            } catch (Exception e) { return "{}"; }
        }
    }
}
