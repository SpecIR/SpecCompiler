/**
 * SpecCompiler Theme - Light/Dark mode switching
 * Manages theme state, persistence, and system preference sync
 */

var SpecCompiler = SpecCompiler || {};

(function() {
  'use strict';

  var STORAGE_KEY = 'speccompiler-theme';
  var currentTheme = null;
  var userHasExplicitChoice = false;

  /**
   * Initialize theme system
   */
  function init() {
    // Check for saved theme preference
    var savedTheme = localStorage.getItem(STORAGE_KEY);

    if (savedTheme) {
      userHasExplicitChoice = true;
      currentTheme = savedTheme;
      apply(currentTheme);
    } else {
      // Use system preference
      currentTheme = getSystemPreference();
      apply(currentTheme);
      listenToSystemChanges();
    }
  }

  /**
   * Toggle between light and dark themes
   */
  function toggle() {
    var newTheme = currentTheme === 'light' ? 'dark' : 'light';
    set(newTheme);
  }

  /**
   * Set a specific theme
   * @param {string} mode - 'light' or 'dark'
   */
  function set(mode) {
    if (mode !== 'light' && mode !== 'dark') {
      console.warn('Invalid theme mode:', mode);
      return;
    }

    currentTheme = mode;
    userHasExplicitChoice = true;
    localStorage.setItem(STORAGE_KEY, mode);
    apply(mode);
  }

  /**
   * Get current theme mode
   * @returns {string} Current theme ('light' or 'dark')
   */
  function get() {
    return currentTheme;
  }

  /**
   * Apply theme to document
   * @param {string} mode - Theme mode to apply
   */
  function apply(mode) {
    var html = document.documentElement;
    if (html) {
      html.setAttribute('data-theme', mode);
    }
  }

  /**
   * Get system color scheme preference
   * @returns {string} 'light' or 'dark'
   */
  function getSystemPreference() {
    if (window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)').matches) {
      return 'dark';
    }
    return 'light';
  }

  /**
   * Listen to system preference changes
   */
  function listenToSystemChanges() {
    if (!window.matchMedia) return;

    var darkModeQuery = window.matchMedia('(prefers-color-scheme: dark)');

    // Modern browsers
    if (darkModeQuery.addEventListener) {
      darkModeQuery.addEventListener('change', onSystemPreferenceChange);
    }
    // Legacy browsers
    else if (darkModeQuery.addListener) {
      darkModeQuery.addListener(onSystemPreferenceChange);
    }
  }

  /**
   * Handle system preference change
   * @param {MediaQueryListEvent} e - Change event
   */
  function onSystemPreferenceChange(e) {
    // Only follow system if user hasn't made explicit choice
    if (!userHasExplicitChoice) {
      currentTheme = e.matches ? 'dark' : 'light';
      apply(currentTheme);
    }
  }

  // Export public API
  SpecCompiler.Theme = {
    init: init,
    toggle: toggle,
    set: set,
    get: get
  };

})();
