/**
 * HumWatch — Time range helpers, timezone management, and relative time display.
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

// --- Timezone management ---

HumWatch.utils._timezoneCache = null;

HumWatch.utils.getTimezone = function() {
    if (HumWatch.utils._timezoneCache) return HumWatch.utils._timezoneCache;
    var stored = localStorage.getItem('humwatch_timezone');
    if (stored && stored !== 'auto') {
        HumWatch.utils._timezoneCache = stored;
        return stored;
    }
    var detected = Intl.DateTimeFormat().resolvedOptions().timeZone;
    HumWatch.utils._timezoneCache = detected;
    return detected;
};

HumWatch.utils.setTimezone = function(tz) {
    if (tz === 'auto') {
        localStorage.removeItem('humwatch_timezone');
    } else {
        localStorage.setItem('humwatch_timezone', tz);
    }
    HumWatch.utils._timezoneCache = null; // clear cache
};

HumWatch.utils.isAutoTimezone = function() {
    var stored = localStorage.getItem('humwatch_timezone');
    return !stored || stored === 'auto';
};

// Common IANA timezone list for the Settings selector
HumWatch.utils.timezoneList = [
    'America/New_York',
    'America/Chicago',
    'America/Denver',
    'America/Los_Angeles',
    'America/Anchorage',
    'Pacific/Honolulu',
    'America/Toronto',
    'America/Vancouver',
    'America/Sao_Paulo',
    'America/Argentina/Buenos_Aires',
    'America/Mexico_City',
    'Europe/London',
    'Europe/Berlin',
    'Europe/Paris',
    'Europe/Rome',
    'Europe/Madrid',
    'Europe/Amsterdam',
    'Europe/Stockholm',
    'Europe/Moscow',
    'Asia/Dubai',
    'Asia/Kolkata',
    'Asia/Bangkok',
    'Asia/Singapore',
    'Asia/Shanghai',
    'Asia/Tokyo',
    'Asia/Seoul',
    'Australia/Sydney',
    'Australia/Melbourne',
    'Australia/Perth',
    'Pacific/Auckland',
    'UTC',
];

// --- Time range helpers ---

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

// --- Formatting with timezone support ---

HumWatch.utils.formatTimestamp = function(isoString) {
    if (!isoString) return '';
    var d = (isoString instanceof Date) ? isoString : new Date(isoString);
    var tz = HumWatch.utils.getTimezone();
    return d.toLocaleTimeString([], {
        hour: '2-digit', minute: '2-digit', second: '2-digit',
        timeZone: tz,
    });
};

HumWatch.utils.formatTime = function(isoString) {
    if (!isoString) return '';
    var d = (isoString instanceof Date) ? isoString : new Date(isoString);
    var tz = HumWatch.utils.getTimezone();
    return d.toLocaleTimeString([], {
        hour: '2-digit', minute: '2-digit',
        timeZone: tz,
    });
};

HumWatch.utils.formatDate = function(isoString) {
    if (!isoString) return '';
    var d = (isoString instanceof Date) ? isoString : new Date(isoString);
    var tz = HumWatch.utils.getTimezone();
    return d.toLocaleDateString([], { month: 'short', day: 'numeric', timeZone: tz }) + ' ' +
           d.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit', timeZone: tz });
};

/**
 * Format a Date object for Chart.js axis ticks and tooltips.
 * Accepts format hints: 'time' (HH:mm:ss), 'short' (HH:mm), 'day' (MMM d).
 */
HumWatch.utils.formatChartTime = function(date, hint) {
    if (!date) return '';
    var tz = HumWatch.utils.getTimezone();
    if (hint === 'day') {
        return date.toLocaleDateString([], { month: 'short', day: 'numeric', timeZone: tz });
    }
    if (hint === 'time') {
        return date.toLocaleTimeString([], {
            hour: '2-digit', minute: '2-digit', second: '2-digit',
            timeZone: tz,
        });
    }
    // default: short time
    return date.toLocaleTimeString([], {
        hour: '2-digit', minute: '2-digit',
        timeZone: tz,
    });
};

// --- Relative time ---

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
