/**
 * HumWatch — Chart.js configuration factory.
 */
window.HumWatch = window.HumWatch || {};
HumWatch.charts = {};

HumWatch.charts._colors = null;

HumWatch.charts.getColors = function() {
    if (HumWatch.charts._colors) return HumWatch.charts._colors;
    var s = getComputedStyle(document.documentElement);
    HumWatch.charts._colors = {
        chart: [
            s.getPropertyValue('--hw-chart-1').trim(),
            s.getPropertyValue('--hw-chart-2').trim(),
            s.getPropertyValue('--hw-chart-3').trim(),
            s.getPropertyValue('--hw-chart-4').trim(),
            s.getPropertyValue('--hw-chart-5').trim(),
            s.getPropertyValue('--hw-chart-6').trim(),
            s.getPropertyValue('--hw-chart-7').trim(),
            s.getPropertyValue('--hw-chart-8').trim(),
        ],
        text: s.getPropertyValue('--hw-text-secondary').trim(),
        textDim: s.getPropertyValue('--hw-text-tertiary').trim(),
        grid: s.getPropertyValue('--hw-border-color').trim(),
        bg: s.getPropertyValue('--hw-bg-primary').trim(),
    };
    return HumWatch.charts._colors;
};

HumWatch.charts.resetColors = function() {
    HumWatch.charts._colors = null;
};

HumWatch.charts._commonOptions = function() {
    var colors = HumWatch.charts.getColors();
    return {
        responsive: true,
        maintainAspectRatio: false,
        animation: { duration: 0 },
        interaction: {
            mode: 'index',
            intersect: false,
        },
        plugins: {
            legend: {
                display: false,
            },
            tooltip: {
                backgroundColor: 'rgba(10, 10, 15, 0.9)',
                titleColor: colors.text,
                bodyColor: colors.text,
                borderColor: colors.grid,
                borderWidth: 1,
                titleFont: { family: "'JetBrains Mono', monospace", size: 11 },
                bodyFont: { family: "'JetBrains Mono', monospace", size: 11 },
                padding: 8,
            },
        },
        scales: {
            x: {
                display: true,
                type: 'time',
                time: {
                    tooltipFormat: 'HH:mm:ss',
                    displayFormats: {
                        second: 'HH:mm:ss',
                        minute: 'HH:mm',
                        hour: 'HH:mm',
                        day: 'MMM d',
                    }
                },
                border: {
                    display: true,
                    color: colors.grid,
                },
                grid: {
                    color: colors.grid,
                },
                ticks: {
                    display: true,
                    color: colors.text,
                    font: { family: "'JetBrains Mono', monospace", size: 10 },
                    maxTicksLimit: 6,
                    maxRotation: 0,
                }
            },
            y: {
                display: true,
                border: {
                    display: true,
                    color: colors.grid,
                },
                grid: {
                    color: colors.grid,
                },
                ticks: {
                    display: true,
                    color: colors.text,
                    font: { family: "'JetBrains Mono', monospace", size: 10 },
                    maxTicksLimit: 5,
                },
            },
        },
    };
};

HumWatch.charts.createTimeSeriesChart = function(canvas, datasets, options) {
    var colors = HumWatch.charts.getColors();
    var chartDatasets = datasets.map(function(ds, i) {
        return Object.assign({
            borderColor: colors.chart[i % colors.chart.length],
            backgroundColor: 'transparent',
            borderWidth: 1.5,
            pointRadius: 0,
            pointHitRadius: 10,
            tension: 0.3,
        }, ds);
    });

    var opts = HumWatch.charts._commonOptions();
    if (options) {
        if (options.yLabel) {
            opts.scales.y.title = { display: true, text: options.yLabel, color: colors.textDim,
                font: { family: "'JetBrains Mono', monospace", size: 10 } };
        }
        if (options.yMin !== undefined) opts.scales.y.min = options.yMin;
        if (options.yMax !== undefined) opts.scales.y.max = options.yMax;
        if (options.legend) opts.plugins.legend.display = true;
        if (options.legend) {
            opts.plugins.legend.labels = {
                color: colors.text,
                font: { family: "'JetBrains Mono', monospace", size: 10 },
                boxWidth: 12,
                padding: 8,
            };
        }
    }

    return new Chart(canvas, {
        type: 'line',
        data: { datasets: chartDatasets },
        options: opts,
    });
};

HumWatch.charts.createAreaChart = function(canvas, datasets, options) {
    var colors = HumWatch.charts.getColors();
    var chartDatasets = datasets.map(function(ds, i) {
        var color = ds.borderColor || colors.chart[i % colors.chart.length];
        return Object.assign({
            borderColor: color,
            backgroundColor: color + '30', // 30 = ~19% opacity hex
            borderWidth: 1.5,
            pointRadius: 0,
            pointHitRadius: 10,
            tension: 0.3,
            fill: 'origin',
        }, ds);
    });

    var opts = HumWatch.charts._commonOptions();
    if (options) {
        if (options.yLabel) {
            opts.scales.y.title = { display: true, text: options.yLabel, color: colors.textDim,
                font: { family: "'JetBrains Mono', monospace", size: 10 } };
        }
        if (options.yMin !== undefined) opts.scales.y.min = options.yMin;
        if (options.yMax !== undefined) opts.scales.y.max = options.yMax;
    }

    return new Chart(canvas, {
        type: 'line',
        data: { datasets: chartDatasets },
        options: opts,
    });
};

HumWatch.charts.createSparkline = function(canvas, data, color) {
    var c = color || HumWatch.charts.getColors().chart[0];
    // Use fixed canvas dimensions to prevent runaway resizing
    canvas.width = 120;
    canvas.height = 32;
    return new Chart(canvas, {
        type: 'line',
        data: {
            datasets: [{
                data: data,
                borderColor: c,
                backgroundColor: c + '20',
                borderWidth: 1,
                pointRadius: 0,
                tension: 0.4,
                fill: 'origin',
            }]
        },
        options: {
            responsive: false,
            maintainAspectRatio: false,
            animation: { duration: 0 },
            plugins: { legend: { display: false }, tooltip: { enabled: false } },
            scales: {
                x: { type: 'time', display: false },
                y: { display: false },
            },
        },
    });
};

// Helper to push a data point and maintain window
HumWatch.charts.appendData = function(chart, datasetIndex, point, maxPoints) {
    var ds = chart.data.datasets[datasetIndex];
    if (!ds) return;
    ds.data.push(point);
    if (maxPoints && ds.data.length > maxPoints) {
        ds.data.shift();
    }
    chart.update('none');
};

// Helper to load full dataset
HumWatch.charts.setData = function(chart, datasetIndex, data) {
    var ds = chart.data.datasets[datasetIndex];
    if (!ds) return;
    ds.data = data;
    chart.update('none');
};

// Convert API history response to Chart.js data format
HumWatch.charts.historyToChartData = function(historyArray) {
    return historyArray.map(function(d) {
        return { x: new Date(d.timestamp), y: d.value };
    });
};
