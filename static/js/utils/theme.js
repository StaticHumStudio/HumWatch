/**
 * HumWatch — Theme switching logic.
 */
window.HumWatch = window.HumWatch || {};
HumWatch.theme = {};

HumWatch.theme.STORAGE_KEY = 'humwatch_theme';

HumWatch.theme.available = {
    'default': { name: 'Default (Static Hum)', file: null },
    'light':   { name: 'Light', file: '/css/themes/theme-light.css' },
    'terminal': { name: 'Terminal', file: '/css/themes/theme-terminal.css' }
};

HumWatch.theme.get = function() {
    return localStorage.getItem(HumWatch.theme.STORAGE_KEY) || 'default';
};

HumWatch.theme.set = function(themeName) {
    var themeInfo = HumWatch.theme.available[themeName];
    if (!themeInfo) themeName = 'default';
    themeInfo = HumWatch.theme.available[themeName];

    var link = document.getElementById('theme-override');
    if (link) {
        link.href = themeInfo.file || '';
    }

    localStorage.setItem(HumWatch.theme.STORAGE_KEY, themeName);
};

HumWatch.theme.init = function() {
    var current = HumWatch.theme.get();
    HumWatch.theme.set(current);
};
