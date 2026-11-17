(() => {
  const active = state => (state.curses || []).filter(c => c.status === 'active' || c.status === 'pending');
  window.curseBlocksQuests = state => active(state).length > 0;
  window.curseBanner = state => {
    const curses = active(state);
    if (!curses.length) return '';
    return `<section class="curse-banner"><div class="curse-heading"><span class="curse-mark">☠</span><div><small>FÖRBANNELSE AKTIV</small><b>${curses.length} förbannelse${curses.length===1?'':'r'} återstår</b></div><span class="curse-lock">🔒 Uppdrag låsta</span></div><div class="curse-items">${curses.map(c=>{const d=creatureDefinition(c.name);return `<article class="curse-item"><div class="curse-creature-icon">${mascot(d?.icon||'goblin',62,d?.palette)}</div><div class="curse-task"><b>${esc(c.name)} har lagt till en uppgift</b><span>${esc(c.task)}</span><small>Deadline: ${new Intl.DateTimeFormat('sv-SE',{day:'numeric',month:'short',hour:'2-digit',minute:'2-digit'}).format(new Date(c.deadlineAt))} · 0 XP · 0 mynt</small>${c.status==='pending'?'<small class="curse-pending">Uppgiften är inskickad · inväntar klartecken</small>':''}</div>${c.status==='pending'?`<span class="curse-submit curse-waiting">Väntar på klartecken</span>`:`<button class="curse-submit" data-curse-submit="${c.id}">Markera som klar</button>`}</article>`}).join('')}</div><p class="curse-note">Vanliga uppdrag låses upp när alla förbannelser har besegrats och godkänts. Förbannelseuppgifter ger inga belöningar.</p></section>`;
  };
  window.creatureLibraryMarkup = () => `<details class="creature-library"><summary><span>Varelsebibliotek</span><small>50 vanliga · 6 förbannade · visa drop rates</small></summary><div class="library-grid">${[...creatureDefinitions,...cursedCreatureDefinitions].map(c=>`<article class="library-creature ${c.isCursed?'is-cursed':''}"><div class="library-art">${mascot(c.icon,68,c.palette)}</div><div class="library-copy"><b>${esc(c.name)}</b><span>${c.isCursed?c.label:c.label+' · '+c.rarity}</span><p>${esc(c.description)}</p><small>${c.isCursed?`Trä ${c.drops.wooden}% · Silver ${c.drops.silver}% · Guld ${c.drops.gold}% · Diamant ${c.drops.diamond}%`:`Träkista ${c.dropChanceWooden.toFixed(c.dropChanceWooden===1.875?3:2)}% · ${c.cooldownHours?`Nedkylning ${c.cooldownHours} tim`:'Engångsbruk'}`}</small></div></article>`).join('')}</div></details>`;
})();


