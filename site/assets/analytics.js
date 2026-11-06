/* PostHog, shared with every tommymassaro.com site and read back at
   stats.tommymassaro.com. The canonical copy of this tag, with the reasoning
   behind each line, is snippets/subdomain-analytics.html in tmass1/portfolio.

   Loaded by the home page and the setup guide. The privacy and terms pages
   don't load it. Reports nothing from localhost by design, so it cannot be
   verified in dev; load the deployed page with ?__posthog_debug=true instead.
   Visit any page once with ?analytics=off to keep your own visits out. */
(function () {
  /* ── 1. Which site this is ───────────────────────────────────────────
     Set it per deployment, or leave it empty and it is taken from the
     hostname — `mark.tommymassaro.com` becomes "mark". Set it by hand when
     two hostnames are really one product and should read as one site. */
  var SITE = "";

  var KEY = "phc_uaWkjgzs42jdt5M9k7JX8CHZdMBbzteeJjDJqNhHGf8s";
  var HOST = "https://us.i.posthog.com";
  /* The assets host is the API host with "-assets" after the region. Both
     are real and they are not interchangeable: the `i.` host takes events,
     this one serves the library. */
  var ASSETS = "https://us-assets.i.posthog.com";

  var host = location.hostname;

  if (!SITE) {
    SITE =
      host === "tommymassaro.com" || host === "www.tommymassaro.com"
        ? "portfolio"
        : host.split(".")[0];
  }

  /* ── 2. Nothing from a dev machine ───────────────────────────────────
     A deny-list rather than a list of production hostnames, so a new
     subdomain starts reporting on its own instead of silently going dark
     until somebody remembers this file. The portfolio learned this the
     expensive way: every page of it was clicked through on localhost while
     it was being built, and all of it was counted. */
  var DEV = ["localhost", "127.0.0.1", "[::1]"];
  if (DEV.indexOf(host) !== -1 || /\.(local|localhost)$/.test(host)) return;

  var cookie = function (name) {
    var m = document.cookie.match("(^|; )" + name + "=([^;]*)");
    return m ? decodeURIComponent(m[2]) : null;
  };

  /* Written on the parent domain on purpose: one opt-out then covers every
     subdomain at once. localStorage could not — it is scoped per origin, so
     switching off on the portfolio would leave every app still counting. */
  var setCookie = function (name, value, maxAge) {
    document.cookie =
      name +
      "=" +
      encodeURIComponent(value) +
      ";domain=.tommymassaro.com;path=/;max-age=" +
      maxAge +
      ";samesite=lax;secure";
  };

  /* ── 3. The per-device opt-out ───────────────────────────────────────
     Visit any of these sites once with `?analytics=off` and none of them
     count this browser again; `?analytics=on` undoes it. Deliberately
     guessable — anyone who finds it can opt themselves out too, which is a
     feature. The alternative is a secret, and a secret in client-side
     JavaScript is not one. */
  try {
    var q = new URLSearchParams(location.search).get("analytics");
    if (q === "off") setCookie("tm-analytics-off", "1", 10 * 365 * 86400);
    if (q === "on") setCookie("tm-analytics-off", "", 0);
  } catch (e) {
    /* No URLSearchParams, or a malformed query. Analytics simply stay on. */
  }

  if (cookie("tm-analytics-off") === "1") return;

  /* An explicit refusal always wins. See the consent note at the top: this
     reads an answer that nothing writes yet. */
  if (cookie("tm-consent") === "denied") return;

  /* ── 4. Load and start ───────────────────────────────────────────────
     The same loader the portfolio uses in production: the library from the
     assets host with an `onload`, rather than PostHog's minified stub. The
     stub exists only to queue calls made before the library arrives, and
     waiting for onload removes the need for a queue at all. */
  var start = function () {
    window.posthog.init(KEY, {
      api_host: HOST,
      /* Only build person profiles for people we identify, which on a set
         of demo sites is nobody — anonymous visitors stay anonymous. */
      person_profiles: "identified_only",
      /* Where Tidy parts from the canonical copy, on purpose: its privacy page
         says the site counts page views and Download clicks, without cookies,
         and this keeps that true. Nothing is kept between pages, so each page
         load counts as a new visitor, and a visitor isn't followed across the
         other sites. And the project's session recording, automatic clicks,
         heatmaps, page-speed measurements and surveys, switched on in PostHog's
         settings for all its sites, stay off here, so a change there can't
         quietly make the page untrue. */
      persistence: "memory",
      disable_session_recording: true,
      autocapture: false,
      rageclick: false,
      capture_heatmaps: false,
      capture_dead_clicks: false,
      capture_performance: false,
      disable_surveys: true,
      loaded: function (ph) {
        /* A convenience label, not load-bearing. The dashboard groups by
           `$host`, which PostHog attaches to every event by itself — so if
           this never runs, or the first pageview goes out before it does,
           nothing is lost. It exists to make filtering in PostHog's own UI
           read as "site = tidy-app" rather than as a hostname. */
        ph.register({ site: SITE });
      },
    });
  };

  var el = document.createElement("script");
  el.src = ASSETS + "/static/array.js";
  el.onload = start;
  document.head.appendChild(el);

  /* ── 5. Download buttons ─────────────────────────────────────────────
     Mark the link and the click is counted:

         <a href="/Mark.dmg" data-track-download="mark" data-platform="macos">
         <a href="https://apps.apple.com/…" data-track-download="tidy" data-platform="ios">

     `data-track-download` rather than the obvious `data-download` because
     the obvious one was already taken: Mark's own site/page.ts selects
     `[data-download]` to point every download link at the current .dmg, and
     a test asserts on it. Sharing the attribute would have coupled a
     measurement concern to a functional one in a way neither side declares,
     and this snippet goes on sites it cannot see. The ugly name is the
     whole point — nothing else will have claimed it.

     `sendBeacon` with `send_instantly` because a download link may or may
     not unload the page and the markup does not say which: a same-origin
     file leaves the page alone, an App Store link navigates away and can
     kill an ordinary in-flight request. A beacon is handed to the browser
     to deliver regardless, so both cases are covered without the snippet
     needing to know which it is looking at.

     Listening on the capture phase so this runs before any handler on the
     link itself, including one that calls preventDefault and navigates by
     hand. */
  var track = function (app, extra) {
    if (!window.posthog || !window.posthog.capture) return;
    var props = { app: app, site: SITE };
    for (var k in extra) {
      if (extra[k]) props[k] = extra[k];
    }
    try {
      window.posthog.capture("app_downloaded", props, {
        transport: "sendBeacon",
        send_instantly: true,
      });
    } catch (e) {
      /* Never let measurement break a download. */
    }
  };

  document.addEventListener(
    "click",
    function (event) {
      var el =
        event.target &&
        event.target.closest &&
        event.target.closest("[data-track-download]");
      if (!el) return;
      track(el.getAttribute("data-track-download"), {
        platform: el.getAttribute("data-platform"),
        href: el.getAttribute("href"),
      });
    },
    true,
  );

  /* For a download that is not a link — a button that builds the file, or
     one behind a framework's own handler — call it directly:
         window.tmTrackDownload("fritter", { platform: "macos" }) */
  window.tmTrackDownload = track;
})();
    
