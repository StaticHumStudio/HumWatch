/**
 * HumWatch — CPU detail page.
 *
 * Improvements over raw display:
 *   - Threshold reference lines loaded from config (warn / critical)
 *   - Smooth toggle (EMA) to tame noisy instantaneous readings
 *   - Min / Max / Avg stats bar above the temperature chart
 *   - Package-only default with "Show Cores" toggle
 *   - 5-minute temperature log table
 */
window.HumWatch = window.HumWatch || {};
HumWatch.pages = HumWatch.pages || {};

HumWatch.pages.cpu = {
    _charts: [],
    _timeRange: '1h',
    _coreCount: 0,
    _showCores: false,
    _smooth: true,
    _tempWarn: 85,        // overridden from config
    _tempCrit: 95,        // overridden from config

    init: function(container) {
        var self = this;
        this._charts = [];
        this._container = container;

        container.innerHTML =
            '<div class="hw-page-header"><h2>CPU</h2><div class="hw-subtitle" id="cpu-name"></div></div>' +
            '<div class="hw-chart-toolbar" id="cpu-toolbar">' +
                '<div class="hw-time-range" id="cpu-time-range"></div>' +
                '<div class="hw-toolbar-separator"></div>' +
                '<button class="hw-btn' + (this._smooth ? ' active' : '') + '" id="cpu-smooth-btn" title="Exponential moving average smoothing">Smooth</button>' +
                '<button class="hw-btn' + (this._showCores ? ' active' : '') + '" id="cpu-cores-btn" title="Show individual core temperatures">Show Cores</button>' +
            '</div>' +
            '<div class="hw-grid hw-grid-2" style="margin-top:var(--hw-space-md)">' +
                '<div class="hw-card">' +
                    '<div class="hw-card-header"><span class="hw-card-title">Core Temperatures</span></div>' +
                    '<div class="hw-stats-bar" id="cpu-temp-stats"></div>' +
                    '<div class="hw-chart-container"><canvas id="cpu-temp-chart"></canvas></div>' +
                '</div>' +
                '<div class="hw-card"><div class="hw-card-header"><span class="hw-card-title">Core Load</span></div><div class="hw-chart-container"><canvas id="cpu-load-chart"></canvas></div></div>' +
            '</div>' +
            '<div class="hw-grid hw-grid-2" style="margin-top:var(--hw-space-md)">' +
                '<div class="hw-card"><div class="hw-card-header"><span class="hw-card-title">Core Clock Speed</span></div><div class="hw-chart-container"><canvas id="cpu-clock-chart"></canvas></div></div>' +
                '<div class="hw-card"><div class="hw-card-header"><span class="hw-card-title">Package Power &amp; Voltage</span></div><div class="hw-chart-container"><canvas id="cpu-power-chart"></canvas></div></div>' +
            '</div>' +
            '<div class="hw-card" style="margin-top:var(--hw-space-md)">' +
                '<div class="hw-card-header"><span class="hw-card-title">Temperature Log (5-min avg)</span></div>' +
                '<div class="hw-table-container" id="cpu-temp-table"></div>' +
            '</div>';

        this._renderTimeRange();

        // Smooth toggle
        var smoothBtn = document.getElementById('cpu-smooth-btn');
        if (smoothBtn) {
            smoothBtn.addEventListener('click', function() {
                self._smooth = !self._smooth;
                smoothBtn.classList.toggle('active', self._smooth);
                self._loadCharts();
            });
        }

        // Show Cores toggle
        var coresBtn = document.getElementById('cpu-cores-btn');
        if (coresBtn) {
            coresBtn.addEventListener('click', function() {
                self._showCores = !self._showCores;
                coresBtn.classList.toggle('active', self._showCores);
                self._loadCharts();
            });
        }

        // Load config thresholds + core count, then render
        Promise.all([
            HumWatch.api.getConfig(),
            HumWatch.api.getCurrent(),
        ]).then(function(results) {
            var config = results[0];
            var current = results[1];

            // Apply config thresholds
            var thresholds = config.alert_thresholds || {};
            if (thresholds.cpu_temp_warn) self._tempWarn = thresholds.cpu_temp_warn;
            if (thresholds.cpu_temp_critical) self._tempCrit = thresholds.cpu_temp_critical;

            // Detect core count
            var cpu = (current.categories || {}).cpu || {};
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

    _renderTempStats: function(packageData) {
        var el = document.getElementById('cpu-temp-stats');
        if (!el) return;
        var stats = HumWatch.charts.computeStats(packageData);
        if (!stats) {
            el.innerHTML = '';
            return;
        }
        var maxClass = stats.max >= this._tempCrit ? ' critical' : (stats.max >= this._tempWarn ? ' warn' : '');
        el.innerHTML =
            '<div class="hw-stat"><span class="hw-stat-label">Min</span><span class="hw-stat-value">' + stats.min + '\u00B0C</span></div>' +
            '<div class="hw-stat"><span class="hw-stat-label">Avg</span><span class="hw-stat-value">' + stats.avg + '\u00B0C</span></div>' +
            '<div class="hw-stat"><span class="hw-stat-label">Max</span><span class="hw-stat-value' + maxClass + '">' + stats.max + '\u00B0C</span></div>' +
            '<div class="hw-stat"><span class="hw-stat-label">Readings</span><span class="hw-stat-value">' + stats.count + '</span></div>';
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
            self._buildTempChart(data, tempMetrics, colors);
            self._buildLoadChart(data, loadMetrics, colors);
            self._buildClockChart(data, clockMetrics, colors);
            self._buildPowerChart(data, colors);

            // Mark any charts that didn't get data
            HumWatch.utils.markEmptyCharts(self._container);
        }).catch(function(err) {
            console.error('CPU chart load error:', err);
            HumWatch.utils.markEmptyCharts(self._container);
        });

        // Load temp table separately at 5-min resolution
        self._loadTempTable(tempMetrics, range);
    },

    _buildTempChart: function(data, tempMetrics, colors) {
        var self = this;
        var packageRaw = HumWatch.charts.historyToChartData(data['cpu_temp_package'] || []);

        // Update stats (always from package, always raw)
        this._renderTempStats(packageRaw);

        if (packageRaw.length === 0) return;

        // Determine which metrics to show
        var metricsToShow = ['cpu_temp_package'];
        if (this._showCores) {
            for (var i = 0; i < this._coreCount; i++) {
                metricsToShow.push('cpu_temp_core_' + i);
            }
        }

        // Build datasets
        var datasets = metricsToShow.map(function(m, idx) {
            var raw = HumWatch.charts.historyToChartData(data[m] || []);
            var chartData = self._smooth ? HumWatch.charts.emaSmooth(raw, 0.25) : raw;
            var label = m === 'cpu_temp_package' ? 'Package' : 'Core ' + m.replace('cpu_temp_core_', '');
            return {
                label: label,
                data: chartData,
                borderColor: colors[idx % colors.length],
                borderWidth: m === 'cpu_temp_package' ? 2 : 1,
            };
        }).filter(function(ds) { return ds.data.length > 0; });

        // Add threshold reference lines from config
        var timePoints = [packageRaw[0].x, packageRaw[packageRaw.length - 1].x];
        datasets.push(HumWatch.charts.thresholdDataset(
            'Warn (' + this._tempWarn + '\u00B0C)', this._tempWarn, 'rgba(240, 168, 48, 0.5)', timePoints
        ));
        datasets.push(HumWatch.charts.thresholdDataset(
            'Crit (' + this._tempCrit + '\u00B0C)', this._tempCrit, 'rgba(231, 76, 60, 0.5)', timePoints
        ));

        var tempCanvas = document.getElementById('cpu-temp-chart');
        if (tempCanvas) {
            this._charts.push(HumWatch.charts.createTimeSeriesChart(
                tempCanvas, datasets, { yLabel: '\u00B0C', yMin: 0, legend: true }
            ));
        }
    },

    _buildLoadChart: function(data, loadMetrics, colors) {
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
                this._charts.push(HumWatch.charts.createTimeSeriesChart(loadCanvas, loadDatasets, { yLabel: '%', yMin: 0, yMax: 100, legend: true }));
            }
        }
    },

    _buildClockChart: function(data, clockMetrics, colors) {
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
                this._charts.push(HumWatch.charts.createTimeSeriesChart(clockCanvas, clockDatasets, { yLabel: 'MHz', yMin: 0, legend: true }));
            }
        }
    },

    _buildPowerChart: function(data, colors) {
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
                this._charts.push(HumWatch.charts.createTimeSeriesChart(powerCanvas, powerDs, { yLabel: 'W', yMin: 0, legend: true }));
            }
        }
    },

    _loadTempTable: function(tempMetrics, range) {
        var self = this;
        var el = document.getElementById('cpu-temp-table');
        if (!el) return;

        el.innerHTML = '<div class="hw-loading"><div class="hw-spinner"></div></div>';

        // Fetch at 5-minute resolution (300s)
        HumWatch.api.getHistoryMulti(tempMetrics, range.from, range.to, 300).then(function(data) {
            // Build a map of timestamp -> { metric: value }
            var timestamps = {};
            tempMetrics.forEach(function(metric) {
                var points = data[metric] || [];
                points.forEach(function(pt) {
                    if (!timestamps[pt.timestamp]) timestamps[pt.timestamp] = {};
                    timestamps[pt.timestamp][metric] = pt.value;
                });
            });

            var sortedTimes = Object.keys(timestamps).sort().reverse();

            if (sortedTimes.length === 0) {
                el.innerHTML = '<p style="color:var(--hw-text-tertiary);font-size:var(--hw-font-size-sm);padding:var(--hw-space-md)">No temperature data for this range.</p>';
                return;
            }

            // Build header: Time | Pkg | Core 0 | Core 1 | ...
            var headerCells = '<th>Time</th><th class="hw-text-right">Pkg</th>';
            for (var i = 0; i < self._coreCount; i++) {
                headerCells += '<th class="hw-text-right">C' + i + '</th>';
            }

            var warnT = self._tempWarn;
            var critT = self._tempCrit;
            var rows = '';
            sortedTimes.forEach(function(ts) {
                var row = timestamps[ts];
                var timeStr = HumWatch.utils.formatTime(ts);

                rows += '<tr>';
                rows += '<td>' + timeStr + '</td>';

                // Package temp cell
                var pkgVal = row['cpu_temp_package'];
                var pkgStyle = '';
                if (pkgVal !== undefined && pkgVal >= critT) pkgStyle = ' style="color:var(--hw-status-critical)"';
                else if (pkgVal !== undefined && pkgVal >= warnT) pkgStyle = ' style="color:var(--hw-status-warn)"';
                rows += '<td class="hw-text-right"' + pkgStyle + '>' + (pkgVal !== undefined ? Math.round(pkgVal) + '\u00B0' : '\u2014') + '</td>';

                // Core temp cells
                for (var c = 0; c < self._coreCount; c++) {
                    var coreVal = row['cpu_temp_core_' + c];
                    var coreStyle = '';
                    if (coreVal !== undefined && coreVal >= critT) coreStyle = ' style="color:var(--hw-status-critical)"';
                    else if (coreVal !== undefined && coreVal >= warnT) coreStyle = ' style="color:var(--hw-status-warn)"';
                    rows += '<td class="hw-text-right"' + coreStyle + '>' + (coreVal !== undefined ? Math.round(coreVal) + '\u00B0' : '\u2014') + '</td>';
                }
                rows += '</tr>';
            });

            el.innerHTML = '<table class="hw-table"><thead><tr>' + headerCells + '</tr></thead><tbody>' + rows + '</tbody></table>';
        }).catch(function(err) {
            console.error('Temp table load error:', err);
            el.innerHTML = '<p style="color:var(--hw-text-tertiary);font-size:var(--hw-font-size-sm);padding:var(--hw-space-md)">Failed to load temperature data.</p>';
        });
    },
};
