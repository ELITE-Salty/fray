// Progressive enhancement only. Timing and persistence are always server-side.
function updateTimers() {
  document.querySelectorAll('[data-timer]').forEach(el => {
    const seconds = Math.max(0, Math.floor((Date.now() - Date.parse(el.dataset.timer)) / 1000));
    el.textContent = `${Math.floor(seconds / 3600)}:${String(Math.floor(seconds / 60) % 60).padStart(2, '0')}:${String(seconds % 60).padStart(2, '0')} elapsed`;
  });
}
updateTimers();
setInterval(updateTimers, 1000);
// Only show fields relevant to the selected entry mode. No data fabrication.
const mode = document.getElementById('id_mode');
if (mode) {
  const update = () => {
    ['local_date', 'minutes', 'started_at', 'ended_at'].forEach(name => {
      const field = document.getElementById(`id_${name}`);
      if (field) field.closest('p').hidden = (['local_date', 'minutes'].includes(name)) !== (mode.value === 'duration');
    });
  };
  mode.addEventListener('change', update);
  update();
}
