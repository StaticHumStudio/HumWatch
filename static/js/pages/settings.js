/**
 * HumWatch — Settings page: theme selector, alert thresholds.
 */
window.HumWatch = window.HumWatch || {};
HumWatch.pages = HumWatch.pages || {};

HumWatch.pages.settings = {
    init: function(container) {
        var currentTheme = HumWatch.theme.get();

        container.innerHTML =
            '<div class="hw-page-header"><h2>Settings</h2></div>' +
            '<div class="hw-grid hw-grid-2">' +
                '<div class="hw-card">' +
                    '<div class="hw-card-header"><span class="hw-card-title">Theme</span></div>' +
                    '<div id="settings-theme"></div>' +
                '</div>' +
                '<div class="hw-card">' +
                    '<div class="hw-card-header"><span class="hw-card-title">Alert Thresholds</span></div>' +
                    '<div id="settings-thresholds"></div>' +
                '</div>' +
            '</div>' +
            '<div class="hw-card" style="margin-top:var(--hw-space-md)">' +
                '<div class="hw-card-header"><span class="hw-card-title">About</span></div>' +
                '<div class="hw-info-grid">' +
                    '<span class="hw-info-label">Agent</span><span class="hw-info-value" id="settings-version">--</span>' +
                    '<span class="hw-info-label">Port</span><span class="hw-info-value" id="settings-port">--</span>' +
                    '<span class="hw-info-label">Interval</span><span class="hw-info-value" id="settings-interval">--</span>' +
                    '<span class="hw-info-label">Retention</span><span class="hw-info-value" id="settings-retention">--</span>' +
                '</div>' +
            '</div>';

        this._renderThemeSelector(currentTheme);
        this._renderThresholds();
        this._loadAbout();
    },

    destroy: function() {},
    onSSEData: function() {},

    _renderThemeSelector: function(currentTheme) {
        var container = document.getElementById('settings-theme');
        if (!container) return;
        var html = '';

        Object.keys(HumWatch.theme.available).forEach(function(key) {
            var info = HumWatch.theme.available[key];
            var isActive = key === currentTheme;
            html += '<label style="display:flex;align-items:center;gap:var(--hw-space-sm);padding:var(--hw-space-sm) 0;cursor:pointer">' +
                '<input type="radio" name="theme" value="' + key + '"' + (isActive ? ' checked' : '') + '>' +
                '<span style="color:' + (isActive ? 'var(--hw-accent-primary)' : 'var(--hw-text-primary)') + '">' + info.name + '</span>' +
            '</label>';
        });

        container.innerHTML = html;

        container.querySelectorAll('input[name="theme"]').forEach(function(radio) {
            radio.addEventListener('change', function() {
                HumWatch.theme.set(radio.value);
                HumWatch.charts.resetColors();
            });
        });
    },

    _renderThresholds: function() {
        var container = document.getElementById('settings-thresholds');
        if (!container) return;

        var config = (HumWatch.router._config || {}).alert_thresholds || {};
        var stored = {};
        try { stored = JSON.parse(localStorage.getItem('humwatch_thresholds')) || {}; } catch (e) {}

        var thresholds = [
            { key: 'cpu_temp_warn', label: 'CPU Temp Warn', unit: '\u00B0C' },
            { key: 'cpu_temp_critical', label: 'CPU Temp Critical', unit: '\u00B0C' },
            { key: 'gpu_temp_warn', label: 'GPU Temp Warn', unit: '\u00B0C' },
            { key: 'gpu_temp_critical', label: 'GPU Temp Critical', unit: '\u00B0C' },
            { key: 'ram_percent_warn', label: 'RAM Warn', unit: '%' },
            { key: 'ram_percent_critical', label: 'RAM Critical', unit: '%' },
        ];

        var html = '<div style="display:grid;grid-template-columns:1fr 80px;gap:var(--hw-space-xs) var(--hw-space-sm);align-items:center">';
        thresholds.forEach(function(t) {
            var val = stored[t.key] != null ? stored[t.key] : (config[t.key] || '');
            html += '<label style="font-size:var(--hw-font-size-sm);color:var(--hw-text-secondary)">' + t.label + ' (' + t.unit + ')</label>';
            html += '<input class="hw-input threshold-input" data-key="' + t.key + '" type="number" value="' + val + '" style="width:80px;text-align:right">';
        });
        html += '</div>';
        html += '<button class="hw-btn" id="save-thresholds" style="margin-top:var(--hw-space-md)">Save Thresholds</button>';

        container.innerHTML = html;

        document.getElementById('save-thresholds').addEventListener('click', function() {
            var vals = {};
            container.querySelectorAll('.threshold-input').forEach(function(input) {
                vals[input.dataset.key] = parseFloat(input.value) || 0;
            });
            localStorage.setItem('humwatch_thresholds', JSON.stringify(vals));
            // Visual feedback
            var btn = document.getElementById('save-thresholds');
            btn.textContent = 'Saved!';
            setTimeout(function() { btn.textContent = 'Save Thresholds'; }, 1500);
        });
    },

    _loadAbout: function() {
        HumWatch.api.getConfig().then(function(cfg) {
            var el;
            el = document.getElementById('settings-port'); if (el) el.textContent = cfg.port || '--';
            el = document.getElementById('settings-interval'); if (el) el.textContent = (cfg.collection_interval_seconds || '--') + 's';
            el = document.getElementById('settings-retention'); if (el) el.textContent = (cfg.retention_days || '--') + ' days';
        }).catch(function() {});

        HumWatch.api.getHealth().then(function(h) {
            var el = document.getElementById('settings-version');
            if (el) el.textContent = 'v' + (h.version || '--');
        }).catch(function() {});
    },
};
