package com.emrysmxo.survivalgame.local;

import android.app.Activity;
import android.os.Bundle;
import android.os.Build;
import android.view.Display;
import android.view.View;
import android.view.WindowManager;
import android.webkit.WebResourceRequest;
import android.webkit.WebResourceResponse;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import androidx.webkit.WebViewAssetLoader;

// Оболочка: открывает игру из файлов внутри APK (assets/www) через
// https://appassets.androidplatform.net/ — fetch, Worker и .glb работают как на сайте.
public class MainActivity extends Activity {
    private WebView web;

    @Override
    protected void onCreate(Bundle b) {
        super.onCreate(b);
        getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
        boost();
        web = new WebView(this);
        web.setLayerType(View.LAYER_TYPE_HARDWARE, null);   // отрисовка на видеокарте
        web.setBackgroundColor(0xFF0C120C);
        setContentView(web);

        final WebViewAssetLoader loader = new WebViewAssetLoader.Builder()
                .addPathHandler("/assets/", new WebViewAssetLoader.AssetsPathHandler(this))
                .build();
        WebSettings s = web.getSettings();
        s.setJavaScriptEnabled(true);
        s.setDomStorageEnabled(true);
        s.setMediaPlaybackRequiresUserGesture(false);
        s.setCacheMode(WebSettings.LOAD_DEFAULT);
        web.setWebViewClient(new WebViewClient() {
            @Override
            public WebResourceResponse shouldInterceptRequest(WebView v, WebResourceRequest r) {
                return loader.shouldInterceptRequest(r.getUrl());
            }
        });
        web.loadUrl("https://appassets.androidplatform.net/assets/www/index.html");
        hideBars();
    }

    // Максимум от телефона: самая высокая частота экрана (90/120/144 Гц) и устойчивая
    // производительность (система не душит процессор/видеокарту так, как у обычных приложений).
    private void boost() {
        try {
            if (Build.VERSION.SDK_INT >= 24) getWindow().setSustainedPerformanceMode(true);
        } catch (Throwable t) { /* не поддерживается */ }
        try {
            if (Build.VERSION.SDK_INT >= 23) {
                Display d = getWindowManager().getDefaultDisplay();
                Display.Mode best = d.getMode();
                for (Display.Mode m : d.getSupportedModes()) {
                    if (m.getPhysicalWidth() == best.getPhysicalWidth() && m.getPhysicalHeight() == best.getPhysicalHeight()
                            && m.getRefreshRate() > best.getRefreshRate()) best = m;
                }
                WindowManager.LayoutParams lp = getWindow().getAttributes();
                lp.preferredDisplayModeId = best.getModeId();
                if (Build.VERSION.SDK_INT >= 30) lp.preferredRefreshRate = best.getRefreshRate();
                getWindow().setAttributes(lp);
            }
        } catch (Throwable t) { /* оставим как есть */ }
    }

    private void hideBars() {
        getWindow().getDecorView().setSystemUiVisibility(
                View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY | View.SYSTEM_UI_FLAG_FULLSCREEN
                | View.SYSTEM_UI_FLAG_HIDE_NAVIGATION | View.SYSTEM_UI_FLAG_LAYOUT_STABLE
                | View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN | View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION);
    }

    @Override public void onWindowFocusChanged(boolean f) { super.onWindowFocusChanged(f); if (f) hideBars(); }
    @Override protected void onPause() { super.onPause(); web.onPause(); }
    @Override protected void onResume() { super.onResume(); web.onResume(); }
    @Override protected void onDestroy() { web.destroy(); super.onDestroy(); }
}
