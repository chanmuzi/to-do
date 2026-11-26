/* Float 시안 공용 스크립트. docs/mockups.md를 먼저 읽는다.
   FloatKit.note(블록 목록, 설정) → 노트 그림 HTML
   FloatKit.picks(칸 id, 항목 번호, 선택지 목록) → 고르는 카드
   FloatKit.answers({key, items}) → 맨 아래 답 복사(브라우저에 고른 값 저장) */
(function(){
  var CHK='<svg viewBox="0 0 14 14"><path d="M3.6 7.2 6 9.5 10.4 4.8"/></svg>';
  function chev(open,sz){return '<svg viewBox="0 0 12 12" style="width:'+sz+'px;height:'+sz+'px"><path d="'+(open?'M3 4.5 6 7.5 9 4.5':'M4.5 3 7.5 6 4.5 9')+'"/></svg>';}
  function esc(s){return String(s).replace(/[&<>"]/g,function(c){return {'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'}[c];});}
  /* 블록: {k:'p'|'todo'|'bullet'|'toggle', l:깊이, t:글(일반 글), html:서식 넣은 글(t 대신), d:완료, f:접힘, h:제목 1~3, sel:블록 고름, style:줄에 더할 style} */
  function block(b){
    var cls='blk k-'+b.k+(b.h?' h'+b.h:'')+(b.d?' done':'')+(b.sel?' bsel':''),g='';
    if(b.k==='todo')g='<span class="g"><span class="cb'+(b.d?' on':'')+'">'+(b.d?CHK:'')+'</span></span>';
    else if(b.k==='bullet')g='<span class="g"><span class="bu b'+((b.l||0)%3)+'"></span></span>';
    else if(b.k==='toggle'){var sz=b.h?[0,16,14,13][b.h]:12;g='<span class="g" style="width:'+(b.h?sz+9:21)+'px"><span class="cv">'+chev(!b.f,sz)+'</span></span>';}
    return '<div class="'+cls+'" style="--lv:'+(b.l||0)+(b.style?';'+b.style:'')+'">'+g+'<span class="tx">'+(b.html!=null?b.html:esc(b.t||''))+'</span></div>';
  }
  /* 설정: {title, dark, narrow, bar:서식 막대 HTML, after:본문 뒤 HTML} */
  function note(blocks,o){o=o||{};
    return '<div class="app'+(o.dark?' dk':'')+'"><div class="note'+(o.narrow?' narrow':'')+'">'+(o.title!=null?'<div class="ntop"><span class="nttl">'+esc(o.title)+'</span></div>':'')+
      '<div class="nbody">'+blocks.map(block).join('')+'</div>'+(o.bar||'')+'</div></div>';
  }
  function app(html,o){return '<div class="app'+(o&&o.dark?' dk':'')+'">'+html+'</div>';}
  /* 선택지: {id, name, rec, desc, draw:function()→그림 HTML} */
  function picks(gridId,n,opts){
    var g=document.getElementById(gridId),keep={};
    g.querySelectorAll('input:checked').forEach(function(r){keep[r.value]=1;});
    g.className='picks';g.innerHTML='';
    opts.forEach(function(o){var c=document.createElement('label');c.className='pick';
      c.innerHTML='<span class="opt"><input type="radio" name="q'+n+'" value="'+o.id+'"><span><strong>'+o.name+'</strong>'+(o.rec?'<span class="rec">추천</span>':'')+'</span></span>'+
        (o.draw?'<div class="stage">'+o.draw()+'</div>':'')+(o.desc?'<p>'+o.desc+'</p>':'');
      if(keep[o.id])c.querySelector('input').checked=true;
      g.appendChild(c);});
    if(FloatKit._sync)FloatKit._sync();
  }
  /* items: [{n, title, labels:{id:이름}}]. 페이지에 #prog #copy #ans #cst와 항목마다 #memo<n>이 있어야 한다 */
  function answers(cfg){
    var KEY=cfg.key,Q=cfg.items;
    function v(n){var r=document.querySelector('input[name="q'+n+'"]:checked');return r?r.value:'';}
    function m(n){return document.getElementById('memo'+n);}
    function txt(){return Q.map(function(q){var x=v(q.n),mm=m(q.n)?m(q.n).value.trim():'';return q.n+'. '+q.title+': '+(x?(q.labels[x]||x):'아직 안 고름')+(mm?' / 메모: '+mm:'');}).join('\n');}
    function save(){var s={},c=0;Q.forEach(function(q){var x=v(q.n);if(x)c++;s[q.n]={v:x,m:m(q.n)?m(q.n).value:''};});
      document.getElementById('ans').value=txt();document.getElementById('prog').textContent=Q.length+'개 중 '+c+'개 고름';
      st=s;try{localStorage.setItem(KEY,JSON.stringify(s));}catch(e){}}
    var st={};try{st=JSON.parse(localStorage.getItem(KEY)||'{}')||{};}catch(e){}
    function restore(){Q.forEach(function(q){var s=st[q.n]||{};document.querySelectorAll('input[name="q'+q.n+'"]').forEach(function(r){if(s.v===r.value)r.checked=true;});});}
    document.addEventListener('change',function(e){if(e.target&&/^q\d+$/.test(e.target.name||''))save();});
    Q.forEach(function(q){var t=m(q.n);if(!t)return;if((st[q.n]||{}).m)t.value=st[q.n].m;t.addEventListener('input',save);});
    document.getElementById('copy').addEventListener('click',function(){var a=document.getElementById('ans'),c=document.getElementById('cst'),t=txt();
      function ok(){c.textContent='복사했어요. 대화에 붙여 넣어 주세요.';}function fb(){a.focus();a.select();c.textContent='복사가 막혔어요. 글이 선택돼 있으니 직접 복사해 주세요.';}
      try{if(navigator.clipboard&&navigator.clipboard.writeText){navigator.clipboard.writeText(t).then(ok,fb);}else fb();}catch(e){fb();}});
    FloatKit._sync=function(){restore();save();};
    FloatKit._sync();
  }
  window.FloatKit={note:note,block:block,app:app,picks:picks,answers:answers,esc:esc};
})();
