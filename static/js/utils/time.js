/**
 * HumWatch — Time range helpers and relative time display.
 */
window.HumWatch = window.HumWatch || {};
HumWatch.utils = HumWatch.utils || {};

HumWatch.utils.timeRangePresets = {
    '5m':  { seconds: 300,    label: '5m' },
    '15m': { seconds: 900,    label: '15m' },
    '1h':  { seconds: 3600,   label: '1h' },
    '6h':  { seconds: 21600,  label: '6h' },
    '24h': { seconds: 86400,  label: '24h' },
    '3d':  { seconds: 259200, label: '3d' },
    '7d':  { seconds: 604800, label: '7d' }
};

HumWatch.utils.getTimeRange = function(preset) {
    var info = HumWatch.utils.timeRangePresets[preset];
    if (!info) info = { seconds: 3600 };
    var now = new Date();
    var from = new Date(now.getTime() - info.seconds * 1000);
    return {
        from: from.toISOString(),
        to: now.toISOString()
    };
};

HumWatch.utils.timeAgo = function(isoString) {
    if (!isoString) return '';
    var date = new Date(isoString);
    var now = new Date();
    var diff = (now - date) / 1000;

    if (diff < 10) return 'just now';
    if (diff < 60) return Math.floor(diff) + 's ago';
    if (diff < 3600) return Math.floor(diff / 60) + 'm ago';
    if (diff < 86400) return Math.floor(diff / 3600) + 'h ago';
    return Math.floor(diff / 86400) + 'd ago';
};

HumWatch.utils.formatTimestamp = function(isoString) {
    if (!isoString) return '';
    var d = new Date(isoString);
    return d.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit', second: '2-digit' });
};

HumWatch.utils.formatDate = function(isoString) {
    if (!isoString) return '';
    var d = new Date(isoString);
    return d.toLocaleDateString([], { month: 'short', day: 'numeric' }) + ' ' +
           d.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
};
