/**
 * HumWatch — Number formatting and unit display helpers.
 */
window.HumWatch = window.HumWatch || {};
HumWatch.utils = HumWatch.utils || {};

HumWatch.utils.formatTemp = function(value) {
    if (value == null) return '--';
    return value.toFixed(1) + ' \u00B0C';
};

HumWatch.utils.formatPercent = function(value) {
    if (value == null) return '--';
    return value.toFixed(1) + '%';
};

HumWatch.utils.formatBytes = function(bytes) {
    if (bytes == null) return '--';
    if (bytes < 1024) return bytes.toFixed(0) + ' B';
    if (bytes < 1024 * 1024) return (bytes / 1024).toFixed(1) + ' KB';
    if (bytes < 1024 * 1024 * 1024) return (bytes / (1024 * 1024)).toFixed(1) + ' MB';
    if (bytes < 1024 * 1024 * 1024 * 1024) return (bytes / (1024 * 1024 * 1024)).toFixed(2) + ' GB';
    return (bytes / (1024 * 1024 * 1024 * 1024)).toFixed(2) + ' TB';
};

HumWatch.utils.formatMB = function(mb) {
    if (mb == null) return '--';
    if (mb < 1024) return mb.toFixed(0) + ' MB';
    return (mb / 1024).toFixed(1) + ' GB';
};

HumWatch.utils.formatRate = function(mbps) {
    if (mbps == null) return '--';
    if (mbps < 0.01) return (mbps * 1024).toFixed(1) + ' KB/s';
    if (mbps < 100) return mbps.toFixed(2) + ' MB/s';
    return (mbps / 1024).toFixed(2) + ' GB/s';
};

HumWatch.utils.formatUptime = function(seconds) {
    if (seconds == null) return '--';
    var d = Math.floor(seconds / 86400);
    var h = Math.floor((seconds % 86400) / 3600);
    var m = Math.floor((seconds % 3600) / 60);
    if (d > 0) return d + 'd ' + h + 'h ' + m + 'm';
    if (h > 0) return h + 'h ' + m + 'm';
    return m + 'm';
};

HumWatch.utils.formatValue = function(value, unit) {
    if (value == null) return '--';
    switch (unit) {
        case '\u00B0C': return HumWatch.utils.formatTemp(value);
        case '%': return HumWatch.utils.formatPercent(value);
        case 'MB': return HumWatch.utils.formatMB(value);
        case 'MB/s': return HumWatch.utils.formatRate(value);
        case 'MHz': return value.toFixed(0) + ' MHz';
        case 'W': return value.toFixed(1) + ' W';
        case 'V': return value.toFixed(3) + ' V';
        case 'RPM': return value.toFixed(0) + ' RPM';
        case 's': return HumWatch.utils.formatUptime(value);
        case 'bytes': return HumWatch.utils.formatBytes(value);
        case 'mAh': return value.toFixed(0) + ' mAh';
        case 'bool': return value ? 'Yes' : 'No';
        default: return value.toFixed(1);
    }
};

HumWatch.utils.getStatusClass = function(value, warnThreshold, critThreshold) {
    if (value == null) return '';
    if (value >= critThreshold) return 'critical';
    if (value >= warnThreshold) return 'warn';
    return 'ok';
};

/**
 * Scan a container for chart cards with empty canvases (no Chart.js instance)
 * and replace them with a "not available" message.
 * Call this AFTER chart building is complete.
 */
HumWatch.utils.markEmptyCharts = function(parentEl) {
    if (!parentEl) return;
    var cards = parentEl.querySelectorAll('.hw-card');
    cards.forEach(function(card) {
        // Skip cards that are already marked or don't have chart containers
        if (card.classList.contains('hw-no-data')) return;
        var chartContainer = card.querySelector('.hw-chart-container');
        if (!chartContainer) return;
        var canvas = chartContainer.querySelector('canvas');
        if (!canvas) return;

        // Check if Chart.js created a chart on this canvas
        var hasChart = canvas.__chartjs_instance__ ||
                       (Chart && Chart.getChart && Chart.getChart(canvas));
        if (!hasChart) {
            card.classList.add('hw-no-data');
            chartContainer.innerHTML =
                '<div class="hw-no-data-msg">' +
                    '<i data-lucide="slash"></i>' +
                    '<p>Not available on this hardware</p>' +
                '</div>';
            if (window.lucide) lucide.createIcons();
        }
    });
};
