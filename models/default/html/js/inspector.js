/**
 * SpecCompiler Inspector - Right-side contextual pane
 * Shows metadata, attributes, and traceability links for the current route selection.
 */

var SpecCompiler = SpecCompiler || {};

(function() {
  'use strict';

  var db = null;
  var lastRoute = null;
  var navHistory = [];
  var MAX_HISTORY = 50;

  var titleEl = null;
  var bodyEl = null;
  var followBtn = null;
  var backBtn = null;
  var followEnabled = true;
  var lastFollowKey = null;

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

  function setFollowEnabled(enabled) {
    followEnabled = !!enabled;
    saveBool('speccompiler_inspector_follow', followEnabled);
    updateFollowUi();
  }

  function updateFollowUi() {
    if (!followBtn) return;
    followBtn.setAttribute('aria-pressed', followEnabled ? 'true' : 'false');
    followBtn.textContent = followEnabled ? 'Follow' : 'Pinned';
  }

  function init() {
    titleEl = document.getElementById('inspector-title');
    bodyEl = document.getElementById('inspector-body');
    followBtn = document.getElementById('inspector-follow-toggle');
    backBtn = document.getElementById('inspector-back-btn');

    followEnabled = loadBool('speccompiler_inspector_follow', true);
    updateFollowUi();
    updateBackBtn();

    if (backBtn) {
      backBtn.addEventListener('click', goBack);
    }
    if (followBtn) {
      followBtn.addEventListener('click', function() {
        setFollowEnabled(!followEnabled);
      });
    }
    if (bodyEl) {
      bodyEl.addEventListener('click', onInspectorBodyClick);
    }

    // When enabled, follow the currently visible section/object as the user scrolls.
    document.addEventListener('speccompiler:active-element', function(ev) {
      if (!followEnabled) return;

      var d = ev && ev.detail ? ev.detail : null;
      if (!d || !d.specId || !d.elementId) return;

      // Don't override inspector when inspecting an explicit view payload.
      if (lastRoute && lastRoute.type === 'stored-view') return;

      var key = String(d.specId) + '::' + String(d.elementId);
      if (key === lastFollowKey) return;
      lastFollowKey = key;

      // Update without mutating the URL hash.
      lastRoute = { type: 'element', spec: d.specId, elementId: d.elementId };
      renderElement(d.specId, d.elementId);
    });

    renderEmpty();
  }

  function setDatabase(database) {
    db = database;
    // Refresh current view with richer data.
    if (lastRoute) {
      update(lastRoute);
    }
  }

  function pushHistory(route) {
    if (!route) return;
    navHistory.push(route);
    if (navHistory.length > MAX_HISTORY) {
      navHistory.splice(0, navHistory.length - MAX_HISTORY);
    }
  }

  function isSameRoute(a, b) {
    if (!a || !b) return false;
    if (a.type !== b.type || a.spec !== b.spec) return false;
    if (a.type === 'element') return a.elementId === b.elementId;
    if (a.type === 'stored-view') return a.viewId === b.viewId;
    return true;
  }

  function goBack() {
    if (!navHistory.length) return;
    lastRoute = navHistory.pop();
    renderRoute(lastRoute);
    updateBackBtn();
  }

  function updateBackBtn() {
    if (!backBtn) return;
    if (navHistory.length > 0) {
      backBtn.removeAttribute('hidden');
    } else {
      backBtn.setAttribute('hidden', '');
    }
  }

  function renderRoute(route) {
    if (!route) { renderEmpty(); return; }
    if (route.type === 'doc') { renderDoc(route.spec); return; }
    if (route.type === 'element') { renderElement(route.spec, route.elementId); return; }
    if (route.type === 'stored-view') { renderStoredView(route.spec, route.viewId); return; }
    renderEmpty();
  }

  function update(route) {
    if (!titleEl || !bodyEl || !route) return;

    if (lastRoute && !isSameRoute(lastRoute, route)) {
      pushHistory(lastRoute);
    }
    lastRoute = route;

    renderRoute(route);
    updateBackBtn();
  }

  function renderEmpty() {
    if (!titleEl || !bodyEl) return;
    titleEl.textContent = 'Inspector';
    bodyEl.innerHTML = '<div class="inspector-empty">Select an item to see details.</div>';
  }

  function renderDoc(specId) {
    titleEl.textContent = (specId || 'Docs').toUpperCase();

    if (!db || !specId) {
      bodyEl.innerHTML = [
        '<div class="inspector-section">',
        '  <h3>Document</h3>',
        '  <dl class="inspector-kv">',
        '    <dt>ID</dt><dd>' + escapeHtml(String(specId || '')) + '</dd>',
        '  </dl>',
        '</div>',
        '<div class="inspector-empty">Database not available. Run `bash scripts/build.sh --install` (or `bash scripts/install.sh`) to build vendor dependencies for search/filters.</div>'
      ].join('');
      return;
    }

    var specRows = safeSelect(
      'SELECT identifier, long_name, type_ref, pid FROM specifications WHERE identifier = ? LIMIT 1',
      [specId]
    );
    var spec = (specRows && specRows[0]) ? specRows[0] : null;

    var counts = safeSelect(
      'SELECT type_ref, COUNT(*) AS count FROM spec_objects WHERE specification_ref = ? GROUP BY type_ref ORDER BY count DESC',
      [specId]
    ) || [];

    var html = '';
    html += '<div class="inspector-section">';
    html += '<h3>Document</h3>';
    html += '<dl class="inspector-kv">';
    html += '<dt>ID</dt><dd>' + escapeHtml(specId) + '</dd>';
    if (spec) {
      if (spec.long_name) html += '<dt>Title</dt><dd>' + escapeHtml(spec.long_name) + '</dd>';
      if (spec.type_ref) html += '<dt>Type</dt><dd>' + escapeHtml(spec.type_ref) + '</dd>';
      if (spec.pid) html += '<dt>PID</dt><dd>' + escapeHtml(spec.pid) + '</dd>';
    }
    html += '</dl>';
    html += '</div>';

    if (counts.length) {
      html += '<div class="inspector-section">';
      html += '<h3>Inventory</h3>';
      html += '<dl class="inspector-kv">';
      counts.slice(0, 12).forEach(function(row) {
        html += '<dt>' + escapeHtml(String(row.type_ref || '')) + '</dt><dd>' + escapeHtml(String(row.count || 0)) + '</dd>';
      });
      html += '</dl>';
      html += '</div>';
    }

    bodyEl.innerHTML = html;
  }

  function renderElement(specId, elementIdRaw) {
    var elementId = decodeSafe(elementIdRaw);
    titleEl.textContent = elementId ? elementId : 'Selection';

    if (!db || !specId || !elementId) {
      bodyEl.innerHTML = '<div class="inspector-empty">No selection details available.</div>';
      return;
    }

    var objRows = safeSelect(
      'SELECT id, pid, label, type_ref, title_text, from_file, start_line, end_line ' +
      'FROM spec_objects ' +
      'WHERE specification_ref = ? AND (' +
      '  pid = ? OR label = ? OR ' +
      "  (type_ref = 'SECTION' AND label LIKE 'section:%' AND substr(label, instr(label, ':')+1) = ?)" +
      ') ' +
      'LIMIT 1',
      [specId, elementId, elementId, elementId]
    );

    var obj = (objRows && objRows[0]) ? objRows[0] : null;
    if (!obj) {
      // Fallback: floats (figures/tables/listings) use their anchor as the HTML id.
      var floatRows = safeSelect(
        'SELECT id, specification_ref, type_ref, label, anchor, caption, from_file, start_line, parent_object_id, ' +
        '       pandoc_attributes, raw_content, raw_ast, resolved_ast ' +
        'FROM spec_floats ' +
        'WHERE specification_ref = ? AND (anchor = ? OR label = ? OR CAST(id AS TEXT) = ?) ' +
        'LIMIT 1',
        [specId, elementId, elementId, elementId]
      );
      var fl = (floatRows && floatRows[0]) ? floatRows[0] : null;
      if (fl) {
        renderFloat(specId, elementId, fl);
        return;
      }

      bodyEl.innerHTML = [
        '<div class="inspector-section">',
        '  <h3>Selection</h3>',
        '  <dl class="inspector-kv">',
        '    <dt>Spec</dt><dd>' + escapeHtml(specId) + '</dd>',
        '    <dt>ID</dt><dd>' + escapeHtml(elementId) + '</dd>',
        '  </dl>',
        '</div>',
        '<div class="inspector-empty">No metadata found for this anchor.</div>',
      ].join('');
      return;
    }

    // Attributes
    var attrs = safeSelect(
      'SELECT name, datatype, string_value, int_value, real_value, bool_value, date_value, enum_ref, raw_value, ast ' +
      'FROM spec_attribute_values WHERE owner_object_id = ? ORDER BY name',
      [obj.id]
    ) || [];

    // Child floats scoped to this object.
    var floats = safeSelect(
      'SELECT id, specification_ref, type_ref, label, anchor, caption, from_file, start_line, ' +
      '       pandoc_attributes, raw_content, raw_ast, resolved_ast ' +
      'FROM spec_floats WHERE parent_object_id = ? ORDER BY file_seq LIMIT 24',
      [obj.id]
    ) || [];

    // Views in the same file/range (line-scoped when available).
    var views = loadViewsForObject(specId, obj);

    // Relations (inbound/outbound)
    var outbound = safeSelect(
      'SELECT r.type_ref, COALESCE(rt.long_name, r.type_ref, \'link\') AS rel_name, ' +
       '       r.target_text, r.is_ambiguous, ' +
       '       so.specification_ref AS target_spec, so.pid AS target_pid, so.title_text AS target_title, ' +
       '       sf.specification_ref AS float_spec, sf.anchor AS float_anchor, sf.label AS float_label, sf.caption AS float_caption ' +
      'FROM spec_relations r ' +
      'LEFT JOIN spec_relation_types rt ON rt.identifier = r.type_ref ' +
      'LEFT JOIN spec_objects so ON so.id = r.target_object_id ' +
      'LEFT JOIN spec_floats sf ON sf.id = r.target_float_id ' +
      'WHERE r.source_object_id = ? ' +
      'ORDER BY rel_name, target_spec, target_pid, float_label, r.target_text ' +
      'LIMIT 100',
      [obj.id]
    ) || [];

    var inbound = safeSelect(
      'SELECT r.type_ref, COALESCE(rt.long_name, r.type_ref, \'link\') AS rel_name, ' +
       '       r.target_text, r.is_ambiguous, ' +
       '       so.specification_ref AS source_spec, so.pid AS source_pid, so.title_text AS source_title, ' +
       '       NULL AS float_spec, NULL AS float_anchor, NULL AS float_label, NULL AS float_caption ' +
      'FROM spec_relations r ' +
      'LEFT JOIN spec_relation_types rt ON rt.identifier = r.type_ref ' +
      'LEFT JOIN spec_objects so ON so.id = r.source_object_id ' +
      'WHERE r.target_object_id = ? ' +
      'ORDER BY rel_name, source_spec, source_pid, r.target_text ' +
      'LIMIT 100',
      [obj.id]
    ) || [];

    var html = '';

    html += '<div class="inspector-section">';
    html += '<h3>Properties</h3>';
    html += '<dl class="inspector-kv">';
    html += '<dt>Spec</dt><dd>' + escapeHtml(specId) + '</dd>';
    html += '<dt>Type</dt><dd>' + escapeHtml(String(obj.type_ref || '')) + '</dd>';
    if (obj.pid) html += '<dt>PID</dt><dd>' + escapeHtml(obj.pid) + '</dd>';
    if (obj.title_text) html += '<dt>Title</dt><dd>' + escapeHtml(obj.title_text) + '</dd>';
    if (obj.from_file) html += '<dt>File</dt><dd>' + escapeHtml(obj.from_file) + '</dd>';
    if (obj.start_line) html += '<dt>Line</dt><dd>' + escapeHtml(String(obj.start_line)) + '</dd>';
    html += '</dl>';
    html += '</div>';

    if (attrs.length) {
      html += '<div class="inspector-section">';
      html += '<h3>Attributes</h3>';
      html += '<dl class="inspector-kv">';
      attrs.slice(0, 24).forEach(function(a) {
        html += '<dt>' + escapeHtml(String(a.name || '')) + '</dt><dd>' + escapeHtml(formatAttrValue(a)) + '</dd>';
      });
      if (attrs.length > 24) {
        html += '<dt></dt><dd class="inspector-empty">+' + escapeHtml(String(attrs.length - 24)) + ' more</dd>';
      }
      html += '</dl>';
      html += '</div>';
    }

    html += renderArtifactSection('Floats', floats, renderFloatArtifact, 'No floats in this object.');
    html += renderArtifactSection('Views', views, renderViewArtifact, 'No views in this object scope.');
    html += renderRelationSection('Outbound', outbound, true);
    html += renderRelationSection('Inbound', inbound, false);

    bodyEl.innerHTML = html;
  }

  function renderFloat(specId, elementId, fl) {
    titleEl.textContent = elementId ? elementId : (fl.label || 'Float');

    var parent = null;
    if (fl.parent_object_id) {
      var parentRows = safeSelect(
        'SELECT specification_ref, pid, title_text, type_ref FROM spec_objects WHERE id = ? LIMIT 1',
        [fl.parent_object_id]
      );
      parent = (parentRows && parentRows[0]) ? parentRows[0] : null;
    }

    var attrs = safeSelect(
      'SELECT name, datatype, string_value, int_value, real_value, bool_value, date_value, enum_ref, raw_value, ast ' +
      'FROM spec_attribute_values WHERE owner_float_id = ? ORDER BY name',
      [fl.id]
    ) || [];

    var inbound = safeSelect(
      'SELECT r.type_ref, COALESCE(rt.long_name, r.type_ref, \'link\') AS rel_name, ' +
       '       r.target_text, r.is_ambiguous, ' +
       '       so.specification_ref AS source_spec, so.pid AS source_pid, so.title_text AS source_title, ' +
       '       NULL AS float_spec, NULL AS float_anchor, NULL AS float_label, NULL AS float_caption ' +
      'FROM spec_relations r ' +
      'LEFT JOIN spec_relation_types rt ON rt.identifier = r.type_ref ' +
      'LEFT JOIN spec_objects so ON so.id = r.source_object_id ' +
      'WHERE r.target_float_id = ? ' +
      'ORDER BY rel_name, source_spec, source_pid, r.target_text ' +
      'LIMIT 100',
      [fl.id]
    ) || [];

    var html = '';
    html += '<div class="inspector-section">';
    html += '<h3>Float</h3>';
    html += '<dl class="inspector-kv">';
    html += '<dt>Spec</dt><dd>' + escapeHtml(specId) + '</dd>';
    html += '<dt>Type</dt><dd>' + escapeHtml(String(fl.type_ref || '')) + '</dd>';
    if (fl.label) html += '<dt>Label</dt><dd>' + escapeHtml(String(fl.label)) + '</dd>';
    if (fl.anchor) html += '<dt>Anchor</dt><dd>' + escapeHtml(String(fl.anchor)) + '</dd>';
    if (fl.caption) html += '<dt>Caption</dt><dd>' + escapeHtml(String(fl.caption)) + '</dd>';
    if (fl.from_file) html += '<dt>File</dt><dd>' + escapeHtml(String(fl.from_file)) + '</dd>';
    if (fl.start_line) html += '<dt>Line</dt><dd>' + escapeHtml(String(fl.start_line)) + '</dd>';
    if (parent && parent.pid && parent.specification_ref) {
      var parentHref = '#/' + encodeURIComponent(String(parent.specification_ref)) + '/' + encodeURIComponent(String(parent.pid));
      html += '<dt>Parent</dt><dd><a class="inspector-link" href="' + escapeHtml(parentHref) + '">' + escapeHtml(String(parent.pid)) + (parent.title_text ? ': ' + escapeHtml(String(parent.title_text)) : '') + '</a></dd>';
    }
    html += '</dl>';
    html += '</div>';

    if (attrs.length) {
      html += '<div class="inspector-section">';
      html += '<h3>Attributes</h3>';
      html += '<dl class="inspector-kv">';
      attrs.slice(0, 24).forEach(function(a) {
        html += '<dt>' + escapeHtml(String(a.name || '')) + '</dt><dd>' + escapeHtml(formatAttrValue(a)) + '</dd>';
      });
      if (attrs.length > 24) {
        html += '<dt></dt><dd class="inspector-empty">+' + escapeHtml(String(attrs.length - 24)) + ' more</dd>';
      }
      html += '</dl>';
      html += '</div>';
    }

    html += renderArtifactSection('Raw Payload', [fl], renderFloatArtifact, 'No raw payload available.');
    html += renderRelationSection('Inbound', inbound, false);
    bodyEl.innerHTML = html;
  }

  function renderStoredView(specId, viewId) {
    var rows = safeSelect(
      'SELECT id, specification_ref, view_type_ref, from_file, start_line, file_seq, raw_ast, resolved_ast, resolved_data ' +
      'FROM spec_views WHERE specification_ref = ? AND id = ? LIMIT 1',
      [specId, viewId]
    ) || [];
    var view = rows[0];

    if (!view) {
      titleEl.textContent = 'View';
      bodyEl.innerHTML = '<div class="inspector-empty">View metadata not found.</div>';
      return;
    }

    titleEl.textContent = String(view.view_type_ref || 'View') + ' #' + String(view.id);

    var html = '';
    html += '<div class="inspector-section">';
    html += '<h3>View</h3>';
    html += '<dl class="inspector-kv">';
    html += '<dt>Spec</dt><dd>' + escapeHtml(String(view.specification_ref || specId || '')) + '</dd>';
    html += '<dt>Type</dt><dd>' + escapeHtml(String(view.view_type_ref || '')) + '</dd>';
    html += '<dt>ID</dt><dd>' + escapeHtml(String(view.id)) + '</dd>';
    if (view.from_file) html += '<dt>File</dt><dd>' + escapeHtml(String(view.from_file)) + '</dd>';
    if (view.start_line) html += '<dt>Line</dt><dd>' + escapeHtml(String(view.start_line)) + '</dd>';
    html += '</dl>';
    html += '</div>';

    html += renderRawPayloadSection(getViewRawEntries(view));
    bodyEl.innerHTML = html;
  }

  function renderArtifactSection(title, items, itemRenderer, emptyText) {
    var rows = items || [];
    var html = '';
    html += '<div class="inspector-section">';
    html += '<h3>' + escapeHtml(String(title || 'Items')) + ' (' + escapeHtml(String(rows.length)) + ')</h3>';

    if (!rows.length) {
      html += '<div class="inspector-empty">' + escapeHtml(String(emptyText || 'None')) + '</div>';
      html += '</div>';
      return html;
    }

    html += '<div class="inspector-artifacts">';
    rows.slice(0, 24).forEach(function(item) {
      html += itemRenderer(item);
    });
    if (rows.length > 24) {
      html += '<div class="inspector-empty">+' + escapeHtml(String(rows.length - 24)) + ' more</div>';
    }
    html += '</div>';
    html += '</div>';
    return html;
  }

  function renderFloatArtifact(fl) {
    var target = fl.anchor || fl.label || String(fl.id || '');
    var href = (fl.specification_ref && target)
      ? '#/' + encodeURIComponent(String(fl.specification_ref)) + '/' + encodeURIComponent(String(target))
      : null;

    var html = '';
    html += '<div class="inspector-artifact">';
    if (href) {
      html += '<a class="inspector-link" href="' + escapeHtml(href) + '">';
    } else {
      html += '<div class="inspector-link">';
    }
    html += '<span class="rel-type">FLOAT</span>';
    html += '<span>' + escapeHtml(String(target || 'float')) + (fl.caption ? ': ' + escapeHtml(String(fl.caption)) : '') + '</span>';
    html += href ? '</a>' : '</div>';

    html += '<dl class="inspector-kv">';
    html += '<dt>Type</dt><dd>' + escapeHtml(String(fl.type_ref || '')) + '</dd>';
    if (fl.start_line) html += '<dt>Line</dt><dd>' + escapeHtml(String(fl.start_line)) + '</dd>';
    html += '</dl>';
    html += renderRawPayloadEntries(getFloatRawEntries(fl));
    html += '</div>';
    return html;
  }

  function renderViewArtifact(view) {
    var html = '';
    html += '<div class="inspector-artifact">';
    html += '<button type="button" class="inspector-link inspector-action" ' +
      'data-inspect-kind="view" data-spec-id="' + escapeHtml(String(view.specification_ref || '')) + '" ' +
      'data-view-id="' + escapeHtml(String(view.id || '')) + '">';
    html += '<span class="rel-type">VIEW</span>';
    html += '<span>' + escapeHtml(String(view.view_type_ref || 'VIEW')) + ' #' + escapeHtml(String(view.id || '')) + '</span>';
    html += '</button>';

    html += '<dl class="inspector-kv">';
    if (view.start_line) html += '<dt>Line</dt><dd>' + escapeHtml(String(view.start_line)) + '</dd>';
    if (view.from_file) html += '<dt>File</dt><dd>' + escapeHtml(String(view.from_file)) + '</dd>';
    html += '</dl>';
    html += renderRawPayloadEntries(getViewRawEntries(view));
    html += '</div>';
    return html;
  }

  function renderRawPayloadSection(entries) {
    var html = '';
    html += '<div class="inspector-section">';
    html += '<h3>Raw Values</h3>';
    html += renderRawPayloadEntries(entries || []);
    html += '</div>';
    return html;
  }

  function renderRawPayloadEntries(entries) {
    var html = '';
    var hasEntries = false;
    (entries || []).forEach(function(entry) {
      var formatted = formatRawValue(entry ? entry.value : null);
      if (!formatted) return;
      hasEntries = true;
      html += '<details class="inspector-raw-entry">';
      html += '<summary>' + escapeHtml(String(entry.label || 'Raw')) + '</summary>';
      html += '<pre class="inspector-raw-value">' + escapeHtml(formatted) + '</pre>';
      html += '</details>';
    });

    if (!hasEntries) {
      html += '<div class="inspector-empty">No raw values.</div>';
    }
    return html;
  }

  function getFloatRawEntries(fl) {
    return [
      { label: 'Raw Content', value: fl.raw_content },
      { label: 'Raw AST', value: fl.raw_ast },
      { label: 'Resolved AST', value: fl.resolved_ast },
      { label: 'Pandoc Attributes', value: fl.pandoc_attributes },
    ];
  }

  function getViewRawEntries(view) {
    return [
      { label: 'Raw Value', value: view.raw_ast },
      { label: 'Resolved AST', value: view.resolved_ast },
      { label: 'Resolved Data', value: view.resolved_data },
    ];
  }

  function formatRawValue(value) {
    if (value == null) return '';
    var raw = String(value);
    if (!raw.trim()) return '';

    var trimmed = raw.trim();
    var first = trimmed.charAt(0);
    if (first === '{' || first === '[' || first === '"') {
      try {
        var parsed = JSON.parse(trimmed);
        if (typeof parsed === 'string') return parsed;
        return JSON.stringify(parsed, null, 2);
      } catch (e) {
        return raw;
      }
    }
    return raw;
  }

  function loadViewsForObject(specId, obj) {
    if (!specId || !obj || !obj.from_file) return [];

    // Require both start_line and end_line for meaningful view scoping.
    // Without a line range we can't tell which views belong to this object.
    if (obj.start_line == null || obj.end_line == null) return [];

    return safeSelect(
      'SELECT id, specification_ref, view_type_ref, from_file, start_line, file_seq, raw_ast, resolved_ast, resolved_data ' +
      'FROM spec_views WHERE specification_ref = ? AND from_file = ? ' +
      'AND start_line IS NOT NULL AND start_line BETWEEN ? AND ? ' +
      'ORDER BY start_line, file_seq LIMIT 24',
      [specId, obj.from_file, obj.start_line, obj.end_line]
    ) || [];
  }

  function onInspectorBodyClick(ev) {
    var target = ev.target;
    while (target && target !== bodyEl) {
      var kind = target.getAttribute ? target.getAttribute('data-inspect-kind') : null;
      if (kind === 'view') {
        ev.preventDefault();
        inspectView(target.getAttribute('data-spec-id'), target.getAttribute('data-view-id'));
        return;
      }
      target = target.parentElement;
    }
  }

  function inspectView(specId, viewIdRaw) {
    var viewId = Number(viewIdRaw);
    if (!specId || !Number.isFinite(viewId)) return;
    var newRoute = { type: 'stored-view', spec: specId, viewId: viewId };
    if (lastRoute && !isSameRoute(lastRoute, newRoute)) {
      pushHistory(lastRoute);
    }
    lastRoute = newRoute;
    renderStoredView(specId, viewId);
    updateBackBtn();
  }

  function renderRelationSection(title, rels, isOutbound) {
    var html = '';
    html += '<div class="inspector-section">';
    html += '<h3>' + escapeHtml(title) + ' (' + escapeHtml(String((rels || []).length)) + ')</h3>';

    if (!rels || rels.length === 0) {
      html += '<div class="inspector-empty">No links</div>';
      html += '</div>';
      return html;
    }

    html += '<div class="inspector-links">';

    rels.slice(0, 40).forEach(function(r) {
      var relType = String(r.rel_name || r.type_ref || 'link');
      var target = isOutbound ? formatRelationTarget(r) : formatRelationSource(r);
      var href = target.href;
      var label = target.label;

      if (href) {
        html += '<a class="inspector-link" href="' + escapeHtml(href) + '">';
      } else {
        html += '<div class="inspector-link">';
      }

      html += '<span class="rel-type">' + escapeHtml(relType) + '</span>';
      html += '<span>' + escapeHtml(label) + '</span>';

      if (href) {
        html += '</a>';
      } else {
        html += '</div>';
      }
    });

    if (rels.length > 40) {
      html += '<div class="inspector-empty">+' + escapeHtml(String(rels.length - 40)) + ' more</div>';
    }

    html += '</div>';
    html += '</div>';
    return html;
  }

  function formatRelationTarget(r) {
    if (r.target_pid && r.target_spec) {
      return {
        href: '#/' + encodeURIComponent(String(r.target_spec)) + '/' + encodeURIComponent(String(r.target_pid)),
        label: String(r.target_pid) + (r.target_title ? ': ' + String(r.target_title) : '')
      };
    }

    if (r.float_spec && (r.float_anchor || r.float_label)) {
      var anchor = r.float_anchor || r.float_label;
      return {
        href: '#/' + encodeURIComponent(String(r.float_spec)) + '/' + encodeURIComponent(String(anchor)),
        label: String(anchor) + (r.float_caption ? ': ' + String(r.float_caption) : '')
      };
    }

    return {
      href: null,
      label: String(r.target_text || '(unresolved)')
    };
  }

  function formatRelationSource(r) {
    if (r.source_pid && r.source_spec) {
      return {
        href: '#/' + encodeURIComponent(String(r.source_spec)) + '/' + encodeURIComponent(String(r.source_pid)),
        label: String(r.source_pid) + (r.source_title ? ': ' + String(r.source_title) : '')
      };
    }

    if (r.float_spec && (r.float_anchor || r.float_label)) {
      var anchor = r.float_anchor || r.float_label;
      return {
        href: '#/' + encodeURIComponent(String(r.float_spec)) + '/' + encodeURIComponent(String(anchor)),
        label: String(anchor) + (r.float_caption ? ': ' + String(r.float_caption) : '')
      };
    }

    return {
      href: null,
      label: String(r.target_text || '(unresolved)')
    };
  }

	  function formatAttrValue(a) {
	    if (!a) return '';

	    // Prefer typed values, fall back to raw.
	    if (a.string_value != null) return String(a.string_value);
	    if (a.int_value != null) return String(a.int_value);
	    if (a.real_value != null) return String(a.real_value);
	    if (a.date_value != null) return String(a.date_value);
	    if (a.bool_value != null) return a.bool_value ? 'true' : 'false';
	    if (a.enum_ref != null) return String(a.enum_ref);
	    if (a.raw_value != null) return String(a.raw_value);
	    return '';
	  }

  function stripHtml(html) {
    // Conservative: render rich content as plain text inside inspector.
    var div = document.createElement('div');
    div.innerHTML = html;
    return (div.textContent || '').trim();
  }

  function safeSelect(sql, params) {
    try {
      if (!db || !db.selectObjects) return null;
      return db.selectObjects(sql, params);
    } catch (e) {
      console.warn('Inspector query failed:', e);
      return null;
    }
  }

  function decodeSafe(s) {
    if (!s) return '';
    try {
      return decodeURIComponent(String(s));
    } catch (e) {
      return String(s);
    }
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

  SpecCompiler.Inspector = {
    init: init,
    update: update,
    setDatabase: setDatabase
  };

})();
