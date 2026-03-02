/**
 * HumWatch — Battery detail page.
 */
window.HumWatch = window.HumWatch || {};
HumWatch.pages = HumWatch.pages || {};

HumWatch.pages.battery = {
    _charts: [],
    _timeRange: '6h',

    init: function(container) {
        var self = this;
        this._charts = [];
        this._container = container;

        HumWatch.api.getCurrent().then(function(data) {
            var cats = data.categories || {};
            var hasBattery = cats.battery && Object.keys(cats.battery).length > 0;

            self._renderPage(container, hasBattery ? cats.battery : {});

            if (!hasBattery) {
                HumWatch.utils.markEmptyCharts(container);
                return;
            }
            self._loadCharts();
        }).catch(function() {
            self._renderPage(container, {});
            HumWatch.utils.markEmptyCharts(container);
        });
    },

    _renderPage: function(container, batData) {
        var wear = (batData.battery_wear_level || {}).value;
        var designed = (batData.battery_designed_capacity || {}).value;
        var current = (batData.battery_current_capacity || {}).value;
        var cycles = (batData.battery_cycle_count || {}).value;

        container.innerHTML =
            '<div class="hw-page-header"><h2>Battery</h2></div>' +
            '<div class="hw-time-range" id="bat-time-range"></div>' +
            '<div class="hw-grid hw-grid-2" style="margin-top:var(--hw-space-md)">' +
                '<div class="hw-card"><div class="hw-card-header"><span class="hw-card-title">Charge Level</span></div><div class="hw-chart-container"><canvas id="bat-charge-chart"></canvas></div></div>' +
                '<div class="hw-card"><div class="hw-card-header"><span class="hw-card-title">Charge / Discharge Rate</span></div><div class="hw-chart-container"><canvas id="bat-rate-chart"></canvas></div></div>' +
            '</div>' +
            '<div class="hw-grid hw-grid-2" style="margin-top:var(--hw-space-md)">' +
                '<div class="hw-card"><div class="hw-card-header"><span class="hw-card-title">Voltage</span></div><div class="hw-chart-container"><canvas id="bat-voltage-chart"></canvas></div></div>' +
                '<div class="hw-card"><div class="hw-card-header"><span class="hw-card-title">Temperature</span></div><div class="hw-chart-container"><canvas id="bat-temp-chart"></canvas></div></div>' +
            '</div>' +
            '<div class="hw-grid hw-grid-2" style="margin-top:var(--hw-space-md)">' +
                '<div class="hw-card"><div class="hw-card-header"><span class="hw-card-title">Battery Health</span></div>' +
                    '<div style="padding:var(--hw-space-md)">' +
                        (wear != null ? '<div style="margin-bottom:var(--hw-space-md)"><div style="font-size:var(--hw-font-size-xs);color:var(--hw-text-tertiary);margin-bottom:4px">HEALTH</div><div class="hw-card-value">' + wear.toFixed(0) + '<span class="hw-card-unit">%</span></div></div>' : '') +
                        (designed != null ? '<div class="hw-info-grid"><span class="hw-info-label">Designed</span><span class="hw-info-value">' + designed.toFixed(0) + ' mWh</span>' +
                            '<span class="hw-info-label">Current</span><span class="hw-info-value">' + (current || 0).toFixed(0) + ' mWh</span></div>' : '') +
                        (cycles != null ? '<div style="margin-top:var(--hw-space-md)"><span class="hw-info-label">Cycles: </span><span class="hw-info-value">' + cycles + '</span></div>' : '') +
                    '</div>' +
                '</div>' +
            '</div>';

        this._renderTimeRange();
    },

    destroy: function() {
        this._charts.forEach(function(c) { if (c.destroy) c.destroy(); });
        this._charts = [];
    },

    onSSEData: function() {},

    _renderTimeRange: function() {
        var container = document.getElementById('bat-time-range');
        if (!container) return;
        var self = this;
        container.innerHTML = '';
        Object.keys(HumWatch.utils.timeRangePresets).forEach(function(key) {
            var btn = document.createElement('button');
            btn.className = 'hw-btn' + (key === self._timeRange ? ' active' : '');
            btn.textContent = HumWatch.utils.timeRangePresets[key].label;
            btn.addEventListener('click', function() { self._timeRange = key; self._renderTimeRange(); self._loadCharts(); });
            container.appendChild(btn);
        });
    },

    _loadCharts: function() {
        var self = this;
        var range = HumWatch.utils.getTimeRange(this._timeRange);
        this._charts.forEach(function(c) { if (c.destroy) c.destroy(); });
        this._charts = [];
        var colors = HumWatch.charts.getColors().chart;

        HumWatch.api.getHistoryMulti(['battery_percent', 'battery_charge_rate', 'battery_voltage', 'battery_temp'], range.from, range.to).then(function(data) {
            var chargeCanvas = document.getElementById('bat-charge-chart');
            if (chargeCanvas && data['battery_percent'] && data['battery_percent'].length > 0)
                self._charts.push(HumWatch.charts.createAreaChart(chargeCanvas, [{ label: 'Charge', data: HumWatch.charts.historyToChartData(data['battery_percent']), borderColor: colors[2] }], { yLabel: '%', yMin: 0, yMax: 100 }));

            var rateCanvas = document.getElementById('bat-rate-chart');
            if (rateCanvas && data['battery_charge_rate'] && data['battery_charge_rate'].length > 0)
                self._charts.push(HumWatch.charts.createTimeSeriesChart(rateCanvas, [{ label: 'Rate', data: HumWatch.charts.historyToChartData(data['battery_charge_rate']), borderColor: colors[0] }], { yLabel: 'W' }));

            var voltCanvas = document.getElementById('bat-voltage-chart');
            if (voltCanvas && data['battery_voltage'] && data['battery_voltage'].length > 0)
                self._charts.push(HumWatch.charts.createTimeSeriesChart(voltCanvas, [{ label: 'Voltage', data: HumWatch.charts.historyToChartData(data['battery_voltage']), borderColor: colors[5] }], { yLabel: 'V' }));

            var tempCanvas = document.getElementById('bat-temp-chart');
            if (tempCanvas && data['battery_temp'] && data['battery_temp'].length > 0)
                self._charts.push(HumWatch.charts.createTimeSeriesChart(tempCanvas, [{ label: 'Temp', data: HumWatch.charts.historyToChartData(data['battery_temp']), borderColor: colors[3] }], { yLabel: '\u00B0C' }));

            // Mark any charts that didn't get data as unavailable
            HumWatch.utils.markEmptyCharts(self._container);
        }).catch(function() {
            HumWatch.utils.markEmptyCharts(self._container);
        });
    },
};
