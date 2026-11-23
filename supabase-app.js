/* Supabase auth and family data adapter for the static app. */
(function () {
  const client = window.supabaseClient;
  if (!client) {
    document.querySelector('.app-shell').hidden = true;
    document.getElementById('modal-root').innerHTML = '<div class="auth-screen"><section class="auth-card"><h1>Supabase kunde inte starta</h1><p>Kontrollera internetanslutningen och att Supabase-klienten laddas.</p></section></div>';
    return;
  }

  const data = { familyId: null, member: null, members: [], chores: [], allChores: [], submissions: [], creatures: [], familyCreatures: [], creatureEffects: [], abilityRequests: [], chestCredits: [], familyChallenges: [], plan: null, nextPlan: null, nextWeekChores: [], choreBankItems: [], choreBankReservations: [] };
  let bankCooldownTimer = null;
  function scheduleBankCooldownRefresh() {
    clearTimeout(bankCooldownTimer);
    const nextAvailability = data.choreBankItems.map((item) => item.cooldown_until ? new Date(item.cooldown_until).getTime() : Infinity).filter((time) => Number.isFinite(time) && time > Date.now()).sort((a, b) => a - b)[0];
    if (nextAvailability) bankCooldownTimer = setTimeout(() => refresh().catch(errorMessage), Math.min(2147483647, Math.max(1000, nextAvailability - Date.now() + 250)));
  }
  window.remoteFamily = data;
  window.demoSandbox = { active: false, snapshot: null, workingState: null };
  const escHtml = (value) => String(value ?? '').replace(/[&<>"']/g, (c) => ({ '&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;' }[c]));
  const weekdayNames = ['måndag','tisdag','onsdag','torsdag','fredag','lördag','söndag'];
  const baseWeeklyTitle = (title) => String(title || '').replace(/\s·\s(?:måndag|tisdag|onsdag|torsdag|fredag|lördag|söndag|tillfälle\s+\d+(?:\/\d+)?)$/i, '').trim();
  const weeklyGroupKey = (chore) => `${chore.plan_id}:${chore.created_by || ''}:${chore.created_at}:${baseWeeklyTitle(chore.title).toLocaleLowerCase('sv-SE')}`;
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
  async function openFamilyChest(button) {
    const chestType = ({ 'Träkista':'wooden', 'Silverkista':'silver', 'Guldkista':'gold', 'Diamantkista':'diamond' })[button.dataset.chest];
    if (!chestType) return;
    const keyName = `family-chest:${data.familyId}:${chestType}`;
    let requestKey = sessionStorage.getItem(keyName);
    if (!requestKey) { requestKey = crypto.randomUUID(); sessionStorage.setItem(keyName, requestKey); }
    button.disabled = true;
    try {
      const result = await call(client.rpc('open_creature_chest', { p_family_id: data.familyId, p_chest_type: chestType, p_request_key: requestKey, p_credit_id: button.dataset.chestCredit || null }));
      sessionStorage.removeItem(keyName);
      await refresh();
      const creature = creatureDefinition(result.creature_name);
      const art = creature ? mascot(creature.icon, 122, creature.palette) : '✨';
      const chestArt = chestIllustration(button.dataset.chest, 100);
      const body = result.is_cursed
        ? `<div class="curse-reveal"><span class="curse-reveal-word">FÖRBANNELSE!</span><div class="modal-creature">${art}</div><span class="rarity cursed-rarity">FÖRBANNELSE</span><h2>${escHtml(result.creature_name)} har vaknat…</h2><p>${escHtml(result.curse_task || '')}</p><p class="curse-modal-note">Deadline ${result.deadline_hours} timmar · Vanliga uppdrag låses tills förbannelsen godkänts.</p><button class="primary-button" data-close>Jag tar mig an det</button></div>`
        : `<span class="modal-chest">${chestArt}</span><div class="eyebrow">KISTAN ÄR ÖPPNAD!</div><span class="modal-creature">${art}</span><span class="rarity">${escHtml(creature?.label || result.rarity)}</span><h2>${result.is_duplicate ? 'En vän skickar en hälsning!' : `Möt ${escHtml(result.creature_name)}!`}</h2><p>${result.is_duplicate ? `Du har redan ${escHtml(result.creature_name)}. Du fick ${result.tokens_awarded} mynt.` : escHtml(creature?.description || 'En ny vän har hittat hem!')}</p><button class="primary-button" data-close>Härligt!</button>`;
      window.openModal?.(`<button class="modal-close" data-close aria-label="Stäng">×</button>${body}`);
    } catch (error) {
      if (/not enough coins|unknown chest|sign in|membership|required/i.test(error.message || '')) sessionStorage.removeItem(keyName);
      const message = /not enough coins/i.test(error.message || '') ? 'Du behöver fler mynt för den kistan.' : /unknown chest/i.test(error.message || '') ? 'Den kistan finns inte.' : error.message || 'Kistan kunde inte öppnas just nu. Försök igen.';
      window.showToast?.(message);
      button.disabled = false;
    }
  }

  function showGate(content) {
    root.innerHTML = `<div class="auth-screen"><section class="auth-card"><a class="brand auth-brand" href="#hem"><span class="brand-mark">✦</span><span>familje<span class="brand-light">äventyret</span></span></a>${content}<p class="auth-error" aria-live="polite"></p></section></div>`;
  }
  function abilityErrorText(error) {
    const message = String(error?.message || '').toLowerCase();
    const translations = [
      [/choose a task assigned to you/,'Välj en uppgift som är tilldelad dig.'],[/choose an easy task/,'Den här förmågan gäller bara lätta uppgifter.'],[/choose a medium task/,'Den här förmågan gäller bara mellansvåra uppgifter.'],[/choose an easy or medium task/,'Välj en lätt eller mellansvår uppgift.'],[/choose another active family member/,'Välj en annan aktiv familjemedlem.'],[/choose another creature/,'Välj en annan varelse i din samling.'],[/target creature is not active/,'Målvarelsen är inte längre aktiv i din samling.'],[/not already assigned/,'Den valda personen har redan uppgiften.'],[/already submitted/,'Uppgiften är redan inskickad eller godkänd.'],[/no upcoming task/,'Det finns ingen tillgänglig uppgift för den här förmågan.'],[/replacement task is not available/,'Ersättningsuppgiften är inte längre ledig.'],[/choose an easy replacement/,'Välj en ledig lätt ersättningsuppgift.'],[/deadline has not passed/,'Uppgiftens deadline har inte passerat ännu.'],[/deadline has passed/,'Deadlinen har passerat. Be om en extra möjlighet via förmågan.'],[/already consumed/,'Varelsen har redan förbrukats.'],[/cooldown/i,'Förmågan vilar fortfarande.'],[/unlocks at creature level/,'Varelsen behöver nå nästa nivå först.'],[/curse tasks/,'Förbannelseuppgifter kan inte påverkas av den här kraften.'],[/active family member/,'Du behöver vara aktiv familjemedlem för att göra detta.']
    ];
    return translations.find(([pattern]) => pattern.test(message))?.[1] || error?.message || 'Förmågan kunde inte aktiveras.';
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
    showGate(`<h1>Gå med i familjen</h1><p>Skapa familjens äventyr eller använd en inbjudningskod.</p><form id="family-form" class="auth-form"><label>Ditt visningsnamn<input name="displayName" autocomplete="name" maxlength="60" value="${escHtml(data.member?.display_name || '')}" required></label><label>Familjenamn<input name="familyName" maxlength="80" value="Familjen Rezaei" required></label><button class="primary-button" name="action" value="create" type="submit">Skapa ny familj</button><label>Inbjudningskod<input name="invite" autocomplete="off" maxlength="40" placeholder="t.ex. banan-klöver"></label><button class="auth-secondary" name="action" value="join" type="submit">Gå med med kod</button></form><button class="auth-switch" data-signout>Logga ut</button>`);
  }
  function getMonday() {
    const now = new Date();
    now.setHours(0, 0, 0, 0);
    now.setDate(now.getDate() - ((now.getDay() + 6) % 7));
    return now.toLocaleDateString('sv-SE');
  }
  function getNextMonday() {
    const date = new Date(`${getMonday()}T12:00:00`);
    date.setDate(date.getDate() + 7);
    return date.toLocaleDateString('sv-SE');
  }
  async function bootFamily() {
    if (window.demoSandbox.active) return;
    const user = (await call(client.auth.getUser())).user;
    if (!user) return loginForm();
    const memberships = await call(client.from('family_members').select('family_id,user_id,display_name,role,xp,tokens,streak,is_active').eq('user_id', user.id).eq('is_active', true));
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
    window.gameState.shards = 0;
    window.gameState.streak = data.member.streak;
    window.renderGame?.();
    decorateAdminForm();
    if (realtimeChannel) client.removeChannel(realtimeChannel);
    realtimeChannel = client.channel(`family-${data.familyId}`)
      .on('postgres_changes', { event: '*', schema: 'public', table: 'family_members', filter: `family_id=eq.${data.familyId}` }, () => bootstrapFamily().catch(errorMessage))
      .on('postgres_changes', { event: '*', schema: 'public', table: 'quest_submissions', filter: `family_id=eq.${data.familyId}` }, () => refresh())
      .on('postgres_changes', { event: '*', schema: 'public', table: 'chores', filter: `family_id=eq.${data.familyId}` }, () => refresh())
      .on('postgres_changes', { event: '*', schema: 'public', table: 'chore_bank_items', filter: `family_id=eq.${data.familyId}` }, () => refresh())
      .on('postgres_changes', { event: '*', schema: 'public', table: 'chore_bank_reservations', filter: `family_id=eq.${data.familyId}` }, () => refresh())
      .on('postgres_changes', { event: '*', schema: 'public', table: 'creature_inventory', filter: `family_id=eq.${data.familyId}` }, () => refresh())
      .on('postgres_changes', { event: '*', schema: 'public', table: 'creature_effects', filter: `family_id=eq.${data.familyId}` }, () => refresh())
      .on('postgres_changes', { event: '*', schema: 'public', table: 'creature_ability_requests', filter: `family_id=eq.${data.familyId}` }, () => refresh())
      .on('postgres_changes', { event: '*', schema: 'public', table: 'creature_chest_credits', filter: `family_id=eq.${data.familyId}` }, () => refresh())
      .on('postgres_changes', { event: '*', schema: 'public', table: 'family_challenges', filter: `family_id=eq.${data.familyId}` }, () => refresh())
      .subscribe();
  }
  let bootstrapping = false;
  async function bootstrapFamily() {
    if (bootstrapping) return;
    bootstrapping = true;
    try { return await bootFamily(); }
    finally { bootstrapping = false; }
  }
  async function syncFamilyRole() {
    if (window.demoSandbox.active) return;
    if (!data.familyId || !data.member) return;
    try {
      const membership = await call(client.from('family_members').select('role,is_active').eq('family_id', data.familyId).eq('user_id', data.member.user_id).maybeSingle());
      if (!membership?.is_active || membership.role !== data.member.role) await bootstrapFamily();
    } catch (error) { errorMessage(error); }
  }
  window.addEventListener('focus', syncFamilyRole);
  document.addEventListener('visibilitychange', () => { if (!document.hidden) syncFamilyRole(); });
  async function loadFamilyData() {
    const state = window.gameState;
    if (!state) throw new Error('Spelstatusen kunde inte läsas in. Ladda om sidan.');
    const familyId = data.familyId;
    const [family, members, plans, chores, bankItems, bankReservations, submissions, creatures, creatureEffects, abilityRequests, chestCredits, familyChallenges, weeklyRewards, prizeRows] = await Promise.all([
      call(client.from('families').select('name').eq('id', familyId).single()),
      call(client.from('family_members').select('family_id,user_id,display_name,role,xp,tokens,shards,streak,is_active').eq('family_id', familyId).eq('is_active', true)),
      call(client.from('weekly_plans').select('*').eq('family_id', familyId).in('week_start', [getMonday(), getNextMonday()])),
      call(client.from('chores').select('*,chore_assignments(user_id,deadline_at,scheduled_for),quest_submissions(*)').eq('family_id', familyId).eq('is_active', true)),
      optionalRows(client.from('chore_bank_items').select('*').eq('family_id', familyId).order('created_at', { ascending: false })),
      optionalRows(client.from('chore_bank_reservations').select('*').eq('family_id', familyId)),
      call(client.from('quest_submissions').select('*,chores(title,kind,xp_reward,token_reward)').eq('family_id', familyId).order('submitted_at', { ascending: false })),
      optionalRows(client.from('creature_inventory').select('*').eq('family_id', familyId).eq('user_id', data.member.user_id).order('acquired_at')),
      optionalRows(client.from('creature_effects').select('*').eq('family_id', familyId).eq('user_id', data.member.user_id).gt('uses_remaining', 0).order('created_at')),
      optionalRows(client.from('creature_ability_requests').select('*').eq('family_id', familyId).order('created_at', { ascending: false })),
      optionalRows(client.from('creature_chest_credits').select('*').eq('family_id', familyId).eq('user_id', data.member.user_id).is('redeemed_at', null).order('created_at')),
      optionalRows(client.from('family_challenges').select('*').eq('family_id', familyId).in('status', ['active','complete']).order('starts_at', { ascending: false })),
      call(client.from('weekly_rewards').select('id').eq('family_id', familyId).eq('user_id', data.member.user_id).limit(1)),
      optionalRows(client.from('family_ranking_prizes').select('day_prize,week_prize,season_prize').eq('family_id', familyId).limit(1))
    ]);
    const approved = submissions.filter(row => row.user_id === data.member.user_id &&
      row.status === 'approved' && row.chores?.kind === 'weekly');
    const dayNumbers = [...new Set(approved.map(row => Math.floor(Date.parse(row.decided_at) / 86400000)))]
      .filter(Number.isFinite).sort((a, b) => a - b);
    let run = 0;
    let best = 0;
    dayNumbers.forEach((day, index) => {
      run = day === dayNumbers[index - 1] + 1 ? run + 1 : 1;
      best = Math.max(best, run);
    });
    const now = new Date();
    const startMonth = now.getMonth() - (now.getMonth() + 1) % 3;
    const seasonStart = window.activeSeason?.key === 'christmas'
      ? new Date(now.getFullYear(), 11, 18) : new Date(now.getFullYear(), startMonth, 1);
    state.profileAwards = [
      ['🌱', 'Första steget', 'Ett godkänt uppdrag', approved.length >= 1],
      ['🔥', 'På gång!', 'Fem dagars svit', Math.max(best, members.find(m => m.user_id === data.member.user_id)?.streak || 0) >= 5],
      ['🦊', 'Ny vän', 'Hitta en varelse', creatures.length > 0],
      ['✨', 'Guldstjärna', 'Tio godkända uppdrag', approved.length >= 10],
      ['👪', 'Laget först', 'Få veckans familjebelöning', weeklyRewards.length > 0],
      ['🏆', window.activeSeason?.name || 'Säsongsäventyret', 'Ett godkänt uppdrag denna säsong', approved.some(row => Date.parse(row.decided_at) >= seasonStart.getTime())]
    ];
    data.familyName = family.name;
    data.prizes = prizeRows[0] || { day_prize: "", week_prize: "", season_prize: "" };
    data.members = members;
    data.member = members.find((member) => member.user_id === data.member.user_id) || data.member;
    data.familyCreatures = [];
    if (data.member.role === 'admin') {
      try { data.familyCreatures = await call(client.rpc('admin_list_family_creatures', { p_family_id: familyId })); }
      catch (error) { if (!['PGRST202','42883'].includes(error.code)) throw error; }
    }
    data.plan = plans.find((plan) => plan.week_start === getMonday()) || null;
    data.nextPlan = plans.find((plan) => plan.week_start === getNextMonday()) || null;
    data.creatures = creatures.filter((creature) => !creature.removed_at);
    data.creatureEffects = creatureEffects;
    data.abilityRequests = abilityRequests;
    data.chestCredits = chestCredits;
    data.familyChallenges = familyChallenges;
    state.creatures = data.creatures.map((creature) => { const definition = creatureDefinition(creature.creature_name); return { id: creature.id, catalogId: creature.creature_id, name: creature.creature_name, rarity: creature.rarity.toUpperCase(), rarityKey: creature.rarity, level: creature.level, creatureXp: creature.creature_xp, isCursed: creature.is_cursed, consumedAt: creature.consumed_at, cooldownUntil: creature.cooldown_until ? new Date(creature.cooldown_until).getTime() : null, ready: !creature.consumed_at && (!creature.cooldown_until || new Date(creature.cooldown_until).getTime() <= Date.now()), ability: definition?.ability || '', abilityKey: definition?.abilityKey || '', minLevel: definition?.minLevel || 1, visualTheme: definition?.visualTheme || '' }; });
    const allChores = chores;
    data.allChores = allChores;
    data.choreBankItems = bankItems;
    data.choreBankReservations = bankReservations;
    scheduleBankCooldownRefresh();
    data.submissions = submissions;
    if (data.member.role === 'admin' && !data.plan) {
      const planId = await call(client.rpc('create_weekly_plan', { p_family_id: familyId, p_week_start: getMonday() }));
      data.plan = { id: planId, family_id: familyId, week_start: getMonday(), status: 'open' };
    }
    if (data.member.role === 'admin' && !data.nextPlan) {
      const planId = await call(client.rpc('create_weekly_plan', { p_family_id: familyId, p_week_start: getNextMonday() }));
      data.nextPlan = { id: planId, family_id: familyId, week_start: getNextMonday(), status: 'open' };
    }
    data.chores = allChores.filter((chore) => (chore.chore_assignments || []).some((a) => a.user_id === data.member.user_id) && (chore.kind === 'curse' || (data.plan && chore.plan_id === data.plan.id)));
    data.actionableCount = data.chores.filter((chore) => chore.kind === 'weekly' && data.plan && chore.plan_id === data.plan.id && !submissions.some((submission) => submission.chore_id === chore.id && submission.user_id === data.member.user_id && (submission.status === 'approved' || submission.status === 'pending_approval'))).length;
    data.weeklyChores = allChores.filter((chore) => chore.kind === 'weekly' && chore.is_active && data.plan && chore.plan_id === data.plan.id);
    data.nextWeekChores = allChores.filter((chore) => chore.kind === 'weekly' && chore.is_active && data.nextPlan && chore.plan_id === data.nextPlan.id);
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
    state.role = data.member.role;
    state.xp = data.member.xp;
    state.tokens = data.member.tokens;
    state.shards = 0;
    state.streak = data.member.streak;
    const mapped = submissions.map((s) => ({ id: s.id, questId: s.chore_id, questTitle: s.chores?.title || 'Uppdrag', submittedBy: members.find((m) => m.user_id === s.user_id)?.display_name || 'Familjemedlem', userId: s.user_id, kind: s.chores?.kind || 'weekly', submittedAt: new Date(s.submitted_at).getTime(), decidedAt: s.decided_at ? new Date(s.decided_at).getTime() : null, status: s.status, xp: s.xp_reward, tokens: s.token_reward, reason: s.rejection_reason }));
    state.questSubmissions = mapped;
    state.completed = submissions.filter((s) => s.status === 'approved' && s.chores?.kind === 'weekly' && s.user_id === data.member.user_id).map((s) => s.chore_id);
    state.customQuests = data.chores.filter((c) => c.kind === 'weekly' && (c.chore_assignments || []).some((item) => item.user_id === data.member.user_id)).map((c) => { const assignment = (c.chore_assignments || []).find((item) => item.user_id === data.member.user_id); return ({ id: c.id, title: c.title, detail: c.description, scheduledFor: assignment?.scheduled_for || null, icon: 'dish', color: 'green', xp: c.xp_reward, tokens: c.token_reward, difficulty: c.difficulty || 'Lätt' }); });
    state.curses = allChores.filter((c) => c.kind === 'curse').map((c) => {
      const last = c.quest_submissions?.sort((a, b) => new Date(b.submitted_at) - new Date(a.submitted_at))[0];
      const mine = (c.chore_assignments || []).some((a) => a.user_id === data.member.user_id);
      const submitter = members.find((m) => m.user_id === last?.user_id)?.display_name || 'Familjemedlem';
      return { id: c.id, submissionId: last?.id, name: c.title, task: c.description, status: c.resolved_at ? 'defeated' : last?.status === 'pending_approval' ? 'pending' : 'active', submittedBy: submitter, canSubmit: mine && last?.status !== 'pending_approval', submittedAt: last ? new Date(last.submitted_at).getTime() : null, deadlineAt: c.deadline_at ? new Date(c.deadline_at).getTime() : Date.now() + 86400000, isCursed: true };
    });
    state.notifications = await loadNotifications(familyId, data.member.user_id);
  }
  const taskEffects = new Set(['remove_easy_once','remove_easy_repeat','remove_easy_or_request_medium','remove_easy_medium','request_remove_medium','request_remove_medium_streak','extend_easy_deadline','extend_medium_deadline','swap_easy','request_transfer_easy','request_transfer_easy_medium','deadline_grace']);
  function openCreatureAbility(id) {
    const creature = data.creatures.find((item) => item.id === id);
    if (!creature) return;
    const definition = creatureDefinition(creature.creature_name);
    if (!definition) return;
    const effectKey = definition.abilityKey;
    const activeEffect = data.creatureEffects.find((effect) => effect.creature_id === creature.id && effect.uses_remaining > 0 && (!effect.expires_at || new Date(effect.expires_at).getTime() > Date.now()));
    const levelXp = creature.creature_xp % 100;
    const cooldownEnd = creature.cooldown_until ? new Date(creature.cooldown_until).getTime() : 0;
    const cooldownRemaining = Math.max(0, cooldownEnd - Date.now());
    const cooldownText = cooldownRemaining ? (window.formatAbilityCountdown?.(cooldownRemaining) || new Intl.DateTimeFormat('sv-SE',{dateStyle:'medium',timeStyle:'short'}).format(new Date(cooldownEnd))) : '';
    const assignedTasks = data.allChores.filter((chore) => chore.kind === 'weekly' && chore.is_active && data.plan && chore.plan_id === data.plan.id && (chore.chore_assignments || []).some((assignment) => assignment.user_id === data.member.user_id) && !data.submissions.some((submission) => submission.chore_id === chore.id && submission.user_id === data.member.user_id && ['pending_approval','approved'].includes(submission.status)));
    const allowedDifficulty = ['extend_medium_deadline','request_remove_medium','request_remove_medium_streak'].includes(effectKey) ? ['Mellan'] : ['remove_easy_once','remove_easy_repeat','extend_easy_deadline','request_transfer_easy','swap_easy'].includes(effectKey) ? ['Lätt'] : ['Lätt','Mellan'];
    const targetTasks = assignedTasks.filter((chore) => (!taskEffects.has(effectKey) || allowedDifficulty.includes(chore.difficulty)) && (effectKey !== 'deadline_grace' || (() => { const assignment = chore.chore_assignments?.find((item) => item.user_id === data.member.user_id); const deadline = assignment?.deadline_at || chore.deadline_at; return deadline && new Date(deadline).getTime() < Date.now(); })()));
    const targets = data.creatures.filter((item) => !item.is_cursed && !item.consumed_at && item.id !== creature.id);
    const needsTask = taskEffects.has(effectKey);
    const needsCreature = ['grant_creature_xp','creature_xp_target_next'].includes(effectKey);
    const needsMember = ['request_transfer_easy','request_transfer_easy_medium'].includes(effectKey);
    const needsSwap = effectKey === 'swap_easy';
    const status = creature.consumed_at ? 'Förbrukad' : creature.level < (definition.minLevel || 1) ? `Låses upp på nivå ${definition.minLevel}` : activeEffect ? 'Aktivt' : cooldownText ? `Vilar · ${cooldownText}` : 'Redo';
    const activationLabel = creature.consumed_at ? 'Förbrukad' : creature.level < (definition.minLevel || 1) ? `Nivå ${definition.minLevel}` : activeEffect ? 'Aktivt' : cooldownText ? `Vilar · ${cooldownText}` : 'Använd kraft';
    const blocked = Boolean(creature.is_cursed || creature.consumed_at || creature.level < (definition.minLevel || 1) || activeEffect || cooldownText);
    const taskOptions = targetTasks.map((chore) => `<option value="${escHtml(chore.id)}">${escHtml(chore.title)} · ${escHtml(chore.difficulty)}</option>`).join('');
    const targetOptions = targets.map((item) => `<option value="${escHtml(item.id)}">${escHtml(item.creature_name)} · nivå ${item.level}</option>`).join('');
    const memberOptions = data.members.filter((member) => member.user_id !== data.member.user_id).map((member) => `<option value="${escHtml(member.user_id)}">${escHtml(member.display_name)}</option>`).join('');
    const replacementOptions = data.allChores.filter((chore) => chore.kind === 'weekly' && chore.is_active && chore.difficulty === 'Lätt' && chore.plan_id === data.plan?.id && !(chore.chore_assignments || []).length).map((chore) => `<option value="${escHtml(chore.id)}">${escHtml(chore.title)}</option>`).join('');
    const selectors = `${needsTask ? `<label class="ability-field">Välj uppgift<select data-ability-task required>${taskOptions}</select>${!taskOptions ? '<small>Du har inga tillgängliga uppgifter som passar den här kraften.</small>' : ''}</label>` : ''}${needsCreature ? `<label class="ability-field">Välj varelse<select data-ability-creature required>${targetOptions}</select>${!targetOptions ? '<small>Du behöver en annan aktiv varelse.</small>' : ''}</label>` : ''}${needsMember ? `<label class="ability-field">Välj familjemedlem<select data-ability-member required>${memberOptions}</select>${!memberOptions ? '<small>Det finns ingen annan aktiv familjemedlem.</small>' : ''}</label>` : ''}${needsSwap ? `<label class="ability-field">Välj ersättningsuppgift<select data-ability-replacement required>${replacementOptions}</select>${!replacementOptions ? '<small>Det finns ingen ledig lätt uppgift i veckoplanen.</small>' : ''}</label>` : ''}`;
    const unavailableTarget = (needsTask && !targetOptions) || (needsCreature && !targetOptions) || (needsMember && !memberOptions) || (needsSwap && !replacementOptions);
    const art = mascot(definition.icon, 114, definition.palette);
    window.openModal?.(`<button class="modal-close" data-close aria-label="Stäng">×</button><section class="creature-ability-detail"><div class="creature-detail-art">${art}</div><div class="eyebrow">${escHtml(definition.label)} · NIVÅ ${creature.level}</div><h2>${escHtml(definition.name)}</h2><p>${escHtml(definition.abilityDescription)}</p><div class="ability-xp"><div><b>Varelse-XP</b><span>${creature.creature_xp} XP · ${levelXp}/100 till nästa nivå</span></div><div class="progress"><span style="width:${levelXp}%"></span></div></div><div class="ability-status ${blocked?'is-muted':'is-ready'}">${blocked && !creature.consumed_at && !cooldownText ? '🔒' : activeEffect ? '✨' : '●'} ${escHtml(status)}</div>${activeEffect ? `<p class="ability-active-effect">Effekten väntar på rätt uppgift${activeEffect.expires_at ? ` · går ut ${new Intl.DateTimeFormat('sv-SE',{dateStyle:'short',timeStyle:'short'}).format(new Date(activeEffect.expires_at))}` : ''}.</p>` : ''}${selectors}<p class="ability-confirm-copy">När du aktiverar visas serverns beslut här. Uppgifter som tas bort ger inga belöningar; förbannelseuppgifter kan inte väljas.</p><button class="primary-button" type="button" data-use-creature="${escHtml(creature.id)}" ${blocked || unavailableTarget ? 'disabled' : ''}>${escHtml(activationLabel)}</button></section>`);
  }
  async function useCreatureAbility(button) {
    const id = button.dataset.useCreature;
    const keyName = `creature-ability:${data.familyId}:${id}`;
    let requestKey = sessionStorage.getItem(keyName);
    if (!requestKey) { requestKey = crypto.randomUUID(); sessionStorage.setItem(keyName, requestKey); }
    button.disabled = true;
    try {
      const result = await call(client.rpc('use_creature_ability', {
        p_family_id: data.familyId,
        p_creature_instance_id: id,
        p_request_key: requestKey,
        p_target_chore_id: root.querySelector('[data-ability-task]')?.value || null,
        p_secondary_chore_id: root.querySelector('[data-ability-replacement]')?.value || null,
        p_target_creature_id: root.querySelector('[data-ability-creature]')?.value || null,
        p_target_user_id: root.querySelector('[data-ability-member]')?.value || null
      }));
      if (!result?.ok) {
        sessionStorage.removeItem(keyName);
        button.disabled = false;
        window.showToast?.(abilityErrorText({ message: result?.message || 'Förmågan kunde inte aktiveras.' }));
        return;
      }
      sessionStorage.removeItem(keyName);
      await refresh();
      window.openModal?.(`<div class="ability-result"><div class="eyebrow">${result.status === 'pending_admin' ? 'VÄNTAR PÅ ADMIN' : 'FÖRMÅGAN ÄR AKTIVERAD'}</div><h2>${escHtml(result.creature_name || 'Varelsen')}</h2><p>${escHtml(result.message || 'Förmågan har aktiverats.')}</p><button class="primary-button" data-close>Klart</button></div>`);
    } catch (error) {
      if (/choose |already submitted|not available|not active|deadline|already consumed|cooldown|unlocks at|curse tasks|family member/i.test(error.message || '')) sessionStorage.removeItem(keyName);
      window.showToast?.(abilityErrorText(error));
      button.disabled = false;
    }
  }
  function renderAbilityRequests() {
    const section = document.getElementById('creature-ability-requests');
    const form = document.getElementById('admin-create-quest');
    if (!form || data.member.role !== 'admin') { section?.remove(); return; }
    const pending = data.abilityRequests.filter((request) => request.status === 'pending');
    const members = new Map(data.members.map((member) => [member.user_id, member.display_name]));
    const rows = pending.map((request) => {
      const chore = data.allChores.find((item) => item.id === request.chore_id);
      const title = request.request_type === 'deadline_grace' ? 'Extra inlämningsmöjlighet' : request.request_type === 'transfer' ? 'Överföring av uppgift' : 'Borttagning av uppgift';
      const detail = `${members.get(request.requester_id) || 'Medlem'} · ${chore?.title || 'uppgift'}${request.target_user_id ? ` → ${members.get(request.target_user_id) || 'familjemedlem'}` : ''}`;
      return `<div class="approval-row ability-request-row"><div class="admin-list-copy"><b>${title}</b><small>${escHtml(detail)} · ${escHtml(request.effect_key)}</small></div><input class="rejection-reason" data-ability-reason placeholder="Anledning vid nekande"><button type="button" class="curse-submit curse-approve" data-ability-decision="approved" data-ability-request="${escHtml(request.id)}">Godkänn</button><button type="button" class="filter-tab admin-remove" data-ability-decision="rejected" data-ability-request="${escHtml(request.id)}">Neka</button></div>`;
    }).join('');
    const card = section || document.createElement('section');
    card.id = 'creature-ability-requests'; card.className = 'card admin-section creature-ability-requests';
    const markup = `<div class="section-head"><div><h2>Varelseförfrågningar</h2><p class="admin-muted">Adminbeslut krävs för uppgiftsändringar. Beslutet skickas till spelaren.</p></div><span class="level-chip">${pending.length} VÄNTAR</span></div>${rows || '<p class="admin-muted">Inga varelseförfrågningar väntar.</p>'}`;
    if (card.innerHTML !== markup) card.innerHTML = markup;
    if (!section) form.closest('.admin-section')?.before(card);
  }
  function decorateDemoAdmin(form) {
    if (!window.demoSandbox.active || data.member?.role !== 'admin') return;
    const state = window.gameState;
    if (!state) return;
    let bankCard = document.getElementById('admin-chore-bank');
    if (!bankCard) {
      bankCard = document.createElement('section');
      bankCard.id = 'admin-chore-bank';
      bankCard.className = 'card admin-section admin-chore-bank';
      bankCard.innerHTML = '<div class="section-head"><div><div class="eyebrow">EXTRA ÄVENTYR · DEMO</div><h2>Sysselbanken</h2><p class="admin-muted">Prova att skapa och plocka extrasysslor. Alla ändringar stannar i demoläget.</p></div><span class="level-chip">ENDAST DEMO</span></div><form id="demo-admin-create-bank-item" class="admin-quest-form bank-chore-form"><label>Sysslans namn<input name="title" required maxlength="85" placeholder="Till exempel: Vattna blommorna"></label><label>Beskrivning<input name="description" maxlength="300" placeholder="Kort instruktion"></label><label>XP-belöning<input name="xp" type="number" min="0" max="500" value="15" required></label><label>Myntbelöning<input name="tokens" type="number" min="0" max="100" value="3" required></label><label>Svårighetsgrad<select name="difficulty"><option value="Lätt">Lätt</option><option value="Mellan">Mellan</option><option value="Svår">Svår</option></select></label><label>Personer som behövs<input name="requiredPeople" type="number" min="1" max="8" value="1" required></label><label>Vila efter slutförd (dagar)<input name="cooldownDays" type="number" min="1" max="90" value="7" required></label><button class="primary-button" type="submit">＋ Lägg i Sysselbanken</button></form><div class="bank-admin-list"></div>';
      form.closest('.admin-section')?.after(bankCard);
    }
    const items = state.demoBankItems || [];
    const bankList = bankCard.querySelector('.bank-admin-list');
    const bankMarkup = items.length ? items.map((item) => `<div class="admin-list-row"><div class="admin-list-copy"><b>${escHtml(item.title)}</b><small>${escHtml(item.difficulty || 'Lätt')} · ${item.xp_reward} XP · ${item.token_reward} mynt · ${Number(item.required_people)||1} person${Number(item.required_people)===1?'':'er'} · ${Number(item.cooldown_days)||7} dagars vila${item.cooldown_until && new Date(item.cooldown_until).getTime()>Date.now() ? ' · Vilar' : ' · Tillgänglig'}</small>${item.description ? `<small>${escHtml(item.description)}</small>` : ''}</div><button type="button" class="filter-tab" data-demo-edit-bank="${escHtml(item.id)}">Redigera</button><button type="button" class="filter-tab admin-remove" data-demo-delete-bank="${escHtml(item.id)}">Ta bort</button></div>`).join('') : '<p class="admin-muted">Banken är tom. Lägg till en syssla för att prova den.</p>';
    if (bankList && bankList.dataset.signature !== bankMarkup) { bankList.innerHTML = bankMarkup; bankList.dataset.signature = bankMarkup; }

    let weekCard = document.getElementById('demo-weekly-chores');
    if (!weekCard) {
      weekCard = document.createElement('section');
      weekCard.id = 'demo-weekly-chores';
      weekCard.className = 'card admin-section admin-weekly-chores';
      document.getElementById('admin-chore-bank')?.before(weekCard);
    }
    const allWeekChores = [...(state.demoWeeklyChores || [])];
    for (const chore of state.customQuests || []) if (!allWeekChores.some((entry) => String(entry.id) === String(chore.id))) allWeekChores.push(chore);
    const chores = allWeekChores;
    const weekMarkup = `<div class="section-head"><div><h2>Denna vecka</h2><p class="admin-muted">Redigera veckans uppgifter i en isolerad kopia. Inget sparas på familjekontot.</p></div><span class="level-chip">${chores.length} SYSSLOR</span></div>${chores.map((chore) => `<div class="admin-list-row"><div class="admin-list-copy"><b>${escHtml(chore.title)}</b><small>${escHtml(chore.assignedTo || 'Familjeuppgift')}</small><small>${escHtml(chore.difficulty || 'Lätt')} · ${Number(chore.xp) || 0} XP · ${Number(chore.tokens) || 0} mynt</small></div><button type="button" class="filter-tab" data-edit-demo-weekly="${escHtml(chore.id)}">Redigera</button></div>`).join('') || '<p class="admin-muted">Inga veckosysslor finns i den här demoläget än.</p>'}`;
    if (weekCard.innerHTML !== weekMarkup) weekCard.innerHTML = weekMarkup;
  }

  function decorateDemoQuests() {
    if (!window.demoSandbox.active) return;
    const current = document.querySelector('#view-root .chore-bank-card');
    const state = window.gameState;
    if (!current || !state) return;
    const members = data.members.length ? data.members : [{ user_id: data.member?.user_id || 'demo-admin', display_name: data.member?.display_name || 'Admin' }];
    const now = Date.now();
    const items = state.demoBankItems || [];
    const html = `<section class="card chore-bank-card demo-chore-bank"><div class="chore-bank-heading"><div><div class="eyebrow">EXTRA ÄVENTYR</div><h2>Sysselbanken</h2><p>Reservera en extrasyssla. När alla platser är fyllda får deltagarna uppgiften.</p></div><span class="chore-bank-mark">＋</span></div>${items.length ? `<div class="chore-bank-list">${items.filter((item) => item.is_active !== false).map((item) => { const reserved = Array.isArray(item.reserved_by) ? item.reserved_by : []; const needed = Math.max(1, Number(item.required_people) || 1); const until = item.cooldown_until ? new Date(item.cooldown_until).getTime() : 0; const cooling = until > now; const left = cooling ? Math.max(1, Math.ceil((until - now) / 86400000)) : 0; return `<article class="chore-bank-offer"><div class="chore-bank-icon">✦</div><div class="chore-bank-copy"><b>${escHtml(item.title)}</b><small>${escHtml(item.description || 'Extra syssla')} · ${escHtml(item.difficulty || 'Lätt')}</small><span>+${item.xp_reward} XP · ${item.token_reward} mynt</span><small>${cooling ? `Vilar i ${left} dagar` : `${reserved.length}/${needed} personer reserverade`} · ${Number(item.cooldown_days)||7} dagars vila</small></div><div class="bank-claim-actions">${cooling ? '<span class="level-chip">VILAR</span>' : members.map((member) => { const already = reserved.includes(member.user_id); return `<button class="filter-tab bank-join-button" type="button" data-demo-bank-reserve="${escHtml(item.id)}" data-demo-bank-user="${escHtml(member.user_id)}" ${already ? 'disabled' : ''}>${already ? 'Reserverad: ' : 'Anslut: '}${escHtml(member.display_name)}</button>`; }).join('')}</div></article>`; }).join('')}</div>` : '<div class="chore-bank-empty"><span>🌱</span><b>Inga extrasysslor just nu</b><small>Skapa en syssla i adminpanelen för att prova banken.</small></div>'}</section>`;
    const signature = JSON.stringify(items);
    if (current.dataset.demoBankSignature !== signature) { current.outerHTML = html; document.querySelector('#view-root .demo-chore-bank').dataset.demoBankSignature = signature; }
  }

  function decorateAdminForm() {
    const form = document.getElementById('admin-create-quest');
    if (!form) return;
    if (data.member.role === 'admin' && !document.getElementById('admin-chore-bank')) {
      const bankCard = document.createElement('section');
      bankCard.id = 'admin-chore-bank';
      bankCard.className = 'card admin-section admin-chore-bank';
      bankCard.innerHTML = '<div class="section-head"><div><div class="eyebrow">EXTRA ÄVENTYR</div><h2>Sysselbanken</h2><p class="admin-muted">Skapa fristående extrasysslor som familjen kan plocka på sig. Belöningen delas ut efter vanligt admin-godkännande.</p></div><span class="level-chip">EXTRA XP + MYNT</span></div><form id="admin-create-bank-chore" class="admin-quest-form bank-chore-form"><label>Sysslans namn<input name="title" required maxlength="85" placeholder="Till exempel: Vattna blommorna"></label><label>Beskrivning<input name="description" maxlength="300" placeholder="Kort instruktion"></label><label>XP-belöning<input name="xp" type="number" min="0" max="500" value="30" readonly required></label><label>Myntbelöning<input name="tokens" type="number" min="0" max="100" value="15" readonly required></label><label>Svårighetsgrad<select name="difficulty"><option value="Lätt" selected>Lätt</option><option value="Mellan">Mellan</option><option value="Svår">Svår</option></select></label><label>Personer som behövs<input name="requiredPeople" type="number" min="1" max="${data.members.length}" value="1" required></label><label>Vila efter utdelning (dagar)<input name="cooldownDays" type="number" min="0" max="365" value="7" required><small>0 dagar betyder direkt tillgänglig igen.</small></label><button class="primary-button" type="submit">＋ Lägg i Sysselbanken</button></form><div class="bank-admin-list"></div>';
      form.closest('.admin-section')?.after(bankCard);
    }
    const bankList = document.querySelector('#admin-chore-bank .bank-admin-list');
    if (bankList) {
      const memberNames = new Map(data.members.map((member) => [member.user_id, member.display_name]));
      const reservations = data.choreBankReservations || [];
      const items = data.choreBankItems || [];
      const bankMarkup = items.length ? items.map((item) => {
        const held = reservations.filter((row) => row.item_id === item.id);
        const required = Math.max(1, Number(item.required_people) || 1);
        const cooling = item.cooldown_until && new Date(item.cooldown_until).getTime() > Date.now();
        const stateLabel = cooling ? `VILAR TILL ${new Intl.DateTimeFormat('sv-SE',{day:'numeric',month:'short',hour:'2-digit',minute:'2-digit'}).format(new Date(item.cooldown_until))}` : held.length ? `${held.length}/${required} RESERVERADE` : 'LEDIG';
        const heldNames = held.map((row) => memberNames.get(row.user_id) || 'Medlem').join(', ');
        return `<div class="admin-list-row bank-admin-row"><div class="admin-list-copy"><b>${escHtml(item.title)}</b><small>${escHtml(item.difficulty)} · ${item.xp_reward} XP · ${item.token_reward} mynt · ${required} person${required === 1 ? '' : 'er'} · ${Number(item.cooldown_days) || 0} dagars vila</small>${item.description ? `<small>${escHtml(item.description)}</small>` : ''}${required > 1 ? `<small>Platser: ${held.length}/${required}${heldNames ? ` · ${escHtml(heldNames)}` : ''}</small>` : ''}</div><span class="level-chip">${stateLabel}</span><button type="button" class="filter-tab" data-edit-bank-chore="${escHtml(item.id)}">Redigera</button><button type="button" class="filter-tab admin-remove" data-delete-bank-chore="${escHtml(item.id)}">Ta bort</button></div>`;
      }).join('') : '<p class="admin-muted">Banken är tom än. Lägg till en syssla så kan familjen plocka på sig den.</p>';
      if (bankList.dataset.signature !== bankMarkup) { bankList.innerHTML = bankMarkup; bankList.dataset.signature = bankMarkup; }
    }
    if (data.member.role === 'admin') {
      let sandboxCard = document.getElementById('admin-sandbox-entry');
      if (!sandboxCard) { sandboxCard = document.createElement('section'); sandboxCard.id = 'admin-sandbox-entry'; sandboxCard.className = 'card admin-section sandbox-entry-card'; sandboxCard.innerHTML = '<div><span class="eyebrow">RISKFRI TESTYTA</span><h2>Testa utan risk</h2><p class="admin-muted">Öppna en separat kopia av familjeäventyret med obegränsat antal mynt. Inget du gör sparas på familjekontot.</p></div><button type="button" class="primary-button" data-demo-start>Starta demoläge</button>'; form.closest('.admin-section')?.before(sandboxCard); }
    }
    let prizeCard = document.getElementById('admin-ranking-prizes');
    if (!prizeCard) {
      prizeCard = document.createElement('section');
      prizeCard.id = 'admin-ranking-prizes';
      prizeCard.className = 'card admin-section admin-ranking-prizes';
      prizeCard.innerHTML = '<div class="section-head"><div><h2>Rankingpriser</h2><p class="admin-muted">Skriv priset som vinnaren får. Lämna tomt eller skriv ”Inget pris” om perioden saknar pris.</p></div></div><form id="admin-prizes-form" class="ranking-prize-form"><label>Dagens pris<input name="day_prize" maxlength="160" placeholder="Inget pris"></label><label>Veckans pris<input name="week_prize" maxlength="160" placeholder="Inget pris"></label><label>Säsongens pris<input name="season_prize" maxlength="160" placeholder="Inget pris"></label><button class="primary-button" type="submit">Spara priser</button></form>';
      document.querySelector('.admin-picker')?.after(prizeCard);
    }
    const prizeForm = prizeCard.querySelector('#admin-prizes-form');
    if (prizeForm && document.activeElement?.form !== prizeForm) {
      for (const field of ['day_prize','week_prize','season_prize']) prizeForm.elements[field].value = data.prizes?.[field] || '';
    }
    renderAbilityRequests();
    const existingMemberCard = document.getElementById('family-member-management');
    const memberCard = existingMemberCard || document.createElement('section');
    const adminCount = data.members.filter((member) => member.role === 'admin').length;
    const memberSignature = data.members.map((member) => `${member.user_id}:${member.display_name}:${member.role}`).join('|');
    if (!existingMemberCard || memberCard.dataset.signature !== memberSignature) {
      memberCard.id = 'family-member-management';
      memberCard.className = 'card admin-section family-member-management';
      memberCard.innerHTML = `<div class="section-head"><div><h2>Hantera familjemedlemmar</h2><p class="admin-muted">Ändra roller eller ta bort medlemmar från familjen.</p></div><span class="level-chip">${data.members.length} MEDLEMMAR</span></div><div class="family-member-list">${data.members.map((member) => `<div class="family-member-admin-row" data-family-user="${escHtml(member.user_id)}"><div class="family-member-admin-name"><b>${escHtml(member.display_name)}</b>${member.user_id === data.member.user_id ? '<small>Du</small>' : ''}</div><select data-member-role aria-label="Roll för ${escHtml(member.display_name)}"><option value="player" ${member.role === 'player' ? 'selected' : ''} ${member.role === 'admin' && adminCount <= 1 ? 'disabled' : ''}>Spelare</option><option value="admin" ${member.role === 'admin' ? 'selected' : ''}>Administratör</option></select><button class="filter-tab" type="button" data-save-member-role>Spara roll</button><button class="filter-tab admin-remove" type="button" data-remove-family-member ${(member.user_id === data.member.user_id || (member.role === 'admin' && adminCount <= 1)) ? 'disabled' : ''}>Ta bort</button></div>`).join('')}</div>`;
      memberCard.dataset.signature = memberSignature;
      if (!existingMemberCard) form.closest('.admin-section')?.before(memberCard);
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
    let nextWeekCard = document.getElementById('admin-next-week-card');
    const memberNames = new Map(data.members.map((member) => [member.user_id, member.display_name]));
    const nextWeekGroups = [...data.nextWeekChores.reduce((groups, chore) => {
      const key = weeklyGroupKey(chore);
      if (!groups.has(key)) groups.set(key, { key, title: baseWeeklyTitle(chore.title), occurrences: [] });
      groups.get(key).occurrences.push(chore);
      return groups;
    }, new Map()).values()];
    const nextWeekSignature = `${data.members.map((member) => `${member.user_id}:${member.display_name}`).join('|')}|${data.nextPlan?.week_start || 'saknas'}:${data.nextPlan?.status || 'saknas'}|${data.nextWeekChores.map((chore) => `${chore.id}:${chore.title}:${chore.created_at}:${chore.created_by}:${chore.description}:${chore.xp_reward}:${chore.token_reward}:${chore.difficulty}:${(chore.chore_assignments || []).map((assignment) => `${assignment.user_id}:${assignment.scheduled_for || ''}`).sort().join(',')}:${(chore.quest_submissions || []).map((submission) => `${submission.id}:${submission.status}`).sort().join(',')}`).join('|')}`;
    const nextPlanLabel = data.nextPlan?.week_start
      ? new Intl.DateTimeFormat('sv-SE', { day: 'numeric', month: 'long' }).format(new Date(`${data.nextPlan.week_start}T12:00:00`))
      : 'nästa vecka';
    if (!nextWeekCard || nextWeekCard.dataset.memberSignature !== nextWeekSignature) {
      nextWeekCard = nextWeekCard || document.createElement('section');
      nextWeekCard.id = 'admin-next-week-card';
      nextWeekCard.className = 'card admin-section admin-next-week-card';
      const days = ['Måndag','Tisdag','Onsdag','Torsdag','Fredag','Lördag','Söndag'];
      const memberOptions = data.members.map((member) => `<option value="${escHtml(member.user_id)}">${escHtml(member.display_name)}</option>`).join('');
      const plannedGroupsHtml = nextWeekGroups.map((group) => {
        const occurrences = group.occurrences;
        const sample = occurrences[0];
        const isDaySchedule = occurrences.some((item) => (item.chore_assignments || []).some((assignment) => assignment.scheduled_for)
          || /\s·\s(?:måndag|tisdag|onsdag|torsdag|fredag|lördag|söndag)$/i.test(item.title));
        const scheduleSummary = isDaySchedule
          ? occurrences.map((item) => {
            const assignment = (item.chore_assignments || [])[0];
            const dateDay = assignment?.scheduled_for ? (new Date(`${assignment.scheduled_for}T12:00:00Z`).getUTCDay() + 6) % 7 : weekdayNames.findIndex((day) => item.title.toLocaleLowerCase('sv-SE').endsWith(`· ${day}`));
            const dayLabel = dateDay >= 0 ? weekdayNames[dateDay].slice(0, 3) : 'dag';
            return `${dayLabel} · ${memberNames.get(assignment?.user_id) || 'Ingen ansvarig'}`;
          }).join('  ·  ')
          : `${occurrences.length} ${occurrences.length === 1 ? 'tillfälle' : 'tillfällen'} · ${[...new Set(occurrences.flatMap((item) => (item.chore_assignments || []).map((assignment) => memberNames.get(assignment.user_id)).filter(Boolean)))].join(', ') || 'Ingen tilldelad'}`;
        const hasSubmission = occurrences.some((item) => (item.quest_submissions || []).length > 0);
        const hasApproved = occurrences.some((item) => (item.quest_submissions || []).some((submission) => submission.status === 'approved'));
        return `<div class="admin-list-row planned-chore-group"><div class="admin-list-copy"><b>${escHtml(group.title)}</b><small class="planned-chore-schedule">${escHtml(scheduleSummary)}</small><small>${occurrences.length} tillfällen · ${escHtml(sample.difficulty || 'Lätt')} · ${sample.xp_reward} XP · ${sample.token_reward} mynt${hasSubmission ? ' · Inskickad och låst för redigering' : ''}</small></div><div class="planned-chore-group-actions"><button class="filter-tab" type="button" data-edit-weekly-group="${escHtml(occurrences[0].id)}" ${hasSubmission || data.nextPlan?.status !== 'open' ? 'disabled title="En inskickad syssla kan inte redigeras."' : ''}>Redigera</button><button class="filter-tab admin-remove" type="button" data-delete-weekly-group="${escHtml(occurrences[0].id)}" ${hasApproved || data.nextPlan?.status !== 'open' ? 'disabled title="En godkänd syssla kan inte tas bort."' : ''}>Ta bort</button></div></div>`;
      }).join('');

      nextWeekCard.innerHTML = `<div class="section-head"><div><h2>Planera nästa vecka</h2><p class="admin-muted">Välj om sysslan görs tillsammans eller skapa ett schema med en ansvarig person per dag. Veckan börjar ${escHtml(nextPlanLabel)}.</p></div><span class="level-chip">${data.nextPlan?.status === 'closed' ? 'STÄNGD' : 'NÄSTA VECKA'}</span></div><form id="admin-next-week-quest" class="admin-quest-form next-week-quest-form"><label>Sysslans namn<input name="title" required maxlength="85" placeholder="Till exempel: Töm diskmaskinen"></label><label>Beskrivning<input name="detail" maxlength="90" placeholder="Påminnelse eller instruktion"></label><label>XP per tillfälle<input name="xp" type="number" min="0" max="500" value="30" readonly required></label><label>Mynt per tillfälle<input name="tokens" type="number" min="0" max="100" value="15" readonly required></label><label>Svårighetsgrad<select name="difficulty"><option value="Lätt" selected>Lätt</option><option value="Mellan">Mellan</option><option value="Svår">Svår</option></select></label><fieldset class="next-week-assignees" data-count-assignees><legend>Gör sysslan tillsammans</legend><p class="schedule-help">Alla valda personer får samma uppgift och kan samarbeta.</p>${data.members.map((member) => `<label><input type="checkbox" name="assignees" value="${escHtml(member.user_id)}" checked> ${escHtml(member.display_name)}</label>`).join('')}</fieldset><fieldset class="next-week-schedule"><legend>Hur ska sysslan fördelas?</legend><label><input type="radio" name="scheduleMode" value="count" checked> Gemensam syssla · antal gånger</label><label><input type="radio" name="scheduleMode" value="days"> En ansvarig per veckodag</label><label class="frequency-choice" data-frequency-choice>Antal tillfällen<select name="frequency">${Array.from({length:7},(_,index)=>`<option value="${index+1}">${index+1} ${index===0?'gång':'gånger'} i veckan</option>`).join('')}</select></label><div class="weekday-assignment-list" data-weekday-choice hidden><p class="schedule-help">Välj dag och ansvarig. Du kan fördela till exempel sex dagar jämnt mellan tre personer.</p>${days.map((day,index)=>`<div class="weekday-assignment" data-weekday-row><label class="weekday-assignment-day"><input type="checkbox" name="weekdays" value="${index+1}"><b>${day}</b></label><select name="weekdayAssignee" aria-label="Ansvarig för ${day}" disabled>${memberOptions}</select></div>`).join('')}<output class="weekday-assignment-summary" data-schedule-summary>Välj vilka dagar sysslan ska göras.</output></div></fieldset><button class="primary-button" type="submit" ${data.nextPlan?.status === 'closed' ? 'disabled' : ''}>+ Lägg till nästa vecka</button></form><div class="admin-list-row next-week-list-heading"><b>Planerade sysslor</b><span>${nextWeekGroups.length} sysslor · ${data.nextWeekChores.length} tillfällen</span></div><div class="admin-next-week-list">${plannedGroupsHtml || '<p class="admin-muted">Inga sysslor planerade ännu.</p>'}</div>`;
      nextWeekCard.dataset.memberSignature = nextWeekSignature;
      document.getElementById('weekly-plan-card')?.after(nextWeekCard);
    }
    let choreManager = document.getElementById('admin-weekly-chores');
    if (!choreManager) { choreManager = document.createElement('section'); choreManager.id = 'admin-weekly-chores'; choreManager.className = 'card admin-section admin-weekly-chores'; }
    const weeklyChoreMarkup = data.weeklyChores.map((chore) => {
      const assignees = (chore.chore_assignments || []).map((assignment) => memberNames.get(assignment.user_id)).filter(Boolean);
      const completed = (chore.quest_submissions || []).some((submission) => submission.status === 'approved');
      return `<div class="admin-list-row"><div class="admin-list-copy"><b>${escHtml(chore.title)}</b><small>${escHtml(assignees.join(', ') || 'Ingen tilldelad')} · ${escHtml(chore.difficulty || 'Lätt')} · ${chore.xp_reward} XP · ${chore.token_reward} mynt</small></div><button class="filter-tab" type="button" data-edit-current-weekly-chore="${escHtml(chore.id)}" ${chore.quest_submissions?.length || data.plan?.status !== 'open' ? 'disabled title="Uppgiften har redan skickats in eller veckan är stängd."' : ''}>Redigera</button><button class="filter-tab admin-remove" type="button" data-delete-weekly-chore="${escHtml(chore.id)}" ${completed ? 'disabled title="En redan godkänd uppgift kan inte tas bort."' : ''}>Ta bort</button></div>`;
    }).join('');
    const managerMarkup = `<div class="section-head"><div><h2>Denna vecka</h2><p class="admin-muted">Redigera eller ta bort veckans uppgifter. Redigering låses när någon har skickat in uppgiften.</p></div><span class="level-chip">${data.weeklyChores.length} SYSSLOR</span></div>${weeklyChoreMarkup || '<p class="admin-muted">Inga aktiva veckosysslor att hantera.</p>'}`;
    if (choreManager.innerHTML !== managerMarkup) choreManager.innerHTML = managerMarkup;
    if (!choreManager.isConnected) document.getElementById('weekly-plan-card')?.after(choreManager);
    let creatureManager = document.getElementById('admin-family-creatures');
    if (!creatureManager) { creatureManager = document.createElement('section'); creatureManager.id = 'admin-family-creatures'; creatureManager.className = 'card admin-section admin-family-creatures'; }
    const creatureMarkup = `<div class="section-head"><div><h2>Hantera familjens varelser</h2><p class="admin-muted">Ta bort valfri varelse, även en förbannelsevarelse, från en familjemedlems samling.</p></div><span class="level-chip">${data.familyCreatures.length} VARELSER</span></div>${data.familyCreatures.map((creature) => `<div class="admin-list-row"><div class="admin-list-copy"><b>${escHtml(creature.creature_name)} · Nivå ${creature.level}</b><small>${escHtml(creature.display_name)} · ${escHtml(creature.rarity)}${creature.is_cursed ? ' · Förbannelsevarelse' : ''}</small></div><button class="filter-tab admin-remove" type="button" data-remove-family-creature="${escHtml(creature.id)}">Ta bort</button></div>`).join('') || '<p class="admin-muted">Inga varelser finns i familjens samlingar.</p>'}`;
    if (creatureManager.innerHTML !== creatureMarkup) creatureManager.innerHTML = creatureMarkup;
    if (!creatureManager.isConnected) choreManager.after(creatureManager);
    if (creatureManager.nextElementSibling !== nextWeekCard) creatureManager.after(nextWeekCard);
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
    const chestNote = document.querySelector('#view-root .shop-card>p:last-child');
    const syncedChestNote = 'Mynt, kistor och varelser sparas i familjens gemensamma samling.';
    if (chestNote && chestNote.textContent !== syncedChestNote) chestNote.textContent = syncedChestNote;
    const shopCard = document.querySelector('#view-root .shop-card');
    if (shopCard) {
      const credits = data.chestCredits.filter((credit) => !credit.redeemed_at);
      let creditShelf = document.getElementById('creature-chest-credits');
      if (credits.length) {
        if (!creditShelf) { creditShelf = document.createElement('div'); creditShelf.id = 'creature-chest-credits'; creditShelf.className = 'creature-chest-credits'; shopCard.insertBefore(creditShelf, shopCard.querySelector('.chest-row')); }
        const markup = `<b>Dina fria kistor</b><div>${credits.map((credit) => { const chestName = ({ wooden: 'Träkista', silver: 'Silverkista', gold: 'Guldkista', diamond: 'Diamantkista' })[credit.chest_type] || 'Träkista'; return `<button type="button" class="buy-button" data-chest="${chestName}" data-chest-credit="${escHtml(credit.id)}">Öppna gratis ${chestName.toLowerCase()}</button>`; }).join('')}</div>`;
        if (creditShelf.innerHTML !== markup) creditShelf.innerHTML = markup;
      } else creditShelf?.remove();
      let challengeShelf = document.getElementById('family-challenges-live');
      if (data.familyChallenges.length) {
        if (!challengeShelf) { challengeShelf = document.createElement('section'); challengeShelf.id = 'family-challenges-live'; challengeShelf.className = 'family-challenges-live'; shopCard.after(challengeShelf); }
        const markup = `<div class="section-head"><h2>Familjens utmaningar</h2><span class="level-chip">${data.familyChallenges.filter((item) => item.status === 'active').length} AKTIVA</span></div>${data.familyChallenges.map((item) => `<div class="family-challenge-row"><div><b>${escHtml(item.title)}</b><small>${item.status === 'complete' ? 'Klar!' : `Avslutas ${new Intl.DateTimeFormat('sv-SE',{dateStyle:'medium'}).format(new Date(item.ends_at))}`}</small></div><span>${item.progress}/${item.goal}</span><div class="progress"><span style="width:${Math.min(100,Math.round(item.progress/item.goal*100))}%"></span></div></div>`).join('')}`;
        if (challengeShelf.innerHTML !== markup) challengeShelf.innerHTML = markup;
      } else challengeShelf?.remove();
    }
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
    const xpPerLevel = 1000;
    const totalXp = Math.max(0, Number(data.member.xp) || 0);
    const level = Math.floor(totalXp / xpPerLevel) + 1;
    const levelXp = totalXp % xpPerLevel;
    for (const card of document.querySelectorAll('.profile-card, .right-col .player-card')) {
      const chip = card.querySelector('.level-chip');
      const label = card.querySelector('.xp-label b');
      const bar = card.querySelector('.progress span');
      const levelText = card.classList.contains('profile-card') ? `NIVÅ ${level} · ÄVENTYRARE` : `NIVÅ ${level}`;
      const progressText = `${levelXp} / ${xpPerLevel} XP`;
      if (chip && chip.textContent !== levelText) chip.textContent = levelText;
      if (label && label.textContent !== progressText) label.textContent = progressText;
      if (bar) bar.style.width = `${levelXp / xpPerLevel * 100}%`;
    }
    const playerCard = document.querySelector('.right-col .player-card');
    if (playerCard) {
      const playerName = playerCard.querySelector('.player-meta b');
      if (playerName && playerName.textContent !== name) playerName.textContent = name;
      const rank = [...data.members].sort((a, b) => b.xp - a.xp).findIndex((member) => member.user_id === data.member.user_id) + 1;
      const rankText = playerCard.querySelector('.player-foot b');
      if (rankText && rankText.textContent !== `#${rank} av ${data.members.length}`) rankText.textContent = `#${rank} av ${data.members.length}`;
      const rankLabel = playerCard.querySelector('.player-foot span');
      if (rankLabel && rankLabel.textContent !== `👥 Familjerank · ${name}`) rankLabel.textContent = `👥 Familjerank · ${name}`;

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
    const activityCard = document.querySelector('#view-root .activity-card');
    if (activityCard) {
      const recent = [...data.submissions].sort((a, b) => Date.parse(b.submitted_at) - Date.parse(a.submitted_at)).slice(0, 4);
      const activityMarkup = `<div class="section-head"><h2>Senaste nytt</h2><span>${recent.length ? 'Familjen' : ''}</span></div>${recent.map((submission) => {
        const member = data.members.find((item) => item.user_id === submission.user_id);
        const person = member?.display_name || 'Familjemedlem';
        const title = submission.chores?.title || 'Uppdrag';
        const status = submission.status === 'approved' ? 'klarade uppdraget' : submission.status === 'rejected' ? 'behöver försöka igen med' : 'skickade in';
        const detail = submission.status === 'approved' ? `Godkänd · +${Number(submission.xp_reward) || 0} XP` : submission.status === 'rejected' ? 'Nekad · kan skickas in igen' : 'Väntar på godkännande';
        const face = submission.status === 'approved' ? '✓' : submission.status === 'rejected' ? '↻' : '◷';
        return `<div class="activity-line"><div class="activity-face" aria-hidden="true">${face}</div><div class="activity-text"><b>${escHtml(person)}</b> ${status} ${escHtml(title)}<small>${detail}</small></div></div>`;
      }).join('') || '<p class="empty-note">Här visas familjens senaste godkännanden och inlämnade uppgifter.</p>'}`;
      if (activityCard.dataset.remoteMarkup !== activityMarkup) { activityCard.dataset.remoteMarkup = activityMarkup; activityCard.innerHTML = activityMarkup; }
    }
    const homeProgress = document.querySelector('.left-col .family-card');
    if (homeProgress) {
      const completed = data.weekProgress?.completed || 0;
      const assigned = data.weekProgress?.assigned || 0;
      const percent = assigned ? Math.round(completed / assigned * 100) : 0;
      const summary = homeProgress.querySelector('.family-progress-summary');
      const summaryMarkup = assigned ? `<b>${completed} av ${assigned}</b> sysslor godkända den här veckan` : 'Inga sysslor tilldelade ännu.';
      if (summary && summary.innerHTML !== summaryMarkup) summary.innerHTML = summaryMarkup;
      const bar = homeProgress.querySelector('.progress span');
      if (bar) bar.style.width = `${percent}%`;
    }
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
      actions.innerHTML = `<div class="section-head"><div><h2>Familjeinställningar</h2><p>Lämna familjen eller hantera hela familjens äventyr.</p></div></div><div class="family-settings-actions"><button type="button" class="filter-tab family-leave-button" data-leave-family >Lämna familjen</button>${data.member.role === 'admin' ? '<button type="button" class="filter-tab family-delete-button" data-delete-family>Radera familjen</button>' : ''}</div>`;
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
  }
  const viewObserver = new MutationObserver(() => { if (window.demoSandbox.active) { decorateDemoAdmin(document.getElementById('admin-create-quest')); decorateDemoQuests(); return; } decorateLiveUi(); decorateAdminForm(); });
  viewObserver.observe(document.getElementById('view-root'), { childList: true });
  async function refresh() {
    if (window.demoSandbox.active) return;
    try { await loadFamilyData(); window.renderGame?.(); decorateAdminForm(); }
    catch (error) { errorMessage(error); }
  }
  function startDemoMode() {
    if (data.member?.role !== 'admin') return;
    window.demoSandbox.snapshot = window.gameState;
    window.demoSandbox.active = true;
    const liveOffers = (data.choreBankItems || []).filter((item) => item.is_active && !item.claimed_at).map((item) => ({ ...item, required_people: 1, cooldown_days: 7, reserved_by: [] }));
    window.demoSandbox.bankItems = liveOffers.length ? JSON.parse(JSON.stringify(liveOffers)) : [
      { id: 'demo-bank-dish', title: 'Plocka ur diskmaskinen', description: 'Ställ tillbaka den rena disken.', difficulty: 'Lätt', xp_reward: 20, token_reward: 8, is_active: true },
      { id: 'demo-bank-plants', title: 'Vattna växterna', description: 'Ge familjens växter lite omsorg.', difficulty: 'Mellan', xp_reward: 35, token_reward: 15, is_active: true },
      { id: 'demo-bank-room', title: 'Gör fint i hallen', description: 'Ställ skor på plats och häng upp jackor.', difficulty: 'Svår', xp_reward: 50, token_reward: 25, is_active: true }
    ];
    window.demoSandbox.weeklyChores = (data.weeklyChores || []).map((chore) => ({ id: chore.id, title: chore.title, detail: chore.description || '', xp: Number(chore.xp_reward)||0, tokens: Number(chore.token_reward)||0, difficulty: chore.difficulty || 'Lätt', assignedTo: (chore.chore_assignments || []).map((assignment) => data.members.find((member) => member.user_id === assignment.user_id)?.display_name).filter(Boolean).join(', ') }));
    data.choreBankItems = JSON.parse(JSON.stringify(window.demoSandbox.bankItems));
    window.beginLocalDemo?.();
    decorateDemoAdmin(document.getElementById('admin-create-quest'));
    decorateDemoQuests();
    document.body.classList.add('demo-mode');
    const banner = document.createElement('div');
    banner.id = 'demo-mode-banner'; banner.className = 'demo-mode-banner';
    banner.innerHTML = '<span><b>DEMOLÄGE</b><small>Isolerad kopia · obegränsat med mynt · ändringar sparas inte på familjekontot</small></span><button type="button" data-demo-exit>Avsluta demo</button>';
    document.querySelector('#view-root')?.before(banner);
    window.showToast?.('Demoläget är igång. Familjekontot påverkas inte.');
  }
  async function stopDemoMode() {
    if (!window.demoSandbox.active) return;
    const snapshot = window.demoSandbox.snapshot;
    window.demoSandbox.active = false;
    window.demoSandbox.snapshot = null;
    window.demoSandbox.workingState = null;
    document.body.classList.remove('demo-mode');
    document.getElementById('demo-mode-banner')?.remove();
    window.restoreLocalDemo?.(snapshot);
    await refresh();
    window.showToast?.('Demoläget avslutades. Familjens riktiga data är återställd.');
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
  async function loadNotifications(familyId, userId) {
    return (await call(client.from('notifications').select('*').eq('family_id', familyId).eq('user_id', userId).order('created_at', { ascending: false }).limit(20))).map((n) => ({ message: n.message, createdAt: new Date(n.created_at).getTime() }));
  }
  document.addEventListener('submit', (event) => { onAuthSubmit(event); onFamilySubmit(event); }, true);
  document.addEventListener('click', async (event) => {
    const demoStart = event.target.closest('[data-demo-start]');
    if (demoStart) { event.preventDefault(); event.stopImmediatePropagation(); startDemoMode(); return; }
    const demoExit = event.target.closest('[data-demo-exit]');
    if (demoExit && window.demoSandbox.active) { event.preventDefault(); event.stopImmediatePropagation(); await stopDemoMode(); return; }
    if (window.demoSandbox.active) {
      const demoState = window.gameState;
      const reserveButton = event.target.closest('[data-demo-bank-reserve]');
      if (reserveButton && demoState) {
        event.preventDefault(); event.stopImmediatePropagation();
        const item = (demoState.demoBankItems || []).find((entry) => String(entry.id) === reserveButton.dataset.demoBankReserve);
        const userId = reserveButton.dataset.demoBankUser;
        if (!item || !userId || (item.cooldown_until && new Date(item.cooldown_until).getTime() > Date.now())) return;
        item.reserved_by = Array.isArray(item.reserved_by) ? item.reserved_by : [];
        if (item.reserved_by.includes(userId)) return;
        item.reserved_by.push(userId);
        const required = Math.max(1, Number(item.required_people) || 1);
        if (item.reserved_by.length >= required) {
          const participants = item.reserved_by.slice(0, required);
          participants.forEach((participantId) => {
            const member = data.members.find((entry) => entry.user_id === participantId);
            demoState.customQuests.push({ id: `demo-bank-task-${item.id}-${participantId}-${Date.now()}`, title: item.title, detail: item.description || 'Extra syssla', icon: 'dish', color: 'green', difficulty: item.difficulty || 'Lätt', xp: Number(item.xp_reward) || 0, tokens: Number(item.token_reward) || 0, demoBankId: item.id, assignedTo: member?.display_name || 'Familjemedlem' });
          });
          item.cooldown_until = new Date(Date.now() + Math.max(1, Number(item.cooldown_days) || 7) * 86400000).toISOString();
          item.reserved_by = [];
          window.showToast?.('Alla platser fylldes. Sysslan delades ut och banken vilar nu.');
        } else window.showToast?.(`${item.reserved_by.length}/${required} personer har reserverat sysslan.`);
        window.demoSandbox.workingState = demoState; window.renderGame?.(); return;
      }
      const editDemoWeekly = event.target.closest('[data-edit-demo-weekly]');
      if (editDemoWeekly && demoState) {
        event.preventDefault(); event.stopImmediatePropagation();
        const chore = [...(demoState.demoWeeklyChores || []), ...(demoState.customQuests || [])].find((entry) => String(entry.id) === editDemoWeekly.dataset.editDemoWeekly);
        if (!chore) return;
        window.openModal?.(`<div class="planned-chore-edit"><button class="modal-close" data-close aria-label="Stäng">×</button><div class="eyebrow">DEMOLÄGE · DENNA VECKA</div><h2>Redigera uppgift</h2><p>Ändringarna påverkar bara den tillfälliga demoläget.</p><form id="demo-edit-weekly"><input type="hidden" name="id" value="${escHtml(chore.id)}"><label>Uppgiftens namn<input name="title" maxlength="85" required value="${escHtml(chore.title)}"></label><label>Beskrivning<textarea name="description" maxlength="300" rows="3">${escHtml(chore.detail || '')}</textarea></label><div class="planned-chore-rewards"><label>XP<input name="xp" type="number" min="0" max="500" required value="${Number(chore.xp)||0}"></label><label>Mynt<input name="tokens" type="number" min="0" max="100" required value="${Number(chore.tokens)||0}"></label></div><label>Svårighetsgrad<select name="difficulty"><option ${chore.difficulty==='Lätt'?'selected':''}>Lätt</option><option ${chore.difficulty==='Mellan'?'selected':''}>Mellan</option><option ${chore.difficulty==='Svår'?'selected':''}>Svår</option></select></label><button class="primary-button" type="submit">Spara ändringar</button></form></div>`);
        return;
      }
      const editDemoBank = event.target.closest('[data-demo-edit-bank]');
      if (editDemoBank && demoState) {
        event.preventDefault(); event.stopImmediatePropagation();
        const item = (demoState.demoBankItems || []).find((entry) => String(entry.id) === editDemoBank.dataset.demoEditBank);
        if (!item) return;
        window.openModal?.(`<div class="planned-chore-edit"><button class="modal-close" data-close aria-label="Stäng">×</button><div class="eyebrow">DEMOLÄGE · SYSSELBANKEN</div><h2>Redigera banksyssla</h2><form id="demo-edit-bank-item"><input type="hidden" name="id" value="${escHtml(item.id)}"><label>Sysslans namn<input name="title" maxlength="85" required value="${escHtml(item.title)}"></label><label>Beskrivning<textarea name="description" maxlength="300" rows="3">${escHtml(item.description||'')}</textarea></label><div class="planned-chore-rewards"><label>XP<input name="xp" type="number" min="0" max="500" required value="${Number(item.xp_reward)||0}"></label><label>Mynt<input name="tokens" type="number" min="0" max="100" required value="${Number(item.token_reward)||0}"></label></div><label>Svårighetsgrad<select name="difficulty"><option ${item.difficulty==='Lätt'?'selected':''}>Lätt</option><option ${item.difficulty==='Mellan'?'selected':''}>Mellan</option><option ${item.difficulty==='Svår'?'selected':''}>Svår</option></select></label><label>Personer som behövs<input name="requiredPeople" type="number" min="1" max="8" required value="${Number(item.required_people)||1}"></label><label>Vila efter slutförd (dagar)<input name="cooldownDays" type="number" min="1" max="90" required value="${Number(item.cooldown_days)||7}"></label><button class="primary-button" type="submit">Spara ändringar</button></form></div>`);
        return;
      }
      const deleteDemoBank = event.target.closest('[data-demo-delete-bank]');
      if (deleteDemoBank && demoState) {
        event.preventDefault(); event.stopImmediatePropagation();
        if (!window.confirm('Ta bort sysslan från demolägets Sysselbank?')) return;
        demoState.demoBankItems = (demoState.demoBankItems || []).filter((entry) => String(entry.id) !== deleteDemoBank.dataset.demoDeleteBank);
        window.demoSandbox.workingState = demoState; window.renderGame?.(); return;
      }
      return;
    }
    const editBankChore = event.target.closest('[data-edit-bank-chore]');
    if (editBankChore && data.member?.role === 'admin') {
      const item = data.choreBankItems.find((row) => row.id === editBankChore.dataset.editBankChore);
      if (!item) return;
      event.preventDefault(); event.stopImmediatePropagation();
      window.openModal?.(`<div class="planned-chore-edit bank-chore-edit"><button class="modal-close" data-close aria-label="Stäng">×</button><div class="eyebrow">SYSSELBANKEN</div><h2>Redigera syssla</h2><p>Ändringarna gäller nästa gång sysslan delas ut.</p><form id="admin-edit-bank-chore"><input type="hidden" name="itemId" value="${escHtml(item.id)}"><label>Sysslans namn<input name="title" maxlength="85" required value="${escHtml(item.title)}"></label><label>Beskrivning<textarea name="description" maxlength="300" rows="3">${escHtml(item.description || '')}</textarea></label><div class="planned-chore-rewards"><label>XP<input name="xp" type="number" min="0" max="500" required value="${item.xp_reward}"></label><label>Mynt<input name="tokens" type="number" min="0" max="100" required value="${item.token_reward}"></label></div><label>Svårighetsgrad<select name="difficulty"><option value="Lätt" ${item.difficulty === 'Lätt' ? 'selected' : ''}>Lätt</option><option value="Mellan" ${item.difficulty === 'Mellan' ? 'selected' : ''}>Mellan</option><option value="Svår" ${item.difficulty === 'Svår' ? 'selected' : ''}>Svår</option></select></label><label>Personer som behövs<input name="requiredPeople" type="number" min="1" max="${data.members.length}" required value="${item.required_people || 1}"></label><label>Vila efter utdelning (dagar)<input name="cooldownDays" type="number" min="0" max="365" required value="${item.cooldown_days ?? 7}"><small>0 dagar betyder direkt tillgänglig igen.</small></label><button class="primary-button" type="submit">Spara ändringar</button></form></div>`);
      return;
    }
    const deleteBankChore = event.target.closest('[data-delete-bank-chore]');
    if (deleteBankChore && data.member?.role === 'admin') {
      event.preventDefault(); event.stopImmediatePropagation();
      const item = data.choreBankItems.find((row) => row.id === deleteBankChore.dataset.deleteBankChore);
      if (!item || !window.confirm(`Ta bort ”${item.title}” från Sysselbanken? Eventuella reservationer tas bort. Uppgifter som redan delats ut påverkas inte.`)) return;
      deleteBankChore.disabled = true;
      try { await call(client.rpc('admin_delete_chore_bank_item', { p_item_id: item.id })); await refresh(); window.showToast?.('Sysslan togs bort från Sysselbanken.'); }
      catch (error) { window.showToast?.(error.message || 'Sysslan kunde inte tas bort.'); deleteBankChore.disabled = false; }
      return;
    }
    const claimBankChore = event.target.closest('[data-claim-bank-chore]');
    if (claimBankChore && data.familyId && data.member) {
      event.preventDefault(); event.stopImmediatePropagation();
      claimBankChore.disabled = true;
      try {
        const choreId = await call(client.rpc('claim_chore_bank_item', { p_item_id: claimBankChore.dataset.claimBankChore }));
        await refresh();
        if (choreId) window.showToast?.('Sysslan har delats ut till alla reserverade deltagare.');
        else {
          const item = data.choreBankItems.find((row) => row.id === claimBankChore.dataset.claimBankChore);
          const count = data.choreBankReservations.filter((row) => row.item_id === claimBankChore.dataset.claimBankChore).length;
          window.showToast?.(`Du har reserverat en plats · ${count}/${item?.required_people || 1} personer.`);
        }
      } catch (error) {
        const message = /no open weekly plan/i.test(error.message || '') ? 'Det finns ingen öppen uppdragsvecka just nu.'
          : /already reserved/i.test(error.message || '') ? 'Du har redan reserverat en plats för sysslan.'
          : /cooldown|vilar fortfarande/i.test(error.message || '') ? 'Sysslan vilar och blir snart tillgänglig igen.'
          : /already claimed|not available|all slots/i.test(error.message || '') ? 'Platserna är redan tagna. Uppdatera sidan om en annan spelare just reserverade.'
          : /resolve active curses first/i.test(error.message || '') ? 'Lös först familjens aktiva förbannelseuppgifter.'
          : error.message || 'Extrasysslan kunde inte tilldelas.';
        window.showToast?.(message); claimBankChore.disabled = false;
      }
      return;
    }
    const bell = event.target.closest('.notification-button');
    if (bell && data.member && data.familyId) {
      event.stopImmediatePropagation();
      const familyId = data.familyId;
      const userId = data.member.user_id;
      bell.disabled = true;
      try {
        const notices = await loadNotifications(familyId, userId);
        if (data.familyId === familyId && data.member?.user_id === userId && !window.demoSandbox.active) {
          window.gameState.notifications = notices;
          window.showNotifications();
        }
      } catch {
        window.showToast?.('Aviseringarna kunde inte hämtas. Försök igen.');
      } finally {
        bell.disabled = false;
      }
      return;
    }
    const clearNotifications = event.target.closest('[data-clear-notifications]');
    if (clearNotifications && data.member && data.familyId && !window.demoSandbox.active) {
      event.preventDefault(); event.stopImmediatePropagation(); clearNotifications.disabled = true;
      try {
        await call(client.from('notifications').delete().eq('family_id', data.familyId).eq('user_id', data.member.user_id));
        window.gameState.notifications = [];
        window.showNotifications();
      } catch (error) {
        clearNotifications.disabled = false;
        window.showToast?.('Aviseringarna kunde inte rensas. Kontrollera att den senaste SQL-migreringen är installerad.');
      }
      return;
    }
    const editCurrentChore = event.target.closest('[data-edit-current-weekly-chore]');
    if (editCurrentChore && data.familyId && data.member?.role === 'admin') {
      event.preventDefault(); event.stopImmediatePropagation();
      const chore = data.weeklyChores.find((item) => item.id === editCurrentChore.dataset.editCurrentWeeklyChore);
      if (!chore || !data.plan || data.plan.status !== 'open') return;
      if ((chore.quest_submissions || []).length) { window.showToast?.('Uppgiften har skickats in och kan därför inte redigeras.'); return; }
      const assignments = chore.chore_assignments || [];
      const scheduledFor = assignments.find((item) => item.scheduled_for)?.scheduled_for || '';
      const baseTitle = chore.title.replace(/\s·\s(?:måndag|tisdag|onsdag|torsdag|fredag|lördag|söndag)$/i, '').trim();
      const selectedUsers = new Set(assignments.map((item) => item.user_id));
      const memberFields = data.members.map((member) => `<label><input type="checkbox" name="assignees" value="${escHtml(member.user_id)}" ${selectedUsers.has(member.user_id) ? 'checked' : ''}> ${escHtml(member.display_name)}</label>`).join('');
      const weekdays = ['Måndag','Tisdag','Onsdag','Torsdag','Fredag','Lördag','Söndag'];
      const dayOptions = weekdays.map((day,index) => { const date = new Date(`${data.plan.week_start}T12:00:00Z`); date.setUTCDate(date.getUTCDate()+index); const value = new Intl.DateTimeFormat('sv-SE',{timeZone:'UTC',year:'numeric',month:'2-digit',day:'2-digit'}).format(date); return `<option value="${value}" ${value===scheduledFor?'selected':''}>${day} · ${new Intl.DateTimeFormat('sv-SE',{day:'numeric',month:'short',timeZone:'UTC'}).format(date)}</option>`; }).join('');
      window.openModal?.(`<div class="planned-chore-edit"><button class="modal-close" data-close aria-label="Stäng">×</button><div class="eyebrow">DENNA VECKA</div><h2>Redigera veckouppgift</h2><p>Ändra uppgiftens namn, belöning, ansvariga eller dag.</p><form id="admin-edit-current-weekly-chore"><input type="hidden" name="choreId" value="${escHtml(chore.id)}"><label>Uppgiftens namn<input name="title" maxlength="85" required value="${escHtml(baseTitle)}"></label><label>Beskrivning<textarea name="description" maxlength="300" rows="3">${escHtml(chore.description||'')}</textarea></label><div class="planned-chore-rewards"><label>XP-belöning<input name="xp" type="number" min="0" max="500" required value="${chore.xp_reward}"></label><label>Myntbelöning<input name="tokens" type="number" min="0" max="100" required value="${chore.token_reward}"></label></div><label>Svårighetsgrad<select name="difficulty"><option ${chore.difficulty==='Lätt'?'selected':''}>Lätt</option><option ${chore.difficulty==='Mellan'?'selected':''}>Mellan</option><option ${chore.difficulty==='Svår'?'selected':''}>Svår</option></select></label><label>Planerad dag<select name="scheduledFor"><option value="" ${!scheduledFor?'selected':''}>Ingen särskild dag</option>${dayOptions}</select></label><fieldset class="planned-chore-assignees"><legend>Ansvariga personer</legend>${memberFields}</fieldset><p class="planned-chore-note">Om en viss dag väljs ska exakt en person vara ansvarig. Redigering låses när uppgiften skickats in.</p><button class="primary-button" type="submit">Spara ändringar</button></form></div>`);
      return;
    }
    const editWeeklyGroup = event.target.closest('[data-edit-weekly-group]');
    if (editWeeklyGroup && data.familyId && data.member.role === 'admin') {
      event.preventDefault(); event.stopImmediatePropagation();
      const selectedOccurrence = data.nextWeekChores.find((item) => item.id === editWeeklyGroup.dataset.editWeeklyGroup);
      if (!selectedOccurrence || !data.nextPlan || data.nextPlan.status !== 'open') return;
      const groupKey = weeklyGroupKey(selectedOccurrence);
      const occurrences = data.nextWeekChores.filter((item) => weeklyGroupKey(item) === groupKey);
      if (occurrences.some((item) => (item.quest_submissions || []).length)) { window.showToast?.('Sysslan har redan skickats in och kan därför inte redigeras.'); return; }
      const sample = occurrences[0];
      const byDay = new Map();
      for (const item of occurrences) {
        const assignment = (item.chore_assignments || [])[0];
        let day = assignment?.scheduled_for ? (new Date(`${assignment.scheduled_for}T12:00:00Z`).getUTCDay() + 6) % 7 + 1 : 0;
        if (!day) day = weekdayNames.findIndex((name) => item.title.toLocaleLowerCase('sv-SE').endsWith(`· ${name}`)) + 1;
        if (day > 0) byDay.set(day, assignment?.user_id || data.members[0]?.user_id || '');
      }
      const isDaySchedule = byDay.size > 0;
      const userIds = [...new Set(occurrences.flatMap((item) => (item.chore_assignments || []).map((assignment) => assignment.user_id)))];
      const membersHtml = data.members.map((member) => `<label><input type="checkbox" name="assignees" value="${escHtml(member.user_id)}" ${userIds.includes(member.user_id) ? 'checked' : ''}> ${escHtml(member.display_name)}</label>`).join('');
      const weekdays = ['Måndag','Tisdag','Onsdag','Torsdag','Fredag','Lördag','Söndag'];
      const dayRowsHtml = weekdays.map((day, index) => {
        const number = index + 1;
        const date = new Date(`${data.nextPlan.week_start}T12:00:00Z`);
        date.setUTCDate(date.getUTCDate() + index);
        const dateLabel = new Intl.DateTimeFormat('sv-SE', { day: 'numeric', month: 'short', timeZone: 'UTC' }).format(date);
        const options = data.members.map((member) => `<option value="${escHtml(member.user_id)}" ${byDay.get(number) === member.user_id ? 'selected' : ''}>${escHtml(member.display_name)}</option>`).join('');
        return `<div class="weekday-assignment ${byDay.has(number) ? 'is-selected' : ''}" data-edit-weekday-row><label class="weekday-assignment-day"><input type="checkbox" name="weekdays" value="${number}" ${byDay.has(number) ? 'checked' : ''}><b>${day} · ${dateLabel}</b></label><select name="weekdayAssignee" aria-label="Ansvarig för ${day}" ${byDay.has(number) ? '' : 'disabled'}>${options}</select></div>`;
      }).join('');
      const count = occurrences.length;
      window.openModal?.(`<div class="planned-chore-edit planned-chore-group-edit"><button class="modal-close" data-close aria-label="Stäng">×</button><h2>Redigera planerad syssla</h2><p>Ändringarna gäller hela sysslan och dess ${count} tillfällen.</p><form id="admin-edit-planned-group"><input type="hidden" name="occurrenceIds" value="${escHtml(JSON.stringify(occurrences.map((item) => item.id)))}"><label>Sysslans namn<input name="title" maxlength="85" required value="${escHtml(selectedOccurrence.title.replace(/\s·\s(?:måndag|tisdag|onsdag|torsdag|fredag|lördag|söndag|tillfälle\s+\d+(?:\/\d+)?)$/i, '').trim())}"></label><label>Beskrivning<textarea name="description" maxlength="300" rows="3">${escHtml(sample.description || '')}</textarea></label><div class="planned-chore-rewards"><label>XP per tillfälle<input name="xp" type="number" min="0" max="500" required value="${sample.xp_reward}"></label><label>Mynt per tillfälle<input name="tokens" type="number" min="0" max="100" required value="${sample.token_reward}"></label></div><label>Svårighetsgrad<select name="difficulty"><option value="Lätt" ${sample.difficulty === 'Lätt' ? 'selected' : ''}>Lätt</option><option value="Mellan" ${sample.difficulty === 'Mellan' ? 'selected' : ''}>Mellan</option><option value="Svår" ${sample.difficulty === 'Svår' ? 'selected' : ''}>Svår</option></select></label><fieldset class="planned-group-mode"><legend>Fördelning</legend><label><input type="radio" name="mode" value="count" ${isDaySchedule ? '' : 'checked'}> Samma ansvariga vid varje tillfälle</label><label><input type="radio" name="mode" value="days" ${isDaySchedule ? 'checked' : ''}> En ansvarig per vald veckodag</label></fieldset><div data-edit-count-controls ${isDaySchedule ? 'hidden' : ''}><label>Antal tillfällen<select name="frequency">${Array.from({length:7}, (_, index) => `<option value="${index + 1}" ${count === index + 1 ? 'selected' : ''}>${index + 1} ${index === 0 ? 'gång' : 'gånger'} i veckan</option>`).join('')}</select></label><fieldset class="planned-chore-assignees"><legend>Ansvariga vid varje tillfälle</legend>${membersHtml}</fieldset></div><div class="weekday-assignment-list planned-group-days" data-edit-day-controls ${isDaySchedule ? '' : 'hidden'}><p class="schedule-help">Välj vilka dagar sysslan ska göras och vem som ansvarar för var och en.</p>${dayRowsHtml}<output class="weekday-assignment-summary">${byDay.size} dagar valda</output></div><button class="primary-button" type="submit">Spara hela sysslan</button></form></div>`);
      return;
    }
    const deleteWeeklyGroup = event.target.closest('[data-delete-weekly-group]');
    if (deleteWeeklyGroup && data.familyId && data.member.role === 'admin') {
      event.preventDefault(); event.stopImmediatePropagation();
      const selectedOccurrence = data.nextWeekChores.find((item) => item.id === deleteWeeklyGroup.dataset.deleteWeeklyGroup);
      if (!selectedOccurrence) return;
      const occurrences = data.nextWeekChores.filter((item) => weeklyGroupKey(item) === weeklyGroupKey(selectedOccurrence));
      if (!window.confirm(`Ta bort hela sysslan ”${baseWeeklyTitle(selectedOccurrence.title)}” med ${occurrences.length} tillfällen?`)) return;
      deleteWeeklyGroup.disabled = true;
      try {
        await call(client.rpc('admin_delete_planned_weekly_chore_group', { p_occurrence_ids: occurrences.map((item) => item.id) }));
        await refresh(); window.showToast?.('Hela den planerade sysslan har tagits bort.');
      } catch (error) { deleteWeeklyGroup.disabled = false; window.showToast?.(error.message); }
      return;
    }
    const editPlannedChore = event.target.closest('[data-edit-weekly-chore]');
    if (editPlannedChore && data.familyId && data.member.role === 'admin') {
      event.preventDefault(); event.stopImmediatePropagation();
      const chore = data.nextWeekChores.find((item) => item.id === editPlannedChore.dataset.editWeeklyChore);
      if (!chore || !data.nextPlan || data.nextPlan.status !== 'open') return;
      const assignments = chore.chore_assignments || [];
      const scheduledFor = assignments.find((item) => item.scheduled_for)?.scheduled_for || '';
      const baseTitle = chore.title.replace(/\s·\s(?:måndag|tisdag|onsdag|torsdag|fredag|lördag|söndag)$/i, '');
      const selectedUsers = new Set(assignments.map((item) => item.user_id));
      const memberFields = data.members.map((member) => `<label><input type="checkbox" name="assignees" value="${escHtml(member.user_id)}" ${selectedUsers.has(member.user_id) ? 'checked' : ''}> ${escHtml(member.display_name)}</label>`).join('');
      const weekdays = ['Måndag','Tisdag','Onsdag','Torsdag','Fredag','Lördag','Söndag'];
      const dayOptions = weekdays.map((day,index) => { const date = new Date(`${data.nextPlan.week_start}T12:00:00`); date.setDate(date.getDate()+index); const value = new Intl.DateTimeFormat('sv-SE',{timeZone:'Europe/Stockholm'}).format(date); return `<option value="${value}" ${value===scheduledFor?'selected':''}>${day} · ${new Intl.DateTimeFormat('sv-SE',{day:'numeric',month:'short'}).format(date)}</option>`; }).join('');
      window.openModal?.(`<div class="planned-chore-edit"><button class="modal-close" data-close aria-label="Stäng">×</button><div class="eyebrow">NÄSTA VECKA</div><h2>Redigera syssla</h2><p>Ändra detaljer, ansvariga eller vilken dag sysslan ska göras.</p><form id="admin-edit-planned-chore"><input type="hidden" name="choreId" value="${escHtml(chore.id)}"><label>Sysslans namn<input name="title" maxlength="85" required value="${escHtml(baseTitle)}"></label><label>Beskrivning<textarea name="description" maxlength="300" rows="3">${escHtml(chore.description||'')}</textarea></label><div class="planned-chore-rewards"><label>XP-belöning<input name="xp" type="number" min="0" max="500" required value="${chore.xp_reward}"></label><label>Myntbelöning<input name="tokens" type="number" min="0" max="100" required value="${chore.token_reward}"></label></div><label>Svårighetsgrad<select name="difficulty"><option value="Lätt" ${chore.difficulty==='Lätt'?'selected':''}>Lätt</option><option value="Mellan" ${chore.difficulty==='Mellan'?'selected':''}>Mellan</option><option value="Svår" ${chore.difficulty==='Svår'?'selected':''}>Svår</option></select></label><label>Planerad dag<select name="scheduledFor"><option value="" ${!scheduledFor?'selected':''}>Ingen särskild dag · gemensam syssla</option>${dayOptions}</select></label><fieldset class="planned-chore-assignees"><legend>Ansvariga personer</legend>${memberFields}</fieldset><p class="planned-chore-note">Väljer du en dag behöver exakt en person vara ansvarig. Utan dag kan flera göra sysslan tillsammans.</p><button class="primary-button" type="submit">Spara ändringar</button></form></div>`);
      return;
    }
    const deleteWeeklyChore = event.target.closest('[data-delete-weekly-chore]');
    if (deleteWeeklyChore && data.familyId && data.member.role === 'admin') {
      event.preventDefault(); event.stopImmediatePropagation();
      if (!window.confirm('Ta bort sysslan från veckans uppgifter? Om den väntar på godkännande skickas den tillbaka som nekad.')) return;
      deleteWeeklyChore.disabled = true;
      try { await call(client.rpc('admin_delete_weekly_chore', { p_chore_id: deleteWeeklyChore.dataset.deleteWeeklyChore })); await refresh(); window.showToast?.('Sysslan har tagits bort från veckans uppgifter.'); }
      catch (error) { deleteWeeklyChore.disabled = false; window.showToast?.(error.message); }
      return;
    }
    const removeFamilyCreature = event.target.closest('[data-remove-family-creature]');
    if (removeFamilyCreature && data.familyId && data.member.role === 'admin') {
      event.preventDefault(); event.stopImmediatePropagation();
      const creature = data.familyCreatures.find((item) => item.id === removeFamilyCreature.dataset.removeFamilyCreature);
      if (!creature || !window.confirm(`Ta bort ${creature.creature_name} från ${creature.display_name}s samling?`)) return;
      removeFamilyCreature.disabled = true;
      try {
        await call(client.rpc('admin_remove_family_creature', { p_family_id: data.familyId, p_creature_instance_id: creature.id }));
        await refresh();
        window.showToast?.(`${creature.creature_name} har tagits bort från samlingen.`);
      } catch (error) { removeFamilyCreature.disabled = false; window.showToast?.(error.message); }
      return;
    }
    const abilityButton = event.target.closest('[data-ability]');
    if (abilityButton && data.familyId) {
      event.preventDefault(); event.stopImmediatePropagation();
      openCreatureAbility(abilityButton.dataset.ability);
      return;
    }
    const activateAbility = event.target.closest('[data-use-creature]');
    if (activateAbility && data.familyId) {
      event.preventDefault(); event.stopImmediatePropagation();
      await useCreatureAbility(activateAbility);
      return;
    }
    const abilityDecision = event.target.closest('[data-ability-decision]');
    if (abilityDecision && data.familyId && data.member.role === 'admin') {
      event.preventDefault(); event.stopImmediatePropagation(); abilityDecision.disabled = true;
      try {
        await call(client.rpc('decide_creature_ability_request', { p_request_id: abilityDecision.dataset.abilityRequest, p_decision: abilityDecision.dataset.abilityDecision, p_reason: abilityDecision.closest('.ability-request-row')?.querySelector('[data-ability-reason]')?.value || '' }));
        await refresh(); window.showToast?.('Varelseförfrågan hanterad.');
      } catch (error) { abilityDecision.disabled = false; window.showToast?.(error.message); }
      return;
    }
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
    const chestCredit = event.target.closest('[data-chest-credit]');
    if (chestCredit && data.familyId) {
      event.preventDefault(); event.stopImmediatePropagation();
      await openFamilyChest(chestCredit);
      return;
    }
    const roleSave = event.target.closest('[data-save-member-role]');
    if (roleSave && data.familyId && data.member.role === 'admin') {
      const row = roleSave.closest('[data-family-user]');
      try {
        await call(client.rpc('admin_set_member_role', { p_family_id: data.familyId, p_user_id: row.dataset.familyUser, p_role: row.querySelector('[data-member-role]').value }));
        await refresh();
        window.showToast?.('Familjemedlemmens roll uppdaterades.');
      } catch (error) {
        const message = /admin_set_member_role|schema cache|could not find the function/i.test(error.message || '')
          ? 'Rollhanteringen saknas i databasen. Kör migrationen 20261118_family_management.sql i Supabase.'
          : /only a family admin/i.test(error.message || '')
            ? 'Bara en familjeadmin kan ändra roller.'
            : error.message;
        window.showToast?.(message);
      }
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
    if (window.demoSandbox.active) return;
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
      await openFamilyChest(event.target.closest('[data-chest]'));
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
  document.addEventListener('change', (event) => {
    const groupForm = event.target.closest('#admin-edit-planned-group');
    if (groupForm) {
      const mode = groupForm.querySelector('[name="mode"]:checked')?.value || 'count';
      groupForm.querySelector('[data-edit-count-controls]').hidden = mode !== 'count';
      groupForm.querySelector('[data-edit-day-controls]').hidden = mode !== 'days';
      const row = event.target.closest('[data-edit-weekday-row]');
      if (row && event.target.name === 'weekdays') {
        row.classList.toggle('is-selected', event.target.checked);
        row.querySelector('select').disabled = !event.target.checked;
      }
      const selectedDays = [...groupForm.querySelectorAll('[name="weekdays"]:checked')].length;
      const summary = groupForm.querySelector('.weekday-assignment-summary');
      if (summary) summary.textContent = `${selectedDays} ${selectedDays === 1 ? 'dag' : 'dagar'} valda`;
      return;
    }
    const scheduleForm = event.target.closest('#admin-next-week-quest');
    if (!scheduleForm) return;
    const mode = scheduleForm.querySelector('[name="scheduleMode"]:checked')?.value;
    if (event.target.name === 'scheduleMode') {
      scheduleForm.querySelector('[data-frequency-choice]').hidden = mode !== 'count';
      scheduleForm.querySelector('[data-weekday-choice]').hidden = mode !== 'days';
      scheduleForm.querySelector('[data-count-assignees]').hidden = mode !== 'count';
    }
    if (event.target.name === 'weekdays') {
      const row = event.target.closest('[data-weekday-row]');
      const person = row?.querySelector('[name="weekdayAssignee"]');
      if (person) person.disabled = !event.target.checked;
      row?.classList.toggle('is-selected', event.target.checked);
    }
    if (event.target.name === 'weekdays' || event.target.name === 'weekdayAssignee') {
      const rows = [...scheduleForm.querySelectorAll('[data-weekday-row]')].filter((row) => row.querySelector('[name="weekdays"]').checked);
      const summary = scheduleForm.querySelector('[data-schedule-summary]');
      if (!rows.length) { summary.textContent = 'Välj vilka dagar sysslan ska göras.'; return; }
      const totals = new Map();
      rows.forEach((row) => {
        const person = row.querySelector('[name="weekdayAssignee"]');
        const name = person.selectedOptions[0]?.textContent || 'Familjemedlem';
        totals.set(name, (totals.get(name) || 0) + 1);
      });
      summary.textContent = `${rows.length} dagar · ${[...totals].map(([name,count]) => `${name} ${count}`).join(' · ')}`;
    }
  });
  document.addEventListener('submit', async (event) => {
    if (window.demoSandbox.active) {
      const demoState = window.gameState;
      const formElement = event.target;
      const values = new FormData(formElement);
      if (formElement.id === 'demo-admin-create-bank-item' && demoState) {
        event.preventDefault(); event.stopImmediatePropagation();
        const title = String(values.get('title') || '').trim();
        if (!title) return;
        demoState.demoBankItems = demoState.demoBankItems || [];
        demoState.demoBankItems.unshift({ id: `demo-bank-${Date.now()}`, title, description: String(values.get('description')||'').trim(), difficulty: String(values.get('difficulty')||'Lätt'), xp_reward: Number(values.get('xp'))||0, token_reward: Number(values.get('tokens'))||0, required_people: Math.max(1, Number(values.get('requiredPeople'))||1), cooldown_days: Math.max(1, Number(values.get('cooldownDays'))||7), reserved_by: [], is_active: true });
        window.demoSandbox.workingState = demoState; formElement.reset(); formElement.elements.xp.value = '15'; formElement.elements.tokens.value = '3'; formElement.elements.requiredPeople.value = '1'; formElement.elements.cooldownDays.value = '7'; window.renderGame?.(); window.showToast?.('Sysslan lades till i demolägets Sysselbank.'); return;
      }
      if (formElement.id === 'demo-edit-bank-item' && demoState) {
        event.preventDefault(); event.stopImmediatePropagation();
        const item = (demoState.demoBankItems||[]).find((entry) => String(entry.id) === String(values.get('id')));
        if (!item) return;
        Object.assign(item, { title: String(values.get('title')||'').trim(), description: String(values.get('description')||'').trim(), difficulty: String(values.get('difficulty')||'Lätt'), xp_reward: Number(values.get('xp'))||0, token_reward: Number(values.get('tokens'))||0, required_people: Math.max(1,Number(values.get('requiredPeople'))||1), cooldown_days: Math.max(1,Number(values.get('cooldownDays'))||7) });
        document.getElementById('modal-root').innerHTML = ''; window.demoSandbox.workingState = demoState; window.renderGame?.(); window.showToast?.('Banksysslan uppdaterades i demoläget.'); return;
      }
      if (formElement.id === 'demo-edit-weekly' && demoState) {
        event.preventDefault(); event.stopImmediatePropagation();
        const chore = [...(demoState.demoWeeklyChores||[]), ...(demoState.customQuests||[])].find((entry) => String(entry.id) === String(values.get('id')));
        if (!chore) return;
        Object.assign(chore, { title: String(values.get('title')||'').trim(), detail: String(values.get('description')||'').trim(), xp: Number(values.get('xp'))||0, tokens: Number(values.get('tokens'))||0, difficulty: String(values.get('difficulty')||'Lätt') });
        const localQuest = (demoState.customQuests||[]).find((entry) => String(entry.id) === String(values.get('id')));
        if (localQuest && localQuest !== chore) Object.assign(localQuest, { title: chore.title, detail: chore.detail, xp: chore.xp, tokens: chore.tokens, difficulty: chore.difficulty });
        document.getElementById('modal-root').innerHTML = ''; window.demoSandbox.workingState = demoState; window.renderGame?.(); window.showToast?.('Uppgiften uppdaterades i demoläget.'); return;
      }
      return;
    }
  }, true);
  document.addEventListener('submit', async (event) => {
    if (window.demoSandbox.active) return;
    if (event.target.id === 'admin-edit-bank-chore' && data.familyId) {
      event.preventDefault(); event.stopImmediatePropagation();
      if (data.member.role !== 'admin') return;
      const values = new FormData(event.target);
      const button = event.submitter; if (button) button.disabled = true;
      try {
        await call(client.rpc('admin_update_chore_bank_item', {
          p_item_id: String(values.get('itemId')),
          p_title: String(values.get('title') || '').trim(),
          p_description: String(values.get('description') || '').trim(),
          p_xp: Number(values.get('xp')),
          p_tokens: Number(values.get('tokens')),
          p_difficulty: String(values.get('difficulty') || 'Lätt'),
          p_required_people: Number(values.get('requiredPeople')),
          p_cooldown_days: Number(values.get('cooldownDays'))
        }));
        document.getElementById('modal-root').innerHTML = '';
        await refresh(); window.showToast?.('Sysselbanksuppgiften har uppdaterats.');
      } catch (error) { window.showToast?.(error.message || 'Ändringarna kunde inte sparas.'); }
      finally { if (button) button.disabled = false; }
      return;
    }
    if (event.target.id === 'admin-create-bank-chore' && data.familyId) {
      event.preventDefault(); event.stopImmediatePropagation();
      if (data.member.role !== 'admin') return;
      const values = new FormData(event.target);
      const title = String(values.get('title') || '').trim();
      const description = String(values.get('description') || '').trim();
      const xp = Number(values.get('xp'));
      const tokens = Number(values.get('tokens'));
      const difficulty = String(values.get('difficulty') || 'Lätt');
      const requiredPeople = Number(values.get('requiredPeople'));
      const cooldownDays = Number(values.get('cooldownDays'));
      const button = event.submitter; if (button) button.disabled = true;
      try {
        await call(client.rpc('admin_create_chore_bank_item_configured', { p_family_id: data.familyId, p_title: title, p_description: description, p_xp: xp, p_tokens: tokens, p_difficulty: difficulty, p_required_people: requiredPeople, p_cooldown_days: cooldownDays }));
        event.target.reset(); event.target.elements.xp.value = '30'; event.target.elements.tokens.value = '15';
        await refresh(); window.showToast?.('Extrasysslan lades i Sysselbanken.');
      } catch (error) { window.showToast?.(error.message || 'Extrasysslan kunde inte sparas.'); }
      finally { if (button) button.disabled = false; }
      return;
    }
    if (event.target.id === 'admin-prizes-form' && data.familyId) {
      event.preventDefault(); event.stopImmediatePropagation();
      if (data.member.role !== 'admin') return;
      const values = new FormData(event.target);
      const prizes = Object.fromEntries(['day_prize','week_prize','season_prize'].map(key => [key, String(values.get(key) || '').trim()]));
      const button = event.submitter; if (button) button.disabled = true;
      try {
        await call(client.from('family_ranking_prizes').upsert({ family_id: data.familyId, ...prizes }, { onConflict: 'family_id' }));
        data.prizes = prizes; window.remoteFamily.prizes = prizes;
        window.showToast?.('Rankingpriserna har sparats.');
      } catch (error) { window.showToast?.(error.message || 'Priserna kunde inte sparas.'); }
      finally { if (button) button.disabled = false; }
      return;
    }
    if (event.target.id === 'admin-self-token-form' && data.familyId) {
      event.preventDefault(); event.stopImmediatePropagation();
      if (data.member.role !== 'admin') return;
      const amount = Math.floor(Number(new FormData(event.target).get('amount')));
      if (!Number.isInteger(amount) || amount < 1 || amount > 1000) { window.showToast?.('Ange mellan 1 och 1 000 mynt.'); return; }
      const button = event.submitter; if (button) button.disabled = true;
      try { await call(client.rpc('admin_grant_self_tokens', { p_family_id: data.familyId, p_amount: amount })); await refresh(); window.showToast?.(`${amount} mynt lades till på ditt konto.`); }
      catch (error) { window.showToast?.(error.message); }
      finally { if (button) button.disabled = false; }
      return;
    }
    if (event.target.id === 'admin-edit-current-weekly-chore' && data.familyId) {
      event.preventDefault(); event.stopImmediatePropagation();
      if (data.member.role !== 'admin' || !data.plan || data.plan.status !== 'open') return;
      const form = new FormData(event.target);
      const selected = [...event.target.querySelectorAll('[name="assignees"]:checked')].map((input) => input.value);
      const scheduledFor = String(form.get('scheduledFor') || '') || null;
      if (!selected.length) { window.showToast?.('Välj minst en ansvarig person.'); return; }
      if (scheduledFor && selected.length !== 1) { window.showToast?.('En uppgift med bestämd dag ska ha exakt en ansvarig.'); return; }
      const button = event.submitter; if (button) button.disabled = true;
      try {
        await call(client.rpc('admin_update_current_weekly_chore', {
          p_chore_id: String(form.get('choreId')),
          p_title: String(form.get('title') || '').trim(),
          p_description: String(form.get('description') || '').trim(),
          p_xp: Number(form.get('xp')),
          p_tokens: Number(form.get('tokens')),
          p_difficulty: String(form.get('difficulty') || 'Lätt'),
          p_assignees: selected,
          p_scheduled_for: scheduledFor
        }));
        document.getElementById('modal-root').innerHTML = '';
        await refresh(); window.showToast?.('Veckans uppgift har uppdaterats.');
      } catch (error) {
        const message = /admin_update_current_weekly_chore|schema cache|could not find the function/i.test(error.message || '')
          ? 'Databasuppdateringen för redigering av veckans uppgifter saknas.'
          : error.message;
        window.showToast?.(message);
      } finally { if (button) button.disabled = false; }
      return;
    }
    if (event.target.id === 'admin-edit-planned-group' && data.familyId) {
      event.preventDefault(); event.stopImmediatePropagation();
      if (data.member.role !== 'admin' || !data.nextPlan || data.nextPlan.status !== 'open') return;
      const formElement = event.target;
      const form = new FormData(formElement);
      const mode = String(form.get('mode') || 'count');
      const occurrenceIds = JSON.parse(String(form.get('occurrenceIds') || '[]'));
      const assignees = [...formElement.querySelectorAll('[data-edit-count-controls] [name="assignees"]:checked')].map((input) => input.value);
      const schedule = [...formElement.querySelectorAll('[name="weekdays"]:checked')].map((checkbox) => ({
        day: Number(checkbox.value),
        user_id: checkbox.closest('[data-edit-weekday-row]')?.querySelector('[name="weekdayAssignee"]')?.value
      }));
      if (!occurrenceIds.length) { window.showToast?.('Sysslan kunde inte hittas. Ladda om sidan och försök igen.'); return; }
      if (mode === 'count' && !assignees.length) { window.showToast?.('Välj minst en ansvarig person.'); return; }
      if (mode === 'days' && (!schedule.length || schedule.some((item) => !item.user_id))) { window.showToast?.('Välj minst en dag och en ansvarig person för varje dag.'); return; }
      const button = event.submitter; if (button) button.disabled = true;
      try {
        const result = await call(client.rpc('admin_update_planned_weekly_chore_group', {
          p_occurrence_ids: occurrenceIds,
          p_title: String(form.get('title') || '').trim(),
          p_description: String(form.get('description') || '').trim(),
          p_xp: Number(form.get('xp')),
          p_tokens: Number(form.get('tokens')),
          p_difficulty: String(form.get('difficulty') || 'Lätt'),
          p_mode: mode,
          p_frequency: mode === 'count' ? Number(form.get('frequency')) : null,
          p_assignees: mode === 'count' ? assignees : [],
          p_schedule: mode === 'days' ? schedule : null
        }));
        document.getElementById('modal-root').innerHTML = '';
        await refresh(); window.showToast?.(`Sysslan har uppdaterats med ${result} tillfällen.`);
      } catch (error) {
        const message = /admin_update_planned_weekly_chore_group|schema cache|could not find the function/i.test(error.message || '')
          ? 'Databasuppdateringen för samlad redigering av planerade sysslor saknas.'
          : error.message;
        window.showToast?.(message);
      } finally { if (button) button.disabled = false; }
      return;
    }
    if (event.target.id === 'admin-edit-planned-chore' && data.familyId) {
      event.preventDefault(); event.stopImmediatePropagation();
      if (data.member.role !== 'admin' || !data.nextPlan || data.nextPlan.status !== 'open') return;
      const form = new FormData(event.target);
      const selected = [...event.target.querySelectorAll('[name="assignees"]:checked')].map((input) => input.value);
      const scheduledFor = String(form.get('scheduledFor') || '') || null;
      if (!selected.length) { window.showToast?.('Välj minst en ansvarig person.'); return; }
      if (scheduledFor && selected.length !== 1) { window.showToast?.('En syssla med en bestämd dag ska ha exakt en ansvarig.'); return; }
      const button = event.submitter; if (button) button.disabled = true;
      try {
        await call(client.rpc('admin_update_planned_weekly_chore', {
          p_chore_id: String(form.get('choreId')),
          p_title: String(form.get('title') || '').trim(),
          p_description: String(form.get('description') || '').trim(),
          p_xp: Number(form.get('xp')),
          p_tokens: Number(form.get('tokens')),
          p_difficulty: String(form.get('difficulty') || 'Lätt'),
          p_assignees: selected,
          p_scheduled_for: scheduledFor
        }));
        document.getElementById('modal-root').innerHTML = '';
        await refresh(); window.showToast?.('Den planerade sysslan har uppdaterats.');
      } catch (error) {
        const message = /admin_update_planned_weekly_chore|schema cache|could not find the function/i.test(error.message || '')
          ? 'Kör databasuppdateringen 20261122171418_edit_planned_weekly_chores.sql för att redigera planerade sysslor.'
          : error.message;
        window.showToast?.(message);
      } finally { if (button) button.disabled = false; }
      return;
    }
    if (event.target.id === 'admin-next-week-quest' && data.familyId) {
      event.preventDefault();
      event.stopImmediatePropagation();
      if (data.member.role !== 'admin' || !data.nextPlan || data.nextPlan.status !== 'open') return;
      const form = new FormData(event.target);
      const mode = String(form.get('scheduleMode') || 'count');
      const title = String(form.get('title') || '').trim();
      const common = {
        p_plan_id: data.nextPlan.id,
        p_title: title,
        p_description: String(form.get('detail') || '').trim(),
        p_xp: Number(form.get('xp')),
        p_tokens: Number(form.get('tokens')),
        p_difficulty: String(form.get('difficulty') || 'Lätt')
      };
      let assignees = [];
      let schedule = [];
      if (mode === 'count') {
        assignees = [...event.target.querySelectorAll('[name="assignees"]:checked')].map((el) => el.value);
        if (!assignees.length) { window.showToast?.('Välj minst en person som ska göra sysslan tillsammans.'); return; }
      } else {
        schedule = [...event.target.querySelectorAll('[data-weekday-row]')]
          .filter((row) => row.querySelector('[name="weekdays"]').checked)
          .map((row) => ({ day: Number(row.querySelector('[name="weekdays"]').value), user_id: row.querySelector('[name="weekdayAssignee"]').value }));
        if (!schedule.length) { window.showToast?.('Välj minst en dag och ansvarig person.'); return; }
        if (schedule.some((item) => !item.user_id)) { window.showToast?.('Välj en ansvarig för varje vald dag.'); return; }
      }
            const button = event.submitter;
      if (button) button.disabled = true;
      try {
        const count = mode === 'days'
          ? await call(client.rpc('add_assigned_weekly_chores', { ...common, p_schedule: schedule }))
          : await call(client.rpc('add_scheduled_weekly_chores', { ...common, p_assignees: assignees, p_frequency: Number(form.get('frequency')) }));
        await refresh();
        window.showToast?.(mode === 'days'
          ? `${count} dag${count === 1 ? '' : 'ar'} fördelad${count === 1 ? '' : 'e'} på familjen.`
          : `${count} syssla${count === 1 ? '' : 'or'} planerad${count === 1 ? '' : 'e'} för nästa vecka.`);
      } catch (error) {
        const message = /add_assigned_weekly_chores|add_scheduled_weekly_chores|schema cache|could not find the function/i.test(error.message || '')
          ? 'Kör databasuppdateringen 20261122162917_assign_weekly_chore_days.sql för att använda dagsfördelning.'
          : error.message;
        window.showToast?.(message);
      }
      finally { if (button) button.disabled = false; }
      return;
    }
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
    if (window.demoSandbox.active) return;
    if (!session) { data.familyId = null; data.member = null; if (realtimeChannel) client.removeChannel(realtimeChannel); document.querySelector('.app-shell').hidden = true; loginForm(); }
    else if (event === 'SIGNED_IN' && !data.familyId) setTimeout(() => { if (!data.familyId) bootstrapFamily().catch(errorMessage); }, 0);
  });
  document.querySelector('.app-shell').hidden = true;
  loginForm();
  bootstrapFamily().catch(errorMessage);
})();
