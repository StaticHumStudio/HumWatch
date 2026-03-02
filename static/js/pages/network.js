/**
 * HumWatch — Network detail page.
 */
window.HumWatch = window.HumWatch || {};
HumWatch.pages = HumWatch.pages || {};

HumWatch.pages.network = {
    _charts: [],
    _timeRange: '1h',

    init: function(container) {
        this._charts = [];
        this._container = container;
        container.innerHTML =
            '<div class="hw-page-header"><h2>Network</h2></div>' +
            '<div class="hw-time-range" id="net-time-range"></div>' +
            '<div class="hw-grid hw-grid-2" style="margin-top:var(--hw-space-md)">' +
                '<div class="hw-card"><div class="hw-card-header"><span class="hw-card-title">Throughput</span></div><div class="hw-chart-container"><canvas id="net-throughput-chart"></canvas></div></div>' +
                '<div class="hw-card" id="net-totals"><div class="hw-card-header"><span class="hw-card-title">Cumulative Transfer</span></div><div id="net-totals-content"></div></div>' +
            '</div>';

        this._renderTimeRange();
        this._loadCharts();
        this._loadTotals();
    },

    destroy: function() {
        this._charts.forEach(function(c) { if (c.destroy) c.destroy(); });
        this._charts = [];
    },

    onSSEData: function(data) {
        if (data && data.categories && data.categories.network) {
            this._updateTotals(data.categories.network);
        }
    },

    _renderTimeRange: function() {
        var container = document.getElementById('net-time-range');
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

        HumWatch.api.getHistoryMulti(['net_sent_rate', 'net_recv_rate'], range.from, range.to).then(function(data) {
            var canvas = document.getElementById('net-throughput-chart');
            if (!canvas) return;
            var ds = [];
            if (data['net_recv_rate'] && data['net_recv_rate'].length > 0)
                ds.push({ label: 'Download', data: HumWatch.charts.historyToChartData(data['net_recv_rate']), borderColor: colors[1] });
            if (data['net_sent_rate'] && data['net_sent_rate'].length > 0)
                ds.push({ label: 'Upload', data: HumWatch.charts.historyToChartData(data['net_sent_rate']), borderColor: colors[0] });
            if (ds.length > 0)
                self._charts.push(HumWatch.charts.createAreaChart(canvas, ds, { yLabel: 'MB/s', yMin: 0, legend: true }));
            HumWatch.utils.markEmptyCharts(self._container);
        }).catch(function() {
            HumWatch.utils.markEmptyCharts(self._container);
        });
    },

    _loadTotals: function() {
        var self = this;
        HumWatch.api.getCurrent().then(function(data) {
            if (data && data.categories && data.categories.network)
                self._updateTotals(data.categories.network);
        }).catch(function() {});
    },

    _updateTotals: function(netData) {
        var el = document.getElementById('net-totals-content');
        if (!el) return;
        var sent = (netData.net_bytes_sent || {}).value;
        var recv = (netData.net_bytes_recv || {}).value;
        el.innerHTML =
            '<div class="hw-info-grid" style="margin-top:var(--hw-space-md)">' +
                '<span class="hw-info-label">Downloaded</span><span class="hw-info-value">' + HumWatch.utils.formatBytes(recv) + '</span>' +
                '<span class="hw-info-label">Uploaded</span><span class="hw-info-value">' + HumWatch.utils.formatBytes(sent) + '</span>' +
            '</div>';
    },
};
