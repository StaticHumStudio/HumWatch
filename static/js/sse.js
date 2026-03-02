/**
 * HumWatch — SSE connection manager with auto-reconnect.
 */
window.HumWatch = window.HumWatch || {};
HumWatch.sse = {};

HumWatch.sse._source = null;
HumWatch.sse._callbacks = { metrics: [], processes: [] };
HumWatch.sse._reconnectDelay = 1000;
HumWatch.sse._maxDelay = 30000;
HumWatch.sse._connected = false;

HumWatch.sse.onMetrics = function(callback) {
    HumWatch.sse._callbacks.metrics.push(callback);
};

HumWatch.sse.onProcesses = function(callback) {
    HumWatch.sse._callbacks.processes.push(callback);
};

HumWatch.sse.offMetrics = function(callback) {
    var idx = HumWatch.sse._callbacks.metrics.indexOf(callback);
    if (idx !== -1) HumWatch.sse._callbacks.metrics.splice(idx, 1);
};

HumWatch.sse.offProcesses = function(callback) {
    var idx = HumWatch.sse._callbacks.processes.indexOf(callback);
    if (idx !== -1) HumWatch.sse._callbacks.processes.splice(idx, 1);
};

HumWatch.sse.connect = function() {
    if (HumWatch.sse._source) {
        HumWatch.sse._source.close();
    }

    var source = new EventSource('/api/sse');
    HumWatch.sse._source = source;

    source.addEventListener('metrics', function(e) {
        try {
            var data = JSON.parse(e.data);
            HumWatch.sse._callbacks.metrics.forEach(function(cb) {
                try { cb(data); } catch (err) { console.error('SSE metrics callback error:', err); }
            });
        } catch (err) {
            console.error('SSE metrics parse error:', err);
        }
    });

    source.addEventListener('processes', function(e) {
        try {
            var data = JSON.parse(e.data);
            HumWatch.sse._callbacks.processes.forEach(function(cb) {
                try { cb(data); } catch (err) { console.error('SSE processes callback error:', err); }
            });
        } catch (err) {
            console.error('SSE processes parse error:', err);
        }
    });

    source.onopen = function() {
        HumWatch.sse._connected = true;
        HumWatch.sse._reconnectDelay = 1000;
        HumWatch.sse._updateIndicator('connected');
    };

    source.onerror = function() {
        HumWatch.sse._connected = false;
        HumWatch.sse._updateIndicator('reconnecting');

        source.close();
        HumWatch.sse._source = null;

        // Exponential backoff reconnect
        setTimeout(function() {
            HumWatch.sse.connect();
            // Fetch current data to fill any gap
            HumWatch.api.getCurrent().then(function(data) {
                HumWatch.sse._callbacks.metrics.forEach(function(cb) {
                    try { cb(data); } catch (e) {}
                });
            }).catch(function() {});
        }, HumWatch.sse._reconnectDelay);

        HumWatch.sse._reconnectDelay = Math.min(
            HumWatch.sse._reconnectDelay * 2,
            HumWatch.sse._maxDelay
        );
    };
};

HumWatch.sse.disconnect = function() {
    if (HumWatch.sse._source) {
        HumWatch.sse._source.close();
        HumWatch.sse._source = null;
    }
    HumWatch.sse._connected = false;
    HumWatch.sse._updateIndicator('disconnected');
};

HumWatch.sse._updateIndicator = function(state) {
    var dot = document.getElementById('sse-dot');
    var label = document.getElementById('sse-label');
    if (!dot || !label) return;

    dot.className = 'hw-sse-dot';
    switch (state) {
        case 'connected':
            dot.classList.add('connected');
            label.textContent = 'Live';
            break;
        case 'reconnecting':
            dot.classList.add('reconnecting');
            label.textContent = 'Reconnecting...';
            break;
        default:
            label.textContent = 'Disconnected';
    }
};
