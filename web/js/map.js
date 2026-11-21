/* Mapa: MapLibre GL (build CSP, arquivo próprio), países Natural Earth em GeoJSON local,
   um ponto por CIDADE (posição = centro da cidade), agrupamento nativo e marcadores HTML acessíveis. */
(function () {
  'use strict';
  var RBC = window.RBC, t = RBC.t, esc = RBC.esc;
  var libPromise = null, worldPromise = null;

  function loadCss(href) {
    if (document.querySelector('link[data-mlcss]')) return Promise.resolve();
    return new Promise(function (res) {
      var l = document.createElement('link'); l.rel = 'stylesheet'; l.href = href; l.setAttribute('data-mlcss', '');
      l.onload = res; l.onerror = res; document.head.appendChild(l);
    });
  }
  function webglOk() {
    try { var c = document.createElement('canvas'); return !!(c.getContext('webgl2') || c.getContext('webgl')); } catch (e) { return false; }
  }
  RBC.mapLib = function () {
    if (!libPromise) {
      libPromise = Promise.all([loadCss('css/maplibre-gl.css'), RBC.loadScript('vendor/maplibre-gl-csp.js')]).then(function () {
        if (!window.maplibregl) throw new Error('maplibre indisponível');
        window.maplibregl.setWorkerUrl('vendor/maplibre-gl-csp-worker.js');
        return window.maplibregl;
      });
      libPromise.catch(function () { libPromise = null; });
    }
    return libPromise;
  };
  RBC.worldData = function () {
    if (!worldPromise) {
      worldPromise = window.fetch('data/world.geojson').then(function (r) { if (!r.ok) throw new Error('HTTP ' + r.status); return r.json(); });
      worldPromise.catch(function () { worldPromise = null; });
    }
    return worldPromise;
  };

  function features(cities) {
    return { type: 'FeatureCollection', features: cities.map(function (c) { return { type: 'Feature', geometry: { type: 'Point', coordinates: [c.lng, c.lat] }, properties: { k: c.key, n: c.n } }; }) };
  }
  function cityLabel(c) { return (c.city || '') + ', ' + RBC.countryName(c.country); }

  /* opts: { el, cities, onSelect(key), onError(err), focusKey } → controlador */
  RBC.createMap = function (opts) {
    var ctl = { map: null, markers: {}, dead: false, selected: opts.focusKey || null, byKey: {} };
    function reindex() { ctl.byKey = {}; opts.cities.forEach(function (c) { ctl.byKey[c.key] = c; }); }
    reindex();
    if (!webglOk()) {
      ctl.update = ctl.flyTo = ctl.select = function () {}; ctl.destroy = function () { ctl.dead = true; };
      window.setTimeout(function () { if (!ctl.dead) opts.onError(new Error('WebGL indisponível')); }, 0); return ctl;
    }
    Promise.all([RBC.mapLib(), RBC.worldData()]).then(function (res) {
      if (ctl.dead) return;
      var ml = res[0], world = res[1], map;
      try {
        map = new ml.Map({
          container: opts.el, attributionControl: false, dragRotate: false, pitchWithRotate: false, touchPitch: false,
          renderWorldCopies: false, minZoom: 0.6, maxZoom: 12, center: [10, 15], zoom: 1,
          locale: { 'NavigationControl.ZoomIn': t('map.zoom_in'), 'NavigationControl.ZoomOut': t('map.zoom_out'), 'AttributionControl.ToggleAttribution': t('map.attribution') },
          style: {
            version: 8,
            sources: {
              world: { type: 'geojson', data: world },
              pts: { type: 'geojson', data: features(opts.cities), cluster: true, clusterRadius: 56, clusterMaxZoom: 9, clusterProperties: { total: ['+', ['get', 'n']] } }
            },
            layers: [
              { id: 'sea', type: 'background', paint: { 'background-color': '#DCE6DE' } },
              { id: 'land', type: 'fill', source: 'world', paint: { 'fill-color': '#F4EDDF' } },
              { id: 'borders', type: 'line', source: 'world', paint: { 'line-color': '#B9AC8E', 'line-width': ['interpolate', ['linear'], ['zoom'], 1, 0.4, 6, 1.1] } },
              { id: 'pts-hit', type: 'circle', source: 'pts', paint: { 'circle-radius': 2, 'circle-opacity': 0, 'circle-stroke-opacity': 0 } }
            ]
          }
        });
      } catch (err) { opts.onError(err); return; }
      ctl.map = map;
      map.on('error', function (ev) { if (window.console && ev && ev.error) console.warn('mapa:', ev.error.message); });
      map.addControl(new ml.NavigationControl({ showCompass: false }), 'top-right');
      map.addControl(new ml.AttributionControl({ compact: true, customAttribution: t('map.credit') }), 'bottom-right');
      var canvas = map.getCanvas(); canvas.setAttribute('aria-label', t('map.canvas')); canvas.setAttribute('role', 'region');
      map.on('load', function () {
        fit(ctl, opts.cities, ctl.selected);
        refresh(ctl, opts);
        if (ctl.selected && ctl.byKey[ctl.selected]) opts.onSelect(ctl.selected, true);
      });
      map.on('moveend', function () { refresh(ctl, opts); });
      map.on('sourcedata', function (e) { if (e.sourceId === 'pts' && e.isSourceLoaded) refresh(ctl, opts); });
    }, function (err) { if (!ctl.dead) opts.onError(err); });

    ctl.update = function (cities) {
      opts.cities = cities; reindex();
      if (!ctl.map || !ctl.map.getSource('pts')) return;
      Object.keys(ctl.markers).forEach(function (k) { ctl.markers[k].remove(); }); ctl.markers = {};
      ctl.map.getSource('pts').setData(features(cities));
      fit(ctl, cities);
    };
    ctl.select = function (key) { ctl.selected = key; Object.keys(ctl.markers).forEach(function (k) { var b = ctl.markers[k].getElement(); if (b.hasAttribute('data-k')) b.setAttribute('aria-pressed', b.getAttribute('data-k') === key ? 'true' : 'false'); }); };
    ctl.destroy = function () { ctl.dead = true; if (ctl.map) { try { ctl.map.remove(); } catch (e) { /* segue */ } } ctl.map = null; ctl.markers = {}; };
    return ctl;
  };

  function fit(ctl, cities, focus) {
    var map = ctl.map; if (!map) return;
    if (focus && ctl.byKey[focus]) { var f = ctl.byKey[focus]; map.jumpTo({ center: [f.lng, f.lat], zoom: 7 }); return; }
    if (!cities.length) { map.jumpTo({ center: [10, 15], zoom: 1 }); return; }
    var minX = 180, minY = 90, maxX = -180, maxY = -90;
    cities.forEach(function (c) { minX = Math.min(minX, c.lng); maxX = Math.max(maxX, c.lng); minY = Math.min(minY, c.lat); maxY = Math.max(maxY, c.lat); });
    if (maxX - minX < 0.05 && maxY - minY < 0.05) { map.jumpTo({ center: [minX, minY], zoom: 8 }); return; }
    try { map.fitBounds([[minX, minY], [maxX, maxY]], { padding: 48, maxZoom: 8, duration: 0 }); } catch (e) { map.jumpTo({ center: [10, 15], zoom: 1 }); }
  }

  /* Recria os marcadores HTML (botões) a partir dos pontos e grupos visíveis. */
  function refresh(ctl, opts) {
    var map = ctl.map; if (!map || !map.getSource('pts')) return;
    var ml = window.maplibregl, feats = map.querySourceFeatures('pts'), seen = {};
    feats.forEach(function (f) {
      var pr = f.properties, key = pr.cluster ? 'c' + pr.cluster_id : 'p' + pr.k;
      if (seen[key]) return; seen[key] = 1;
      if (ctl.markers[key]) return;
      var b = document.createElement('button'); b.type = 'button';
      if (pr.cluster) {
        var n = pr.total || pr.point_count, size = n < 10 ? 'sm' : n < 60 ? 'md' : 'lg';
        b.className = 'mk mk--cluster mk--' + size; b.innerHTML = '<span aria-hidden="true">' + n + '</span>';
        b.setAttribute('aria-label', t('map.cluster', { n: n }));
        b.addEventListener('click', function () {
          var src = map.getSource('pts'), center = f.geometry.coordinates;
          var p = src.getClusterExpansionZoom(pr.cluster_id);
          var go = function (z) { map.easeTo({ center: center, zoom: Math.min(z + 0.2, 11), duration: RBC.reducedMotion() ? 0 : 500 }); };
          if (p && p.then) p.then(go, function () { go(map.getZoom() + 2); }); else go(map.getZoom() + 2);
        });
      } else {
        var c = ctl.byKey[pr.k]; if (!c) return;
        b.className = 'mk mk--city' + (pr.n > 1 ? ' mk--multi' : ''); b.setAttribute('data-k', pr.k);
        b.innerHTML = pr.n > 1 ? '<span aria-hidden="true">' + pr.n + '</span>' : '';
        b.setAttribute('aria-pressed', ctl.selected === pr.k ? 'true' : 'false');
        b.setAttribute('aria-label', t('map.city', { city: cityLabel(c), n: pr.n }));
        b.addEventListener('click', function () { ctl.select(pr.k); opts.onSelect(pr.k); });
      }
      ctl.markers[key] = new ml.Marker({ element: b, anchor: 'center' }).setLngLat(f.geometry.coordinates).addTo(map);
    });
    Object.keys(ctl.markers).forEach(function (k) {
      if (!seen[k]) { var el = ctl.markers[k].getElement(); if (el === document.activeElement) return; ctl.markers[k].remove(); delete ctl.markers[k]; }
    });
  }

  RBC.mapLegend = function () {
    function row(cls, key, hint) { return '<li><span class="lg lg--' + cls + '" aria-hidden="true"></span><span><strong>' + esc(t(key)) + '</strong>' + (hint ? '<br><span class="muted">' + esc(t(hint)) + '</span>' : '') + '</span></li>'; }
    return '<div class="legend"><h3 class="legend__title">' + esc(t('map.legend')) + '</h3><ul>' +
      row('city', 'map.legend.city', 'map.legend.city_hint') + row('cluster', 'map.legend.cluster', 'map.legend.cluster_hint') + '</ul></div>';
  };
})();
