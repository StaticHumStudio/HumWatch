/**
 * HumWatch — Processes page: live table with sorting.
 */
window.HumWatch = window.HumWatch || {};
HumWatch.pages = HumWatch.pages || {};

HumWatch.pages.processes = {
    _sortKey: 'cpu_percent',
    _sortAsc: false,
    _processes: [],

    init: function(container) {
        var self = this;
        container.innerHTML =
            '<div class="hw-page-header"><h2>Processes</h2><div class="hw-subtitle">Top processes by resource usage (updated every 10s)</div></div>' +
            '<div class="hw-card">' +
                '<div class="hw-table-container">' +
                    '<table class="hw-table" id="proc-table">' +
                        '<thead><tr>' +
                            '<th data-sort="name">Name</th>' +
                            '<th data-sort="pid">PID</th>' +
                            '<th class="hw-text-right" data-sort="cpu_percent">CPU %</th>' +
                            '<th class="hw-text-right" data-sort="memory_mb">Memory</th>' +
                        '</tr></thead>' +
                        '<tbody></tbody>' +
                    '</table>' +
                '</div>' +
            '</div>';

        // Sort header clicks
        document.querySelectorAll('#proc-table th[data-sort]').forEach(function(th) {
            th.addEventListener('click', function() {
                var key = th.dataset.sort;
                if (self._sortKey === key) {
                    self._sortAsc = !self._sortAsc;
                } else {
                    self._sortKey = key;
                    self._sortAsc = key === 'name';
                }
                self._render();
            });
        });

        HumWatch.api.getProcesses().then(function(data) {
            self._processes = data.processes || [];
            self._render();
        }).catch(function() {});
    },

    destroy: function() {},

    onSSEProcesses: function(data) {
        this._processes = data.processes || [];
        this._render();
    },

    _render: function() {
        var procs = this._processes.slice();
        var key = this._sortKey;
        var asc = this._sortAsc;

        procs.sort(function(a, b) {
            var va = a[key], vb = b[key];
            if (typeof va === 'string') {
                va = va.toLowerCase(); vb = (vb || '').toLowerCase();
                return asc ? va.localeCompare(vb) : vb.localeCompare(va);
            }
            return asc ? (va - vb) : (vb - va);
        });

        var tbody = document.querySelector('#proc-table tbody');
        if (!tbody) return;
        tbody.innerHTML = procs.map(function(p) {
            return '<tr><td>' + (p.name || '--') + '</td><td>' + p.pid + '</td>' +
                '<td class="hw-text-right">' + (p.cpu_percent || 0).toFixed(1) + '%</td>' +
                '<td class="hw-text-right">' + HumWatch.utils.formatMB(p.memory_mb) + '</td></tr>';
        }).join('');
    },
};
