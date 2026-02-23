/**
 * SpecCompiler App - Main application entry point
 * Orchestrates initialization and coordinates all modules
 */

var SpecCompiler = SpecCompiler || {};

(function() {
  'use strict';

  var db = null;
  var dbLoaded = false;
  var paneUiInitialized = false;

  function loadBool(key, defaultValue) {
    try {
      var v = localStorage.getItem(key);
      if (v === null || v === undefined) return !!defaultValue;
      return v === '1' || v === 'true';
    } catch (e) {
      return !!defaultValue;
    }
  }

  function saveBool(key, value) {
    try {
      localStorage.setItem(key, value ? '1' : '0');
    } catch (e) {}
  }

  function loadNumber(key, defaultValue) {
    try {
      var v = localStorage.getItem(key);
      if (v === null || v === undefined || v === '') return defaultValue;
      var n = Number(v);
      return Number.isFinite(n) ? n : defaultValue;
    } catch (e) {
      return defaultValue;
    }
  }

  function saveNumber(key, value) {
    try {
      if (value === null || value === undefined) {
        localStorage.removeItem(key);
        return;
      }
      localStorage.setItem(key, String(value));
    } catch (e) {}
  }

  /**
   * Initialize the application
   */
  function init() {
    console.log('SpecCompiler: Initializing...');

    // 1. Theme must be first to prevent flash
    if (SpecCompiler.Theme) {
      SpecCompiler.Theme.init();
    }

    // 2. Initialize sidebar (extract TOCs, build UI)
    if (SpecCompiler.Sidebar) {
      SpecCompiler.Sidebar.init();
    }

    // 2b. Initialize inspector (contextual right pane)
    if (SpecCompiler.Inspector) {
      SpecCompiler.Inspector.init();
    }

    // 2c. Setup pane interactions
    setupPaneUI();
    setupSidebarResizer();
    setupInspectorResizer();

    // 3. Setup route handler
    if (SpecCompiler.Router) {
      SpecCompiler.Router.onRouteChange(handleRoute);
    }

    // 4. Initialize router (parse initial URL, dispatch)
    if (SpecCompiler.Router) {
      SpecCompiler.Router.init();
    }

    // 5. Load database asynchronously
    loadDatabase().then(function(database) {
      db = database;
      dbLoaded = true;
      console.log('SpecCompiler: Database loaded');

      // Initialize search with database
      if (SpecCompiler.Search) {
        SpecCompiler.Search.init(db);
      }

      // Inspector can now run DB-backed queries
      if (SpecCompiler.Inspector) {
        SpecCompiler.Inspector.setDatabase(db);
      }

      console.log('SpecCompiler: Initialization complete');
    }).catch(function(err) {
      console.error('SpecCompiler: Database loading failed:', err);
      console.log('SpecCompiler: Running without database (search disabled; inspector limited)');

      // Initialize search without DB (will show unavailable state)
      if (SpecCompiler.Search) {
        SpecCompiler.Search.init(null);
      }

      if (SpecCompiler.Inspector) {
        SpecCompiler.Inspector.setDatabase(null);
      }
    });
  }

  /**
   * Central route handler
   * @param {Object} route - Current route object
   * @param {Object} oldRoute - Previous route object
   */
  function handleRoute(route, oldRoute) {
    console.log('Route:', route);

    var contentDiv = document.querySelector('.content');

    updateHeaderUI(route);
    if (SpecCompiler.Inspector) {
      SpecCompiler.Inspector.update(route);
    }

    if (route.type === 'root') {
      // Redirect to first available spec
      redirectToFirstSpec();
      return;
    }

    if (route.type === 'doc') {
      // Show document
      if (SpecCompiler.Sidebar) {
        SpecCompiler.Sidebar.showDoc(route.spec);
      }

      // Scroll to top
      if (contentDiv) contentDiv.scrollTop = 0;
    }

    else if (route.type === 'element') {
      // Show document and scroll to element
      if (SpecCompiler.Sidebar) {
        SpecCompiler.Sidebar.showDoc(route.spec);
      }

      // Scroll to element (delay to ensure rendering)
      setTimeout(function() {
        scrollToElement(route.elementId);
      }, 50);
    }
  }

  /**
   * Redirect to first available spec
   */
  function redirectToFirstSpec() {
    var firstSection = document.querySelector('.doc-section');
    if (firstSection) {
      var docId = firstSection.id.replace('doc-', '');
      if (SpecCompiler.Router) {
        SpecCompiler.Router.navigate('#/' + docId);
      }
    }
  }

  /**
   * Setup UI toggles for collapsing the left navigation and right inspector panes.
   */
  function setupPaneUI() {
    if (paneUiInitialized) return;
    paneUiInitialized = true;

    var main = document.querySelector('.main');
    if (!main) return;

    var btnNav = document.getElementById('btn-toggle-nav');
    var btnInspector = document.getElementById('btn-toggle-inspector');

    var navCollapsed = loadBool('speccompiler_nav_collapsed', false);
    var inspectorCollapsed = loadBool('speccompiler_inspector_collapsed', false);

    function apply() {
      main.classList.toggle('nav-collapsed', navCollapsed);
      main.classList.toggle('inspector-collapsed', inspectorCollapsed);

      if (btnNav) {
        btnNav.setAttribute('aria-pressed', navCollapsed ? 'true' : 'false');
        btnNav.title = navCollapsed ? 'Show navigation' : 'Hide navigation';
      }
      if (btnInspector) {
        btnInspector.setAttribute('aria-pressed', inspectorCollapsed ? 'true' : 'false');
        btnInspector.title = inspectorCollapsed ? 'Show inspector' : 'Hide inspector';
      }
    }

    function setNavCollapsed(v) {
      navCollapsed = !!v;
      saveBool('speccompiler_nav_collapsed', navCollapsed);
      apply();
    }

    function setInspectorCollapsed(v) {
      inspectorCollapsed = !!v;
      saveBool('speccompiler_inspector_collapsed', inspectorCollapsed);
      apply();
    }

    if (btnNav) {
      btnNav.addEventListener('click', function() {
        setNavCollapsed(!navCollapsed);
      });
    }

    if (btnInspector) {
      btnInspector.addEventListener('click', function() {
        setInspectorCollapsed(!inspectorCollapsed);
      });
    }

    // Initial paint
    apply();

    // Expose minimal API for debugging/integration.
    SpecCompiler.App = SpecCompiler.App || {};
    SpecCompiler.App.toggleNav = function() { setNavCollapsed(!navCollapsed); };
    SpecCompiler.App.toggleInspector = function() { setInspectorCollapsed(!inspectorCollapsed); };
  }

  function setupSidebarResizer() {
    var resizer = document.getElementById('resizer-sidebar');
    var sidebar = document.querySelector('.sidebar');
    var main = document.querySelector('.main');
    if (!resizer || !sidebar || !main) return;

    var minW = 220;
    var maxW = 560;

    resizer.setAttribute('aria-valuemin', String(minW));
    resizer.setAttribute('aria-valuemax', String(maxW));

    function clamp(n, a, b) {
      return Math.max(a, Math.min(b, n));
    }

    function applyWidth(px, persist) {
      var w = clamp(Math.round(px), minW, maxW);
      document.documentElement.style.setProperty('--layout-sidebar-width', String(w) + 'px');
      resizer.setAttribute('aria-valuenow', String(w));
      if (persist) {
        saveNumber('speccompiler_sidebar_width', w);
      }
    }

    // Restore previous width if available.
    var saved = loadNumber('speccompiler_sidebar_width', null);
    if (saved != null) {
      applyWidth(saved, false);
    } else {
      // Prime aria-valuenow from computed width.
      try {
        resizer.setAttribute('aria-valuenow', String(Math.round(sidebar.getBoundingClientRect().width)));
      } catch (_) {}
    }

    var dragging = false;
    var startX = 0;
    var startW = 0;

    function onDown(e) {
      if (!e) return;
      if (main.classList.contains('nav-collapsed')) return;
      if (e.button != null && e.button !== 0) return;

      dragging = true;
      startX = e.clientX;
      startW = sidebar.getBoundingClientRect().width;

      resizer.classList.add('resizing');
      document.body.classList.add('is-resizing');

      try { resizer.setPointerCapture(e.pointerId); } catch (_) {}
      e.preventDefault();
    }

    function onMove(e) {
      if (!dragging) return;
      var dx = e.clientX - startX;
      applyWidth(startW + dx, false);
    }

    function onUp(e) {
      if (!dragging) return;
      dragging = false;
      resizer.classList.remove('resizing');
      document.body.classList.remove('is-resizing');

      try {
        applyWidth(sidebar.getBoundingClientRect().width, true);
      } catch (_) {}

      try { resizer.releasePointerCapture(e.pointerId); } catch (_) {}
    }

    resizer.addEventListener('pointerdown', onDown);
    resizer.addEventListener('pointermove', onMove);
    resizer.addEventListener('pointerup', onUp);
    resizer.addEventListener('pointercancel', onUp);
  }

  function setupInspectorResizer() {
    var resizer = document.getElementById('resizer-inspector');
    var inspector = document.querySelector('.inspector');
    var main = document.querySelector('.main');
    console.log('SpecCompiler: setupInspectorResizer', {
      resizer: !!resizer,
      inspector: !!inspector,
      main: !!main
    });
    if (!resizer || !inspector || !main) return;

    var minW = 280;
    var maxW = 560;

    resizer.setAttribute('aria-valuemin', String(minW));
    resizer.setAttribute('aria-valuemax', String(maxW));

    function clamp(n, a, b) {
      return Math.max(a, Math.min(b, n));
    }

    function applyWidth(px, persist) {
      var w = clamp(Math.round(px), minW, maxW);
      document.documentElement.style.setProperty('--layout-inspector-width', String(w) + 'px');
      resizer.setAttribute('aria-valuenow', String(w));
      if (persist) {
        saveNumber('speccompiler_inspector_width', w);
      }
    }

    // Restore previous width if available.
    var saved = loadNumber('speccompiler_inspector_width', null);
    if (saved != null) {
      applyWidth(saved, false);
    } else {
      try {
        resizer.setAttribute('aria-valuenow', String(Math.round(inspector.getBoundingClientRect().width)));
      } catch (_) {}
    }

    var dragging = false;
    var startX = 0;
    var startW = 0;

    function onDown(e) {
      if (!e) return;
      if (main.classList.contains('inspector-collapsed')) return;
      if (e.button != null && e.button !== 0) return;

      dragging = true;
      startX = e.clientX;
      startW = inspector.getBoundingClientRect().width;

      resizer.classList.add('resizing');
      document.body.classList.add('is-resizing');

      try { resizer.setPointerCapture(e.pointerId); } catch (_) {}
      e.preventDefault();
    }

    function onMove(e) {
      if (!dragging) return;
      // Inspector grows leftward: negative dx = larger inspector
      var dx = e.clientX - startX;
      applyWidth(startW - dx, false);
    }

    function onUp(e) {
      if (!dragging) return;
      dragging = false;
      resizer.classList.remove('resizing');
      document.body.classList.remove('is-resizing');

      try {
        applyWidth(inspector.getBoundingClientRect().width, true);
      } catch (_) {}

      try { resizer.releasePointerCapture(e.pointerId); } catch (_) {}
    }

    resizer.addEventListener('pointerdown', onDown);
    resizer.addEventListener('pointermove', onMove);
    resizer.addEventListener('pointerup', onUp);
    resizer.addEventListener('pointercancel', onUp);
  }

  /**
   * Update breadcrumbs + active tab based on current route.
   * @param {Object} route - Route object
   */
  function updateHeaderUI(route) {
    updateBreadcrumbs(route);
  }

  function updateBreadcrumbs(route) {
    var el = document.getElementById('breadcrumbs');
    if (!el || !route) return;

    var parts = [];
	    if (route.type === 'doc' || route.type === 'element') {
	      parts.push('<a href="#/">Docs</a>');
	      parts.push('<span class="separator">/</span>');
	      parts.push('<a href="#/' + encodeURIComponent(route.spec) + '">' + escapeHtml(String(route.spec || '').toUpperCase()) + '</a>');
	      if (route.type === 'element' && route.elementId) {
	        parts.push('<span class="separator">/</span>');
	        parts.push('<span>' + escapeHtml(String(route.elementId)) + '</span>');
	      }
	    } else {
	      // root/unknown
	      parts.push('<a href="#/">Docs</a>');
	    }

    el.innerHTML = parts.join('');
  }

  function escapeHtml(str) {
    if (str == null) return '';
    return String(str)
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/\"/g, '&quot;')
      .replace(/'/g, '&#39;');
  }

  /**
   * Scroll to element by ID with highlighting
   * @param {string} id - Element ID to scroll to
   */
  function scrollToElement(id) {
    if (!id) return;

    var activeSection = document.querySelector('.doc-section.active');
    if (!activeSection) return;

    // Try various methods to find the element
    var element = findElement(activeSection, id);

    if (!element) {
      console.warn('Element not found:', id);
      return;
    }

    // Scroll into view
    element.scrollIntoView({ behavior: 'instant', block: 'start' });

    // Add highlight flash
    element.classList.add('highlight-flash');
    setTimeout(function() {
      element.classList.remove('highlight-flash');
    }, 2000);

    // Update TOC highlight
    if (SpecCompiler.Sidebar) {
      SpecCompiler.Sidebar.highlightTocItem(id);
    }
  }

  /**
   * Find element by ID using multiple strategies
   * @param {HTMLElement} container - Container to search in
   * @param {string} id - Element ID
   * @returns {HTMLElement|null} Found element
   */
  function findElement(container, id) {
    // 1. Try direct ID match
    var element = container.querySelector('#' + CSS.escape(id));
    if (element) return element;

    // 2. Try data-id attribute (for spec objects)
    element = container.querySelector('[data-id="' + CSS.escape(id) + '"]');
    if (element) return element;

    // 3. Try partial match (for anchors/bookmarks)
    element = container.querySelector('a[name="' + CSS.escape(id) + '"]');
    if (element) return element;

    // 4. Try finding heading by text content
    var headings = container.querySelectorAll('h1, h2, h3, h4, h5, h6');
    for (var i = 0; i < headings.length; i++) {
      var heading = headings[i];
      if (heading.textContent.trim() === id || heading.id === id) {
        return heading;
      }
    }

    // 5. Try finding spec-object-header
    var specObjects = container.querySelectorAll('.spec-object-header');
    for (var j = 0; j < specObjects.length; j++) {
      var obj = specObjects[j];
      var objHeading = obj.querySelector('h1, h2, h3, h4, h5, h6');
      if (objHeading && objHeading.textContent.indexOf(id) !== -1) {
        return obj;
      }
    }

    return null;
  }

  /**
   * Load SQLite database from embedded data
   * @returns {Promise} Resolves with database handle
   */
  function loadDatabase() {
    return new Promise(function(resolve, reject) {
      // Check if database is embedded
      var dbScript = document.getElementById('speccompiler-db');
      if (!dbScript || !dbScript.textContent.trim()) {
        reject(new Error('No embedded database found'));
        return;
      }

      // Check if sqlite3 WASM is available
      if (typeof sqlite3InitModule === 'undefined') {
        reject(new Error('SQLite WASM not available'));
        return;
      }

      // Initialize SQLite WASM
      sqlite3InitModule().then(function(sqlite3) {
        console.log('SQLite WASM initialized');

        // Decode base64 database
        var base64Data = dbScript.textContent.trim();
        var binaryString = atob(base64Data);
        var bytes = new Uint8Array(binaryString.length);

        for (var i = 0; i < binaryString.length; i++) {
          bytes[i] = binaryString.charCodeAt(i);
        }

        console.log('Database decoded:', bytes.length, 'bytes');

        // Quick sanity-check: ensure we decoded a valid SQLite file header.
        // This prevents confusing runtime errors later (e.g., SQLITE_NOTADB).
        try {
          var header = 'SQLite format 3\u0000';
          for (var hi = 0; hi < header.length; hi++) {
            if (bytes[hi] !== header.charCodeAt(hi)) {
              throw new Error('Embedded DB header mismatch');
            }
          }
        } catch (e) {
          reject(new Error('Embedded database is not a valid SQLite file'));
          return;
        }

        // Create database from bytes
        var db = new sqlite3.oo1.DB();

        // Import the data.
        // IMPORTANT: sqlite3_deserialize() expects a pointer to WASM memory, not a JS Uint8Array.
        // If we pass a JS object, xWrap will coerce it to 0 and we end up deserializing garbage.
        var pData = 0;
        try {
          pData = sqlite3.wasm.allocFromTypedArray(bytes);
          var rc = sqlite3.capi.sqlite3_deserialize(
            db.pointer,
            'main',
            pData,
            bytes.length,
            bytes.length,
            sqlite3.capi.SQLITE_DESERIALIZE_FREEONCLOSE | sqlite3.capi.SQLITE_DESERIALIZE_RESIZEABLE
          );

          if (rc !== sqlite3.capi.SQLITE_OK) {
            // sqlite3 won't own pData unless SQLITE_OK, so free on failure.
            sqlite3.wasm.dealloc(pData);
            reject(new Error('Failed to deserialize database: ' + rc));
            return;
          }
          // On success, SQLite takes ownership of pData due to FREEONCLOSE.
          pData = 0;
        } catch (e) {
          if (pData) {
            try { sqlite3.wasm.dealloc(pData); } catch (_) {}
          }
          reject(e);
          return;
        }

        console.log('Database deserialized successfully');

        // Wrap database with helper methods
        var dbWrapper = {
          db: db,

          selectObjects: function(sql, params) {
            try {
              var results = [];
              var stmt = this.db.prepare(sql);

              if (params) {
                stmt.bind(params);
              }

              while (stmt.step()) {
                var row = stmt.get({});
                results.push(row);
              }

              stmt.finalize();
              return results;
            } catch (e) {
              console.error('Query error:', e);
              throw e;
            }
          },

          selectValue: function(sql, params) {
            try {
              var stmt = this.db.prepare(sql);

              if (params) {
                stmt.bind(params);
              }

              var value = null;
              if (stmt.step()) {
                value = stmt.get([])[0];
              }

              stmt.finalize();
              return value;
            } catch (e) {
              console.error('Query error:', e);
              throw e;
            }
          }
        };

        resolve(dbWrapper);

      }).catch(function(err) {
        console.error('SQLite initialization error:', err);
        reject(err);
      });
    });
  }

  // Register initialization on DOM ready
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    // DOM already loaded
    init();
  }

  // Export public API
  SpecCompiler.App = SpecCompiler.App || {};
  SpecCompiler.App.init = init;
  SpecCompiler.App.getDatabase = function() { return db; };
  SpecCompiler.App.isDatabaseLoaded = function() { return dbLoaded; };

})();
