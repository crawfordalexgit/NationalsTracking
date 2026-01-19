(function(){
  // Lightweight date adapter shim to satisfy Chart.js adapter check and avoid CDN adapter fetch
  function installShim(){
    try{
      if (!window.Chart) return;
      window.Chart._adapters = window.Chart._adapters || {};
      if (!window.Chart._adapters._date) {
        window.Chart._adapters._date = {
          init: function() {},
          parse: function(value, _format) {
            if (value === null || value === undefined) return null;
            if (typeof value === 'number') { var d=new Date(value); return isNaN(d.getTime())?null:d; }
            if (value instanceof Date) return value;
            var s = (''+value).trim();
            // ISO / RFC
            var d = new Date(s);
            if (!isNaN(d.getTime())) return d;
            // dd/mm/yyyy fallback
            var m = s.match(/^(\d{1,2})\/(\d{1,2})\/(\d{2,4})$/);
            if (m) {
              var day = parseInt(m[1],10), mon = parseInt(m[2],10)-1, yr = parseInt(m[3],10);
              if (yr < 100) yr += 2000;
              var d2 = new Date(yr, mon, day);
              if (!isNaN(d2.getTime())) return d2;
            }
            return null;
          },
          format: function(date, fmt) { try { if (date === null || date === undefined) return ''; var d = (date instanceof Date) ? date : new Date(date); return d.toISOString(); } catch(e) { return '' } },
          add: function(date, amount, unit) { var d = new Date(date); if (unit === 'day') d.setDate(d.getDate() + amount); else if (unit === 'month') d.setMonth(d.getMonth() + amount); else if (unit === 'year') d.setFullYear(d.getFullYear() + amount); else d.setTime(d.getTime() + amount); return d; },
          startOf: function(date, unit, isoWeekday) { var d = new Date(date); if (unit === 'day') d.setHours(0,0,0,0); else if (unit === 'isoWeek') { var day = d.getDay(); var diff = (day + 6) % 7; d.setDate(d.getDate() - diff); d.setHours(0,0,0,0); } else if (unit === 'month') { d.setDate(1); d.setHours(0,0,0,0); } return d; }
        };
      }
    } catch(e){ /* ignore */ }
  }
  if (window.Chart) installShim(); else window.addEventListener('load', installShim);
})();
