/*
 * Copyright (c) 2026 Cedric. All rights reserved.
 * Source-available under the Gen2Recomped License (see LICENSE.md).
 *
 * THE BOTTOM SCREEN, ON HARDWARE THAT HAS ONE.
 *
 * The AYN Thor has a second panel. Android exposes it as a presentation
 * display; LOVE does not, and teaching LOVE would mean patching and rebuilding
 * the engine's NDK tree for every release. This is the other way round: an
 * ordinary Java class in the app module, no native code, talking to Lua
 * through three files in the save directory.
 *
 * It deliberately lives at mobile/second-display/ rather than inside
 * mobile/android/, because mobile/android/ is a vendored love-android checkout
 * that gets deleted and re-cloned. scripts/build_android.sh copies this file in
 * and patches the manifest; see install_second_display_host() there.
 *
 * WHY A ContentProvider AND NOT AN Application SUBCLASS.
 * A provider is instantiated before Application.onCreate and is handed a
 * Context, which is all this needs -- and registering one ADDS an element to
 * love-android's manifest, where <application android:name> would REPLACE
 * whatever that vendored manifest already declares. The provider serves
 * nothing; query/insert/etc. are stubs.
 *
 * THE PROTOCOL is defined in src/render/SecondScreen.lua and repeated here
 * because the two ends never meet. tools/gen4_second_display_protocol_check.lua
 * reads both files and fails if they drift.
 *
 *   second_display/host.txt   written HERE, once a second:
 *                             "<version> <displays> <width> <height>"
 *                             Lua offers `display` mode only while this says
 *                             a matching version and displays >= 2.
 *   second_display/frame.bin  written by LUA: "G2SD", then version, width,
 *                             height, sequence as little-endian u16 -- twelve
 *                             bytes -- then width*height*4 bytes of RGBA.
 *   second_display/touch.txt  appended HERE, read and truncated by Lua:
 *                             "<down|move|up> <id> <x> <y>" a line.
 */

package org.love2d.android;

import android.app.Activity;
import android.app.Application;
import android.app.Presentation;
import android.content.ContentProvider;
import android.content.ContentValues;
import android.content.Context;
import android.database.Cursor;
import android.graphics.Bitmap;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Paint;
import android.graphics.Rect;
import android.hardware.display.DisplayManager;
import android.net.Uri;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.util.Log;
import android.view.Display;
import android.view.MotionEvent;
import android.view.View;

import java.io.File;
import java.io.FileOutputStream;
import java.io.RandomAccessFile;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.nio.charset.Charset;

public class SecondDisplayHost extends ContentProvider {

  private static final String TAG = "G2SecondDisplay";

  /* --- the protocol. Must match src/render/SecondScreen.lua. --- */
  public static final int PROTOCOL = 1;
  public static final String MAGIC = "G2SD";
  public static final int HEADER_BYTES = 12;
  public static final String DIR = "second_display";
  public static final String HOST_FILE = "host.txt";
  public static final String FRAME_FILE = "frame.bin";
  public static final String TOUCH_FILE = "touch.txt";
  /* conf.lua pins the Android identity to "pokemon-love2d" and sets
   * t.externalstorage, so LOVE's save directory is
   * getExternalFilesDir(null)/save/pokemon-love2d. The internal path is
   * checked too rather than assumed away: a build with externalstorage off
   * would use it, and writing the handshake into both costs one file. */
  public static final String IDENTITY = "pokemon-love2d";

  private static final int HOST_INTERVAL_MS = 1000;
  private static final int FRAME_POLL_MS = 16;

  private Context appContext;
  private final Handler ui = new Handler(Looper.getMainLooper());
  private volatile boolean running = false;
  private Thread pump;
  private volatile Activity activeActivity;
  private volatile PanelPresentation presentation;
  private File[] roots = new File[0];
  private volatile File frameFile, touchFile;

  private volatile int lastSeq = -1;
  private volatile int frameW = 0, frameH = 0;

  /* ------------------------------------------------------------------ *
   * Provider plumbing: exists to be constructed early, serves nothing.
   * ------------------------------------------------------------------ */

  @Override
  public boolean onCreate() {
    appContext = getContext();
    if (appContext == null) return false;
    appContext = appContext.getApplicationContext();
    roots = saveRoots(appContext);
    if (roots.length == 0) {
      Log.w(TAG, "no save directory found; second display inactive");
      return true;
    }
    Log.i(TAG, "SecondDisplayHost created");
    for (File root : roots) Log.i(TAG, "save root: " + root.getAbsolutePath());

    if (appContext instanceof Application) {
      ((Application) appContext).registerActivityLifecycleCallbacks(
          new Lifecycle());
    }
    return true;
  }

  @Override public Cursor query(Uri u, String[] p, String s, String[] a, String o) { return null; }
  @Override public String getType(Uri u) { return null; }
  @Override public Uri insert(Uri u, ContentValues v) { return null; }
  @Override public int delete(Uri u, String s, String[] a) { return 0; }
  @Override public int update(Uri u, ContentValues v, String s, String[] a) { return 0; }

  /* ------------------------------------------------------------------ *
   * Where LOVE keeps its save directory.
   * ------------------------------------------------------------------ */

  private static File[] saveRoots(Context ctx) {
    java.util.ArrayList<File> out = new java.util.ArrayList<File>();
    File ext = ctx.getExternalFilesDir(null);
    if (ext != null) out.add(new File(new File(ext, "save"), IDENTITY));
    File in = ctx.getFilesDir();
    if (in != null) out.add(new File(new File(in, "save"), IDENTITY));
    java.util.ArrayList<File> dirs = new java.util.ArrayList<File>();
    for (File base : out) {
      File d = new File(base, DIR);
      // Lua's love.filesystem.write creates the directory itself, but the
      // handshake has to be readable BEFORE Lua has ever written anything --
      // that is what makes the option appear in the menu at all.
      if (d.isDirectory() || d.mkdirs()) dirs.add(d);
    }
    return dirs.toArray(new File[0]);
  }

  /* ------------------------------------------------------------------ *
   * Follow the game's own activity: a Presentation belongs to one.
   * ------------------------------------------------------------------ */

  private final class Lifecycle implements Application.ActivityLifecycleCallbacks {
    @Override public void onActivityResumed(Activity a) { attach(a); }
    @Override public void onActivityPaused(Activity a) { detach(); }
    @Override public void onActivityCreated(Activity a, Bundle b) { }
    @Override public void onActivityStarted(Activity a) { }
    @Override public void onActivityStopped(Activity a) { }
    @Override public void onActivitySaveInstanceState(Activity a, Bundle b) { }
    @Override public void onActivityDestroyed(Activity a) { }
  }

  private Display secondaryDisplay() {
    DisplayManager dm =
        (DisplayManager) appContext.getSystemService(Context.DISPLAY_SERVICE);
    if (dm == null) {
      Log.w(TAG, "DisplayManager unavailable");
      return null;
    }

    Display[] all = dm.getDisplays();
    if (all != null) {
      for (Display d : all) {
        Log.d(TAG, "display id=" + d.getDisplayId()
            + " name=" + d.getName()
            + " flags=" + d.getFlags()
            + " state=" + d.getState());
      }
    }

    Display[] ds = dm.getDisplays(DisplayManager.DISPLAY_CATEGORY_PRESENTATION);
    if (ds != null && ds.length > 0) return ds[0];

    // Some dual-screen devices do not mark their built-in lower panel as a
    // presentation display. Any non-default Android Display is usable.
    if (all != null) {
      for (Display d : all) {
        if (d.getDisplayId() != Display.DEFAULT_DISPLAY) return d;
      }
    }
    return null;
  }

  private void attach(Activity activity) {
    activeActivity = activity;
    if (!running) startPump();
    ensurePresentation();
  }

  /** Runs on the UI thread. Safe to call repeatedly while the pump waits for
   * Android to expose a late/hot-plugged secondary display. */
  private void ensurePresentation() {
    if (Looper.myLooper() != Looper.getMainLooper()) {
      ui.post(new Runnable() {
        @Override public void run() { ensurePresentation(); }
      });
      return;
    }
    if (!running || presentation != null) return;
    Activity activity = activeActivity;
    if (activity == null || activity.isFinishing()) return;

    Display d = secondaryDisplay();
    if (d == null) {
      writeHost(1, 0, 0);
      return;
    }

    android.graphics.Point size = new android.graphics.Point();
    d.getSize(size);
    Log.i(TAG, "using secondary display id=" + d.getDisplayId()
        + " name=" + d.getName() + " size=" + size.x + "x" + size.y);

    PanelPresentation p = new PanelPresentation(activity, d);
    try {
      p.show();
      presentation = p;
      lastSeq = -1;
      writeHost(2, size.x, size.y);
      Log.i(TAG, "Presentation.show succeeded");
      Log.i(TAG, "second display attached: " + size.x + "x" + size.y);
    } catch (Throwable t) {
      Log.e(TAG, "presentation refused", t);
      try { p.dismiss(); } catch (Throwable ignored) { }
      presentation = null;
      writeHost(1, 0, 0);
    }
  }

  private void detach() {
    running = false;
    activeActivity = null;
    if (pump != null) { pump.interrupt(); pump = null; }
    final PanelPresentation p = presentation;
    presentation = null;
    if (p != null) ui.post(new Runnable() {
      @Override public void run() { try { p.dismiss(); } catch (Throwable ignored) { } }
    });
  }

  private void startPump() {
    running = true;
    pump = new Thread(new Runnable() {
      @Override public void run() {
        long lastHost = 0;
        long lastDiscovery = 0;
        while (running) {
          long now = android.os.SystemClock.uptimeMillis();
          PanelPresentation panel = presentation;

          // AYN and other dual-screen firmware can publish the lower Display
          // after the Activity has already resumed. Keep looking instead of
          // permanently settling into the one-display state.
          if (panel == null && now - lastDiscovery >= HOST_INTERVAL_MS) {
            lastDiscovery = now;
            ui.post(new Runnable() {
              @Override public void run() { ensurePresentation(); }
            });
          }

          if (now - lastHost >= HOST_INTERVAL_MS) {
            lastHost = now;
            panel = presentation;
            if (panel == null) writeHost(1, 0, 0);
            else writeHost(2, panel.panelWidth(), panel.panelHeight());
          }

          panel = presentation;
          if (panel != null) readFrameOnce(panel);
          try { Thread.sleep(FRAME_POLL_MS); }
          catch (InterruptedException e) { return; }
        }
      }
    }, "g2-second-display");
    pump.setDaemon(true);
    pump.start();
  }


