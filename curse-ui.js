(() => {
  const active = state => (state.curses || []).filter(c => c.status === 'active' || c.status === 'pending');
  window.curseBlocksQuests = state => active(state).length > 0;
  window.curseBanner = state => {
    const curses = active(state);
    if (!curses.length) return '';
    return `<section class="curse-banner"><div class="curse-heading"><span class="curse-mark">☠</span><div><small>FÖRBANNELSE AKTIV</small><b>${curses.length} förbannelse${curses.length===1?'':'r'} återstår</b></div><span class="curse-lock">🔒 Uppdrag låsta</span></div><div class="curse-items">${curses.map(c=>{const d=creatureDefinition(c.name);return `<article class="curse-item"><div class="curse-creature-icon">${mascot(d?.icon||'goblin',62,d?.palette)}</div><div class="curse-task"><b>${esc(c.name)} har lagt till en uppgift</b><span>${esc(c.task)}</span><small>Deadline: ${new Intl.DateTimeFormat('sv-SE',{day:'numeric',month:'short',hour:'2-digit',minute:'2-digit'}).format(new Date(c.deadlineAt))} · 0 XP · 0 mynt</small>${c.status==='pending'?'<small class="curse-pending">Uppgiften är inskickad · inväntar klartecken</small>':''}</div>${c.status==='pending'?`<span class="curse-submit curse-waiting">Väntar på klartecken</span>`:c.canSubmit===false?'<span class="curse-submit curse-waiting">Tilldelad annan spelare</span>':`<button class="curse-submit" data-curse-submit="${c.id}">Markera som klar</button>`}</article>`}).join('')}</div><p class="curse-note">Vanliga uppdrag låses upp när alla förbannelser har besegrats och godkänts. Förbannelseuppgifter ger inga belöningar.</p></section>`;
  };
  window.creatureLibraryMarkup = () => {
    const groups = [
      ['Common', 'Vanliga', creatureDefinitions.filter(c => c.rarity === 'Common')],
      ['Uncommon', 'Ovanliga', creatureDefinitions.filter(c => c.rarity === 'Uncommon')],
      ['Rare', 'Sällsynta', creatureDefinitions.filter(c => c.rarity === 'Rare')],
      ['Epic', 'Episka', creatureDefinitions.filter(c => c.rarity === 'Epic')],
      ['Legendary', 'Legendariska', creatureDefinitions.filter(c => c.rarity === 'Legendary')],
      ['Cursed', 'Förbannelser', cursedCreatureDefinitions]
    ];
    const all = groups.flatMap(([, , list]) => list);
    const unlocked = c => c.isCursed
      ? state.curses.some(x => x.name === c.name) || state.curseHistory.some(x => x.name === c.name)
      : state.creatures.some(x => x.name === c.name && !x.isCursed);
    const tabs = [['all','Alla',all.length],...groups.map(([key,title,list])=>[key,title,list.length])];
    return `<details class="creature-library"><summary><span>Varelsebibliotek</span><small>${all.length} varelser · ${all.filter(unlocked).length} upplåsta</small></summary><div class="library-browser"><div class="library-tabs" role="tablist" aria-label="Välj varelsekategori">${tabs.map(([key,title,count],i)=>`<button type="button" class="library-tab ${i===0?'active':''}" data-library-category="${key}" role="tab" aria-selected="${i===0}">${title}<small>${count}</small></button>`).join('')}</div><div class="library-groups">${groups.map(([key,title,list])=>`<section class="library-category" data-library-group="${key}"><div class="library-category-heading"><h3>${title}</h3><span>${list.filter(unlocked).length} / ${list.length} upplåsta</span></div><div class="library-card-grid">${list.map(c=>{const found=unlocked(c);return `<button type="button" class="library-card ${found?'is-unlocked':'is-locked'} ${c.isCursed?'is-cursed':''}" data-library-creature="${esc(c.id)}" data-rarity="${esc(c.rarity)}" aria-label="${found?'Visa':'Visa låst varelse'}: ${esc(c.name)}"><span class="library-card-art">${mascot(c.icon,112,c.palette)}${found?'':'<i aria-hidden="true">🔒</i>'}</span><span class="library-card-name">${esc(c.name)}</span><span class="library-card-rarity">${c.isCursed?'FÖRBANNELSE':esc(c.label)}</span><span class="library-card-state">${found?'UPPLÅST':'EJ UPPLÅST'}</span></button>`}).join('')}</div></section>`).join('')}</div></div></details>`;
  };
})();


