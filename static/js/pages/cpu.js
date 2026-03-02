/**
 * HumWatch — CPU detail page.
 */
window.HumWatch = window.HumWatch || {};
HumWatch.pages = HumWatch.pages || {};

HumWatch.pages.cpu = {
    _charts: [],
    _timeRange: '1h',
    _coreCount: 0,

    init: function(container) {
        var self = this;
        this._charts = [];
        this._container = container;

        container.innerHTML =
            '<div class="hw-page-header"><h2>CPU</h2><div class="hw-subtitle" id="cpu-name"></div></div>' +
            '<div class="hw-time-range" id="cpu-time-range"></div>' +
            '<div class="hw-grid hw-grid-2" style="margin-top:var(--hw-space-md)">' +
                '<div class="hw-card"><div class="hw-card-header"><span class="hw-card-title">Core Temperatures</span></div><div class="hw-chart-container"><canvas id="cpu-temp-chart"></canvas></div></div>' +
                '<div class="hw-card"><div class="hw-card-header"><span class="hw-card-title">Core Load</span></div><div class="hw-chart-container"><canvas id="cpu-load-chart"></canvas></div></div>' +
            '</div>' +
            '<div class="hw-grid hw-grid-2" style="margin-top:var(--hw-space-md)">' +
                '<div class="hw-card"><div class="hw-card-header"><span class="hw-card-title">Core Clock Speed</span></div><div class="hw-chart-container"><canvas id="cpu-clock-chart"></canvas></div></div>' +
                '<div class="hw-card"><div class="hw-card-header"><span class="hw-card-title">Package Power &amp; Voltage</span></div><div class="hw-chart-container"><canvas id="cpu-power-chart"></canvas></div></div>' +
            '</div>';

        this._renderTimeRange();

        // Detect core count from current data
        HumWatch.api.getCurrent().then(function(data) {
            var cpu = (data.categories || {}).cpu || {};
            var coreCount = 0;
            for (var k in cpu) {
                if (k.match(/^cpu_load_core_\d+$/)) coreCount++;
            }
            self._coreCount = coreCount || 4;

            var name = document.getElementById('cpu-name');
            if (name) name.textContent = coreCount + ' cores detected';

            self._loadCharts();
        }).catch(function() {
            self._coreCount = 4;
            self._loadCharts();
        });
    },

    destroy: function() {
        this._charts.forEach(function(c) { if (c.destroy) c.destroy(); });
        this._charts = [];
    },

    onSSEData: function(data) {
        // Live updates are handled by chart data appending if on short time range
    },

    _renderTimeRange: function() {
        var container = document.getElementById('cpu-time-range');
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

        // Destroy old charts
        this._charts.forEach(function(c) { if (c.destroy) c.destroy(); });
        this._charts = [];

        // Build metric lists
        var tempMetrics = ['cpu_temp_package'];
        var loadMetrics = [];
        var clockMetrics = [];
        for (var i = 0; i < this._coreCount; i++) {
            tempMetrics.push('cpu_temp_core_' + i);
            loadMetrics.push('cpu_load_core_' + i);
            clockMetrics.push('cpu_clock_core_' + i);
        }

        var allMetrics = tempMetrics.concat(loadMetrics).concat(clockMetrics).concat(['cpu_power_package', 'cpu_voltage']);

        HumWatch.api.getHistoryMulti(allMetrics, range.from, range.to).then(function(data) {
            // Temperature chart
            var tempDatasets = tempMetrics.map(function(m, idx) {
                return {
                    label: m === 'cpu_temp_package' ? 'Package' : 'Core ' + (idx - 1),
                    data: HumWatch.charts.historyToChartData(data[m] || []),
                    borderColor: colors[idx % colors.length],
                };
            }).filter(function(ds) { return ds.data.length > 0; });

            if (tempDatasets.length > 0) {
                var tempCanvas = document.getElementById('cpu-temp-chart');
                if (tempCanvas) {
                    self._charts.push(HumWatch.charts.createTimeSeriesChart(tempCanvas, tempDatasets, { yLabel: '\u00B0C', yMin: 0, legend: true }));
                }
            }

            // Load chart
            var loadDatasets = loadMetrics.map(function(m, idx) {
                return {
                    label: 'Core ' + idx,
                    data: HumWatch.charts.historyToChartData(data[m] || []),
                    borderColor: colors[idx % colors.length],
                };
            }).filter(function(ds) { return ds.data.length > 0; });

            if (loadDatasets.length > 0) {
                var loadCanvas = document.getElementById('cpu-load-chart');
                if (loadCanvas) {
                    self._charts.push(HumWatch.charts.createTimeSeriesChart(loadCanvas, loadDatasets, { yLabel: '%', yMin: 0, yMax: 100, legend: true }));
                }
            }

            // Clock chart
            var clockDatasets = clockMetrics.map(function(m, idx) {
                return {
                    label: 'Core ' + idx,
                    data: HumWatch.charts.historyToChartData(data[m] || []),
                    borderColor: colors[idx % colors.length],
                };
            }).filter(function(ds) { return ds.data.length > 0; });

            if (clockDatasets.length > 0) {
                var clockCanvas = document.getElementById('cpu-clock-chart');
                if (clockCanvas) {
                    self._charts.push(HumWatch.charts.createTimeSeriesChart(clockCanvas, clockDatasets, { yLabel: 'MHz', yMin: 0, legend: true }));
                }
            }

            // Power & Voltage chart
            var powerDs = [];
            if (data['cpu_power_package'] && data['cpu_power_package'].length > 0) {
                powerDs.push({ label: 'Power (W)', data: HumWatch.charts.historyToChartData(data['cpu_power_package']), borderColor: colors[0] });
            }
            if (data['cpu_voltage'] && data['cpu_voltage'].length > 0) {
                powerDs.push({ label: 'Voltage (V)', data: HumWatch.charts.historyToChartData(data['cpu_voltage']), borderColor: colors[1], yAxisID: 'y1' });
            }

            if (powerDs.length > 0) {
                var powerCanvas = document.getElementById('cpu-power-chart');
                if (powerCanvas) {
                    self._charts.push(HumWatch.charts.createTimeSeriesChart(powerCanvas, powerDs, { yLabel: 'W', yMin: 0, legend: true }));
                }
            }
            // Mark any charts that didn't get data
            HumWatch.utils.markEmptyCharts(self._container);
        }).catch(function(err) {
            console.error('CPU chart load error:', err);
            HumWatch.utils.markEmptyCharts(self._container);
        });
    },
};
