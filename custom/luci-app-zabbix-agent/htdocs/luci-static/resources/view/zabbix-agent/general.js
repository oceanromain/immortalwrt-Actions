'use strict';
'require form';
'require rpc';
'require uci';
'require view';

const callRcInit = rpc.declare({
	object: 'rc',
	method: 'init',
	params: [ 'name', 'action' ],
	expect: { result: false }
});

return view.extend({
	render: function() {
		let m, s, o;

		m = new form.Map('zabbix_agentd', _('Zabbix Agent'),
			_('Manage Zabbix agent service and connection settings.'));

		s = m.section(form.NamedSection, 'general', 'zabbix_agentd');
		s.anonymous = true;

		o = s.option(form.Flag, 'enabled', _('Enable'));
		o.default = '1';
		o.rmempty = false;

		o = s.option(form.Value, 'server', _('Zabbix server'),
			_('Comma-separated passive Zabbix server IP addresses or hostnames.'));
		o.default = '127.0.0.1';

		o = s.option(form.Value, 'server_active', _('Active Zabbix server'),
			_('Zabbix active-check target, e.g. 127.0.0.1:10051. Leave empty to disable active checks.'));
		o.placeholder = '127.0.0.1:10051';

		o = s.option(form.Value, 'hostname', _('Hostname'),
			_('Optional unique host name. Defaults to the system hostname.'));

		o = s.option(form.Value, 'listen_ip', _('Listen IP'));
		o.datatype = 'ipaddr';
		o.default = '0.0.0.0';

		o = s.option(form.Value, 'listen_port', _('Listen port'));
		o.datatype = 'port';
		o.default = '10050';

		o = s.option(form.ListValue, 'debug_level', _('Debug level'));
		o.value('0', _('Critical'));
		o.value('1', _('Error'));
		o.value('2', _('Warning'));
		o.value('3', _('Notice'));
		o.value('4', _('Debug'));
		o.default = '3';

		o = s.option(form.Value, 'timeout', _('Timeout'),
			_('Agent check timeout in seconds (1-30).'));
		o.datatype = 'range(1,30)';
		o.default = '3';

		return m.render();
	},

	handleSaveApply: function(ev, mode) {
		return view.prototype.handleSaveApply.apply(this, arguments).then(function() {
			return callRcInit('zabbix-agentd-sync', 'restart');
		}).then(function() {
			return callRcInit('zabbix_agentd', 'restart');
		});
	}
});
