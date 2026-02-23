/**
 * SpecCompiler Search - SQLite-WASM powered search
 * Full-text search across objects and floats with debouncing and keyboard shortcuts
 */

var SpecCompiler = SpecCompiler || {};

(function() {
  'use strict';

  var db = null;
  var searchInput = null;
  var resultsContainer = null;
  var debounceTimer = null;
  var DEBOUNCE_MS = 150;
  var isSearchActive = false;
  var lastResults = [];
  var lastQueryText = '';
  var filters = { spec: 'all', type: 'all', attr: 'all' };
  var attributeNamesCache = null;

  /**
   * Initialize search system
   * @param {Object} database - SQLite database handle
   */
  function init(database) {
    db = database;
    searchInput = document.getElementById('search-input');

    if (!searchInput) return;

    resultsContainer = getSidebarSearchContainer();
    if (resultsContainer) {
      // Event delegation for filter controls (container content is re-rendered on each search)
      resultsContainer.addEventListener('change', onFilterChange);
      resultsContainer.addEventListener('click', onFilterClick);
    }

    // Setup input handler
    searchInput.addEventListener('input', onInput);
    searchInput.addEventListener('focus', onFocus);
    searchInput.addEventListener('blur', onBlur);

    // Setup keyboard shortcuts
    setupKeyboardShortcuts();
  }

  /**
   * Setup global keyboard shortcuts
   */
  function setupKeyboardShortcuts() {
    document.addEventListener('keydown', function(e) {
      // Cmd/Ctrl + K to focus search
      if ((e.metaKey || e.ctrlKey) && e.key === 'k') {
        e.preventDefault();
        if (searchInput) {
          searchInput.focus();
          searchInput.select();
        }
      }

      // Escape to clear and blur
      if (e.key === 'Escape' && document.activeElement === searchInput) {
        clearResults();
        searchInput.blur();
      }
    });
  }

  /**
   * Input event handler (debounced)
   */
  function onInput(e) {
    var text = e.target.value.trim();

    clearTimeout(debounceTimer);

    if (!text) {
      clearResults();
      return;
    }

    debounceTimer = setTimeout(function() {
      performSearch(text);
    }, DEBOUNCE_MS);
  }

  /**
   * Focus event handler
   */
  function onFocus() {
    if (searchInput && searchInput.value.trim()) {
      performSearch(searchInput.value.trim());
    }
  }

  /**
   * Blur event handler (delayed to allow click on results)
   */
  function onBlur() {
    // Delay to allow click events on results
    setTimeout(function() {
      if (document.activeElement !== searchInput) {
        // Don't clear if still active
      }
    }, 200);
  }

  /**
   * Perform search query
   * @param {string} text - Search query text
   */
  function performSearch(text) {
    if (!db) {
      renderNotAvailable();
      return;
    }

    lastQueryText = text;

    lastResults = query(text);
    renderResults(lastResults, text);
    highlightTocMatches(getFilteredResults(lastResults));
  }

  /**
   * Query database for search results
   * @param {string} text - Search query
   * @returns {Array} Array of result objects
   */
  function query(text) {
    if (!db || !text) return [];

    var ftsQuery = buildFtsQuery(text);
    if (!ftsQuery) return [];

    try {
      // Attribute mode: search within a specific attribute field using the main query text.
      if (filters.attr && filters.attr !== 'all') {
        var attrsSql =
          "SELECT " +
          "  o.id AS object_id, " +
          "  NULL AS float_id, " +
          "  COALESCE(" +
          "    o.pid," +
          "    CASE WHEN o.type_ref = 'SECTION' AND o.label LIKE 'section:%' THEN substr(o.label, instr(o.label, ':')+1) END," +
          "    o.label," +
          "    CAST(o.id AS TEXT)" +
          "  ) AS identifier, " +
          "  o.type_ref AS type, " +
          "  o.title_text AS title, " +
          "  fts_attributes.attr_value AS content, " +
          "  fts_attributes.spec_id AS spec_id, " +
          "  bm25(fts_attributes) as score " +
          "FROM fts_attributes " +
          "JOIN spec_objects o ON o.id = fts_attributes.owner_ref " +
          "WHERE fts_attributes.attr_name = ? " +
          "  AND fts_attributes MATCH ? " +
          "ORDER BY score " +
          "LIMIT 500";

        var rows = db.selectObjects(attrsSql, [String(filters.attr), ftsQuery]) || [];
        var out = [];
        var seen = new Set();
        for (var ri = 0; ri < rows.length; ri++) {
          var r = rows[ri];
          if (!r || r.object_id == null) continue;
          var k = String(r.object_id);
          if (seen.has(k)) continue;
          seen.add(k);
          out.push(r);
          if (out.length >= 200) break;
        }
        return out;
      }

      // Query objects
      var objectsSql =
        "SELECT " +
        "  o.id AS object_id, " +
        "  NULL AS float_id, " +
        "  COALESCE(" +
        "    o.pid," +
        "    CASE WHEN o.type_ref = 'SECTION' AND o.label LIKE 'section:%' THEN substr(o.label, instr(o.label, ':')+1) END," +
        "    fts_objects.identifier" +
        "  ) AS identifier, " +
        "  fts_objects.object_type as type, " +
        "  fts_objects.title, " +
        "  fts_objects.content, " +
        "  fts_objects.spec_id, " +
        "  bm25(fts_objects) as score " +
        "FROM fts_objects " +
        "LEFT JOIN spec_objects o " +
        "  ON o.specification_ref = fts_objects.spec_id " +
        " AND (o.label = fts_objects.identifier OR o.pid = fts_objects.identifier) " +
        "WHERE fts_objects MATCH ? " +
        "ORDER BY score " +
        "LIMIT 200";

      var objects = db.selectObjects(objectsSql, [ftsQuery]) || [];

      // Query floats
      var floatsSql =
        "SELECT " +
        "  NULL AS object_id, " +
        "  sf.id AS float_id, " +
        "  COALESCE(sf.anchor, sf.label, fts_floats.identifier) AS identifier, " +
        "  fts_floats.float_type as type, " +
        "  fts_floats.caption as title, " +
        "  fts_floats.raw_source as content, " +
        "  fts_floats.spec_id as spec_id, " +
        "  bm25(fts_floats) as score " +
        "FROM fts_floats " +
        "LEFT JOIN spec_floats sf " +
        "  ON sf.specification_ref = fts_floats.spec_id " +
        " AND (sf.label = fts_floats.identifier OR CAST(sf.id AS TEXT) = fts_floats.identifier) " +
        "WHERE fts_floats MATCH ? " +
        "ORDER BY score " +
        "LIMIT 200";

      var floats = db.selectObjects(floatsSql, [ftsQuery]) || [];

      // Combine and limit
      var all = objects.concat(floats);
      return all.slice(0, 200);

    } catch (e) {
      console.error('Search query error:', e);
      return [];
    }
  }

  /**
   * Render search results
   * @param {Array} results - Search results array
   * @param {string} query - Original query text
   */
  function renderResults(results, query) {
    var container = getSidebarSearchContainer();
    if (!container) return;

    var filtered = getFilteredResults(results || []);
    container.classList.remove('is-empty');

    if (!results || results.length === 0) {
      container.classList.add('is-empty');
      container.innerHTML = '<div class="search-results-inline"><p class="search-results-empty">No results found</p></div>';
      container.style.display = 'block';
      isSearchActive = true;
      // No results: keep the TOC visible so the sidebar doesn't turn into a blank panel.
      showTOC();
      return;
    }

    // Group by spec
    var grouped = groupBySpec(filtered);

    var html = '<div class="search-results-inline">';
    html += '<div class="search-results-header">';
    html += '<div class="search-results-meta">';
    html += filtered.length + ' result' + (filtered.length !== 1 ? 's' : '');
    html += '</div>';
    html += renderFilters(results || []);
    html += '</div>';

    if (filtered.length === 0) {
      container.classList.add('is-empty');
      html += '<p class="search-results-empty">No results match the current filters</p>';
      html += '</div>';
      container.innerHTML = html;
      container.style.display = 'block';
      isSearchActive = true;
      // No visible results: keep TOC for navigation and reduce "dead space".
      showTOC();
      return;
    }

    Object.keys(grouped).sort().forEach(function(specId) {
      var items = grouped[specId];
      html += '<div class="search-doc-group">';
      html += '<h4 class="search-doc-title">' + escapeHtml(specId.toUpperCase()) + '</h4>';

      items.forEach(function(item) {
        var badge = getTypeBadge(item.type);
        var snippet = generateSnippet(item.content || item.title, query);

        html += '<div class="search-result-item" data-doc="' + escapeHtml(item.spec_id) + '" data-id="' + escapeHtml(item.identifier) + '">';
        html += '<div class="search-result-title">';
        html += badge;
        html += '<span>' + escapeHtml(item.title || item.identifier) + '</span>';
        html += '</div>';
        if (snippet) {
          html += '<div class="search-result-snippet">' + snippet + '</div>';
        }
        html += '</div>';
      });

      html += '</div>';
    });

    html += '</div>';

    container.innerHTML = html;
    container.style.display = 'block';
    isSearchActive = true;
    hideTOC();

    // Add click handlers
    var resultElements = container.querySelectorAll('.search-result-item');
    resultElements.forEach(function(el) {
      el.addEventListener('click', function() {
        var spec = el.getAttribute('data-doc');
        var id = el.getAttribute('data-id');

        if (SpecCompiler.Router) {
          SpecCompiler.Router.navigate('#/' + spec + '/' + id);
        }

        // Clear search on mobile
        if (window.innerWidth < 768) {
          clearResults();
        }
      });
    });
  }

  /**
   * Render "not available" message
   */
  function renderNotAvailable() {
    var container = getSidebarSearchContainer();
    if (!container) return;

    container.innerHTML = '<div class="search-results"><p class="search-empty">Search not available</p></div>';
    container.style.display = 'block';
  }

  /**
   * Clear search results
   */
  function clearResults() {
    if (searchInput) {
      searchInput.value = '';
    }

    var container = getSidebarSearchContainer();
    if (container) {
      container.innerHTML = '';
      container.style.display = 'none';
    }

    isSearchActive = false;
    showTOC();
    clearTocHighlights();

    filters.spec = 'all';
    filters.type = 'all';
    filters.attr = 'all';
  }

  /**
   * Get or create sidebar search container
   * @returns {HTMLElement} Search container
   */
  function getSidebarSearchContainer() {
    var existing = document.getElementById('sidebar-search-results');
    if (existing) return existing;

    var sidebar = document.querySelector('.sidebar');
    if (!sidebar) return null;

    var container = document.createElement('div');
    container.id = 'sidebar-search-results';
    container.className = 'sidebar-search-results';

    // Insert before TOC
    var toc = document.getElementById('sidebar-toc');
    if (toc) {
      sidebar.insertBefore(container, toc);
    } else {
      sidebar.appendChild(container);
    }

    return container;
  }

  /**
   * Hide TOC during search
   */
  function hideTOC() {
    var toc = document.getElementById('sidebar-toc');
    if (toc) {
      toc.style.display = 'none';
    }
  }

  /**
   * Show TOC after search cleared
   */
  function showTOC() {
    var toc = document.getElementById('sidebar-toc');
    if (toc) {
      toc.style.display = '';
    }
  }

  /**
   * Highlight matching TOC items
   * @param {Array} results - Search results
   */
  function highlightTocMatches(results) {
    clearTocHighlights();

    var toc = document.getElementById('sidebar-toc');
    if (!toc) return;

    var ids = results.map(function(r) { return r.identifier; });

    ids.forEach(function(id) {
      var link = toc.querySelector('a[href="#' + id + '"]');
      if (link) {
        link.classList.add('search-match');
      }
    });
  }

  /**
   * Clear TOC search highlights
   */
  function clearTocHighlights() {
    var toc = document.getElementById('sidebar-toc');
    if (!toc) return;

    var matches = toc.querySelectorAll('.search-match');
    matches.forEach(function(el) {
      el.classList.remove('search-match');
    });
  }

  /**
   * Group results by spec_id
   * @param {Array} results - Results array
   * @returns {Object} Grouped results
   */
  function groupBySpec(results) {
    var grouped = {};

    results.forEach(function(item) {
      var spec = item.spec_id || 'unknown';
      if (!grouped[spec]) {
        grouped[spec] = [];
      }
      grouped[spec].push(item);
    });

    return grouped;
  }

  function renderFilters(allResults) {
    var specs = new Set();
    var types = new Set();

    (allResults || []).forEach(function(r) {
      if (r && r.spec_id) specs.add(String(r.spec_id));
      if (r && r.type) types.add(String(r.type));
    });

    // Keep filters consistent with available options, otherwise it's easy to end up with
    // "0 results" while the UI dropdown snaps back to All.
    if (filters.spec !== 'all' && !specs.has(String(filters.spec))) {
      filters.spec = 'all';
    }
    if (filters.type !== 'all' && !types.has(String(filters.type))) {
      filters.type = 'all';
    }

    var specOptions = ['<option value="all">All specs</option>'];
    Array.from(specs).sort().forEach(function(s) {
      specOptions.push('<option value="' + escapeHtml(s) + '"' + (filters.spec === s ? ' selected' : '') + '>' + escapeHtml(s.toUpperCase()) + '</option>');
    });

    var typeOptions = ['<option value="all">All types</option>'];
    Array.from(types).sort().forEach(function(t) {
      typeOptions.push('<option value="' + escapeHtml(t) + '"' + (filters.type === t ? ' selected' : '') + '>' + escapeHtml(t.toUpperCase()) + '</option>');
    });

    var attrs = getAttributeNames();
    if (filters.attr !== 'all' && attrs.indexOf(String(filters.attr)) === -1) {
      filters.attr = 'all';
    }

    var attrOptions = ['<option value="all">Any field</option>'];
    (attrs || []).forEach(function(a) {
      attrOptions.push('<option value="' + escapeHtml(a) + '"' + (filters.attr === a ? ' selected' : '') + '>' + escapeHtml(a) + '</option>');
    });

    return [
      '<div class="search-results-filters">',
      '  <label class="search-filter-item">',
      '    <span class="search-filter-label">Spec</span>',
      '    <select id="search-filter-spec" aria-label="Filter by specification">',
      specOptions.join(''),
      '    </select>',
      '  </label>',
      '  <label class="search-filter-item">',
      '    <span class="search-filter-label">Type</span>',
      '    <select id="search-filter-type" aria-label="Filter by type">',
      typeOptions.join(''),
      '    </select>',
      '  </label>',
      '  <label class="search-filter-item">',
      '    <span class="search-filter-label">Field</span>',
      '    <select id="search-filter-attr" aria-label="Search within attribute field">',
      attrOptions.join(''),
      '    </select>',
      '  </label>',
      '  <button type="button" class="search-filter-reset" data-action="reset-filters">Reset</button>',
      '</div>'
    ].join('');
  }

  function onFilterChange(e) {
    if (!e || !e.target) return;
    if (e.target.id === 'search-filter-spec') {
      filters.spec = e.target.value || 'all';
      renderResults(lastResults, lastQueryText);
      highlightTocMatches(getFilteredResults(lastResults));
      return;
    }
    if (e.target.id === 'search-filter-type') {
      filters.type = e.target.value || 'all';
      renderResults(lastResults, lastQueryText);
      highlightTocMatches(getFilteredResults(lastResults));
      return;
    }
    if (e.target.id === 'search-filter-attr') {
      filters.attr = e.target.value || 'all';
      if (lastQueryText) {
        // Attribute selection changes the search mode, so re-run the query.
        performSearch(lastQueryText);
      } else {
        renderResults(lastResults, lastQueryText);
        highlightTocMatches(getFilteredResults(lastResults));
      }
      return;
    }
  }

  function onFilterClick(e) {
    if (!e || !e.target) return;
    var btn = e.target;
    while (btn && btn !== resultsContainer && !btn.getAttribute('data-action')) {
      btn = btn.parentElement;
    }
    if (!btn || btn === resultsContainer) return;

    if (btn.getAttribute('data-action') === 'reset-filters') {
      filters.spec = 'all';
      filters.type = 'all';
      filters.attr = 'all';
      if (lastQueryText) {
        performSearch(lastQueryText);
      } else {
        renderResults(lastResults, lastQueryText);
        highlightTocMatches(getFilteredResults(lastResults));
      }
    }
  }

  function getFilteredResults(results) {
    var out = results || [];
    if (filters.spec && filters.spec !== 'all') {
      out = out.filter(function(r) { return r && String(r.spec_id) === String(filters.spec); });
    }
    if (filters.type && filters.type !== 'all') {
      out = out.filter(function(r) { return r && String(r.type) === String(filters.type); });
    }

    return out;
  }

  function getAttributeNames() {
    if (attributeNamesCache) return attributeNamesCache;
    if (!db || !db.selectObjects) return [];

    try {
      var rows = db.selectObjects(
        "SELECT DISTINCT name FROM spec_attribute_values " +
        "WHERE owner_object_id IS NOT NULL AND name IS NOT NULL AND name != '' " +
        "ORDER BY name " +
        "LIMIT 2000"
      ) || [];
      attributeNamesCache = rows.map(function(r) { return String(r.name); });
      return attributeNamesCache;
    } catch (e) {
      console.warn('Failed to load attribute names:', e);
      attributeNamesCache = [];
      return attributeNamesCache;
    }
  }

  function buildFtsQuery(text) {
    if (!text) return '';

    var tokens = String(text)
      .trim()
      .split(/\s+/)
      .map(function(t) { return t.replace(/\"/g, '').replace(/\*/g, '').trim(); })
      .filter(function(t) { return t.length > 0; });

    if (tokens.length === 0) return '';

    // Prefix match each token and AND them for predictable filtering.
    return tokens.map(function(t) {
      return '"' + t + '"*';
    }).join(' AND ');
  }

  /**
   * Get type badge HTML
   * @param {string} type - Object or float type
   * @returns {string} Badge HTML
   */
  function getTypeBadge(type) {
    var label = type ? type.toUpperCase() : 'OBJ';
    return '<span class="search-badge">' + escapeHtml(label) + '</span>';
  }

  /**
   * Generate search snippet with highlighting
   * @param {string} text - Content text
   * @param {string} query - Search query
   * @returns {string} HTML snippet
   */
  function generateSnippet(text, query) {
    if (!text) return '';

    var maxLen = 150;
    var textLower = text.toLowerCase();
    var queryLower = query.toLowerCase();
    var index = textLower.indexOf(queryLower);

    var snippet;
    if (index !== -1) {
      // Extract context around match
      var start = Math.max(0, index - 40);
      var end = Math.min(text.length, index + query.length + 90);

      var rawSnippet = text.substring(start, end);

      var prefix = '';
      var suffix = '';
      if (start > 0) prefix = '...';
      if (end < text.length) suffix = '...';

      // Find match position in snippet
      var matchStart = index - start;
      var matchEnd = matchStart + query.length;

      // Split into parts: before match, match, after match
      var beforeMatch = rawSnippet.substring(0, matchStart);
      var matchText = rawSnippet.substring(matchStart, matchEnd);
      var afterMatch = rawSnippet.substring(matchEnd);

      // Escape each part separately
      snippet = prefix + escapeHtml(beforeMatch) + '<mark>' + escapeHtml(matchText) + '</mark>' + escapeHtml(afterMatch) + suffix;
    } else {
      // No match - just truncate
      snippet = text.substring(0, maxLen);
      if (text.length > maxLen) snippet += '...';
      snippet = escapeHtml(snippet);
    }

    return snippet;
  }

  /**
   * Escape HTML
   * @param {string} str - String to escape
   * @returns {string} Escaped string
   */
  function escapeHtml(str) {
    var div = document.createElement('div');
    div.textContent = str;
    return div.innerHTML;
  }

  /**
   * Escape regex special characters
   * @param {string} str - String to escape
   * @returns {string} Escaped string
   */
  function escapeRegex(str) {
    return str.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  }

  // Export public API
  SpecCompiler.Search = {
    init: init,
    query: query,
    clearResults: clearResults
  };

})();
