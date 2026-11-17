(() => {
  const date = new Date();
  const month = date.getMonth();
  const day = date.getDate();
  const themes = {
    spring: { key: 'spring', name: 'Vårsagan', icon: '🌷', label: 'VÅRENS SAGA', hue: '#f4cf5e' },
    summer: { key: 'summer', name: 'Sommarsagan', icon: '☀️', label: 'SOMMARENS SAGA', hue: '#69bde9' },
    autumn: { key: 'autumn', name: 'Höstsagan', icon: '🍂', label: 'HÖSTENS SAGA', hue: '#9a6741' },
    winter: { key: 'winter', name: 'Vintersagan', icon: '❄️', label: 'VINTERNS SAGA', hue: '#6687a0' },
    christmas: { key: 'christmas', name: 'Juläventyret', icon: '🎄', label: 'JULÄVENTYRET', hue: '#a83639' }
  };
  let active = month >= 2 && month <= 4 ? themes.spring : month >= 5 && month <= 7 ? themes.summer : month >= 8 && month <= 10 ? themes.autumn : themes.winter;
  const isChristmas = month === 11 && day >= 18 && day <= 26;
  if (isChristmas) active = themes.christmas;
  window.activeSeason = active;

  function remainingDays() {
    if (isChristmas) return 27 - day;
    const seasonEndMonth = active.key === 'spring' ? 4 : active.key === 'summer' ? 7 : active.key === 'autumn' ? 10 : 1;
    const endYear = active.key === 'winter' && month === 11 ? date.getFullYear() + 1 : date.getFullYear();
    const lastDay = new Date(endYear, seasonEndMonth + 1, 0);
    return Math.max(0, Math.ceil((lastDay - date) / 86400000) + 1);
  }
  window.applySeasonLabels = () => {
    document.documentElement.dataset.season = active.key;
    const themeColor = document.querySelector('meta[name="theme-color"]');
    if (themeColor) themeColor.content = active.hue;
    const miniTitle = document.getElementById('season-mini-title');
    const miniIcon = document.getElementById('season-mini-icon');
    const days = document.getElementById('season-days-left');
    const heroDays = document.getElementById('hero-days-left');
    const hero = document.getElementById('hero-season-label');
    const dateLabel = document.getElementById('current-date');
    if (miniTitle) miniTitle.textContent = active.name;
    if (miniIcon) miniIcon.textContent = active.icon;
    if (days) days.textContent = `${remainingDays()} dagar kvar`;
    if (heroDays) heroDays.textContent = remainingDays();
    if (hero) hero.textContent = `${active.icon} ${active.label}`;
    if (dateLabel) dateLabel.textContent = new Intl.DateTimeFormat('sv-SE', { weekday: 'long', day: 'numeric', month: 'long' }).format(date).toLocaleUpperCase('sv-SE');
  };
})();
