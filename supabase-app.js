/* Supabase auth and family data adapter for the static app. */
(function () {
  const client = window.supabaseClient;
  if (!client) {
    document.querySelector('.app-shell').hidden = true;
    document.getElementById('modal-root').innerHTML = '<div class="auth-screen"><section class="auth-card"><h1>Supabase kunde inte starta</h1><p>Kontrollera internetanslutningen och att Supabase-klienten laddas.</p></section></div>';
    return;
  }

  const data = { familyId: null, member: null, members: [], chores: [], submissions: [], creatures: [], creatureEffects: [], plan: null };
  window.remoteFamily = data;
  const escHtml = (value) => String(value ?? '').replace(/[&<>"']/g, (c) => ({ '&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;' }[c]));
  const root = document.getElementById('modal-root');
  let realtimeChannel = null;
  const call = async (promise) => {
    const { data: result, error } = await promise;
    if (error) throw error;
    return result;
  };
  const optionalRows = async (promise) => {
    try { return await call(promise); }
    catch (error) { if (['42P01','PGRST205'].includes(error.code)) return []; throw error; }
  };

  function showGate(content) {
    root.innerHTML = `<div class="auth-screen"><section class="auth-card"><a class="brand auth-brand" href="#hem"><span class="brand-mark">✦</span><span>familje<span class="brand-light">äventyret</span></span></a>${content}<p class="auth-error" aria-live="polite"></p></section></div>`;
  }
  function errorMessage(error) {
    const target = root.querySelector('.auth-error');
    if (target) target.textContent = error?.message || 'Något gick fel. Försök igen.';
  }
  function loginForm(mode = 'signin') {
    const signup = mode === 'signup';
    showGate(`<h1>${signup ? 'Skapa ditt konto' : 'Välkommen tillbaka'}</h1><p>${signup ? 'Börja äventyret tillsammans med familjen.' : 'Logga in för att öppna familjens äventyr.'}</p><form id="auth-form" class="auth-form"><label>${signup ? 'Ditt namn' : 'Namn (visas i familjen)'}<input name="displayName" autocomplete="name" minlength="1" maxlength="60" ${signup ? 'required' : ''}></label><label>E-post<input name="email" type="email" autocomplete="email" required></label><label>Lösenord<input name="password" type="password" autocomplete="${signup ? 'new-password' : 'current-password'}" minlength="8" required></label><button class="primary-button" type="submit">${signup ? 'Skapa konto' : 'Logga in'}</button></form><button class="auth-switch" data-auth-mode="${signup ? 'signin' : 'signup'}">${signup ? 'Har du redan ett konto? Logga in' : 'Nytt här? Skapa ett konto'}</button>`);
  }
  async function familyGate() {
    showGate(`<h1>Gå med i familjen</h1><p>Skapa familjens äventyr eller använd en inbjudningskod.</p><form id="family-form" class="auth-form"><label>Ditt visningsnamn<input name="displayName" autocomplete="name" maxlength="60" value="${escHtml(data.member?.display_name || '')}" required></label><label>Familjenamn<input name="familyName" maxlength="80" value="Familjen Rezaei" required></label><button class="primary-button" name="action" value="create" type="submit">Skapa ny familj</button><label>Inbjudningskod<input name="invite" autocomplete="off" maxlength="80" placeholder="Klistra in familjens kod"></label><button class="auth-secondary" name="action" value="join" type="submit">Gå med med kod</button></form><button class="auth-switch" data-signout>Logga ut</button>`);
  }
  function getMonday() {
    const now = new Date();
    now.setHours(0, 0, 0, 0);
    now.setDate(now.getDate() - ((now.getDay() + 6) % 7));
    return now.toLocaleDateString('sv-SE');
  }
  async function bootFamily() {
    const user = (await call(client.auth.getUser())).user;
    if (!user) return loginForm();
    const memberships = await call(client.from('family_members').select('family_id,user_id,display_name,role,xp,tokens,shards,streak,is_active').eq('user_id', user.id).eq('is_active', true));
    if (!memberships.length) return familyGate();
    data.member = memberships[0];
    data.familyId = data.member.family_id;
    await loadFamilyData();
    document.querySelector('.app-shell').hidden = false;
    document.body.classList.add('supabase-active');
    root.innerHTML = '';
    document.querySelectorAll('.admin-nav-label,.admin-nav-item,.admin-mobile-item').forEach((el) => { el.hidden = data.member.role !== 'admin'; });
    document.querySelectorAll('.sidebar-player b').forEach((el) => { el.textContent = data.member.display_name; });
    document.querySelectorAll('.sidebar-player small').forEach((el) => { el.textContent = data.member.role === 'admin' ? 'Administratör' : 'Familjemedlem'; });
    document.querySelectorAll('.avatar.top-avatar').forEach((el) => { el.title = data.member.display_name; });
    window.gameState.role = data.member.role;
    window.gameState.xp = data.member.xp;
    window.gameState.tokens = data.member.tokens;
    window.gameState.shards = data.member.shards;
    window.gameState.streak = data.member.streak;
    window.renderGame?.();
    decorateAdminForm();
    if (realtimeChannel) client.removeChannel(realtimeChannel);
    realtimeChannel = client.channel(`family-${data.familyId}`)
      .on('postgres_changes', { event: '*', schema: 'public', table: 'family_members', filter: `family_id=eq.${data.familyId}` }, () => bootstrapFamily().catch(errorMessage))
      .on('postgres_changes', { event: '*', schema: 'public', table: 'quest_submissions', filter: `family_id=eq.${data.familyId}` }, () => refresh())
      .on('postgres_changes', { event: '*', schema: 'public', table: 'chores', filter: `family_id=eq.${data.familyId}` }, () => refresh())
      .on('postgres_changes', { event: '*', schema: 'public', table: 'creature_inventory', filter: `family_id=eq.${data.familyId}` }, () => refresh())
      .on('postgres_changes', { event: '*', schema: 'public', table: 'creature_effects', filter: `family_id=eq.${data.familyId}` }, () => refresh())
      .subscribe();
  }
  let bootstrapping = false;
  async function bootstrapFamily() {
    if (bootstrapping) return;
    bootstrapping = true;
    try { return await bootFamily(); }
    finally { bootstrapping = false; }
  }
  async function loadFamilyData() {
    const familyId = data.familyId;
    const [family, members, plans, chores, submissions, creatures, creatureEffects] = await Promise.all([
      call(client.from('families').select('name').eq('id', familyId).single()),
      call(client.from('family_members').select('family_id,user_id,display_name,role,xp,tokens,shards,streak,is_active').eq('family_id', familyId).eq('is_active', true)),
      call(client.from('weekly_plans').select('*').eq('family_id', familyId).eq('week_start', getMonday()).limit(1)),
      call(client.from('chores').select('*,chore_assignments(user_id),quest_submissions(*)').eq('family_id', familyId).eq('is_active', true)),
      call(client.from('quest_submissions').select('*,chores(title,kind,xp_reward,token_reward)').eq('family_id', familyId).order('submitted_at', { ascending: false })),
      optionalRows(client.from('creature_inventory').select('*').eq('family_id', familyId).eq('user_id', data.member.user_id).order('acquired_at')),
      optionalRows(client.from('creature_effects').select('*').eq('family_id', familyId).eq('user_id', data.member.user_id).gt('uses_remaining', 0).order('created_at'))
    ]);
    data.familyName = family.name;
    data.members = members;
    data.member = members.find((member) => member.user_id === data.member.user_id) || data.member;
    data.plan = plans[0] || null;
    data.creatures = creatures;
    data.creatureEffects = creatureEffects;
    state.creatures = creatures.map((creature) => { const definition = creatureDefinition(creature.creature_name); return { id: creature.id, catalogId: creature.creature_id, name: creature.creature_name, rarity: creature.rarity.toUpperCase(), rarityKey: creature.rarity, level: creature.level, creatureXp: creature.creature_xp, isCursed: creature.is_cursed, cooldownUntil: creature.cooldown_until ? new Date(creature.cooldown_until).getTime() : null, ready: !creature.cooldown_until || new Date(creature.cooldown_until).getTime() <= Date.now(), ability: definition?.ability || '', visualTheme: definition?.visualTheme || '' }; });
    const allChores = chores;
    data.submissions = submissions;
    if (data.member.role === 'admin' && !data.plan) {
      const planId = await call(client.rpc('create_weekly_plan', { p_family_id: familyId, p_week_start: getMonday() }));
      data.plan = { id: planId, family_id: familyId, week_start: getMonday(), status: 'open' };
    }
    data.chores = allChores.filter((chore) => (chore.chore_assignments || []).some((a) => a.user_id === data.member.user_id) && (chore.kind === 'curse' || (data.plan && chore.plan_id === data.plan.id)));
    data.actionableCount = data.chores.filter((chore) => chore.kind === 'weekly' && data.plan && chore.plan_id === data.plan.id && !submissions.some((submission) => submission.chore_id === chore.id && submission.user_id === data.member.user_id && (submission.status === 'approved' || submission.status === 'pending_approval'))).length;
    data.weeklyChores = allChores.filter((chore) => chore.kind === 'weekly' && chore.is_active && data.plan && chore.plan_id === data.plan.id);
    data.memberProgress = members.map((member) => {
      const assigned = data.weeklyChores.flatMap((chore) => (chore.chore_assignments || []).filter((assignment) => assignment.user_id === member.user_id).map(() => chore));
      const completed = assigned.filter((chore) => (chore.quest_submissions || []).some((submission) => submission.user_id === member.user_id && submission.status === 'approved')).length;
      const pending = assigned.filter((chore) => (chore.quest_submissions || []).some((submission) => submission.user_id === member.user_id && submission.status === 'pending_approval')).length;
      return { ...member, assigned: assigned.length, completed, pending };
    });
    data.weekProgress = {
      assigned: data.memberProgress.reduce((sum, member) => sum + member.assigned, 0),
      completed: data.memberProgress.reduce((sum, member) => sum + member.completed, 0)
    };
    const state = window.gameState;
    if (!state) return;
    state.role = data.member.role;
    state.xp = data.member.xp;
    state.tokens = data.member.tokens;
    state.shards = data.member.shards;
    state.streak = data.member.streak;
    const mapped = submissions.map((s) => ({ id: s.id, questId: s.chore_id, questTitle: s.chores?.title || 'Uppdrag', submittedBy: members.find((m) => m.user_id === s.user_id)?.display_name || 'Familjemedlem', userId: s.user_id, kind: s.chores?.kind || 'weekly', submittedAt: new Date(s.submitted_at).getTime(), status: s.status, xp: s.xp_reward, tokens: s.token_reward, reason: s.rejection_reason }));
    state.questSubmissions = mapped;
    state.completed = submissions.filter((s) => s.status === 'approved' && s.chores?.kind === 'weekly' && s.user_id === data.member.user_id).map((s) => s.chore_id);
    state.customQuests = data.chores.filter((c) => c.kind === 'weekly').map((c) => ({ id: c.id, title: c.title, detail: c.description, icon: 'dish', color: 'green', xp: c.xp_reward, tokens: c.token_reward, difficulty: c.difficulty || 'Lätt' }));
    state.curses = allChores.filter((c) => c.kind === 'curse').map((c) => {
      const last = c.quest_submissions?.sort((a, b) => new Date(b.submitted_at) - new Date(a.submitted_at))[0];
      const mine = (c.chore_assignments || []).some((a) => a.user_id === data.member.user_id);
      const submitter = members.find((m) => m.user_id === last?.user_id)?.display_name || 'Familjemedlem';
      return { id: c.id, submissionId: last?.id, name: c.title, task: c.description, status: c.resolved_at ? 'defeated' : last?.status === 'pending_approval' ? 'pending' : 'active', submittedBy: submitter, canSubmit: mine && last?.status !== 'pending_approval', submittedAt: last ? new Date(last.submitted_at).getTime() : null, deadlineAt: c.deadline_at ? new Date(c.deadline_at).getTime() : Date.now() + 86400000, isCursed: true };
    });
    state.notifications = (await call(client.from('notifications').select('*').eq('family_id', familyId).eq('user_id', data.member.user_id).order('created_at', { ascending: false }).limit(20))).map((n) => ({ message: n.message, createdAt: new Date(n.created_at).getTime() }));
  }
  function decorateAdminForm() {
    const form = document.getElementById('admin-create-quest');
    if (!form) return;
    if (!document.getElementById('family-member-management')) {
      const adminCount = data.members.filter((member) => member.role === 'admin').length;
      const memberCard = document.createElement('section');
      memberCard.id = 'family-member-management';
      memberCard.className = 'card admin-section family-member-management';
      memberCard.innerHTML = `<div class="section-head"><div><h2>Hantera familjemedlemmar</h2><p class="admin-muted">Ändra roller eller ta bort medlemmar från familjen.</p></div><span class="level-chip">${data.members.length} MEDLEMMAR</span></div><div class="family-member-list">${data.members.map((member) => `<div class="family-member-admin-row" data-family-user="${escHtml(member.user_id)}"><div class="family-member-admin-name"><b>${escHtml(member.display_name)}</b>${member.user_id === data.member.user_id ? '<small>Du</small>' : ''}</div><select data-member-role aria-label="Roll för ${escHtml(member.display_name)}"><option value="player" ${member.role === 'player' ? 'selected' : ''} ${member.role === 'admin' && adminCount <= 1 ? 'disabled' : ''}>Spelare</option><option value="admin" ${member.role === 'admin' ? 'selected' : ''} ${member.role === 'player' && adminCount >= 2 ? 'disabled' : ''}>Administratör</option></select><button class="filter-tab" type="button" data-save-member-role>Spara roll</button><button class="filter-tab admin-remove" type="button" data-remove-family-member ${(member.user_id === data.member.user_id || (member.role === 'admin' && adminCount <= 1)) ? 'disabled' : ''}>Ta bort</button></div>`).join('')}</div>`;
      form.closest('.admin-section')?.before(memberCard);
    }
    if (!document.getElementById('invite-family-card')) {
      const invite = document.createElement('section');
      invite.id = 'invite-family-card';
      invite.className = 'card admin-section invite-family-card';
      invite.innerHTML = '<h2>Bjud in familjen</h2><p>Skapa en engångskod till en spelare eller den andra vuxna administratören.</p><div class="invite-controls"><select id="invite-role" aria-label="Inbjuden roll"><option value="player">Spelare</option><option value="admin">Vuxen administratör</option></select><button class="primary-button" type="button" data-create-invite>Skapa inbjudningskod</button></div><output id="invite-code-output"></output>';
      form.closest('.admin-section')?.before(invite);
    }
    if (!document.getElementById('weekly-plan-card')) {
      const weekly = document.createElement('section');
      weekly.id = 'weekly-plan-card';
      weekly.className = 'card admin-section weekly-plan-card';
      weekly.innerHTML = `<div class="section-head"><div><h2>Veckans sysslor</h2><p class="admin-muted">Tilldela varje uppgift till familjemedlemmar. När alla är godkända kan ni hämta veckans diamantkistor.</p></div><span class="level-chip">${data.plan?.status === 'closed' ? 'STÄNGD' : 'ÖPPEN'}</span></div><button class="primary-button" type="button" data-close-week ${data.plan?.status === 'closed' ? 'disabled' : ''}>Stäng veckan och dela ut diamantkistor</button>`;
      form.closest('.admin-section')?.before(weekly);
    }
    if (form.querySelector('[data-assignee-picker]')) return;
    const picker = document.createElement('fieldset');
    picker.className = 'assignee-picker';
    picker.dataset.assigneePicker = 'true';
    picker.innerHTML = `<legend>Tilldela till</legend>${data.members.map((m) => `<label><input type="checkbox" name="assignees" value="${escHtml(m.user_id)}" checked> ${escHtml(m.display_name)}</label>`).join('')}`;
    if (!form.querySelector('[name="difficulty"]')) {
      const field = document.createElement('label');
      field.innerHTML = 'Svårighetsgrad<select name="difficulty"><option value="Lätt">Lätt</option><option value="Mellan">Mellan</option><option value="Svår">Svår</option></select>';
      form.insertBefore(field, form.querySelector('[data-assignee-picker]') || form.querySelector('button[type="submit"]'));
    }
    form.insertBefore(picker, form.querySelector('button[type="submit"]'));
  }
  function decorateLiveUi() {
    if (!data.familyId || !data.member) return;
    const name = data.member.display_name;
    const familyName = data.familyName || 'Familjen Rezaei';
    const familyLabel = document.querySelector('.family-switch b');
    if (familyLabel && familyLabel.textContent !== familyName) familyLabel.textContent = familyName;
    document.querySelectorAll('.admin-nav-label,.admin-nav-item,.admin-mobile-item').forEach((el) => { el.hidden = data.member.role !== 'admin'; });
    const greet = document.querySelector('.welcome-row h1');
    if (greet && !greet.textContent.includes(name)) greet.innerHTML = `God morgon, ${escHtml(name)}! <span>☀️</span>`;
    const profileName = document.querySelector('.profile-card h2');
    if (profileName && profileName.textContent !== name) profileName.textContent = name;
    const profileDescription = document.querySelector('.profile-card>p');
    const profileText = `Äventyrare · ${data.member.role === 'admin' ? 'Administratör' : 'Medlem'} i ${familyName}`;
    if (profileDescription && profileDescription.textContent !== profileText) profileDescription.textContent = profileText;
    const playerCard = document.querySelector('.right-col .player-card');
    if (playerCard) {
      const playerName = playerCard.querySelector('.player-meta b');
      if (playerName && playerName.textContent !== name) playerName.textContent = name;
      const level = Math.floor(Math.max(0, data.member.xp) / 1000) + 1;
      const levelChip = playerCard.querySelector('.level-chip');
      if (levelChip && levelChip.textContent !== `NIVÅ ${level}`) levelChip.textContent = `NIVÅ ${level}`;
      const rank = [...data.members].sort((a, b) => b.xp - a.xp).findIndex((member) => member.user_id === data.member.user_id) + 1;
      const rankText = playerCard.querySelector('.player-foot b');
      if (rankText && rankText.textContent !== `#${rank} av ${data.members.length}`) rankText.textContent = `#${rank} av ${data.members.length}`;
      const rankLabel = playerCard.querySelector('.player-foot span');
      if (rankLabel && rankLabel.textContent !== `👥 Familjerank · ${name}`) rankLabel.textContent = `👥 Familjerank · ${name}`;
      const progressLabel = playerCard.querySelector('.xp-label b');
      if (progressLabel && progressLabel.textContent !== `${data.member.xp} / ${(level * 1000)} XP`) progressLabel.textContent = `${data.member.xp} / ${(level * 1000)} XP`;
      const xpBar = playerCard.querySelector('.progress span');
      if (xpBar) xpBar.style.width = `${Math.min(100, Math.round((data.member.xp % 1000) / 10))}%`;
    }
    const familyToday = document.querySelector('.right-col .family-card');
    if (familyToday) {
      const completed = data.weekProgress?.completed || 0;
      const assigned = data.weekProgress?.assigned || 0;
      const pending = data.memberProgress.reduce((sum, member) => sum + member.pending, 0);
      const familyMarkup = `<div class="section-head"><h2>Familjen den här veckan</h2><span style="font-size:9px;color:#8c958d">${completed} av ${assigned} godkända${pending ? ` · ${pending} väntar` : ''}</span></div>${data.memberProgress.map((member, index) => {
        const colors = ['#f4e7d8','#f8e5ea','#e7edfa','#e8f2e2'];
        const avatars = ['🧑','👩','🧒','🧑‍🦱'];
        const percent = member.assigned ? Math.round(member.completed / member.assigned * 100) : 0;
        return `<div class="member-line"><div class="member-avatar" style="background:${colors[index % colors.length]}">${avatars[index % avatars.length]}</div><b>${escHtml(member.display_name)}</b><div class="tiny-progress"><span style="width:${percent}%;background:${colors[index % colors.length]}"></span></div><small>${member.completed}/${member.assigned}${member.pending ? ` · ${member.pending} väntar` : ''}</small></div>`;
      }).join('') || '<p class="admin-muted">Inga familjemedlemmar har lagts till ännu.</p>'}`;
      if (familyToday.dataset.remoteMarkup !== familyMarkup) { familyToday.dataset.remoteMarkup = familyMarkup; familyToday.innerHTML = familyMarkup; }
    }
    const homeProgress = document.querySelector('.left-col .family-card');
    if (homeProgress) {
      const completed = data.weekProgress?.completed || 0;
      const assigned = data.weekProgress?.assigned || 0;
      const percent = assigned ? Math.round(completed / assigned * 100) : 0;
      const summary = homeProgress.querySelector('.section-head span:first-child');
      const summaryMarkup = assigned ? `Familjen har gjort <b>${completed} av ${assigned} sysslor</b> den här veckan` : 'Inga sysslor har tilldelats den här veckan ännu.';
      if (summary && summary.innerHTML !== summaryMarkup) summary.innerHTML = summaryMarkup;
      const badge = homeProgress.querySelector('.section-head span:last-child');
      if (badge && badge.textContent !== `${percent}%`) badge.textContent = `${percent}%`;
      const bar = homeProgress.querySelector('.progress span');
      if (bar) bar.style.width = `${percent}%`;
      const footer = homeProgress.querySelector('div[style*="display:flex"] span');
      const pending = data.memberProgress.reduce((sum, member) => sum + member.pending, 0);
      const footerText = assigned && completed === assigned ? 'Alla veckosysslor är godkända — diamantkistor väntar!' : pending ? `${pending} sysslor väntar på godkännande.` : 'Godkända sysslor räknas in i familjens veckomål.';
      if (footer && footer.textContent !== footerText) footer.textContent = footerText;
    }
    const heroStats = document.querySelector('.hero-stats');
    const memberStat = heroStats?.querySelectorAll('.hero-stat')[2];
    if (memberStat && memberStat.textContent !== `${data.members.length} medlemmar`) memberStat.innerHTML = `<b>${data.members.length}</b> medlemmar`;
    const seasonStat = heroStats?.querySelectorAll('.hero-stat')[1];
    const weekPercent = data.weekProgress?.assigned ? Math.round(data.weekProgress.completed / data.weekProgress.assigned * 100) : 0;
    if (seasonStat && seasonStat.textContent !== `${weekPercent}% av veckans sysslor`) seasonStat.innerHTML = `<b>${weekPercent}%</b> av veckans sysslor`;
    const badge = document.querySelector('.nav-count');
    if (badge) { badge.textContent = data.actionableCount ? String(data.actionableCount) : ''; badge.hidden = !data.actionableCount; }
    const weeklyChallenge = document.querySelector('#view-root .all-quests + .family-card');
    if (weeklyChallenge) {
      const completed = data.weekProgress?.completed || 0;
      const assigned = data.weekProgress?.assigned || 0;
      const percent = assigned ? Math.round(completed / assigned * 100) : 0;
      const pending = data.memberProgress.reduce((sum, member) => sum + member.pending, 0);
      const daysLeft = Math.max(0, 6 - ((new Date().getDay() + 6) % 7));
      const chip = weeklyChallenge.querySelector('.level-chip');
      if (chip && chip.textContent !== `${daysLeft} dagar kvar`) chip.textContent = `${daysLeft} dagar kvar`;
      const description = weeklyChallenge.querySelector('p');
      const descriptionText = assigned ? `${assigned} sysslor är tilldelade den här veckan. Alla behöver godkännas för att familjen ska få diamantkistorna.${pending ? ` ${pending} väntar på godkännande.` : ''}` : 'Veckans sysslor visas här när en administratör har skapat och tilldelat dem.';
      if (description && description.textContent !== descriptionText) description.textContent = descriptionText;
      const bar = weeklyChallenge.querySelector('.progress span');
      if (bar) bar.style.width = `${percent}%`;
      const label = weeklyChallenge.querySelector('.xp-label span');
      if (label && label.textContent !== `${completed} av ${assigned} sysslor godkända`) label.textContent = `${completed} av ${assigned} sysslor godkända`;
      const value = weeklyChallenge.querySelector('.xp-label b');
      if (value && value.textContent !== `${percent}%`) value.textContent = `${percent}%`;
    }
    const permissionCard = document.querySelector('.admin-profile-link');
    if (permissionCard) {
      permissionCard.hidden = data.member.role !== 'admin';
      const badge = permissionCard.querySelector('.admin-role-chip');
      if (badge && badge.textContent !== 'ADMINISTRATÖR') badge.textContent = 'ADMINISTRATÖR';
      const description = permissionCard.querySelector('p');
      if (description && description.textContent !== 'Du är en av familjens administratörer.') description.textContent = 'Du är en av familjens administratörer.';
    }
    const aboutCard = [...document.querySelectorAll('#view-root .family-card')].find((card) => card.querySelector('h2')?.textContent.includes('Om den här appen'));
    const about = aboutCard?.querySelector('.level-chip');
    if (about && about.textContent.includes('ENHETEN')) about.textContent = 'SUPABASE';
    const aboutText = aboutCard?.querySelector('p');
    const syncedText = 'Familjens konton, veckosysslor och godkännanden sparas i den gemensamma databasen.';
    if (aboutText && aboutText.textContent.includes('sparas lokalt') && aboutText.textContent !== syncedText) aboutText.textContent = syncedText;
    if (document.querySelector('#view-root .profile-layout') && !document.getElementById('family-settings-card')) {
      const adminCount = data.members.filter((member) => member.role === 'admin').length;
      const actions = document.createElement('section');
      actions.id = 'family-settings-card';
      actions.className = 'card family-card family-settings-card';
      actions.innerHTML = `<div class="section-head"><div><h2>Familjeinställningar</h2><p>Lämna familjen eller hantera hela familjens äventyr.</p></div></div><div class="family-settings-actions"><button type="button" class="filter-tab family-leave-button" data-leave-family ${data.member.role === 'admin' && adminCount < 2 ? 'disabled' : ''}>Lämna familjen</button>${data.member.role === 'admin' ? '<button type="button" class="filter-tab family-delete-button" data-delete-family>Radera familjen</button>' : ''}</div>${data.member.role === 'admin' && adminCount < 2 ? '<small class="family-settings-note">Bjud först in en annan administratör. Familjen behöver minst en admin.</small>' : ''}`;
      if (aboutCard) aboutCard.before(actions);
      else document.querySelector('#view-root .profile-layout')?.after(actions);
    }
    const adminTitle = document.querySelector('.admin-heading .eyebrow');
    const adminText = `${familyName.toLocaleUpperCase('sv-SE')} · VECKANS PLAN`;
    if (adminTitle && adminTitle.textContent !== adminText) adminTitle.textContent = adminText;
    document.querySelectorAll('.admin-metric').forEach((metric, i) => {
      if (i === 0) { const value = metric.querySelector('b'); if (value && value.textContent !== String(data.members.length)) value.textContent = data.members.length; const caption = metric.querySelector('span'); if (caption && caption.textContent !== 'Aktiva medlemmar') caption.textContent = 'Aktiva medlemmar'; }
    });
    document.querySelectorAll('.approval-admin').forEach((select) => {
      const badge = document.createElement('span'); badge.className = 'approval-admin-name'; badge.textContent = `Beslut av ${name}`; select.replaceWith(badge);
    });
    document.querySelectorAll('.approval-row').forEach((row) => {
      const detail = row.querySelector('.admin-list-copy small')?.textContent || '';
      const ownSubmission = detail.startsWith(`Inskickad av ${name} `);
      row.querySelectorAll('[data-quest-decision],[data-curse-decision]').forEach((button) => { button.disabled = ownSubmission; });
      let note = row.querySelector('.own-submission-note');
      if (ownSubmission && !note) { note = document.createElement('small'); note.className = 'own-submission-note'; note.textContent = 'Du kan inte besluta om din egen uppgift.'; row.appendChild(note); }
    });
  }
  const viewObserver = new MutationObserver(() => { decorateLiveUi(); decorateAdminForm(); });
  viewObserver.observe(document.getElementById('view-root'), { childList: true, subtree: true });
  async function refresh() {
    try { await loadFamilyData(); window.renderGame?.(); decorateAdminForm(); }
    catch (error) { errorMessage(error); }
  }
  async function onAuthSubmit(event) {
    if (event.target.id !== 'auth-form') return;
    event.preventDefault();
    const form = new FormData(event.target);
    const email = String(form.get('email')).trim();
    const password = String(form.get('password'));
    const displayName = String(form.get('displayName') || '').trim();
    try {
      if (event.submitter?.textContent?.includes('Skapa konto')) {
        const { data: result, error } = await client.auth.signUp({ email, password, options: { data: { display_name: displayName } } });
        if (error) throw error;
        if (!result.session) { showGate(`<h1>Kontrollera din e-post</h1><p>Vi har skickat en bekräftelselänk till ${escHtml(email)}. Bekräfta kontot och logga sedan in.</p><button class="primary-button" data-auth-mode="signin">Till inloggningen</button>`); return; }
      } else {
        const { error } = await client.auth.signInWithPassword({ email, password });
        if (error) throw error;
      }
      await bootstrapFamily();
    } catch (error) { errorMessage(error); }
  }
  async function onFamilySubmit(event) {
    if (event.target.id !== 'family-form') return;
    event.preventDefault();
    const form = new FormData(event.target);
    const action = event.submitter?.value;
    const displayName = String(form.get('displayName') || '').trim();
    try {
      if (action === 'join') await call(client.rpc('join_family', { p_invite_code: String(form.get('invite') || '').trim(), p_display_name: displayName }));
      else await call(client.rpc('create_family', { p_name: String(form.get('familyName') || 'Familjen Rezaei').trim(), p_display_name: displayName }));
      await bootstrapFamily();
    } catch (error) { errorMessage(error); }
  }
  document.addEventListener('submit', (event) => { onAuthSubmit(event); onFamilySubmit(event); }, true);
  document.addEventListener('click', async (event) => {
    const mode = event.target.closest('[data-auth-mode]');
    if (mode) { loginForm(mode.dataset.authMode); return; }
    if (event.target.closest('[data-signout]')) { await client.auth.signOut(); loginForm(); }
    if (event.target.closest('[data-create-invite]')) {
      try {
        const role = document.getElementById('invite-role')?.value || 'player';
        const code = await call(client.rpc('create_family_invite', { p_family_id: data.familyId, p_role: role }));
        const output = document.getElementById('invite-code-output');
        output.value = code;
        output.textContent = `Inbjudningskod: ${code}`;
      } catch (error) { window.showToast?.(error.message); }
    }
    if (event.target.closest('[data-close-week]')) {
      try {
        const count = await call(client.rpc('close_weekly_plan', { p_plan_id: data.plan.id }));
        await refresh();
        window.showToast?.(`${count} diamantkistor delades ut.`);
      } catch (error) { window.showToast?.(error.message); }
    }
    const roleSave = event.target.closest('[data-save-member-role]');
    if (roleSave && data.familyId && data.member.role === 'admin') {
      const row = roleSave.closest('[data-family-user]');
      try {
        await call(client.rpc('admin_set_member_role', { p_family_id: data.familyId, p_user_id: row.dataset.familyUser, p_role: row.querySelector('[data-member-role]').value }));
        await refresh();
        window.showToast?.('Familjemedlemmens roll uppdaterades.');
      } catch (error) { window.showToast?.(error.message); }
    }
    const removeMember = event.target.closest('[data-remove-family-member]');
    if (removeMember && data.familyId && data.member.role === 'admin') {
      const row = removeMember.closest('[data-family-user]');
      const member = data.members.find((item) => item.user_id === row?.dataset.familyUser);
      if (member && window.confirm(`Ta bort ${member.display_name} från familjen? Deras tilldelade sysslor tas också bort.`)) {
        try {
          await call(client.rpc('admin_remove_family_member', { p_family_id: data.familyId, p_user_id: member.user_id }));
          await refresh();
          window.showToast?.(`${member.display_name} togs bort från familjen.`);
        } catch (error) { window.showToast?.(error.message); }
      }
    }
    if (event.target.closest('[data-leave-family]') && data.familyId) {
      if (window.confirm(`Lämna ${data.familyName}? Du tas bort från familjens medlemslista och tilldelningar.`)) {
        try {
          await call(client.rpc('leave_family', { p_family_id: data.familyId }));
          data.familyId = null; data.member = null;
          document.querySelector('.app-shell').hidden = true;
          await bootstrapFamily();
        } catch (error) { window.showToast?.(error.message); }
      }
    }
    if (event.target.closest('[data-delete-family]') && data.familyId && data.member.role === 'admin') {
      const typedName = window.prompt(`Detta raderar familjen och dess uppgifter, medlemskap och historik permanent. Skriv familjenamnet exakt för att fortsätta: ${data.familyName}`);
      if (typedName === data.familyName) {
        const confirmed = window.confirm(`Bekräfta permanent radering av ${data.familyName}. Åtgärden kan inte ångras.`);
        if (confirmed) {
          try {
            await call(client.rpc('admin_delete_family', { p_family_id: data.familyId }));
            data.familyId = null; data.member = null;
            document.querySelector('.app-shell').hidden = true;
            await bootstrapFamily();
          } catch (error) { window.showToast?.(error.message); }
        }
      } else if (typedName !== null) window.showToast?.('Familjenamnet stämde inte. Ingen data raderades.');
    }
  }, true);
  document.addEventListener('click', async (event) => {
    const questButton = event.target.closest('[data-quest]');
    if (questButton && data.familyId) {
      event.stopImmediatePropagation();
      const choreId = questButton.dataset.quest;
      const submission = data.submissions.find((s) => s.chore_id === choreId && s.user_id === data.member.user_id);
      try {
        if (!submission || submission.status === 'rejected') {
          await call(client.rpc('submit_chore', { p_chore_id: choreId }));
          await refresh();
          window.showToast?.('Uppgiften väntar nu på en vuxens klartecken.');
        }
      } catch (error) { window.showToast?.(error.message); }
      return;
    }
    if (event.target.closest('[data-chest]') && data.familyId) {
      event.preventDefault(); event.stopImmediatePropagation();
      window.showToast?.('Kistor och varelser flyttas till familjens gemensamma samling i nästa del av kopplingen.');
      return;
    }
    if (event.target.closest('#reset-game') && data.familyId) {
      event.preventDefault(); event.stopImmediatePropagation();
      window.showToast?.('Familjens Supabase-data återställs inte från den här knappen.');
      return;
    }
    const curseSubmit = event.target.closest('[data-curse-submit]');
    if (curseSubmit && data.familyId) {
      event.stopImmediatePropagation();
      try { await call(client.rpc('submit_chore', { p_chore_id: curseSubmit.dataset.curseSubmit })); await refresh(); window.showToast?.('Förbannelseuppgiften väntar på klartecken.'); }
      catch (error) { window.showToast?.(error.message); }
      return;
    }
    const decision = event.target.closest('[data-quest-decision],[data-curse-decision]');
    if (decision && data.familyId) {
      event.stopImmediatePropagation();
      const row = decision.closest('.approval-row');
      try {
        const submissionId = decision.dataset.submission || data.submissions.find((s) => s.chore_id === decision.dataset.curseId && s.status === 'pending_approval')?.id;
        await call(client.rpc('decide_quest_submission', { p_submission_id: submissionId, p_decision: decision.dataset.questDecision || decision.dataset.curseDecision, p_reason: row?.querySelector('[data-reason]')?.value || '' }));
        await refresh();
        window.showToast?.('Beslutet sparades.');
      } catch (error) { window.showToast?.(error.message); }
    }
  }, true);
  document.addEventListener('submit', async (event) => {
    if (event.target.id !== 'admin-create-quest' || !data.familyId) return;
    event.preventDefault();
    event.stopImmediatePropagation();
    if (data.member.role !== 'admin' || !data.plan) return;
    const form = new FormData(event.target);
    const assignees = [...event.target.querySelectorAll('[name="assignees"]:checked')].map((el) => el.value);
    try {
      await call(client.rpc('add_weekly_chore', { p_plan_id: data.plan.id, p_title: String(form.get('title')).trim(), p_description: String(form.get('detail') || ''), p_xp: Number(form.get('xp')), p_tokens: Number(form.get('tokens')), p_assignees: assignees, p_difficulty: String(form.get('difficulty') || 'Lätt') }));
      await refresh();
      window.showToast?.('Veckosysslan har lagts till.');
    } catch (error) { window.showToast?.(error.message); }
  }, true);
  client.auth.onAuthStateChange((event, session) => {
    if (!session) { data.familyId = null; data.member = null; if (realtimeChannel) client.removeChannel(realtimeChannel); document.querySelector('.app-shell').hidden = true; loginForm(); }
    else if (event === 'SIGNED_IN' && !data.familyId) setTimeout(() => { if (!data.familyId) bootstrapFamily().catch(errorMessage); }, 0);
  });
  document.querySelector('.app-shell').hidden = true;
  loginForm();
  bootstrapFamily().catch(errorMessage);
})();
