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
      _setVal('msgGwWeixinAllowedUsers',  w.allowed_users);
      _renderWeixinStatus(w);

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

  // ─── Weixin (Tencent iLink bot) QR-login flow ──────────────────────────
  function _renderWeixinStatus(w){
    const line = _q('msgGwWeixinStatusLine');
    if(!line) return;
    if(w && w.enabled && w.account_id){
      line.innerHTML = '✅ <span style="color:var(--accent)">已绑定</span>  '
        + `account_id=<code>${w.account_id}</code>`
        + (w.base_url ? `  base_url=<code>${w.base_url}</code>` : '')
        + (w.token_masked ? `  token=<code>${w.token_masked}</code>` : '');
    }else{
      line.innerHTML = '⚪ 尚未绑定。点击下方「扫码登录」用个人微信扫码授权一个小微机器人账号。';
    }
  }

  let _wxQrId = '';
  let _wxPollAbort = false;
  let _wxPollTimer = null;

  function _setWxQrStatusText(s, kind){
    const el = _q('msgGwWeixinQrStatusText');
    if(!el) return;
    el.textContent = s || '';
    el.style.color = kind==='ok' ? 'var(--accent)'
                   : kind==='warn' ? '#d29922'
                   : kind==='err' ? '#e94560'
                   : 'var(--text)';
  }
  function _setWxHint(s){
    const el = _q('msgGwWeixinQrHint');
    if(el) el.textContent = s || '';
  }

  function _stopWxPoll(){
    _wxPollAbort = true;
    if(_wxPollTimer){ clearTimeout(_wxPollTimer); _wxPollTimer = null; }
  }

  async function startWeixinQrLogin(){
    _stopWxPoll();
    _wxPollAbort = false;
    const box = _q('msgGwWeixinQrBox');
    const img = _q('msgGwWeixinQrImg');
    const btn = _q('msgGwWeixinQrBtn');
    if(btn) btn.disabled = true;
    if(box) box.style.display = '';
    _setWxQrStatusText('正在向腾讯 iLink 申请二维码…', 'warn');
    _setWxHint('');
    if(img) img.src = '';
    try{
      const r = await api('/api/messaging-gateway/weixin/qrcode');
      if(!r || !r.ok){
        _setWxQrStatusText('❌ 获取二维码失败：' + ((r && r.error) || '未知错误'), 'err');
        if(btn) btn.disabled = false;
        return;
      }
      _wxQrId = r.qrcode || '';
      if(img && r.qrcode_url) img.src = r.qrcode_url;
      _setWxQrStatusText('📱 请使用个人微信扫描二维码…', 'warn');
      _pollWeixinQrStatus();
    }catch(err){
      _setWxQrStatusText('❌ 请求失败：' + (err && err.message ? err.message : err), 'err');
      if(btn) btn.disabled = false;
    }
  }

  function _pollWeixinQrStatus(){
    if(_wxPollAbort || !_wxQrId) return;
    _wxPollTimer = setTimeout(async () => {
      try{
        const r = await api('/api/messaging-gateway/weixin/qrcode/status?qrcode='
                            + encodeURIComponent(_wxQrId));
        const st = (r && r.status) || 'wait';
        if(st === 'wait'){
          _setWxQrStatusText('📱 等待扫描…', 'warn');
          _pollWeixinQrStatus();
        }else if(st === 'scaned'){
          _setWxQrStatusText('✅ 已扫描，请在手机上点击「确认登录」…', 'warn');
          _pollWeixinQrStatus();
        }else if(st === 'expired'){
          _setWxQrStatusText('⌛ 二维码已过期，请重新点击「扫码登录」。', 'err');
          const btn = _q('msgGwWeixinQrBtn'); if(btn) btn.disabled = false;
        }else if(st === 'confirmed'){
          _setWxQrStatusText('🎉 已确认登录，正在保存凭证…', 'ok');
          try{
            await api('/api/messaging-gateway/weixin/save', {
              method: 'POST',
              body: JSON.stringify({
                account_id: r.account_id || '',
                token:      r.token || '',
                base_url:   r.base_url || '',
              }),
            });
            _setWxQrStatusText('✅ 凭证已写入 .env。重启 Gateway 后生效。', 'ok');
            _setStatus('微信扫码登录成功，凭证已保存。请重启 Gateway（关闭 Start 窗口后重新双击启动）。', 'ok');
            await loadMessagingGatewayConfig();
          }catch(err){
            _setWxQrStatusText('❌ 保存凭证失败：' + (err && err.message ? err.message : err), 'err');
          }finally{
            const btn = _q('msgGwWeixinQrBtn'); if(btn) btn.disabled = false;
          }
        }else{
          _setWxQrStatusText('❌ 错误：' + ((r && r.error) || st), 'err');
          const btn = _q('msgGwWeixinQrBtn'); if(btn) btn.disabled = false;
        }
      }catch(err){
        // Network blip — long poll often legitimately times out; just retry.
        _pollWeixinQrStatus();
      }
    }, 1500);
  }

  window.startWeixinQrLogin = startWeixinQrLogin;
})();
