/**
 * SpecCompiler Sidebar - Navigation, TOC, and document switching
 * Manages sidebar state, TOC extraction, scroll spy, and mobile toggle
 */

var SpecCompiler = SpecCompiler || {};

(function() {
  'use strict';

  var tocCache = new Map();
  var currentDocId = null;
  var scrollSpyActive = false;
  var scrollSpyRafId = null;
  var scrollSpyTargets = [];
  var highlightedId = null;
  var lastSpyId = null;

  /**
   * Initialize sidebar
   */
  function init() {
    extractTOCs();
    buildDocSelector();
    setupSidebarScrollShadow();
    setupScrollSpy();
    setupCrossDocLinks();
  }

  /**
   * Extract TOCs from all doc sections
   */
  function extractTOCs() {
    var sections = document.querySelectorAll('.doc-section');
    sections.forEach(function(section) {
      var docId = section.id.replace('doc-', '');
      var toc = section.querySelector('nav#TOC');

      if (toc) {
        // Clone and store
        var clone = toc.cloneNode(true);
        tocCache.set(docId, clone);

        // Hide in-document TOC (sidebar owns navigation)
        toc.style.display = 'none';
      }
    });
  }

  /**
   * Build document selector buttons
   */
  function buildDocSelector() {
    var container = document.getElementById('doc-selector');
    if (!container) return;

    var sections = document.querySelectorAll('.doc-section');
    if (sections.length <= 1) {
      container.style.display = 'none';
      return;
    }

    container.className = 'doc-selector';
    container.innerHTML = '';

    var label = document.createElement('div');
    label.className = 'doc-selector-label';
    label.textContent = 'Specifications';

    var select = document.createElement('select');
    select.className = 'doc-selector-select';
    select.id = 'doc-selector-select';
    select.setAttribute('aria-label', 'Select specification');

    sections.forEach(function(section, index) {
      var docId = section.id.replace('doc-', '');
      var title = getDocTitle(section);

      var opt = document.createElement('option');
      opt.value = docId;
      opt.textContent = title;
      select.appendChild(opt);
    });

    select.addEventListener('change', function() {
      var docId = select.value;
      if (SpecCompiler.Router) {
        SpecCompiler.Router.navigate('#/' + docId);
      }
    });

    container.appendChild(label);
    container.appendChild(select);
  }

  /**
   * Get document title from section
   * @param {HTMLElement} section - Document section element
   * @returns {string} Document title
   */
  function getDocTitle(section) {
    // Prefer the rendered specification title over the first section heading.
    var specTitle = section.querySelector('.spec-title');
    if (specTitle) {
      var t = specTitle.textContent.replace(/\s+/g, ' ').trim();
      if (t) return t;
    }

    var docId = section.id.replace('doc-', '');
    return docId.toUpperCase();
  }

  /**
   * Show a specific document
   * @param {string} docId - Document ID to show
   */
  function showDoc(docId) {
    if (currentDocId === docId) return;

    currentDocId = docId;

    // Update doc sections
    var sections = document.querySelectorAll('.doc-section');
    sections.forEach(function(section) {
      var id = section.id.replace('doc-', '');
      if (id === docId) {
        section.classList.add('active');
      } else {
        section.classList.remove('active');
      }
    });

    // Update TOC
    updateTOC(docId);

    // Update doc selector
    var select = document.getElementById('doc-selector-select');
    if (select) {
      select.value = docId;
    }

    // Prime scroll-spy (and inspector-follow) after DOM/layout updates.
    requestAnimationFrame(function() {
      updateScrollSpy();
    });
  }

  /**
   * Update sidebar TOC for a document
   * @param {string} docId - Document ID
   */
  function updateTOC(docId) {
    var container = document.getElementById('sidebar-toc');
    if (!container) return;

    var toc = tocCache.get(docId);
    if (!toc) {
      container.innerHTML = '<p class="no-toc">No table of contents available</p>';
      return;
    }

    // Clone and insert
    var clone = toc.cloneNode(true);
    container.innerHTML = '';
    container.appendChild(clone);

    // Setup click handlers and collapsible sections
    setupTOCInteractivity(container);

    // Build scroll spy targets based on the rendered TOC
    buildScrollSpyTargets(docId);

    // Reset highlight state when switching documents.
    highlightedId = null;
    lastSpyId = null;
  }

  /**
   * Build a list of scroll spy targets based on TOC links.
   * Includes TOC links plus additional in-document object/heading anchors so
   * inspector-follow can track deeper headings not present in the TOC depth.
   * @param {string} docId - Document ID
   */
  function buildScrollSpyTargets(docId) {
    scrollSpyTargets = [];
    lastSpyId = null;

    var section = document.getElementById('doc-' + docId);
    if (!section) return;

    var tocContainer = document.getElementById('sidebar-toc');
    if (!tocContainer) return;

    var seen = Object.create(null);
    function addTarget(id, target) {
      if (!id || !target || seen[id]) return;
      seen[id] = true;
      scrollSpyTargets.push({ id: id, el: target });
    }

    var links = tocContainer.querySelectorAll('a[href^="#"]');
    links.forEach(function(link) {
      var href = link.getAttribute('href');
      if (!href || href.length < 2) return;

      var id = href.slice(1);
      var target = null;
      try {
        target = section.querySelector('#' + CSS.escape(id));
      } catch (e) {
        target = null;
      }

      addTarget(id, target);
    });

    // Extra anchors for follow-mode: deeper headings / object headers not listed in TOC.
    var extras = section.querySelectorAll(
      '.spec-object-header[id], h1[id], h2[id], h3[id], h4[id], h5[id], h6[id]'
    );
    extras.forEach(function(el) {
      var id = el.id;
      addTarget(id, el);
    });
  }

  /**
   * Setup TOC interactivity - clicks, collapsible sections
   * @param {HTMLElement} container - TOC container
   */
  function setupTOCInteractivity(container) {
    var links = container.querySelectorAll('a');

    links.forEach(function(link) {
      // Add click handler
      link.addEventListener('click', function(e) {
        var href = link.getAttribute('href');
        if (href && href.startsWith('#')) {
          e.preventDefault();
          var elementId = href.substring(1);

          // Navigate via router
          if (SpecCompiler.Router && currentDocId) {
            SpecCompiler.Router.navigate('#/' + currentDocId + '/' + elementId);
          }
        }
      });

      // Add collapsible arrow if has children
      var li = link.parentElement;
      var childUl = li ? li.querySelector('ul') : null;
      if (childUl) {
        childUl.className = 'toc-children';

        var arrow = document.createElement('span');
        arrow.className = 'toc-toggle toc-toggle-expanded';
        arrow.innerHTML = '<svg viewBox="0 0 16 16"><polyline points="6 4 10 8 6 12"/></svg>';
        arrow.setAttribute('role', 'button');
        arrow.setAttribute('aria-label', 'Toggle section');
        arrow.addEventListener('click', function(e) {
          e.preventDefault();
          e.stopPropagation();
          childUl.classList.toggle('collapsed');
          arrow.classList.toggle('toc-toggle-expanded', !childUl.classList.contains('collapsed'));
        });

        link.insertBefore(arrow, link.firstChild);
      }
    });
  }

  /**
   * Highlight a specific TOC item
   * @param {string} id - Element ID to highlight
   */
  function highlightTocItem(id) {
    var container = document.getElementById('sidebar-toc');
    if (!container) return;

    if (highlightedId === id) return;
    highlightedId = id;

    // Remove existing highlights
    var active = container.querySelectorAll('.active');
    active.forEach(function(el) {
      el.classList.remove('active');
    });

    // Find and highlight matching link
    var link = container.querySelector('a[href="#' + id + '"]');
    if (link) {
      link.classList.add('active');

      // Expand parent sections
      var parent = link.parentElement;
      while (parent && parent !== container) {
        if (parent.tagName === 'UL' && parent.classList.contains('toc-children')) {
          parent.classList.remove('collapsed');
          // Find the toggle in the parent LI
          var parentLi = parent.parentElement;
          if (parentLi) {
            var toggle = parentLi.querySelector('.toc-toggle');
            if (toggle) {
              toggle.classList.add('toc-toggle-expanded');
            }
          }
        }
        parent = parent.parentElement;
      }

      // Scroll into view in sidebar
      link.scrollIntoView({ block: 'nearest', behavior: 'auto' });
    }
  }

  /**
   * Setup scroll spy to highlight current section
   */
  function setupScrollSpy() {
    var content = document.querySelector('.content');
    if (!content) return;

    content.addEventListener('scroll', onContentScroll);
    scrollSpyActive = true;
  }

  /**
   * Add a subtle shadow under the fixed sidebar top area when the sidebar content scrolls.
   * This prevents the TOC from visually blending into the doc selector/search area on long TOCs.
   */
  function setupSidebarScrollShadow() {
    var sidebar = document.querySelector('.sidebar');
    var scroller = document.getElementById('sidebar-scroll');
    if (!sidebar || !scroller) return;

    var rafId = null;
    function update() {
      rafId = null;
      sidebar.classList.toggle('shadow-top', scroller.scrollTop > 0);
    }

    scroller.addEventListener('scroll', function() {
      if (rafId) return;
      rafId = requestAnimationFrame(update);
    });

    update();
  }

  /**
   * Content scroll handler (throttled via RAF)
   */
  function onContentScroll() {
    if (scrollSpyRafId) return;

    scrollSpyRafId = requestAnimationFrame(function() {
      updateScrollSpy();
      scrollSpyRafId = null;
    });
  }

  /**
   * Update scroll spy highlighting
   */
  function updateScrollSpy() {
    if (!currentDocId) return;

    var section = document.getElementById('doc-' + currentDocId);
    if (!section || !section.classList.contains('active')) return;

    var content = document.querySelector('.content');
    if (!content) return;

    // Use a small offset so the active section updates early as the user scrolls.
    // The header is outside the scroll container, so this does not need to match header height.
    var offset = 16;

    var currentId = null;
    var bestTop = -Infinity;
    var contentRect = content.getBoundingClientRect();

    // Find the TOC target closest to (but not below) the visible top edge.
    // This does not rely on offsetTop ordering (which can vary with nested offsetParents).
    for (var i = 0; i < scrollSpyTargets.length; i++) {
      var target = scrollSpyTargets[i];
      if (!target || !target.el) continue;

      var rect = target.el.getBoundingClientRect();
      if (rect.top <= contentRect.top + offset && rect.top > bestTop) {
        bestTop = rect.top;
        currentId = target.id;
      }
    }

    // At the very top of a document, the first heading may still be below the offset.
    // In that case, pick the first TOC target so follow/highlight isn't "stuck".
    if (!currentId && scrollSpyTargets.length > 0) {
      currentId = scrollSpyTargets[0].id;
    }

    if (currentId) {
      highlightTocItem(currentId);
      if (currentId !== lastSpyId) {
        lastSpyId = currentId;
        emitActiveElement(currentDocId, currentId);
      }
    }
  }

  function emitActiveElement(specId, elementId) {
    try {
      var ev = new CustomEvent('speccompiler:active-element', {
        detail: { specId: specId, elementId: elementId }
      });
      document.dispatchEvent(ev);
    } catch (e) {
      // CustomEvent may not exist in very old browsers (non-goal for this app).
    }
  }

  /**
   * Toggle mobile sidebar visibility
   */
  function toggleMobile() {
    var sidebar = document.querySelector('.sidebar');
    if (sidebar) {
      sidebar.classList.toggle('open');
    }
  }

  /**
   * Setup cross-document link interception
   */
  function setupCrossDocLinks() {
    document.addEventListener('click', function(e) {
      var target = e.target;

      // Find closest anchor
      while (target && target.tagName !== 'A') {
        target = target.parentElement;
      }

      if (!target) return;

      var href = target.getAttribute('href');
      if (!href) return;

      // Match pattern: xxx.html#yyy or xxx.html
      var match = href.match(/^([^.]+)\.html(?:#(.+))?$/);
      if (match) {
        e.preventDefault();
        var docId = match[1];
        var elementId = match[2];

        if (SpecCompiler.Router) {
          if (elementId) {
            SpecCompiler.Router.navigate('#/' + docId + '/' + elementId);
          } else {
            SpecCompiler.Router.navigate('#/' + docId);
          }
        }
      }
    });
  }

  /**
   * Escape HTML special characters
   * @param {string} str - String to escape
   * @returns {string} Escaped string
   */
  function escapeHtml(str) {
    var div = document.createElement('div');
    div.textContent = str;
    return div.innerHTML;
  }

  // Export public API
  SpecCompiler.Sidebar = {
    init: init,
    showDoc: showDoc,
    updateTOC: updateTOC,
    highlightTocItem: highlightTocItem,
    toggleMobile: toggleMobile
  };

})();
