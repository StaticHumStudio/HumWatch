/**
 * HumWatch — API client (fetch wrapper for all endpoints).
 */
window.HumWatch = window.HumWatch || {};
HumWatch.api = {};

HumWatch.api._baseUrl = '';

HumWatch.api._fetch = function(path, options) {
    var url = HumWatch.api._baseUrl + path;
    options = options || {};
    options.headers = options.headers || {};
    return fetch(url, options).then(function(res) {
        if (!res.ok) throw new Error('HTTP ' + res.status);
        return res.json();
    });
};

HumWatch.api._fetchWithTimeout = function(baseUrl, path, timeoutMs) {
    var url = baseUrl + path;
    var controller = new AbortController();
    var timer = setTimeout(function() { controller.abort(); }, timeoutMs || 3000);
    return fetch(url, { signal: controller.signal })
        .then(function(res) {
            clearTimeout(timer);
            if (!res.ok) throw new Error('HTTP ' + res.status);
            return res.json();
        })
        .catch(function(err) {
            clearTimeout(timer);
            throw err;
        });
};

HumWatch.api.getHealth = function() {
    return HumWatch.api._fetch('/api/health');
};

HumWatch.api.getInfo = function() {
    return HumWatch.api._fetch('/api/info');
};

HumWatch.api.getCurrent = function() {
    return HumWatch.api._fetch('/api/current');
};

HumWatch.api.getConfig = function() {
    return HumWatch.api._fetch('/api/config');
};

HumWatch.api.getHistory = function(metric, from, to, resolution) {
    var params = 'metric=' + encodeURIComponent(metric);
    if (from) params += '&from=' + encodeURIComponent(from);
    if (to) params += '&to=' + encodeURIComponent(to);
    if (resolution) params += '&resolution=' + resolution;
    return HumWatch.api._fetch('/api/history?' + params);
};

HumWatch.api.getHistoryMulti = function(metrics, from, to, resolution) {
    var params = 'metrics=' + encodeURIComponent(metrics.join(','));
    if (from) params += '&from=' + encodeURIComponent(from);
    if (to) params += '&to=' + encodeURIComponent(to);
    if (resolution) params += '&resolution=' + resolution;
    return HumWatch.api._fetch('/api/history/multi?' + params);
};

HumWatch.api.getProcesses = function() {
    return HumWatch.api._fetch('/api/processes');
};

HumWatch.api.getProcessesHistory = function(from, to) {
    var params = '';
    if (from) params += 'from=' + encodeURIComponent(from);
    if (to) params += '&to=' + encodeURIComponent(to);
    return HumWatch.api._fetch('/api/processes/history?' + params);
};

// Remote machine API calls (for multi-machine view)
HumWatch.api.remoteHealth = function(baseUrl) {
    return HumWatch.api._fetchWithTimeout(baseUrl, '/api/health', 3000);
};

HumWatch.api.remoteCurrent = function(baseUrl) {
    return HumWatch.api._fetchWithTimeout(baseUrl, '/api/current', 5000);
};

HumWatch.api.remoteInfo = function(baseUrl) {
    return HumWatch.api._fetchWithTimeout(baseUrl, '/api/info', 5000);
};
