// U-Hermes messaging gateway settings pane.
// Loads/saves model + Feishu + Weixin config via /api/messaging-gateway.
// Backend reads/writes ~/.hermes/config.yaml and ~/.hermes/.env.

(function(){
  function _q(id){ return document.getElementById(id); }

  function _setVal(id, v){ const el=_q(id); if(el) el.value = v==null ? '' : String(v); }
  function _getVal(id){ const el=_q(id); return el ? (el.value || '').trim() : ''; }
  function _setChecked(id, v){ const el=_q(id); if(el) el.checked = !!v; }
  function _getChecked(id){ const el=_q(id); return !!(el && el.checked); }

  function _setStatus(msg, kind){
    const el=_q('msgGwStatus'); if(!el) return;
    if(!msg){ el.style.display='none'; el.textContent=''; return; }
    el.style.display='';
    el.textContent=msg;
    el.style.borderColor = kind==='error' ? 'rgba(233,69,96,.45)'
                         : kind==='ok'    ? 'rgba(46,160,67,.45)'
                         : 'var(--border2)';
  }

  async function loadMessagingGatewayConfig(){
    _setStatus('加载中…', 'info');
    try{
      const cfg = await api('/api/messaging-gateway');

      const f = cfg.feishu || {};
      _setChecked('msgGwFeishuEnabled', f.enabled);
      _setVal('msgGwFeishuAppId',          f.app_id);
      _setVal('msgGwFeishuAppSecret',      '');
      _setVal('msgGwFeishuConnectionMode', f.connection_mode || 'websocket');
      _setVal('msgGwFeishuAllowedUsers',   f.allowed_users);
      _setVal('msgGwFeishuHomeChannel',    f.home_channel);
      const fsHint=_q('msgGwFeishuSecretHint');
      if(fsHint) fsHint.textContent = f.app_secret_set ? `（已配置：${f.app_secret_masked}）` : '（未配置）';

      const w = cfg.weixin || {};
      _setChecked('msgGwWeixinEnabled',   w.enabled);
      _setVal('msgGwWeixinAccountId',     w.account_id);
      _setVal('msgGwWeixinBaseUrl',       w.base_url);
      _setVal('msgGwWeixinAllowedUsers',  w.allowed_users);

      const paths = cfg.paths || {};
      const p=_q('msgGwPaths');
      if(p) p.textContent = `config: ${paths.config || '?'}\nenv:    ${paths.env || '?'}`;

      _setStatus('', '');
    }catch(err){
      _setStatus('加载失败：' + (err && err.message ? err.message : err), 'error');
    }
  }

  async function saveMessagingGatewayConfig(){
    const payload = {
      feishu: {
        enabled:         _getChecked('msgGwFeishuEnabled'),
        app_id:          _getVal('msgGwFeishuAppId'),
        connection_mode: _getVal('msgGwFeishuConnectionMode') || 'websocket',
        allowed_users:   _getVal('msgGwFeishuAllowedUsers'),
        home_channel:    _getVal('msgGwFeishuHomeChannel'),
        ...((_getVal('msgGwFeishuAppSecret')) ? { app_secret: _getVal('msgGwFeishuAppSecret') } : {}),
      },
      weixin: {
        enabled:        _getChecked('msgGwWeixinEnabled'),
        account_id:     _getVal('msgGwWeixinAccountId'),
        base_url:       _getVal('msgGwWeixinBaseUrl'),
        allowed_users:  _getVal('msgGwWeixinAllowedUsers'),
      },
    };
    _setStatus('保存中…', 'info');
    try{
      await api('/api/messaging-gateway', { method:'POST', body: JSON.stringify(payload) });
      _setStatus('已保存。重启 Gateway 后生效：关闭 Start 窗口 → 重新双击 Windows-Start.bat / Mac-Start.command。', 'ok');
      await loadMessagingGatewayConfig();
    }catch(err){
      _setStatus('保存失败：' + (err && err.message ? err.message : err), 'error');
    }
  }

  // Expose globally so panels.js / inline onclick can call them.
  window.loadMessagingGatewayConfig = loadMessagingGatewayConfig;
  window.saveMessagingGatewayConfig = saveMessagingGatewayConfig;

  async function testFeishuConnectivity(){
    _setStatus('正在通过飞书 OpenAPI 发送测试消息…', 'info');
    try{
      const r = await api('/api/messaging-gateway/test-feishu', {
        method:'POST',
        body: '{}',
      });
      if(r && r.ok){
        _setStatus(
          `✅ 发送成功！收件方=${r.target} (${r.receive_id_type})  message_id=${r.message_id || '-'}`,
          'ok'
        );
      }else{
        const stage = r && r.stage ? `[${r.stage}] ` : '';
        const code = (r && r.code != null) ? ` (code=${r.code})` : '';
        _setStatus(`❌ ${stage}${(r && r.error) || '未知错误'}${code}`, 'error');
      }
    }catch(err){
      _setStatus('❌ 请求失败：' + (err && err.message ? err.message : err), 'error');
    }
  }
  window.testFeishuConnectivity = testFeishuConnectivity;
})();
