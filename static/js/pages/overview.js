/**
 * HumWatch — Overview page: identity card, gauges, battery widget, sparklines.
 */
window.HumWatch = window.HumWatch || {};
HumWatch.pages = HumWatch.pages || {};

HumWatch.pages.overview = {
    _gauges: [],
    _sparklines: [],
    _sparklineMap: {},    // key → { chart, valueEl, unit }
    _retryTimer: null,
    _uptimeInterval: null,
    _bootTime: null,

    init: function(container) {
        var self = this;
        this._gauges = [];
        this._sparklines = [];

        container.innerHTML =
            '<div class="hw-page-header"><h2>Overview</h2></div>' +
            '<div class="hw-grid hw-grid-auto" id="ov-gauges"></div>' +
            '<div class="hw-grid hw-grid-2" style="margin-top:var(--hw-space-md)">' +
                '<div class="hw-card" id="ov-info"><div class="hw-loading"><div class="hw-spinner"></div></div></div>' +
                '<div class="hw-card" id="ov-battery" style="display:none"></div>' +
            '</div>' +
            '<div class="hw-card" style="margin-top:var(--hw-space-md)">' +
                '<div class="hw-card-header"><span class="hw-card-title">Last 5 Minutes</span></div>' +
                '<div class="hw-grid hw-grid-4" id="ov-sparklines"></div>' +
            '</div>';

        // Load machine info
        HumWatch.api.getInfo().then(function(info) {
            self._renderInfo(info);
        }).catch(function() {});

        // Load current data for gauges (may 503 if no data yet — SSE will retry)
        HumWatch.api.getCurrent().then(function(data) {
            self._initGauges(data);
            self._renderBattery(data);
        }).catch(function() {
            var gc = document.getElementById('ov-gauges');
            if (gc) gc.innerHTML = '<div class="hw-empty" style="grid-column:1/-1">Waiting for first data collection\u2026</div>';
        });

        // Load sparkline data (use 15m window for better startup coverage)
        self._loadSparklines();
    },

    destroy: function() {
        this._gauges.forEach(function(g) { if (g.destroy) g.destroy(); });
        this._gauges = [];
        this._sparklines.forEach(function(c) { if (c.destroy) c.destroy(); });
        this._sparklines = [];
        this._sparklineMap = {};
        if (this._retryTimer) {
            clearTimeout(this._retryTimer);
            this._retryTimer = null;
        }
        if (this._uptimeInterval) {
            clearInterval(this._uptimeInterval);
            this._uptimeInterval = null;
        }
    },

    onSSEData: function(data) {
        if (!data || !data.categories) return;
        var cats = data.categories;

        // If gauges were never initialized (503 on first load), init them now
        if (this._gauges.length === 0) {
            this._initGauges(data);
        }

        // Update gauges
        var vals = {
            'CPU Load': cats.cpu ? (cats.cpu.cpu_load_total || {}).value : null,
            'CPU Temp': cats.cpu ? (cats.cpu.cpu_temp_package || {}).value : null,
            'GPU Load': cats.gpu ? (cats.gpu.gpu_load || {}).value : null,
            'GPU Temp': cats.gpu ? (cats.gpu.gpu_temp || {}).value : null,
            'RAM': cats.memory ? (cats.memory.mem_percent || {}).value : null,
        };

        this._gauges.forEach(function(g) {
            var v = vals[g.label];
            if (v != null) g.update(v);
        });

        this._renderBattery(data);

        // Update sparklines with live data
        this._updateSparklines(data);
    },

    _initGauges: function(data) {
        var container = document.getElementById('ov-gauges');
        if (!container) return;
        container.innerHTML = '';

        var cats = data.categories || {};
        var config = (HumWatch.router._config || {}).alert_thresholds || {};

        var gaugeConfigs = [
            { label: 'CPU Load', value: (cats.cpu || {}).cpu_load_total, unit: '%', max: 100, warn: 85, crit: 95 },
            { label: 'CPU Temp', value: (cats.cpu || {}).cpu_temp_package, unit: '\u00B0C', max: 110, warn: config.cpu_temp_warn || 85, crit: config.cpu_temp_critical || 95 },
        ];

        if (cats.gpu && cats.gpu.gpu_load) {
            gaugeConfigs.push({ label: 'GPU Load', value: cats.gpu.gpu_load, unit: '%', max: 100, warn: 85, crit: 95 });
            gaugeConfigs.push({ label: 'GPU Temp', value: cats.gpu.gpu_temp, unit: '\u00B0C', max: 110, warn: config.gpu_temp_warn || 80, crit: config.gpu_temp_critical || 90 });
        }

        gaugeConfigs.push({ label: 'RAM', value: (cats.memory || {}).mem_percent, unit: '%', max: 100, warn: config.ram_percent_warn || 85, crit: config.ram_percent_critical || 95 });

        var self = this;
        gaugeConfigs.forEach(function(gc) {
            var card = document.createElement('div');
            card.className = 'hw-card hw-gauge-container';
            var canvas = document.createElement('canvas');
            canvas.className = 'hw-gauge-canvas';
            canvas.style.width = '140px';
            canvas.style.height = '140px';
            card.appendChild(canvas);
            container.appendChild(card);

            var val = gc.value ? gc.value.value : 0;
            var gauge = HumWatch.gauges.create(canvas, {
                min: 0, max: gc.max, value: val || 0,
                label: gc.label, unit: gc.unit,
                warnThreshold: gc.warn, critThreshold: gc.crit,
            });
            self._gauges.push(gauge);
        });
    },

    _renderInfo: function(info) {
        var el = document.getElementById('ov-info');
        if (!el) return;
        var self = this;

        self._bootTime = info.last_boot ? new Date(info.last_boot) : null;

        el.innerHTML =
            '<div class="hw-card-header"><span class="hw-card-title">Machine Info</span>' +
            '<span class="hw-badge hw-badge-ok">Online</span></div>' +
            '<div class="hw-info-grid">' +
                '<span class="hw-info-label">Hostname</span><span class="hw-info-value">' + (info.hostname || '--') + '</span>' +
                '<span class="hw-info-label">OS</span><span class="hw-info-value">' + (info.os_version || '--') + '</span>' +
                '<span class="hw-info-label">CPU</span><span class="hw-info-value">' + (info.cpu_name || '--') + '</span>' +
                '<span class="hw-info-label">GPU</span><span class="hw-info-value">' + (info.gpu_name || 'N/A') + '</span>' +
                '<span class="hw-info-label">RAM</span><span class="hw-info-value">' + HumWatch.utils.formatMB(info.total_ram_mb) + '</span>' +
                '<span class="hw-info-label">Tailscale</span><span class="hw-info-value">' + (info.tailscale_ip || 'N/A') + '</span>' +
                '<span class="hw-info-label">Uptime</span><span class="hw-info-value" id="ov-uptime">' + HumWatch.utils.formatUptime(info.uptime_seconds) + '</span>' +
                '<span class="hw-info-label">Agent</span><span class="hw-info-value">v' + (info.agent_version || '--') + '</span>' +
            '</div>';

        // Live uptime counter
        if (info.uptime_seconds) {
            var uptimeBase = info.uptime_seconds;
            var startTs = Date.now();
            self._uptimeInterval = setInterval(function() {
                var elapsed = (Date.now() - startTs) / 1000;
                var uptimeEl = document.getElementById('ov-uptime');
                if (uptimeEl) uptimeEl.textContent = HumWatch.utils.formatUptime(uptimeBase + elapsed);
            }, 1000);
        }
    },

    _renderBattery: function(data) {
        var el = document.getElementById('ov-battery');
        if (!el) return;
        if (!data || !data.categories || !data.categories.battery) {
            el.style.display = 'none';
            return;
        }

        el.style.display = '';
        var bat = data.categories.battery;
        var pct = (bat.battery_percent || {}).value;
        var plugged = (bat.battery_plugged || {}).value;
        var timeLeft = (bat.battery_time_remaining || {}).value;
        var wear = (bat.battery_wear_level || {}).value;
        var batTemp = (bat.battery_temp || {}).value;

        var fillClass = '';
        if (pct != null) {
            if (pct < 15) fillClass = ' low';
            else if (pct < 30) fillClass = ' medium';
        }

        var fillWidth = Math.max(0, Math.min(100, pct || 0)) + '%';

        el.innerHTML =
            '<div class="hw-card-header"><span class="hw-card-title">Battery</span>' +
            (plugged ? '<span class="hw-badge hw-badge-ok">Plugged In</span>' : '<span class="hw-badge hw-badge-warn">On Battery</span>') +
            '</div>' +
            '<div class="hw-battery-widget">' +
                '<div class="hw-battery-icon"><div class="hw-battery-fill' + fillClass + '" style="width:' + fillWidth + '"></div></div>' +
                '<div>' +
                    '<div class="hw-card-value">' + (pct != null ? pct.toFixed(0) : '--') + '<span class="hw-card-unit">%</span></div>' +
                    (timeLeft ? '<div style="color:var(--hw-text-secondary);font-size:var(--hw-font-size-xs);margin-top:4px">' + HumWatch.utils.formatUptime(timeLeft) + ' remaining</div>' : '') +
                    (wear != null ? '<div style="color:var(--hw-text-tertiary);font-size:var(--hw-font-size-xs);margin-top:2px">Health: ' + wear.toFixed(0) + '%</div>' : '') +
                    (batTemp != null ? '<div style="color:var(--hw-text-tertiary);font-size:var(--hw-font-size-xs);margin-top:2px">Temp: ' + batTemp.toFixed(1) + '\u00B0C</div>' : '') +
                '</div>' +
            '</div>';
    },

    _sparklineMetrics: [
        { key: 'cpu_load_total', label: 'CPU Load', unit: '%', color: 0, sseCategory: 'cpu' },
        { key: 'mem_percent', label: 'RAM Usage', unit: '%', color: 1, sseCategory: 'memory' },
        { key: 'cpu_temp_package', label: 'CPU Temp', unit: '\u00B0C', color: 3, sseCategory: 'cpu' },
        { key: 'net_recv_rate', label: 'Net Down', unit: 'MB/s', color: 5, sseCategory: 'network' },
    ],

    _loadSparklines: function() {
        var self = this;
        var range = HumWatch.utils.getTimeRange('15m');
        var metricKeys = this._sparklineMetrics.map(function(m) { return m.key; });

        HumWatch.api.getHistoryMulti(metricKeys, range.from, range.to).then(function(data) {
            self._renderSparklines(data);

            // If key metrics came back empty, retry once after 15s
            var hasTemp = (data['cpu_temp_package'] || []).length > 0;
            var hasLoad = (data['cpu_load_total'] || []).length > 0;
            if (!hasTemp && !hasLoad && !self._retryTimer) {
                self._retryTimer = setTimeout(function() {
                    self._retryTimer = null;
                    self._loadSparklines();
                }, 15000);
            }
        }).catch(function() {});
    },

    _renderSparklines: function(data) {
        var container = document.getElementById('ov-sparklines');
        if (!container) return;
        container.innerHTML = '';
        var self = this;

        // Destroy old sparkline charts
        this._sparklines.forEach(function(c) { if (c.destroy) c.destroy(); });
        this._sparklines = [];
        this._sparklineMap = {};

        var colors = HumWatch.charts.getColors().chart;

        this._sparklineMetrics.forEach(function(m) {
            var points = data[m.key] || [];
            var chartData = HumWatch.charts.historyToChartData(points);
            var lastVal = chartData.length > 0 ? chartData[chartData.length - 1].y : null;

            var card = document.createElement('div');
            card.style.textAlign = 'center';
            card.innerHTML =
                '<div style="font-size:var(--hw-font-size-xs);color:var(--hw-text-tertiary);margin-bottom:4px">' + m.label + '</div>' +
                '<canvas class="hw-sparkline"></canvas>' +
                '<div class="hw-sparkline-value" style="font-family:var(--hw-font-display);font-size:var(--hw-font-size-sm);margin-top:4px">' +
                    HumWatch.utils.formatValue(lastVal, m.unit) +
                '</div>';
            container.appendChild(card);

            var canvas = card.querySelector('canvas');
            var chart = HumWatch.charts.createSparkline(canvas, chartData, colors[m.color]);
            self._sparklines.push(chart);
            self._sparklineMap[m.key] = {
                chart: chart,
                valueEl: card.querySelector('.hw-sparkline-value'),
                unit: m.unit,
            };
        });
    },

    _updateSparklines: function(data) {
        if (!data || !data.categories) return;
        var cats = data.categories;
        var ts = data.timestamp ? new Date(data.timestamp) : new Date();
        var self = this;

        this._sparklineMetrics.forEach(function(m) {
            var entry = self._sparklineMap[m.key];
            if (!entry || !entry.chart) return;

            var catData = cats[m.sseCategory];
            if (!catData) return;
            var metric = catData[m.key];
            if (!metric || metric.value == null) return;

            var point = { x: ts, y: metric.value };
            HumWatch.charts.appendData(entry.chart, 0, point, 60);

            // Update the value label below the sparkline
            if (entry.valueEl) {
                entry.valueEl.textContent = HumWatch.utils.formatValue(metric.value, entry.unit);
            }
        });
    },
};
