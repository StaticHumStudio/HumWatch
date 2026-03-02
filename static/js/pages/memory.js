/**
 * HumWatch — Memory detail page.
 */
window.HumWatch = window.HumWatch || {};
HumWatch.pages = HumWatch.pages || {};

HumWatch.pages.memory = {
    _charts: [],
    _timeRange: '1h',

    init: function(container) {
        this._charts = [];
        this._container = container;
        container.innerHTML =
            '<div class="hw-page-header"><h2>Memory</h2></div>' +
            '<div class="hw-time-range" id="mem-time-range"></div>' +
            '<div class="hw-grid hw-grid-2" style="margin-top:var(--hw-space-md)">' +
                '<div class="hw-card"><div class="hw-card-header"><span class="hw-card-title">RAM Usage</span></div><div class="hw-chart-container"><canvas id="mem-ram-chart"></canvas></div></div>' +
                '<div class="hw-card"><div class="hw-card-header"><span class="hw-card-title">Swap Usage</span></div><div class="hw-chart-container"><canvas id="mem-swap-chart"></canvas></div></div>' +
            '</div>' +
            '<div class="hw-card" style="margin-top:var(--hw-space-md)">' +
                '<div class="hw-card-header"><span class="hw-card-title">Top Processes by Memory</span></div>' +
                '<div class="hw-table-container"><table class="hw-table" id="mem-proc-table"><thead><tr><th>Name</th><th>PID</th><th class="hw-text-right">CPU %</th><th class="hw-text-right">Memory</th></tr></thead><tbody></tbody></table></div>' +
            '</div>';

        this._renderTimeRange();
        this._loadCharts();
        this._loadProcesses();
    },

    destroy: function() {
        this._charts.forEach(function(c) { if (c.destroy) c.destroy(); });
        this._charts = [];
    },

    onSSEData: function() {},
    onSSEProcesses: function(data) {
        this._renderProcessTable(data.processes || []);
    },

    _renderTimeRange: function() {
        var container = document.getElementById('mem-time-range');
        if (!container) return;
        var self = this;
        container.innerHTML = '';
        Object.keys(HumWatch.utils.timeRangePresets).forEach(function(key) {
            var btn = document.createElement('button');
            btn.className = 'hw-btn' + (key === self._timeRange ? ' active' : '');
            btn.textContent = HumWatch.utils.timeRangePresets[key].label;
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
        this._charts.forEach(function(c) { if (c.destroy) c.destroy(); });
        this._charts = [];

        HumWatch.api.getHistoryMulti(['mem_used', 'mem_percent', 'mem_swap_used'], range.from, range.to).then(function(data) {
            var colors = HumWatch.charts.getColors().chart;

            var ramCanvas = document.getElementById('mem-ram-chart');
            if (ramCanvas && data['mem_used'] && data['mem_used'].length > 0) {
                self._charts.push(HumWatch.charts.createAreaChart(ramCanvas, [{
                    label: 'Used RAM', data: HumWatch.charts.historyToChartData(data['mem_used']),
                    borderColor: colors[1],
                }], { yLabel: 'MB', yMin: 0 }));
            }

            var swapCanvas = document.getElementById('mem-swap-chart');
            if (swapCanvas && data['mem_swap_used'] && data['mem_swap_used'].length > 0) {
                self._charts.push(HumWatch.charts.createAreaChart(swapCanvas, [{
                    label: 'Used Swap', data: HumWatch.charts.historyToChartData(data['mem_swap_used']),
                    borderColor: colors[4],
                }], { yLabel: 'MB', yMin: 0 }));
            }
            HumWatch.utils.markEmptyCharts(self._container);
        }).catch(function(err) {
            console.error('Memory chart error:', err);
            HumWatch.utils.markEmptyCharts(self._container);
        });
    },

    _loadProcesses: function() {
        var self = this;
        HumWatch.api.getProcesses().then(function(data) {
            var procs = (data.processes || []).slice().sort(function(a, b) { return b.memory_mb - a.memory_mb; });
            self._renderProcessTable(procs);
        }).catch(function() {});
    },

    _renderProcessTable: function(procs) {
        var tbody = document.querySelector('#mem-proc-table tbody');
        if (!tbody) return;
        procs = procs.slice().sort(function(a, b) { return b.memory_mb - a.memory_mb; });
        tbody.innerHTML = procs.slice(0, 10).map(function(p) {
            return '<tr><td>' + p.name + '</td><td>' + p.pid + '</td>' +
                '<td class="hw-text-right">' + (p.cpu_percent || 0).toFixed(1) + '%</td>' +
                '<td class="hw-text-right">' + HumWatch.utils.formatMB(p.memory_mb) + '</td></tr>';
        }).join('');
    },
};
