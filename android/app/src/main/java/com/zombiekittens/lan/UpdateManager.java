package com.zombiekittens.lan;

import org.json.JSONArray;
import org.json.JSONObject;

import java.io.ByteArrayOutputStream;
import java.io.InputStream;
import java.net.HttpURLConnection;
import java.net.URL;

/**
 * Consulta la última versión publicada en GitHub Releases y compara con la instalada.
 * La descarga/instalación la hace MainActivity (necesita el contexto de la app).
 */
final class UpdateManager {
    static final String REPO = "AllanCrazyProgrammer/zombie-kittens-lan";
    static final String API = "https://api.github.com/repos/" + REPO + "/releases/latest";
    static final String APK_NAME_HINT = ".apk";

    private UpdateManager() { }

    /** Devuelve {version, url, notes} de la última release con un APK, o null si no hay. Lanza excepción sin red. */
    static JSONObject fetchLatest() throws Exception {
        HttpURLConnection c = (HttpURLConnection) new URL(API).openConnection();
        c.setConnectTimeout(7000);
        c.setReadTimeout(7000);
        c.setRequestProperty("Accept", "application/vnd.github+json");
        c.setRequestProperty("User-Agent", "ZombieKittensLAN");
        try {
            int code = c.getResponseCode();
            if (code == 404) return null;           // sin releases (o repo privado)
            if (code != 200) throw new IllegalStateException("GitHub respondió " + code);
            JSONObject rel = new JSONObject(read(c.getInputStream()));
            String url = null;
            JSONArray assets = rel.optJSONArray("assets");
            if (assets != null) for (int i = 0; i < assets.length(); i++) {
                JSONObject a = assets.getJSONObject(i);
                if (a.optString("name").toLowerCase().endsWith(APK_NAME_HINT)) { url = a.optString("browser_download_url"); break; }
            }
            if (url == null || url.isEmpty()) return null;
            JSONObject o = new JSONObject();
            o.put("version", clean(rel.optString("tag_name")));
            o.put("url", url);
            o.put("notes", rel.optString("body", ""));
            return o;
        } finally {
            c.disconnect();
        }
    }

    /** true si remote es estrictamente mayor que local (comparación numérica por partes: 1.10.0 > 1.9.3). */
    static boolean isNewer(String remote, String local) {
        String[] a = clean(remote).split("\\."), b = clean(local).split("\\.");
        for (int i = 0; i < Math.max(a.length, b.length); i++) {
            int x = i < a.length ? num(a[i]) : 0, y = i < b.length ? num(b[i]) : 0;
            if (x != y) return x > y;
        }
        return false;
    }

    static String clean(String v) {
        return v == null ? "0" : v.trim().replaceFirst("^[vV]", "").replaceAll("[^0-9.].*$", "");
    }

    private static int num(String s) {
        try { return Integer.parseInt(s); } catch (Exception e) { return 0; }
    }

    private static String read(InputStream in) throws Exception {
        try (InputStream i = in) {
            ByteArrayOutputStream out = new ByteArrayOutputStream();
            byte[] buf = new byte[8192];
            int n;
            while ((n = i.read(buf)) > 0) out.write(buf, 0, n);
            return out.toString("UTF-8");
        }
    }
}
