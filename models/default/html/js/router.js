/**
 * SpecCompiler Router - Hash-based navigation
 * Handles URL routing, scroll position caching, and route change events
 */

var SpecCompiler = SpecCompiler || {};

(function() {
  'use strict';

  var currentRoute = null;
  var scrollCache = new Map();
  var routeHandlers = [];

  /**
   * Initialize router - parse initial hash and set up listeners
   */
  function init() {
    window.addEventListener('hashchange', onHashChange);
    currentRoute = parseRoute(window.location.hash);
    normalizeHash(currentRoute);
    dispatchRouteChange();
  }

  /**
   * Navigate to a new route
   * @param {string} path - The hash path (e.g., '#/srs' or '#/srs/REQ-001')
   */
  function navigate(path) {
    // Save current scroll position before navigating
    if (currentRoute) {
      saveScrollPosition();
    }

    // Update hash (will trigger hashchange event)
    window.location.hash = path;
  }

  /**
   * Parse a hash string into a route object
   * @param {string} hash - The window.location.hash value
   * @returns {Object} Route object with type, spec, elementId
   */
  function parseRoute(hash) {
    // Remove leading '#' and any query params
    var path = (hash || '').replace(/^#\/?/, '').split('?')[0];

    if (!path) {
      return { type: 'root', spec: null, elementId: null };
    }

    var parts = path.split('/');

    // Reserved legacy routes: "#/views" used to be an interactive views workspace.
    // Keep backwards compatibility by treating it as root unless there's a real "views" doc.
    if (parts[0] === 'views') {
      try {
        if (!document.getElementById('doc-views')) {
          return { type: 'root', spec: null, elementId: null };
        }
      } catch (e) {
        return { type: 'root', spec: null, elementId: null };
      }
    }

    // Document routes
    var spec = parts[0];
    var elementId = parts[1] || null;

    if (elementId) {
      return { type: 'element', spec: spec, elementId: elementId };
    }

    // Support legacy/internal anchor links like "#SF-002" in the SPA.
    // Without this, the router interprets "#SF-002" as a document route and blanks the UI.
    // If there's no doc section with that id, treat it as an element within a doc section.
    try {
      if (spec && !document.getElementById('doc-' + spec)) {
        var chosen = null;

        // Prefer the doc which actually contains the element id (works for deep links on fresh load).
        var el = document.getElementById(spec);
        if (el && el.closest) {
          var owner = el.closest('.doc-section');
          if (owner && owner.id && owner.id.indexOf('doc-') === 0) {
            chosen = owner.id.slice(4);
          }
        }

        // Fall back to active/first doc.
        if (!chosen) {
          var active = document.querySelector('.doc-section.active') || document.querySelector('.doc-section');
          if (active && active.id && active.id.indexOf('doc-') === 0) {
            chosen = active.id.slice(4);
          }
        }

        if (chosen) {
          return {
            type: 'element',
            spec: chosen,
            elementId: spec,
            _canonicalHash: '#/' + encodeURIComponent(String(chosen)) + '/' + encodeURIComponent(String(spec))
          };
        }
      }
    } catch (e) {
      // Ignore DOM errors and fall back to normal doc route.
    }

    return { type: 'doc', spec: spec, elementId: null };
  }

  /**
   * Register a route change handler
   * @param {Function} handler - Callback function that receives route object
   */
  function onRouteChange(handler) {
    routeHandlers.push(handler);
  }

  /**
   * Get the current parsed route
   * @returns {Object} Current route object
   */
  function getCurrentRoute() {
    return currentRoute;
  }

  /**
   * Hash change event handler
   */
  function onHashChange() {
    var oldRoute = currentRoute;
    currentRoute = parseRoute(window.location.hash);
    normalizeHash(currentRoute);

    // Restore scroll position if navigating back
    restoreScrollPosition(oldRoute);

    dispatchRouteChange(oldRoute);
  }

  function normalizeHash(route) {
    if (!route || !route._canonicalHash) return;
    try {
      if (window.location.hash !== route._canonicalHash && window.history && window.history.replaceState) {
        window.history.replaceState(null, '', route._canonicalHash);
      }
    } catch (e) {
      // Ignore (file:// + older browsers can throw on replaceState).
    }
  }

  /**
   * Dispatch route change to all registered handlers
   * @param {Object} oldRoute - Previous route (optional)
   */
  function dispatchRouteChange(oldRoute) {
    routeHandlers.forEach(function(handler) {
      try {
        handler(currentRoute, oldRoute);
      } catch (e) {
        console.error('Route handler error:', e);
      }
    });
  }

  /**
   * Save current scroll position to cache
   */
  function saveScrollPosition() {
    var content = document.querySelector('.content');
    if (content && currentRoute) {
      var key = routeToKey(currentRoute);
      scrollCache.set(key, content.scrollTop);
    }
  }

  /**
   * Restore scroll position from cache
   */
  function restoreScrollPosition(oldRoute) {
    if (!currentRoute) return;

    var content = document.querySelector('.content');
    if (!content) return;

    // Element routes are "locations" within a document. When navigating between
    // anchors inside the same spec, we want the smooth-scroll to start from the
    // current position (not from the top).
    if (currentRoute.type === 'element') {
      if (oldRoute && (oldRoute.type === 'doc' || oldRoute.type === 'element') && oldRoute.spec === currentRoute.spec) {
        return; // keep current scrollTop
      }
      // Switching specs (or coming from views): reset to top before scrolling to the element.
      content.scrollTop = 0;
      return;
    }

    var key = routeToKey(currentRoute);
    if (scrollCache.has(key)) {
      // Use setTimeout to ensure DOM is updated
      setTimeout(function() {
        content.scrollTop = scrollCache.get(key);
      }, 0);
    } else {
      // New route - scroll to top
      content.scrollTop = 0;
    }
  }

  /**
   * Convert route object to cache key string
   * @param {Object} route - Route object
   * @returns {string} Cache key
   */
  function routeToKey(route) {
    if (route.type === 'element') {
      return route.spec + '/' + route.elementId;
    }
    if (route.type === 'doc') {
      return route.spec;
    }
    return 'root';
  }

  // Export public API
  SpecCompiler.Router = {
    init: init,
    navigate: navigate,
    parseRoute: parseRoute,
    onRouteChange: onRouteChange,
    getCurrentRoute: getCurrentRoute
  };

})();
