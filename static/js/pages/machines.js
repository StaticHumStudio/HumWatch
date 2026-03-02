/**
 * HumWatch — Multi-machine view with Tailscale auto-discovery.
 */
window.HumWatch = window.HumWatch || {};
HumWatch.pages = HumWatch.pages || {};

HumWatch.pages.machines = {
    _refreshInterval: null,
    STORAGE_KEY: 'humwatch_machines',

    init: function(container) {
        var self = this;
        container.innerHTML =
            '<div class="hw-page-header"><h2>Machines</h2><div class="hw-subtitle">Monitor HumWatch instances across your Tailnet</div></div>' +
            '<div class="hw-card" style="margin-bottom:var(--hw-space-md)">' +
                '<div style="display:flex;gap:var(--hw-space-sm);align-items:center">' +
                    '<input class="hw-input" id="machine-ip-input" placeholder="Tailscale IP or hostname (e.g. 100.64.0.2)" style="flex:1">' +
                    '<input class="hw-input" id="machine-label-input" placeholder="Label (optional)" style="width:150px">' +
                    '<button class="hw-btn hw-btn-primary" id="machine-add-btn">Add</button>' +
                '</div>' +
            '</div>' +
            '<div id="machines-discovery-status" style="margin-bottom:var(--hw-space-sm);color:var(--hw-text-tertiary);font-size:var(--hw-font-size-sm)"></div>' +
            '<div class="hw-grid hw-grid-auto" id="machines-grid"></div>';

        document.getElementById('machine-add-btn').addEventListener('click', function() {
            self._addMachine();
        });

        document.getElementById('machine-ip-input').addEventListener('keydown', function(e) {
            if (e.key === 'Enter') self._addMachine();
        });

        this._refresh();
        this._refreshInterval = setInterval(function() { self._refresh(); }, 30000);
    },

    destroy: function() {
        if (this._refreshInterval) {
            clearInterval(this._refreshInterval);
            this._refreshInterval = null;
        }
    },

    onSSEData: function() {},

    _getMachines: function() {
        try { return JSON.parse(localStorage.getItem(this.STORAGE_KEY)) || []; }
        catch (e) { return []; }
    },

    _saveMachines: function(machines) {
        localStorage.setItem(this.STORAGE_KEY, JSON.stringify(machines));
    },

    _addMachine: function() {
        var ipInput = document.getElementById('machine-ip-input');
        var labelInput = document.getElementById('machine-label-input');
        var ip = (ipInput.value || '').trim();
        if (!ip) return;

        // Normalize: add port if not present
        if (!ip.includes(':')) ip += ':9100';
        if (!ip.startsWith('http')) ip = 'http://' + ip;

        var machines = this._getMachines();
        // Avoid duplicates
        if (machines.some(function(m) { return m.url === ip; })) return;

        machines.push({ url: ip, label: labelInput.value.trim() || '' });
        this._saveMachines(machines);
        ipInput.value = '';
        labelInput.value = '';
        this._refresh();
    },

    _removeMachine: function(url) {
        var machines = this._getMachines().filter(function(m) { return m.url !== url; });
        this._saveMachines(machines);
        this._refresh();
    },

    _extractIp: function(url) {
        return (url || '').replace(/^https?:\/\//, '').replace(/:\d+.*$/, '');
    },

    _refresh: function() {
        var grid = document.getElementById('machines-grid');
        var statusEl = document.getElementById('machines-discovery-status');
        if (!grid) return;

        var self = this;
        var manualMachines = this._getMachines();

        // Try auto-discovery first
        HumWatch.api.getPeers().then(function(peers) {
            peers = peers || [];

            // Build set of auto-discovered IPs for dedup
            var discoveredIps = {};
            peers.forEach(function(p) {
                discoveredIps[p.tailscale_ip] = true;
            });

            // Filter out manual entries that overlap with auto-discovered peers
            var filteredManual = manualMachines.filter(function(m) {
                var ip = self._extractIp(m.url);
                return !discoveredIps[ip];
            });

            // Persist de-duped list
            if (filteredManual.length !== manualMachines.length) {
                self._saveMachines(filteredManual);
            }

            // Update discovery status line
            if (statusEl) {
                var onlineCount = peers.filter(function(p) { return p.status === 'online'; }).length;
                if (peers.length > 0) {
                    statusEl.innerHTML =
                        '<i data-lucide="radio" style="width:14px;height:14px;display:inline-block;vertical-align:middle;margin-right:4px"></i>' +
                        onlineCount + ' auto-discovered on Tailnet';
                } else {
                    statusEl.textContent = 'Tailscale discovery inactive \u2014 add machines manually below';
                }
                if (window.lucide) lucide.createIcons();
            }

            // Render
            grid.innerHTML = '';

            // Auto-discovered peers first
            peers.forEach(function(peer) {
                self._renderDiscoveredPeer(peer, grid);
            });

            // Manual entries below
            filteredManual.forEach(function(machine) {
                self._fetchMachineStatus(machine, grid);
            });

            // Empty state
            if (peers.length === 0 && filteredManual.length === 0) {
                grid.innerHTML =
                    '<div class="hw-card"><div class="hw-empty">' +
                        '<i data-lucide="server"></i>' +
                        '<p>No machines found.</p>' +
                        '<p style="color:var(--hw-text-tertiary);font-size:var(--hw-font-size-sm);margin-top:8px">' +
                        'Install HumWatch on other Tailnet machines for auto-discovery, or add an IP above.</p>' +
                    '</div></div>';
                if (window.lucide) lucide.createIcons();
            }
        }).catch(function() {
            // /api/peers unavailable — fall back to manual-only mode
            if (statusEl) statusEl.textContent = '';
            grid.innerHTML = '';

            if (manualMachines.length === 0) {
                grid.innerHTML =
                    '<div class="hw-card"><div class="hw-empty">' +
                        '<i data-lucide="server"></i>' +
                        '<p>No machines added yet.</p>' +
                        '<p style="color:var(--hw-text-tertiary);font-size:var(--hw-font-size-sm);margin-top:8px">' +
                        'Enter a Tailscale IP above to start monitoring.</p>' +
                    '</div></div>';
                if (window.lucide) lucide.createIcons();
                return;
            }

            manualMachines.forEach(function(machine) {
                self._fetchMachineStatus(machine, grid);
            });
        });
    },

    /* ── Auto-discovered peer card ── */

    _renderDiscoveredPeer: function(peer, grid) {
        var cardId = 'machine-' + peer.tailscale_ip.replace(/\./g, '_');
        var online = peer.status === 'online';
        var label = peer.hostname || peer.tailscale_ip;
        if (peer.is_self) label += ' (this machine)';

        var osShort = (peer.os_version || '').substring(0, 35);
        var cpuShort = (peer.cpu_name || '').substring(0, 35);

        var html =
            '<div class="hw-card hw-machine-card' + (online ? '' : ' offline') + '" id="' + cardId + '"' +
                ' style="cursor:' + (peer.is_self ? 'default' : 'pointer') + '">' +
                '<div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:var(--hw-space-sm)">' +
                    '<div class="hw-machine-hostname">' + label + '</div>' +
                    '<div style="display:flex;align-items:center;gap:var(--hw-space-xs)">' +
                        '<span class="hw-badge" style="background:rgba(78,205,196,0.1);color:var(--hw-accent-teal);font-size:10px;padding:2px 6px">auto</span>' +
                        '<span class="hw-badge ' + (online ? 'hw-badge-ok' : 'hw-badge-offline') + '">' + (online ? 'Online' : 'Offline') + '</span>' +
                    '</div>' +
                '</div>' +
                '<div class="hw-machine-metrics">' +
                    '<span style="color:var(--hw-text-tertiary)">IP</span><span>' + peer.tailscale_ip + '</span>' +
                    '<span style="color:var(--hw-text-tertiary)">OS</span><span style="font-size:var(--hw-font-size-sm)">' + (osShort || '--') + '</span>' +
                    '<span style="color:var(--hw-text-tertiary)">CPU</span><span style="font-size:var(--hw-font-size-sm)">' + (cpuShort || '--') + '</span>' +
                    '<span style="color:var(--hw-text-tertiary)">GPU</span><span style="font-size:var(--hw-font-size-sm)">' + (peer.gpu_name || '--') + '</span>' +
                    '<span style="color:var(--hw-text-tertiary)">RAM</span><span>' + (peer.total_ram_mb ? Math.round(peer.total_ram_mb / 1024) + ' GB' : '--') + '</span>' +
                    '<span style="color:var(--hw-text-tertiary)">Version</span><span>' + (peer.agent_version || '--') + '</span>' +
                '</div>' +
            '</div>';

        grid.insertAdjacentHTML('beforeend', html);

        // Click to open that machine's dashboard (unless it's self)
        if (!peer.is_self) {
            var card = document.getElementById(cardId);
            if (card) {
                card.addEventListener('click', function() {
                    window.open(peer.url, '_blank');
                });
            }
        }
    },

    /* ── Manual machine card (existing pattern) ── */

    _fetchMachineStatus: function(machine, grid) {
        var self = this;
        var cardId = 'machine-' + machine.url.replace(/[^a-zA-Z0-9]/g, '_');
        var existingCard = document.getElementById(cardId);

        Promise.all([
            HumWatch.api.remoteHealth(machine.url).catch(function() { return null; }),
            HumWatch.api.remoteCurrent(machine.url).catch(function() { return null; }),
            HumWatch.api.remoteInfo(machine.url).catch(function() { return null; }),
        ]).then(function(results) {
            var health = results[0];
            var current = results[1];
            var info = results[2];
            var online = health && health.status === 'ok';

            var html = self._buildManualCard(machine, online, current, info);

            if (existingCard) {
                existingCard.outerHTML = html;
            } else {
                grid.insertAdjacentHTML('beforeend', html);
            }

            // Bind remove button + card click
            var card = document.getElementById(cardId);
            if (card) {
                var removeBtn = card.querySelector('.machine-remove');
                if (removeBtn) {
                    removeBtn.addEventListener('click', function(e) {
                        e.stopPropagation();
                        self._removeMachine(machine.url);
                    });
                }
                card.addEventListener('click', function() {
                    window.open(machine.url, '_blank');
                });
            }
        });
    },

    _buildManualCard: function(machine, online, current, info) {
        var cardId = 'machine-' + machine.url.replace(/[^a-zA-Z0-9]/g, '_');
        var hostname = (info && info.hostname) ? info.hostname : machine.url;
        var label = machine.label || hostname;
        var cats = (current && current.categories) || {};

        var cpuTemp = cats.cpu ? (cats.cpu.cpu_temp_package || {}).value : null;
        var cpuLoad = cats.cpu ? (cats.cpu.cpu_load_total || {}).value : null;
        var gpuTemp = cats.gpu ? (cats.gpu.gpu_temp || {}).value : null;
        var ramPct = cats.memory ? (cats.memory.mem_percent || {}).value : null;
        var batPct = cats.battery ? (cats.battery.battery_percent || {}).value : null;

        return '<div class="hw-card hw-machine-card' + (online ? '' : ' offline') + '" id="' + cardId + '">' +
            '<div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:var(--hw-space-sm)">' +
                '<div class="hw-machine-hostname">' + label + '</div>' +
                '<div style="display:flex;align-items:center;gap:var(--hw-space-xs)">' +
                    '<span class="hw-badge" style="background:rgba(255,199,0,0.1);color:var(--hw-accent-gold);font-size:10px;padding:2px 6px">manual</span>' +
                    '<span class="hw-badge ' + (online ? 'hw-badge-ok' : 'hw-badge-offline') + '">' + (online ? 'Online' : 'Offline') + '</span>' +
                    '<button class="hw-btn machine-remove" style="padding:2px 6px;font-size:10px" title="Remove">\u00d7</button>' +
                '</div>' +
            '</div>' +
            '<div class="hw-machine-metrics">' +
                '<span style="color:var(--hw-text-tertiary)">CPU Load</span><span>' + (cpuLoad != null ? cpuLoad.toFixed(0) + '%' : '--') + '</span>' +
                '<span style="color:var(--hw-text-tertiary)">CPU Temp</span><span>' + (cpuTemp != null ? cpuTemp.toFixed(0) + '\u00B0C' : '--') + '</span>' +
                '<span style="color:var(--hw-text-tertiary)">GPU Temp</span><span>' + (gpuTemp != null ? gpuTemp.toFixed(0) + '\u00B0C' : '--') + '</span>' +
                '<span style="color:var(--hw-text-tertiary)">RAM</span><span>' + (ramPct != null ? ramPct.toFixed(0) + '%' : '--') + '</span>' +
                (batPct != null ? '<span style="color:var(--hw-text-tertiary)">Battery</span><span>' + batPct.toFixed(0) + '%</span>' : '') +
            '</div>' +
        '</div>';
    },
};
