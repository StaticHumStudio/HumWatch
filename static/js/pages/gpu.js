/**
 * HumWatch — GPU detail page.
 */
window.HumWatch = window.HumWatch || {};
HumWatch.pages = HumWatch.pages || {};

HumWatch.pages.gpu = {
    _charts: [],
    _timeRange: '1h',

    init: function(container) {
        var self = this;
        this._charts = [];
        this._container = container;

        self._renderPage(container);

        HumWatch.api.getCurrent().then(function(data) {
            var cats = data.categories || {};
            var hasGpu = cats.gpu && Object.keys(cats.gpu).length > 0;

            if (!hasGpu) {
                // Mark all chart cards as unavailable
                HumWatch.utils.markEmptyCharts(container);
                return;
            }

            self._loadCharts();
        }).catch(function() {
            // No data yet — mark all as unavailable until data arrives
            HumWatch.utils.markEmptyCharts(container);
        });
    },

    _renderPage: function(container) {
        container.innerHTML =
            '<div class="hw-page-header"><h2>GPU</h2></div>' +
            '<div class="hw-time-range" id="gpu-time-range"></div>' +
            '<div class="hw-grid hw-grid-2" style="margin-top:var(--hw-space-md)">' +
                '<div class="hw-card"><div class="hw-card-header"><span class="hw-card-title">Temperature</span></div><div class="hw-chart-container"><canvas id="gpu-temp-chart"></canvas></div></div>' +
                '<div class="hw-card"><div class="hw-card-header"><span class="hw-card-title">Load</span></div><div class="hw-chart-container"><canvas id="gpu-load-chart"></canvas></div></div>' +
            '</div>' +
            '<div class="hw-grid hw-grid-2" style="margin-top:var(--hw-space-md)">' +
                '<div class="hw-card"><div class="hw-card-header"><span class="hw-card-title">VRAM Usage</span></div><div class="hw-chart-container"><canvas id="gpu-vram-chart"></canvas></div></div>' +
                '<div class="hw-card"><div class="hw-card-header"><span class="hw-card-title">Clock Speeds</span></div><div class="hw-chart-container"><canvas id="gpu-clock-chart"></canvas></div></div>' +
            '</div>' +
            '<div class="hw-grid hw-grid-2" style="margin-top:var(--hw-space-md)">' +
                '<div class="hw-card"><div class="hw-card-header"><span class="hw-card-title">Power Draw</span></div><div class="hw-chart-container"><canvas id="gpu-power-chart"></canvas></div></div>' +
                '<div class="hw-card"><div class="hw-card-header"><span class="hw-card-title">Fan Speed</span></div><div class="hw-chart-container"><canvas id="gpu-fan-chart"></canvas></div></div>' +
            '</div>';
        this._renderTimeRange();
    },

    destroy: function() {
        this._charts.forEach(function(c) { if (c.destroy) c.destroy(); });
        this._charts = [];
    },

    onSSEData: function() {},

    _renderTimeRange: function() {
        var container = document.getElementById('gpu-time-range');
        if (!container) return;
        var self = this;
        var presets = HumWatch.utils.timeRangePresets;
        container.innerHTML = '';
        Object.keys(presets).forEach(function(key) {
            var btn = document.createElement('button');
            btn.className = 'hw-btn' + (key === self._timeRange ? ' active' : '');
            btn.textContent = presets[key].label;
            btn.addEventListener('click', function() {
                self._timeRange = key;
                self._renderTimeRange();
                self._loadCharts();
            });
            container.appendChild(btn);
        });
    },

    _loadCharts: function() {
        var self = this;
        var range = HumWatch.utils.getTimeRange(this._timeRange);
        var colors = HumWatch.charts.getColors().chart;

        this._charts.forEach(function(c) { if (c.destroy) c.destroy(); });
        this._charts = [];

        var metrics = ['gpu_temp', 'gpu_load', 'gpu_vram_used', 'gpu_vram_total', 'gpu_clock_core', 'gpu_clock_memory', 'gpu_power', 'gpu_fan_speed'];

        HumWatch.api.getHistoryMulti(metrics, range.from, range.to).then(function(data) {
            self._buildChart('gpu-temp-chart', data, 'gpu_temp', '\u00B0C', colors[3]);
            self._buildChart('gpu-load-chart', data, 'gpu_load', '%', colors[0], 0, 100);
            self._buildChart('gpu-vram-chart', data, 'gpu_vram_used', 'MB', colors[1]);
            self._buildChartMulti('gpu-clock-chart', data, [
                { key: 'gpu_clock_core', label: 'Core', color: colors[0] },
                { key: 'gpu_clock_memory', label: 'Memory', color: colors[1] },
            ], 'MHz');
            self._buildChart('gpu-power-chart', data, 'gpu_power', 'W', colors[6]);
            self._buildChart('gpu-fan-chart', data, 'gpu_fan_speed', 'RPM', colors[2]);

            // Mark any charts that didn't get data as unavailable
            HumWatch.utils.markEmptyCharts(self._container);
        }).catch(function(err) {
            console.error('GPU chart error:', err);
            HumWatch.utils.markEmptyCharts(self._container);
        });
    },

    _buildChart: function(canvasId, data, metric, unit, color, yMin, yMax) {
        var canvas = document.getElementById(canvasId);
        if (!canvas || !data[metric] || data[metric].length === 0) return;
        var ds = [{ label: metric, data: HumWatch.charts.historyToChartData(data[metric]), borderColor: color }];
        this._charts.push(HumWatch.charts.createTimeSeriesChart(canvas, ds, { yLabel: unit, yMin: yMin, yMax: yMax }));
    },

    _buildChartMulti: function(canvasId, data, configs, unit) {
        var canvas = document.getElementById(canvasId);
        if (!canvas) return;
        var datasets = configs.filter(function(c) { return data[c.key] && data[c.key].length > 0; })
            .map(function(c) { return { label: c.label, data: HumWatch.charts.historyToChartData(data[c.key]), borderColor: c.color }; });
        if (datasets.length === 0) return;
        this._charts.push(HumWatch.charts.createTimeSeriesChart(canvas, datasets, { yLabel: unit, legend: true }));
    },
};
