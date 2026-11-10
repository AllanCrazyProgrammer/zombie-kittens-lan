package com.zombiekittens.lan;

import android.content.res.AssetManager;
import android.util.Log;

import com.google.zxing.BarcodeFormat;
import com.google.zxing.EncodeHintType;
import com.google.zxing.common.BitMatrix;
import com.google.zxing.qrcode.QRCodeWriter;

import org.json.JSONArray;
import org.json.JSONObject;

import java.io.IOException;
import java.io.InputStream;
import java.net.Inet4Address;
import java.net.InetAddress;
import java.net.NetworkInterface;
import java.util.ArrayList;
import java.util.Collections;
import java.util.EnumMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.atomic.AtomicInteger;

import fi.iki.elonen.NanoHTTPD;
import fi.iki.elonen.NanoWSD;

/**
 * Servidor local del juego. Hace dos cosas en un mismo puerto:
 *  1) HTTP: entrega el juego (assets/www) a la propia app y a cualquier navegador de la red (iPhone incluido).
 *  2) WebSocket (/ws): retransmite mensajes entre el anfitrión (el WebView de este teléfono) y los invitados.
 * Las reglas del juego corren en JavaScript dentro del WebView del anfitrión; aquí solo se reenvían mensajes.
 */
public class GameServer extends NanoWSD {
    private static final String TAG = "ZKServer";
    private final AssetManager assets;
    private final int port;
    private volatile Sock host;
    private final Map<String, Sock> clients = new ConcurrentHashMap<>();
    private final AtomicInteger counter = new AtomicInteger();

    public GameServer(int port, AssetManager assets) {
        super(port);
        this.port = port;
        this.assets = assets;
    }

    public int port() { return port; }

    /* ---------------- red local ---------------- */

    /** Direcciones IPv4 privadas de este teléfono, primero las de Wi-Fi / zona Wi-Fi. */
    public static List<String> lanIps() {
        List<String> wifi = new ArrayList<>(), other = new ArrayList<>();
        try {
            for (NetworkInterface ni : Collections.list(NetworkInterface.getNetworkInterfaces())) {
                if (!ni.isUp() || ni.isLoopback()) continue;
                String n = ni.getName().toLowerCase();
                if (n.startsWith("rmnet") || n.startsWith("ccmni") || n.startsWith("pdp") || n.startsWith("dummy") || n.startsWith("tun")) continue;
                for (InetAddress a : Collections.list(ni.getInetAddresses())) {
                    if (!(a instanceof Inet4Address) || !a.isSiteLocalAddress()) continue;
                    if (n.startsWith("wlan") || n.startsWith("ap") || n.startsWith("swlan") || n.startsWith("softap") || n.startsWith("eth")) wifi.add(a.getHostAddress());
                    else other.add(a.getHostAddress());
                }
            }
        } catch (Exception e) {
            Log.w(TAG, "No se pudieron leer las interfaces de red", e);
        }
        wifi.addAll(other);
        return wifi;
    }

    private static boolean isLoopback(String ip) {
        return ip != null && (ip.equals("127.0.0.1") || ip.equals("::1") || ip.equals("0:0:0:0:0:0:0:1") || ip.endsWith(":127.0.0.1"));
    }

    /* ---------------- HTTP ---------------- */

    @Override
    protected Response serveHttp(IHTTPSession s) {
        String uri = s.getUri();
        try {
            if (uri.equals("/info")) {
                List<String> ips = lanIps();
                JSONObject o = new JSONObject();
                o.put("ip", ips.isEmpty() ? "" : ips.get(0));
                o.put("ips", new JSONArray(ips));
                o.put("port", port);
                o.put("local", isLoopback(s.getRemoteIpAddress()));
                o.put("native", true);
                Response r = newFixedLengthResponse(Response.Status.OK, "application/json", o.toString());
                r.addHeader("Cache-Control", "no-store");
                return r;
            }
            if (uri.equals("/qr")) {
                List<String> t = s.getParameters().get("t");
                return newFixedLengthResponse(Response.Status.OK, "image/svg+xml", qrSvg(t == null || t.isEmpty() ? "" : t.get(0)));
            }
            if (uri.contains("..")) return newFixedLengthResponse(Response.Status.FORBIDDEN, MIME_PLAINTEXT, "");
            String path = "www" + (uri.equals("/") ? "/index.html" : uri);
            InputStream in = assets.open(path);
            Response r = newChunkedResponse(Response.Status.OK, mime(path), in);
            r.addHeader("Cache-Control", "no-cache");
            return r;
        } catch (IOException e) {
            return newFixedLengthResponse(Response.Status.NOT_FOUND, MIME_PLAINTEXT, "No encontrado");
        } catch (Exception e) {
            Log.e(TAG, "Error HTTP " + uri, e);
            return newFixedLengthResponse(Response.Status.INTERNAL_ERROR, MIME_PLAINTEXT, "Error");
        }
    }

    private static String mime(String p) {
        if (p.endsWith(".html")) return "text/html; charset=utf-8";
        if (p.endsWith(".js")) return "text/javascript; charset=utf-8";
        if (p.endsWith(".css")) return "text/css; charset=utf-8";
        if (p.endsWith(".woff2")) return "font/woff2";
        if (p.endsWith(".svg")) return "image/svg+xml";
        if (p.endsWith(".png")) return "image/png";
        return "application/octet-stream";
    }

    private static String qrSvg(String text) throws Exception {
        Map<EncodeHintType, Object> hints = new EnumMap<>(EncodeHintType.class);
        hints.put(EncodeHintType.MARGIN, 1);
        BitMatrix m = new QRCodeWriter().encode(text.isEmpty() ? " " : text, BarcodeFormat.QR_CODE, 0, 0, hints);
        int n = m.getWidth();
        StringBuilder sb = new StringBuilder();
        sb.append("<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 ").append(n).append(' ').append(n)
          .append("\" shape-rendering=\"crispEdges\"><rect width=\"100%\" height=\"100%\" fill=\"#fff\"/><path fill=\"#000\" d=\"");
        for (int y = 0; y < n; y++) for (int x = 0; x < n; x++) if (m.get(x, y)) sb.append('M').append(x).append(' ').append(y).append("h1v1h-1z");
        sb.append("\"/></svg>");
        return sb.toString();
    }

    /* ---------------- WebSocket: retransmisión ---------------- */

    @Override
    protected WebSocket openWebSocket(IHTTPSession handshake) {
        return new Sock(handshake);
    }

    public void shutdown() {
        Sock h = host;
        host = null;
        if (h != null) h.quit();
        for (Sock c : clients.values()) c.quit();
        clients.clear();
        stop();
    }

    private class Sock extends WebSocket {
        final boolean isHost;
        final boolean allowed;
        String cid;

        Sock(IHTTPSession hs) {
            super(hs);
            List<String> role = hs.getParameters().get("role");
            isHost = role != null && role.contains("host");
            // Solo el WebView de este mismo teléfono puede ser anfitrión
            allowed = hs.getUri().equals("/ws") && (!isHost || isLoopback(hs.getRemoteIpAddress()));
        }

        synchronized void say(String text) {
            try {
                if (isOpen()) send(text);
            } catch (IOException e) {
                Log.d(TAG, "Envío fallido a " + cid);
            }
        }

        void quit() {
            try {
                close(WebSocketFrame.CloseCode.NormalClosure, "bye", false);
            } catch (IOException ignored) { }
        }

        @Override
        protected void onOpen() {
            if (!allowed) { quit(); return; }
            if (isHost) {
                Sock old = host;
                host = this;
                if (old != null) old.quit();
                for (Sock c : clients.values()) c.quit();
                clients.clear();
                return;
            }
            if (host == null) { say("{\"t\":\"nohost\"}"); quit(); return; }
            cid = "c" + counter.incrementAndGet();
            clients.put(cid, this);
            host.say("{\"ev\":\"open\",\"from\":\"" + cid + "\"}");
        }

        @Override
        protected void onMessage(WebSocketFrame frame) {
            try {
                JSONObject m = new JSONObject(frame.getTextPayload());
                if ("ping".equals(m.optString("t"))) { say("{\"t\":\"pong\"}"); return; }
                if (isHost) {
                    if (host != this) return;
                    Sock c = clients.get(m.optString("to"));
                    JSONObject data = m.optJSONObject("data");
                    if (c != null && data != null) c.say(data.toString());
                } else {
                    Sock h = host;
                    if (h == null || cid == null) return;
                    JSONObject o = new JSONObject();
                    o.put("ev", "msg");
                    o.put("from", cid);
                    o.put("data", m);
                    h.say(o.toString());
                }
            } catch (Exception e) {
                Log.d(TAG, "Mensaje inválido", e);
            }
        }

        @Override
        protected void onClose(WebSocketFrame.CloseCode code, String reason, boolean remote) {
            gone();
        }

        @Override
        protected void onException(IOException e) {
            gone();
        }

        @Override
        protected void onPong(WebSocketFrame pong) { }

        private void gone() {
            if (isHost) {
                if (host == this) {
                    host = null;
                    for (Sock c : clients.values()) c.quit();
                    clients.clear();
                }
            } else if (cid != null && clients.remove(cid, this)) {
                Sock h = host;
                if (h != null) h.say("{\"ev\":\"close\",\"from\":\"" + cid + "\"}");
            }
        }
    }

    /** Arranca en el primer puerto libre a partir de 8765. */
    public static GameServer startOnFreePort(AssetManager assets) throws IOException {
        IOException last = null;
        for (int p = 8765; p < 8775; p++) {
            GameServer s = new GameServer(p, assets);
            try {
                // Sin límite corto de lectura: los clientes mandan "ping" cada 4 s, pero si el anfitrión
                // deja la app en segundo plano un momento no queremos tirar toda la partida.
                s.start(180000, true);
                return s;
            } catch (IOException e) {
                last = e;
            }
        }
        throw last != null ? last : new IOException("Sin puertos libres");
    }

    @SuppressWarnings("unused")
    private static final Class<?> KEEP = NanoHTTPD.class;
}
