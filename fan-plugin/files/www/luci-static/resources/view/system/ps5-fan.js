'use strict';
'require view';
'require rpc';
'require ui';
'require poll';

var getStatus = rpc.declare({ object: 'ps5.fan', method: 'status', expect: {} });
var applySettings = rpc.declare({ object: 'ps5.fan', method: 'apply', params: ['mode', 'target'], expect: {} });

return view.extend({
    load: function() { return getStatus(); },

    render: function(status) {
        var mode = E('select', { 'class': 'cbi-input-select', 'id': 'ps5-fan-mode' }, [
            E('option', { value: 'auto' }, ['自动调速']),
            E('option', { value: 'max' }, ['手动全速'])
        ]);
        mode.value = status.mode || 'auto';
        var target = E('input', { 'class': 'cbi-input-text', type: 'number', min: 40, max: 80, step: 1, value: status.target || 80, 'id': 'ps5-fan-target' });
        var temperature = E('span');
        var actualTarget = E('span');
        var applied = E('span');
        var hardware = E('div', { 'class': 'alert-message warning', style: 'display:none' }, ['当前未检测到 PS5 风扇控制器，设置尚未应用。']);
        var updateStatus = function(data) {
            temperature.textContent = data.temperature_millicelsius != null ? (data.temperature_millicelsius / 1000).toFixed(1) + ' °C' : '温度传感器暂未提供读数';
            actualTarget.textContent = data.actual_target != null ? data.actual_target + ' °C' : '暂未提供';
            applied.textContent = data.applied_mode === 'auto' ? '自动调速' : data.applied_mode === 'max' ? '手动全速' : '尚未应用';
            hardware.style.display = data.hardware_available ? 'none' : '';
        };
        updateStatus(status);
        var submit = function(selectedMode) {
            var value = Number(target.value);
            if (!Number.isInteger(value) || value < 40 || value > 80) {
                ui.addNotification(null, E('p', ['请输入 40–80°C 的整数目标温度。']), 'error');
                return Promise.resolve();
            }
            return applySettings(selectedMode, value).then(function(result) {
                if (!result.ok) throw new Error(result.error || '设置未应用。');
                mode.value = selectedMode;
                updateStatus(result);
                ui.addNotification(null, E('p', ['风扇设置已应用。']), 'info');
            }).catch(function(error) { ui.addNotification(null, E('p', [error.message]), 'error'); });
        };
        poll.add(function() { return getStatus().then(updateStatus); }, 5);
        var row = function(label, control, note) {
            return E('div', { 'class': 'cbi-value' }, [
                E('label', { 'class': 'cbi-value-title' }, [label]),
                E('div', { 'class': 'cbi-value-field' }, note ? [control, E('div', { 'class': 'cbi-value-description' }, [note])] : [control])
            ]);
        };
        return E('div', {}, [
            E('h2', {}, ['PS5 风扇控制']),
            E('p', {}, ['自动模式由主机温控固件按温度调节风扇，开机默认启用。手动模式可强制全速，重启后恢复自动。']),
            hardware,
            E('div', { 'class': 'cbi-section' }, [
                E('h3', {}, ['运行状态']),
                row('APU 温度', temperature),
                row('控制器目标温度', actualTarget),
                row('最近应用模式', applied)
            ]),
            E('div', { 'class': 'cbi-section' }, [
                E('h3', {}, ['调速设置']),
                row('工作模式', mode, '当前内核支持自动调速和手动全速，未提供任意百分比或 RPM 设置。'),
                row('自动目标温度', target, '默认 80°C；较低的目标温度会让自动调速更积极，风扇噪声可能增加。'),
                E('div', { 'class': 'cbi-page-actions' }, [
                    E('button', { 'class': 'cbi-button cbi-button-apply', click: ui.createHandlerFn(this, function() { return submit(mode.value); }) }, ['应用设置']),
                    ' ',
                    E('button', { 'class': 'cbi-button', click: ui.createHandlerFn(this, function() { return submit('auto'); }) }, ['恢复自动调速'])
                ])
            ])
        ]);
    },
    handleSaveApply: null,
    handleSave: null,
    handleReset: null
});
