package com.zombiekittens.lan;

import android.annotation.SuppressLint;
import android.app.Activity;
import android.content.Context;
import android.graphics.Color;
import android.net.nsd.NsdManager;
import android.net.nsd.NsdServiceInfo;
import android.net.wifi.WifiManager;
import android.os.Bundle;
import android.os.VibrationEffect;
import android.os.Vibrator;
import android.util.Log;
import android.view.WindowManager;
import android.webkit.JavascriptInterface;
import android.webkit.WebChromeClient;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.widget.TextView;

import org.json.JSONArray;
import org.json.JSONObject;

import java.net.Inet4Address;
import java.net.InetAddress;
import java.util.ArrayDeque;
import java.util.LinkedHashMap;
import java.util.Map;

/**
 * Pantalla única: un WebView a pantalla completa que carga el juego desde el servidor local.
 * También anuncia/busca partidas en la red Wi-Fi (NSD / mDNS) para que unirse sea un solo toque.
 */
public class MainActivity extends Activity {
    private static final String TAG = "ZK";
    private static final String SERVICE_TYPE = "_zkittens._tcp.";

    private WebView web;
    private GameServer server;
    private NsdManager nsd;
    private WifiManager.MulticastLock mcLock;

    private NsdManager.RegistrationListener regListener;
    private volatile String myServiceName;
    private NsdManager.DiscoveryListener discListener;
    private final Map<String, JSONObject> found = new LinkedHashMap<>();
    private final ArrayDeque<NsdServiceInfo> resolveQueue = new ArrayDeque<>();
    private boolean resolving;

    @SuppressLint("SetJavaScriptEnabled")
    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
        nsd = (NsdManager) getSystemService(Context.NSD_SERVICE);

        try {
            server = GameServer.startOnFreePort(getAssets());
        } catch (Exception e) {
            Log.e(TAG, "No se pudo iniciar el servidor local", e);
            TextView t = new TextView(this);
            t.setText("No se pudo iniciar el juego (puerto ocupado). Cierra la app y vuelve a abrirla.");
            t.setTextColor(Color.WHITE);
            t.setPadding(48, 96, 48, 48);
            setContentView(t);
            return;
        }

        web = new WebView(this);
        web.setBackgroundColor(Color.parseColor("#170C33"));
        web.setOverScrollMode(WebView.OVER_SCROLL_NEVER);
        WebSettings ws = web.getSettings();
        ws.setJavaScriptEnabled(true);
        ws.setDomStorageEnabled(true);
        ws.setMediaPlaybackRequiresUserGesture(false);
        ws.setTextZoom(100);
        ws.setSupportZoom(false);
        web.setWebViewClient(new WebViewClient());
        web.setWebChromeClient(new WebChromeClient());
        web.addJavascriptInterface(new Bridge(), "Android");
        setContentView(web);
        web.loadUrl("http://127.0.0.1:" + server.port() + "/");
        checkForUpdate(false);
    }

    @Override
    public void onBackPressed() {
        if (web == null) { super.onBackPressed(); return; }
        web.evaluateJavascript("window.ZKNative ? window.ZKNative.back() : false", v -> {
            if (!"true".equals(v)) moveTaskToBack(true);
        });
    }

    @Override
    protected void onDestroy() {
        stopAdvertise();
        stopDiscover();
        if (server != null) server.shutdown();
        if (web != null) web.destroy();
        super.onDestroy();
    }

    /* ---------------- actualizaciones ---------------- */

    private void js(String code) {
        runOnUiThread(() -> { if (web != null) web.evaluateJavascript(code, null); });
    }

    /** Busca una versión nueva en GitHub. manual=true avisa también cuando no hay nada o no hay red. */
    private void checkForUpdate(boolean manual) {
        new Thread(() -> {
            try {
                String cur = getPackageManager().getPackageInfo(getPackageName(), 0).versionName;
                org.json.JSONObject o = UpdateManager.fetchLatest();
                if (o != null && UpdateManager.isNewer(o.getString("version"), cur)) {
                    js("window.ZKNative && window.ZKNative.update(" + o + ")");
                } else if (manual) {
                    js("window.ZKNative && window.ZKNative.updateNone(" + (o == null ? "false" : "true") + ")");
                }
            } catch (Exception e) {
                Log.w(TAG, "Actualización: " + e.getMessage());
                if (manual) js("window.ZKNative && window.ZKNative.updateError(" + org.json.JSONObject.quote(String.valueOf(e.getMessage())) + ")");
            }
        }).start();
    }

    /** Descarga el APK nuevo al caché de la app y abre el instalador del sistema. */
    private void downloadAndInstall(String url) {
        if (!getPackageManager().canRequestPackageInstalls()) {
            // Android pide permiso expreso para instalar desde la app: llevamos al usuario a ese ajuste
            runOnUiThread(() -> {
                js("window.ZKNative && window.ZKNative.updateError('Activa \"Instalar apps desconocidas\" para Zombie Kittens y vuelve a tocar Actualizar.')");
                android.content.Intent i = new android.content.Intent(android.provider.Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                        android.net.Uri.parse("package:" + getPackageName()));
                startActivity(i);
            });
            return;
        }
        new Thread(() -> {
            try {
                java.io.File dir = new java.io.File(getCacheDir(), "updates");
                dir.mkdirs();
                java.io.File f = new java.io.File(dir, "update.apk");
                java.net.HttpURLConnection c = (java.net.HttpURLConnection) new java.net.URL(url).openConnection();
                c.setInstanceFollowRedirects(true);
                c.setConnectTimeout(10000);
                c.setReadTimeout(20000);
                long total = c.getContentLengthLong(), done = 0;
                int lastPct = -1;
                try (java.io.InputStream in = c.getInputStream(); java.io.OutputStream out = new java.io.FileOutputStream(f)) {
                    byte[] buf = new byte[16384];
                    int n;
                    while ((n = in.read(buf)) > 0) {
                        out.write(buf, 0, n);
                        done += n;
                        if (total > 0) {
                            int pct = (int) (done * 100 / total);
                            if (pct != lastPct) { lastPct = pct; js("window.ZKNative && window.ZKNative.updateProgress(" + pct + ")"); }
                        }
                    }
                } finally {
                    c.disconnect();
                }
                android.net.Uri uri = androidx.core.content.FileProvider.getUriForFile(this, getPackageName() + ".fileprovider", f);
                runOnUiThread(() -> {
                    android.content.Intent i = new android.content.Intent(android.content.Intent.ACTION_VIEW);
                    i.setDataAndType(uri, "application/vnd.android.package-archive");
                    i.addFlags(android.content.Intent.FLAG_GRANT_READ_URI_PERMISSION | android.content.Intent.FLAG_ACTIVITY_NEW_TASK);
                    startActivity(i);
                    js("window.ZKNative && window.ZKNative.updateProgress(null)");
                });
            } catch (Exception e) {
                Log.w(TAG, "Descarga de actualización", e);
                js("window.ZKNative && window.ZKNative.updateError(" + org.json.JSONObject.quote("No se pudo descargar la actualización. Revisa tu conexión.") + ")");
            }
        }).start();
    }

    /* ---------------- puente JavaScript ---------------- */

    private class Bridge {
        @JavascriptInterface public String version() {
            try { return getPackageManager().getPackageInfo(getPackageName(), 0).versionName; } catch (Exception e) { return ""; }
        }
        @JavascriptInterface public void checkUpdate(boolean manual) { checkForUpdate(manual); }
        @JavascriptInterface public void installUpdate(String url) { downloadAndInstall(url); }
        @JavascriptInterface public void advertise(String name) { runOnUiThread(() -> startAdvertise(name)); }
        @JavascriptInterface public void stopAdvertise() { runOnUiThread(MainActivity.this::stopAdvertise); }
        @JavascriptInterface public void discover() { runOnUiThread(MainActivity.this::startDiscover); }
        @JavascriptInterface public void stopDiscover() { runOnUiThread(MainActivity.this::stopDiscover); }
        @JavascriptInterface public void vibrate(int ms) {
            try {
                Vibrator v = (Vibrator) getSystemService(Context.VIBRATOR_SERVICE);
                if (v != null) v.vibrate(VibrationEffect.createOneShot(Math.max(1, Math.min(ms, 1000)), VibrationEffect.DEFAULT_AMPLITUDE));
            } catch (Exception ignored) { }
        }
    }

    /* ---------------- anunciar / buscar partidas (NSD) ---------------- */

    private void lockMulticast(boolean on) {
        try {
            if (on) {
                if (mcLock == null) {
                    WifiManager wm = (WifiManager) getApplicationContext().getSystemService(Context.WIFI_SERVICE);
                    mcLock = wm.createMulticastLock("zk-nsd");
                    mcLock.setReferenceCounted(false);
                }
                mcLock.acquire();
            } else if (mcLock != null && mcLock.isHeld() && regListener == null && discListener == null) {
                mcLock.release();
            }
        } catch (Exception e) {
            Log.w(TAG, "Multicast lock", e);
        }
    }

    private void startAdvertise(String name) {
        stopAdvertise();
        if (server == null) return;
        String clean = name == null ? "" : name.replaceAll("[^\\p{L}\\p{N} _-]", "").trim();
        NsdServiceInfo info = new NsdServiceInfo();
        info.setServiceName("ZK-" + (clean.isEmpty() ? "Gatito" : clean));
        info.setServiceType(SERVICE_TYPE);
        info.setPort(server.port());
        lockMulticast(true);
        regListener = new NsdManager.RegistrationListener() {
            @Override public void onServiceRegistered(NsdServiceInfo i) { myServiceName = i.getServiceName(); }
            @Override public void onRegistrationFailed(NsdServiceInfo i, int code) { Log.w(TAG, "Registro NSD falló: " + code); }
            @Override public void onServiceUnregistered(NsdServiceInfo i) { }
            @Override public void onUnregistrationFailed(NsdServiceInfo i, int code) { }
        };
        try {
            nsd.registerService(info, NsdManager.PROTOCOL_DNS_SD, regListener);
        } catch (Exception e) {
            Log.w(TAG, "registerService", e);
            regListener = null;
        }
    }

    private void stopAdvertise() {
        if (regListener != null) {
            try { nsd.unregisterService(regListener); } catch (Exception ignored) { }
            regListener = null;
            myServiceName = null;
        }
        lockMulticast(false);
    }

    private void startDiscover() {
        stopDiscover();
        found.clear();
        pushFound();
        lockMulticast(true);
        discListener = new NsdManager.DiscoveryListener() {
            @Override public void onDiscoveryStarted(String type) { }
            @Override public void onDiscoveryStopped(String type) { }
            @Override public void onStartDiscoveryFailed(String type, int code) { Log.w(TAG, "Búsqueda NSD falló: " + code); }
            @Override public void onStopDiscoveryFailed(String type, int code) { }
            @Override public void onServiceFound(NsdServiceInfo info) {
                runOnUiThread(() -> {
                    String n = info.getServiceName();
                    if (n == null || !n.startsWith("ZK-") || n.equals(myServiceName)) return;
                    resolveQueue.add(info);
                    resolveNext();
                });
            }
            @Override public void onServiceLost(NsdServiceInfo info) {
                runOnUiThread(() -> { if (found.remove(info.getServiceName()) != null) pushFound(); });
            }
        };
        try {
            nsd.discoverServices(SERVICE_TYPE, NsdManager.PROTOCOL_DNS_SD, discListener);
        } catch (Exception e) {
            Log.w(TAG, "discoverServices", e);
            discListener = null;
        }
    }

    private void stopDiscover() {
        if (discListener != null) {
            try { nsd.stopServiceDiscovery(discListener); } catch (Exception ignored) { }
            discListener = null;
        }
        resolveQueue.clear();
        lockMulticast(false);
    }

    @SuppressWarnings("deprecation")
    private void resolveNext() {
        if (resolving || resolveQueue.isEmpty() || discListener == null) return;
        NsdServiceInfo next = resolveQueue.poll();
        resolving = true;
        try {
            nsd.resolveService(next, new NsdManager.ResolveListener() {
                @Override public void onResolveFailed(NsdServiceInfo i, int code) {
                    runOnUiThread(() -> { resolving = false; resolveNext(); });
                }
                @Override public void onServiceResolved(NsdServiceInfo i) {
                    runOnUiThread(() -> {
                        resolving = false;
                        try {
                            InetAddress a = i.getHost();
                            if (a instanceof Inet4Address && !i.getServiceName().equals(myServiceName)) {
                                JSONObject o = new JSONObject();
                                o.put("name", i.getServiceName().replaceFirst("^ZK-", "").replaceAll("\\s*\\(\\d+\\)$", ""));
                                o.put("host", a.getHostAddress());
                                o.put("port", i.getPort());
                                found.put(i.getServiceName(), o);
                                pushFound();
                            }
                        } catch (Exception e) {
                            Log.w(TAG, "resolve", e);
                        }
                        resolveNext();
                    });
                }
            });
        } catch (Exception e) {
            resolving = false;
        }
    }

    private void pushFound() {
        if (web == null) return;
        JSONArray arr = new JSONArray(found.values());
        web.evaluateJavascript("window.ZKNative && window.ZKNative.found(" + arr + ")", null);
    }
}
