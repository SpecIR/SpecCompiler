/**
 * SpecCompiler Views - Interactive traceability views
 * Renders database views with sorting, filtering, pagination, and deep linking
 */

var SpecCompiler = SpecCompiler || {};

(function() {
  'use strict';

  var db = null;
  var currentView = null;
  var currentData = null;
  var filteredData = null;
  var sortColumn = null;
  var sortDirection = null;
  var currentPage = 1;
  var ROWS_PER_PAGE = 50;

  var VIEW_DEFS = {
    traceability: {
      title: 'Traceability Matrix',
      description: 'Relationships between spec objects',
      sql: [
        'SELECT',
        '  so.specification_ref AS source_spec,',
        '  so.pid               AS source_id,',
        '  so.type_ref          AS source_type,',
        '  so.title_text        AS source_title,',
        '  r.type_ref           AS relation_type,',
        '  tobj.specification_ref AS target_spec,',
        '  tobj.pid               AS target_id,',
        '  tobj.type_ref          AS target_type,',
        '  tobj.title_text        AS target_title',
        'FROM spec_relations r',
        'LEFT JOIN spec_objects so   ON so.id = r.source_object_id',
        'LEFT JOIN spec_objects tobj ON tobj.id = r.target_object_id',
        "WHERE r.type_ref IS NOT NULL AND r.target_object_id IS NOT NULL",
        'ORDER BY source_spec, source_id, target_spec, target_id'
      ].join(' '),
      linkColumns: ['source_id', 'target_id'],
      specColumns: ['source_spec', 'target_spec']
    },
    coverage: {
      title: 'Coverage Report',
      description: 'HLR coverage by inbound VC trace links (per specification)',
      sql: [
        'SELECT',
        '  h.specification_ref AS spec_id,',
        '  COUNT(DISTINCT h.id) AS hlr_total,',
        '  COUNT(DISTINCT CASE WHEN v.id IS NOT NULL THEN h.id END) AS hlr_covered,',
        '  ROUND(',
        '    100.0 * COUNT(DISTINCT CASE WHEN v.id IS NOT NULL THEN h.id END) /',
        '    NULLIF(COUNT(DISTINCT h.id), 0),',
        '    1',
        '  ) AS coverage_pct',
        'FROM spec_objects h',
        "LEFT JOIN spec_relations r ON r.target_object_id = h.id AND r.type_ref = 'VERIFIES'",
        "LEFT JOIN spec_objects v ON v.id = r.source_object_id AND v.type_ref = 'VC'",
        "WHERE h.type_ref = 'HLR'",
        'GROUP BY h.specification_ref',
        'ORDER BY coverage_pct DESC, spec_id'
      ].join(' '),
      linkColumns: [],
      specialRenderers: { coverage_pct: renderCoverageBar }
    },
    dangling: {
      title: 'Dangling References',
      description: 'Unresolved cross-references and ambiguous relations',
      sql: [
        'SELECT',
        '  r.specification_ref AS spec_id,',
        '  COALESCE(so.specification_ref, r.specification_ref) AS source_spec,',
        '  so.pid AS source_id,',
        '  so.type_ref AS source_type,',
        '  r.type_ref AS relation_type,',
        '  r.target_text AS target_text,',
        '  r.is_ambiguous AS is_ambiguous,',
        '  r.from_file AS from_file,',
        '  r.link_line AS line',
        'FROM spec_relations r',
        'LEFT JOIN spec_objects so ON so.id = r.source_object_id',
        'WHERE (r.target_object_id IS NULL AND r.target_float_id IS NULL) OR r.is_ambiguous = 1',
        'ORDER BY spec_id, from_file, line'
      ].join(' '),
      linkColumns: ['source_id'],
      specColumns: ['source_spec']
    },
    inventory: {
      title: 'Float Inventory',
      description: 'All figures, tables, listings, and diagrams',
      sql: [
        'SELECT',
        '  specification_ref AS spec_id,',
        '  type_ref AS float_type,',
        '  COALESCE(anchor, label) AS float_id,',
        '  label,',
        '  number,',
        '  caption,',
        '  from_file,',
        '  start_line',
        'FROM spec_floats',
        'ORDER BY spec_id, float_type, number, label'
      ].join(' '),
      linkColumns: ['float_id'],
      specColumns: ['spec_id']
    },
    summary: {
      title: 'Object Summary',
      description: 'Object counts by type per specification',
      sql: [
        'SELECT',
        '  specification_ref AS spec_id,',
        '  type_ref AS object_type,',
        '  COUNT(*) AS count',
        'FROM spec_objects',
        "WHERE type_ref != 'SECTION'",
        'GROUP BY specification_ref, type_ref',
        'ORDER BY spec_id, count DESC, object_type'
      ].join(' '),
      linkColumns: []
    }
  };

  /**
   * Initialize views system
   * @param {Object} database - SQLite database handle
   */
  function init(database) {
    db = database;

    // Setup global click handler for view links (event delegation)
    document.addEventListener('click', function(e) {
      if (e.target.classList.contains('view-link')) {
        e.preventDefault();
        var href = e.target.getAttribute('href');
        if (href && SpecCompiler.Router) {
          SpecCompiler.Router.navigate(href);
        }
      }
    });
  }

  /**
   * Render views index page
   * @param {HTMLElement} container - Container element
   */
  function renderIndex(container) {
    if (!container) return;

    var html = '<div class="view-container">';
    html += '<h1>Documentation Views</h1>';
    html += '<p class="view-description">Explore requirements traceability, test coverage, and documentation metrics</p>';
    html += '<div class="view-index">';

    Object.keys(VIEW_DEFS).forEach(function(key) {
      var view = VIEW_DEFS[key];
      html += '<div class="view-card" data-view="' + escapeHtml(key) + '">';
      html += '<h3>' + escapeHtml(view.title) + '</h3>';
      html += '<p>' + escapeHtml(view.description) + '</p>';
      html += '</div>';
    });

    html += '</div>';
    html += '</div>';

    container.innerHTML = html;

    // Add click handlers
    var cards = container.querySelectorAll('.view-card');
    cards.forEach(function(card) {
      card.addEventListener('click', function() {
        var viewName = card.getAttribute('data-view');
        if (SpecCompiler.Router) {
          SpecCompiler.Router.navigate('#/views/' + viewName);
        }
      });
    });
  }

  /**
   * Render a specific view
   * @param {string} viewName - Name of the view to render
   * @param {HTMLElement} container - Container element
   */
  function renderView(viewName, container) {
    if (!container) return;

    var viewDef = VIEW_DEFS[viewName];
    if (!viewDef) {
      container.innerHTML = '<div class="view-container"><div class="view-empty-state"><p>View not found: ' + escapeHtml(viewName) + '</p></div></div>';
      return;
    }

    if (!db) {
      renderNotAvailable(container, viewDef);
      return;
    }

    // Query database
    try {
      var data = db.selectObjects(viewDef.sql);
      currentView = viewName;
      currentData = data;
      filteredData = data.slice();
      sortColumn = null;
      sortDirection = null;
      currentPage = 1;

      renderViewPage(container, viewDef);
    } catch (e) {
      console.error('View query error:', e);
      container.innerHTML = '<div class="view-container"><div class="view-empty-state"><p>Error loading view: ' + escapeHtml(e.message) + '</p></div></div>';
    }
  }

  /**
   * Render view page with controls and table
   * @param {HTMLElement} container - Container element
   * @param {Object} viewDef - View definition
   */
  function renderViewPage(container, viewDef) {
    var html = '<div class="view-container">';

    // Header
    html += '<div class="view-header">';
    html += '<h1>' + escapeHtml(viewDef.title) + '</h1>';
    html += '<p class="view-description">' + escapeHtml(viewDef.description) + '</p>';
    html += '</div>';

    // Toolbar with filter and export
    html += '<div class="view-toolbar">';
    html += '<div class="view-filters">';
    html += '<div class="view-global-filter">';
    html += '<input type="text" class="view-filter-input" id="view-filter" placeholder="Filter all columns...">';
    html += '</div>';
    html += '</div>';
    html += '<button class="view-toolbar-btn" id="btn-copy-csv">Copy as CSV</button>';
    html += '</div>';

    // Table
    html += '<div class="view-table-wrapper">';
    html += '<table class="view-table" id="view-table"></table>';
    html += '</div>';

    // Pagination
    html += '<div class="view-pagination" id="view-pagination"></div>';

    html += '</div>';

    container.innerHTML = html;

    // Render table and controls
    renderTable();
    renderPagination();
    updateStats();

    // Setup event handlers
    setupViewHandlers();
  }

  /**
   * Render table with current data
   */
  function renderTable() {
    var table = document.getElementById('view-table');
    if (!table || !filteredData || filteredData.length === 0) {
      if (table) {
        table.innerHTML = '<tr><td class="view-empty-state">No data available</td></tr>';
      }
      return;
    }

    var viewDef = VIEW_DEFS[currentView];
    var columns = Object.keys(filteredData[0]);

    // Calculate pagination
    var start = (currentPage - 1) * ROWS_PER_PAGE;
    var end = Math.min(start + ROWS_PER_PAGE, filteredData.length);
    var pageData = filteredData.slice(start, end);

    // Build table HTML
    var html = '<thead><tr>';

    columns.forEach(function(col) {
      var sortedClass = '';
      if (sortColumn === col) {
        sortedClass = sortDirection === 'asc' ? ' sorted-asc' : ' sorted-desc';
      }

      html += '<th data-column="' + escapeHtml(col) + '"' + sortedClass + '>';
      html += formatColumnName(col);
      html += '<span class="sort-indicator"></span>';
      html += '</th>';
    });

    html += '</tr></thead><tbody>';

    pageData.forEach(function(row) {
      html += '<tr>';
      columns.forEach(function(col) {
        var value = row[col];
        var rendered = renderCell(col, value, row, viewDef);
        html += '<td>' + rendered + '</td>';
      });
      html += '</tr>';
    });

    html += '</tbody>';

    table.innerHTML = html;

    // Add sort handlers
    var headers = table.querySelectorAll('th');
    headers.forEach(function(th) {
      th.addEventListener('click', function() {
        var col = th.getAttribute('data-column');
        toggleSort(col);
      });
    });
  }

  /**
   * Render a table cell
   * @param {string} column - Column name
   * @param {*} value - Cell value
   * @param {Object} row - Full row object
   * @param {Object} viewDef - View definition
   * @returns {string} Rendered HTML
   */
  function renderCell(column, value, row, viewDef) {
    // Check for special renderer
    if (viewDef.specialRenderers && viewDef.specialRenderers[column]) {
      return viewDef.specialRenderers[column](value, row);
    }

    // Check if it's a link column
    if (viewDef.linkColumns && viewDef.linkColumns.indexOf(column) !== -1) {
      return renderLinkCell(column, value, row, viewDef);
    }

    // Default rendering
    if (value === null || value === undefined) {
      return '<span class="null-value">—</span>';
    }

    return escapeHtml(String(value));
  }

  /**
   * Render a cell as a link
   * @param {string} column - Column name
   * @param {*} value - Cell value
   * @param {Object} row - Full row object
   * @param {Object} viewDef - View definition
   * @returns {string} Link HTML
   */
  function renderLinkCell(column, value, row, viewDef) {
    if (!value) return '<span class="null-value">—</span>';

    // Determine spec from specColumns
    var spec = null;
    if (viewDef.specColumns) {
      // Find corresponding spec column
      var linkIndex = viewDef.linkColumns.indexOf(column);
      if (linkIndex !== -1 && viewDef.specColumns[linkIndex]) {
        spec = row[viewDef.specColumns[linkIndex]];
      }
    }

    if (!spec && row.spec_id) {
      spec = row.spec_id;
    }

    if (!spec) {
      return escapeHtml(String(value));
    }

    var href = '#/' + encodeURIComponent(String(spec)) + '/' + encodeURIComponent(String(value));
    return '<a href="' + escapeHtml(href) + '" class="view-link">' + escapeHtml(String(value)) + '</a>';
  }

  /**
   * Render coverage bar (special renderer)
   * @param {number} value - Percentage value
   * @returns {string} Coverage bar HTML
   */
  function renderCoverageBar(value) {
    if (value === null || value === undefined) {
      return '<span class="null-value">—</span>';
    }

    var pct = parseFloat(value);
    var colorClass = pct >= 80 ? 'good' : (pct >= 50 ? 'partial' : 'poor');

    var html = '<div class="coverage-bar">';
    html += '<div class="coverage-fill ' + colorClass + '" style="width: ' + pct + '%"></div>';
    html += '</div>';
    html += '<div class="coverage-text">';
    html += '<span class="coverage-percentage">' + pct.toFixed(1) + '%</span>';
    html += '</div>';

    return html;
  }

  /**
   * Render pagination controls
   */
  function renderPagination() {
    var container = document.getElementById('view-pagination');
    if (!container || !filteredData) return;

    var totalPages = Math.ceil(filteredData.length / ROWS_PER_PAGE);

    if (totalPages <= 1) {
      container.innerHTML = '';
      return;
    }

    var start = (currentPage - 1) * ROWS_PER_PAGE + 1;
    var end = Math.min(start + ROWS_PER_PAGE - 1, filteredData.length);

    var html = '<div class="view-pagination-info">';
    html += 'Showing ' + start + '-' + end + ' of ' + filteredData.length;
    html += '</div>';
    html += '<div class="view-pagination-controls">';
    html += '<button class="view-pagination-btn" id="btn-first" ' + (currentPage === 1 ? 'disabled' : '') + '>First</button>';
    html += '<button class="view-pagination-btn" id="btn-prev" ' + (currentPage === 1 ? 'disabled' : '') + '>Previous</button>';
    html += '<span class="view-pagination-info">Page ' + currentPage + ' of ' + totalPages + '</span>';
    html += '<button class="view-pagination-btn" id="btn-next" ' + (currentPage === totalPages ? 'disabled' : '') + '>Next</button>';
    html += '<button class="view-pagination-btn" id="btn-last" ' + (currentPage === totalPages ? 'disabled' : '') + '>Last</button>';
    html += '</div>';

    container.innerHTML = html;

    // Add handlers
    var btnFirst = document.getElementById('btn-first');
    var btnPrev = document.getElementById('btn-prev');
    var btnNext = document.getElementById('btn-next');
    var btnLast = document.getElementById('btn-last');

    if (btnFirst) btnFirst.addEventListener('click', function() { goToPage(1); });
    if (btnPrev) btnPrev.addEventListener('click', function() { goToPage(currentPage - 1); });
    if (btnNext) btnNext.addEventListener('click', function() { goToPage(currentPage + 1); });
    if (btnLast) btnLast.addEventListener('click', function() { goToPage(totalPages); });
  }

  /**
   * Update stats display (now handled by pagination)
   */
  function updateStats() {
    // Stats are now displayed in pagination controls
    // This function is kept for backward compatibility
  }

  /**
   * Setup view event handlers
   */
  function setupViewHandlers() {
    // Filter input
    var filterInput = document.getElementById('view-filter');
    if (filterInput) {
      var debounceTimer;
      filterInput.addEventListener('input', function(e) {
        clearTimeout(debounceTimer);
        debounceTimer = setTimeout(function() {
          applyFilter(e.target.value);
        }, 150);
      });
    }

    // Copy CSV button
    var copyBtn = document.getElementById('btn-copy-csv');
    if (copyBtn) {
      copyBtn.addEventListener('click', copyToCSV);
    }
  }

  /**
   * Apply filter to data
   * @param {string} filterText - Filter query
   */
  function applyFilter(filterText) {
    if (!currentData) return;

    var query = filterText.toLowerCase().trim();

    if (!query) {
      filteredData = currentData.slice();
    } else {
      filteredData = currentData.filter(function(row) {
        return Object.values(row).some(function(val) {
          return String(val).toLowerCase().indexOf(query) !== -1;
        });
      });
    }

    currentPage = 1;
    renderTable();
    renderPagination();
    updateStats();
  }

  /**
   * Toggle column sort
   * @param {string} column - Column to sort
   */
  function toggleSort(column) {
    if (sortColumn === column) {
      // Cycle through: asc -> desc -> none
      if (sortDirection === 'asc') {
        sortDirection = 'desc';
      } else if (sortDirection === 'desc') {
        sortColumn = null;
        sortDirection = null;
        filteredData = currentData.slice();
        var filterEl = document.getElementById('view-filter');
        applyFilter(filterEl ? filterEl.value : ''); // Reapply filter
        return;
      }
    } else {
      sortColumn = column;
      sortDirection = 'asc';
    }

    // Sort data
    filteredData.sort(function(a, b) {
      var valA = a[column];
      var valB = b[column];

      // Handle nulls
      if (valA === null || valA === undefined) return 1;
      if (valB === null || valB === undefined) return -1;

      // Compare
      var result = 0;
      if (typeof valA === 'number' && typeof valB === 'number') {
        result = valA - valB;
      } else {
        result = String(valA).localeCompare(String(valB));
      }

      return sortDirection === 'asc' ? result : -result;
    });

    currentPage = 1;
    renderTable();
    renderPagination();
    updateStats();
  }

  /**
   * Go to specific page
   * @param {number} page - Page number
   */
  function goToPage(page) {
    var totalPages = Math.ceil(filteredData.length / ROWS_PER_PAGE);

    if (page < 1 || page > totalPages) return;

    currentPage = page;
    renderTable();
    renderPagination();
    updateStats();

    // Scroll to top of table
    var container = document.querySelector('.view-table-wrapper');
    if (container) {
      container.scrollTop = 0;
    }
  }

  /**
   * Copy table to CSV
   */
  function copyToCSV() {
    if (!filteredData || filteredData.length === 0) return;

    var columns = Object.keys(filteredData[0]);

    // Build CSV
    var csv = columns.map(function(col) {
      return csvEscape(formatColumnName(col));
    }).join(',') + '\n';

    filteredData.forEach(function(row) {
      csv += columns.map(function(col) {
        var val = row[col];
        return csvEscape(val !== null && val !== undefined ? String(val) : '');
      }).join(',') + '\n';
    });

    // Copy to clipboard
    if (navigator.clipboard && navigator.clipboard.writeText) {
      navigator.clipboard.writeText(csv).then(function() {
        showCopyFeedback('Copied to clipboard!');
      }).catch(function(err) {
        console.error('Copy failed:', err);
        showCopyFeedback('Copy failed');
      });
    } else {
      // Fallback for older browsers
      var textarea = document.createElement('textarea');
      textarea.value = csv;
      textarea.style.position = 'fixed';
      textarea.style.opacity = '0';
      document.body.appendChild(textarea);
      textarea.select();
      try {
        document.execCommand('copy');
        showCopyFeedback('Copied to clipboard!');
      } catch (err) {
        console.error('Copy failed:', err);
        showCopyFeedback('Copy failed');
      }
      document.body.removeChild(textarea);
    }
  }

  /**
   * Show copy feedback message
   * @param {string} message - Feedback message
   */
  function showCopyFeedback(message) {
    var btn = document.getElementById('btn-copy-csv');
    if (!btn) return;

    var originalText = btn.textContent;
    btn.textContent = message;
    btn.disabled = true;

    setTimeout(function() {
      btn.textContent = originalText;
      btn.disabled = false;
    }, 2000);
  }

  /**
   * Escape CSV value
   * @param {string} val - Value to escape
   * @returns {string} Escaped value
   */
  function csvEscape(val) {
    if (val.indexOf(',') !== -1 || val.indexOf('"') !== -1 || val.indexOf('\n') !== -1) {
      return '"' + val.replace(/"/g, '""') + '"';
    }
    return val;
  }

  /**
   * Format column name for display
   * @param {string} col - Column name
   * @returns {string} Formatted name
   */
  function formatColumnName(col) {
    return col.split('_').map(function(word) {
      return word.charAt(0).toUpperCase() + word.slice(1);
    }).join(' ');
  }

  /**
   * Render not available message
   * @param {HTMLElement} container - Container element
   * @param {Object} viewDef - View definition
   */
  function renderNotAvailable(container, viewDef) {
    var html = '<div class="view-container">';
    html += '<div class="view-empty-state">';
    html += '<h1>' + escapeHtml(viewDef.title) + '</h1>';
    html += '<p>Database not available. Views require an embedded database.</p>';
    html += '</div>';
    html += '</div>';
    container.innerHTML = html;
  }

  /**
   * Clean up event listeners
   */
  function destroy() {
    currentView = null;
    currentData = null;
    filteredData = null;
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

  // Export public API
  SpecCompiler.Views = {
    init: init,
    renderIndex: renderIndex,
    renderView: renderView,
    destroy: destroy
  };

})();
