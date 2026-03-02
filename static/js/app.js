/**
 * HumWatch — SPA router, page lifecycle, and initialization.
 */
window.HumWatch = window.HumWatch || {};
HumWatch.router = {};
HumWatch.pages = HumWatch.pages || {};

HumWatch.router._currentPage = null;
HumWatch.router._currentPageName = null;
HumWatch.router._metricsHandler = null;
HumWatch.router._processesHandler = null;
HumWatch.router._config = null;

HumWatch.router.routes = {
    'overview':  function() { return HumWatch.pages.overview; },
    'cpu':       function() { return HumWatch.pages.cpu; },
    'gpu':       function() { return HumWatch.pages.gpu; },
    'memory':    function() { return HumWatch.pages.memory; },
    'disk':      function() { return HumWatch.pages.disk; },
    'network':   function() { return HumWatch.pages.network; },
    'battery':   function() { return HumWatch.pages.battery; },
    'processes': function() { return HumWatch.pages.processes; },
    'machines':  function() { return HumWatch.pages.machines; },
    'settings':  function() { return HumWatch.pages.settings; },
};

HumWatch.router.navigate = function(pageName) {
    var container = document.getElementById('app-content');
    if (!container) return;

    // Destroy current page
    if (HumWatch.router._currentPage && HumWatch.router._currentPage.destroy) {
        HumWatch.router._currentPage.destroy();
    }

    // Unregister SSE handlers
    if (HumWatch.router._metricsHandler) {
        HumWatch.sse.offMetrics(HumWatch.router._metricsHandler);
        HumWatch.router._metricsHandler = null;
    }
    if (HumWatch.router._processesHandler) {
        HumWatch.sse.offProcesses(HumWatch.router._processesHandler);
        HumWatch.router._processesHandler = null;
    }

    // Resolve page module
    var resolver = HumWatch.router.routes[pageName];
    if (!resolver) {
        pageName = 'overview';
        resolver = HumWatch.router.routes['overview'];
    }

    var page = resolver();
    if (!page) {
        container.innerHTML = '<div class="hw-empty"><p>Page not found.</p></div>';
        return;
    }

    HumWatch.router._currentPage = page;
    HumWatch.router._currentPageName = pageName;

    // Clear content
    container.innerHTML = '';

    // Update nav highlighting
    HumWatch.router._updateNav(pageName);

    // Initialize page
    if (page.init) {
        page.init(container);
    }

    // Register SSE handlers
    if (page.onSSEData) {
        HumWatch.router._metricsHandler = function(data) {
            page.onSSEData(data);
        };
        HumWatch.sse.onMetrics(HumWatch.router._metricsHandler);
    }
    if (page.onSSEProcesses) {
        HumWatch.router._processesHandler = function(data) {
            page.onSSEProcesses(data);
        };
        HumWatch.sse.onProcesses(HumWatch.router._processesHandler);
    }
};

HumWatch.router._updateNav = function(pageName) {
    // Desktop sidebar
    document.querySelectorAll('#nav-items .hw-nav-item').forEach(function(item) {
        item.classList.toggle('active', item.dataset.page === pageName);
    });
    // Mobile nav
    document.querySelectorAll('#mobile-nav .hw-mobile-nav-item').forEach(function(item) {
        item.classList.toggle('active', item.dataset.page === pageName);
    });
};

HumWatch.router._getPageFromHash = function() {
    var hash = window.location.hash.replace('#/', '').replace('#', '');
    return hash || 'overview';
};

HumWatch.router._onHashChange = function() {
    var page = HumWatch.router._getPageFromHash();
    HumWatch.router.navigate(page);
};

// Category availability — dims nav items for hardware that isn't present
HumWatch.router._checkAvailability = function(data) {
    if (!data || !data.categories) return;
    var cats = data.categories;

    // Map of page name → { navId, check function }
    var checks = [
        { page: 'battery', id: 'nav-battery',  has: !!cats.battery },
        { page: 'gpu',     id: 'nav-gpu',      has: !!(cats.gpu && Object.keys(cats.gpu).length > 0) },
    ];

    checks.forEach(function(c) {
        var el = document.getElementById(c.id) ||
                 document.querySelector('.hw-nav-item[data-page="' + c.page + '"]');
        if (!el) return;
        if (c.has) {
            el.classList.remove('hw-nav-unavailable');
        } else {
            // Only add if not already available (don't re-dim once detected)
            if (!el.dataset.hwDetected) {
                el.classList.add('hw-nav-unavailable');
            }
        }
        if (c.has) el.dataset.hwDetected = '1';
    });
};

// === INITIALIZATION ===
(function() {
    // Wait for DOM
    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', init);
    } else {
        init();
    }

    function init() {
        // Initialize theme
        HumWatch.theme.init();

        // Initialize Lucide icons
        if (window.lucide) {
            lucide.createIcons();
        }

        // Load config for alert thresholds
        HumWatch.api.getConfig().then(function(cfg) {
            HumWatch.router._config = cfg;
        }).catch(function() {});

        // Check hardware availability (dims nav for absent features)
        HumWatch.api.getCurrent().then(function(data) {
            HumWatch.router._checkAvailability(data);
        }).catch(function() {});

        // Keep checking on every SSE push (features may appear later)
        HumWatch.sse.onMetrics(function(data) {
            HumWatch.router._checkAvailability(data);
        });

        // Start SSE connection
        HumWatch.sse.connect();

        // Set up hash routing
        window.addEventListener('hashchange', HumWatch.router._onHashChange);

        // Navigate to initial page
        var initialPage = HumWatch.router._getPageFromHash();
        if (!window.location.hash) {
            window.location.hash = '#/overview';
        } else {
            HumWatch.router.navigate(initialPage);
        }
    }
})();
