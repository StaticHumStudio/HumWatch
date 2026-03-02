/**
 * HumWatch — Canvas-based circular arc gauges.
 */
window.HumWatch = window.HumWatch || {};
HumWatch.gauges = {};

HumWatch.gauges.create = function(canvas, config) {
    var ctx = canvas.getContext('2d');
    var gauge = {
        canvas: canvas,
        ctx: ctx,
        min: config.min || 0,
        max: config.max || 100,
        value: config.value || 0,
        targetValue: config.value || 0,
        label: config.label || '',
        unit: config.unit || '',
        warnThreshold: config.warnThreshold,
        critThreshold: config.critThreshold,
        _animFrame: null,
    };

    gauge.update = function(newValue) {
        gauge.targetValue = Math.max(gauge.min, Math.min(gauge.max, newValue));
        if (!gauge._animFrame) {
            gauge._animate();
        }
    };

    gauge._animate = function() {
        var diff = gauge.targetValue - gauge.value;
        if (Math.abs(diff) < 0.1) {
            gauge.value = gauge.targetValue;
            gauge._draw();
            gauge._animFrame = null;
            return;
        }
        gauge.value += diff * 0.15;
        gauge._draw();
        gauge._animFrame = requestAnimationFrame(gauge._animate);
    };

    gauge._getColor = function(val) {
        var s = getComputedStyle(document.documentElement);
        var cold = s.getPropertyValue('--hw-gauge-cold').trim() || '#4ecdc4';
        var warm = s.getPropertyValue('--hw-gauge-warm').trim() || '#c9a84c';
        var hot = s.getPropertyValue('--hw-gauge-hot').trim() || '#e74c3c';

        if (gauge.critThreshold != null && val >= gauge.critThreshold) return hot;
        if (gauge.warnThreshold != null && val >= gauge.warnThreshold) return warm;

        // Interpolate between cold and warm based on position in range
        var pct = (val - gauge.min) / (gauge.max - gauge.min);
        if (pct < 0.5) return cold;
        if (pct < 0.75) return warm;
        return hot;
    };

    gauge._draw = function() {
        var w = canvas.width;
        var h = canvas.height;
        var size = Math.min(w, h);
        var cx = w / 2;
        var cy = h / 2;
        var radius = size * 0.38;
        var lineWidth = size * 0.08;

        ctx.clearRect(0, 0, w, h);

        // Arc geometry: 220 degrees, starting from lower-left
        var startAngle = Math.PI * 0.75;
        var endAngle = Math.PI * 2.25;
        var totalAngle = endAngle - startAngle;

        // Background arc
        var s = getComputedStyle(document.documentElement);
        var bgColor = s.getPropertyValue('--hw-bg-tertiary').trim() || '#1a1a26';
        ctx.beginPath();
        ctx.arc(cx, cy, radius, startAngle, endAngle);
        ctx.strokeStyle = bgColor;
        ctx.lineWidth = lineWidth;
        ctx.lineCap = 'round';
        ctx.stroke();

        // Value arc
        var pct = (gauge.value - gauge.min) / (gauge.max - gauge.min);
        pct = Math.max(0, Math.min(1, pct));
        var valueAngle = startAngle + totalAngle * pct;

        if (pct > 0.005) {
            ctx.beginPath();
            ctx.arc(cx, cy, radius, startAngle, valueAngle);
            ctx.strokeStyle = gauge._getColor(gauge.value);
            ctx.lineWidth = lineWidth;
            ctx.lineCap = 'round';
            ctx.stroke();
        }

        // Value text
        var textColor = s.getPropertyValue('--hw-text-primary').trim() || '#e8e6e1';
        var dimColor = s.getPropertyValue('--hw-text-secondary').trim() || '#9a9890';
        var valueText = gauge.value.toFixed(gauge.unit === '%' ? 0 : 1);

        ctx.fillStyle = textColor;
        ctx.font = 'bold ' + (size * 0.18) + 'px "JetBrains Mono", monospace';
        ctx.textAlign = 'center';
        ctx.textBaseline = 'middle';
        ctx.fillText(valueText, cx, cy - size * 0.02);

        // Unit text
        ctx.fillStyle = dimColor;
        ctx.font = (size * 0.09) + 'px "JetBrains Mono", monospace';
        ctx.fillText(gauge.unit, cx, cy + size * 0.14);

        // Label text
        ctx.fillStyle = dimColor;
        ctx.font = (size * 0.07) + 'px "JetBrains Mono", monospace';
        ctx.textTransform = 'uppercase';
        ctx.fillText(gauge.label.toUpperCase(), cx, cy + size * 0.32);
    };

    gauge.destroy = function() {
        if (gauge._animFrame) {
            cancelAnimationFrame(gauge._animFrame);
            gauge._animFrame = null;
        }
    };

    // Set canvas resolution for HiDPI
    var dpr = window.devicePixelRatio || 1;
    var rect = canvas.getBoundingClientRect();
    canvas.width = rect.width * dpr;
    canvas.height = rect.height * dpr;
    ctx.scale(dpr, dpr);
    canvas.style.width = rect.width + 'px';
    canvas.style.height = rect.height + 'px';
    // Reset scale for drawing (use canvas pixel coords)
    ctx.setTransform(1, 0, 0, 1, 0, 0);
    canvas.width = rect.width * dpr;
    canvas.height = rect.height * dpr;

    // Initial draw
    gauge._draw();
    return gauge;
};
