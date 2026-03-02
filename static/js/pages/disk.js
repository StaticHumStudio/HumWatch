/**
 * HumWatch — Disk detail page.
 */
window.HumWatch = window.HumWatch || {};
HumWatch.pages = HumWatch.pages || {};

HumWatch.pages.disk = {
    _charts: [],
    _timeRange: '1h',

    init: function(container) {
        this._charts = [];
        this._container = container;
        container.innerHTML =
            '<div class="hw-page-header"><h2>Disk</h2></div>' +
            '<div class="hw-time-range" id="disk-time-range"></div>' +
            '<div class="hw-grid hw-grid-2" style="margin-top:var(--hw-space-md)">' +
                '<div class="hw-card"><div class="hw-card-header"><span class="hw-card-title">Read / Write Throughput</span></div><div class="hw-chart-container"><canvas id="disk-io-chart"></canvas></div></div>' +
                '<div class="hw-card"><div class="hw-card-header"><span class="hw-card-title">Drive Temperatures</span></div><div class="hw-chart-container"><canvas id="disk-temp-chart"></canvas></div></div>' +
            '</div>' +
            '<div class="hw-card" style="margin-top:var(--hw-space-md)">' +
                '<div class="hw-card-header"><span class="hw-card-title">Volume Usage</span></div>' +
                '<div id="disk-volumes"></div>' +
            '</div>';

        this._renderTimeRange();
        this._loadCharts();
        this._loadVolumes();
    },

    destroy: function() {
        this._charts.forEach(function(c) { if (c.destroy) c.destroy(); });
        this._charts = [];
    },

    onSSEData: function(data) {
        if (data && data.categories && data.categories.disk) {
            this._updateVolumes(data.categories.disk);
        }
    },

    _renderTimeRange: function() {
        var container = document.getElementById('disk-time-range');
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

        HumWatch.api.getHistoryMulti(['disk_read_rate', 'disk_write_rate'], range.from, range.to).then(function(data) {
            var ioCanvas = document.getElementById('disk-io-chart');
            if (ioCanvas) {
                var ds = [];
                if (data['disk_read_rate'] && data['disk_read_rate'].length > 0)
                    ds.push({ label: 'Read', data: HumWatch.charts.historyToChartData(data['disk_read_rate']), borderColor: colors[1] });
                if (data['disk_write_rate'] && data['disk_write_rate'].length > 0)
                    ds.push({ label: 'Write', data: HumWatch.charts.historyToChartData(data['disk_write_rate']), borderColor: colors[3] });
                if (ds.length > 0)
                    self._charts.push(HumWatch.charts.createTimeSeriesChart(ioCanvas, ds, { yLabel: 'MB/s', yMin: 0, legend: true }));
            }
            HumWatch.utils.markEmptyCharts(self._container);
        }).catch(function() {
            HumWatch.utils.markEmptyCharts(self._container);
        });
    },

    _loadVolumes: function() {
        var self = this;
        HumWatch.api.getCurrent().then(function(data) {
            if (data && data.categories && data.categories.disk)
                self._updateVolumes(data.categories.disk);
        }).catch(function() {});
    },

    _updateVolumes: function(diskData) {
        var container = document.getElementById('disk-volumes');
        if (!container) return;
        var html = '';
        for (var key in diskData) {
            if (key.startsWith('disk_usage_')) {
                var drive = key.replace('disk_usage_', '');
                var pct = diskData[key].value;
                var cls = pct >= 95 ? 'critical' : (pct >= 85 ? 'warn' : '');
                html += '<div style="display:flex;align-items:center;gap:var(--hw-space-md);margin-bottom:var(--hw-space-sm)">' +
                    '<span style="font-family:var(--hw-font-display);width:40px;color:var(--hw-text-secondary)">' + drive + ':</span>' +
                    '<div class="hw-progress" style="flex:1"><div class="hw-progress-bar ' + cls + '" style="width:' + pct + '%"></div></div>' +
                    '<span style="font-family:var(--hw-font-display);font-size:var(--hw-font-size-sm);width:50px;text-align:right">' + pct.toFixed(1) + '%</span>' +
                '</div>';
            }
        }
        container.innerHTML = html || '<p class="hw-empty">No volume data available.</p>';
    },
};
