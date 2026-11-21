/* Ícones em traço: viewBox 0 0 24 24, stroke=currentColor, stroke-width 1.7.
   Os 12 primeiros de FAMILY vêm do kit de identidade (interface/icone_*.svg);
   os 12 seguintes foram desenhados para o protótipo no mesmo traço. */
(function () {
  'use strict';
  var RBC = window.RBC;
  var FAMILY = {
    // do kit de identidade
    agroecology: '<path d="M12 21V11M12 15C5 15 3 10 4 5c5 0 8 3 8 8M12 11c0-5 3-7 8-7 0 5-3 8-8 8M5 22h14"/>',
    autonomous_spaces: '<path d="M3 11 12 3l9 8M5 10v11h14V10M9 21v-7h6v7"/>',
    books_libraries: '<path d="M3 5c4-1 6 0 9 2 3-2 5-3 9-2v14c-4-1-6 0-9 2-3-2-5-3-9-2zM12 7v14"/>',
    community_connectivity: '<circle cx="12" cy="12" r="3"/><circle cx="3" cy="3" r="2"/><circle cx="21" cy="3" r="2"/><circle cx="3" cy="21" r="2"/><circle cx="21" cy="21" r="2"/><path d="m5 5 5 5m4 4 5 5M5 19l5-5m4-4 5-5"/>',
    consumer_coops: '<path d="m3 8 3 12h12l3-12zM7 8l5-6 5 6M9 11v6M15 11v6M2 8h20"/>',
    ecology_land: '<path d="M3 21 9 9l4 7 3-5 5 10zM7 5h4M9 3v4M4 21h16"/>',
    food_solidarity: '<path d="M3 12h18c0 7-4 9-9 9s-9-2-9-9ZM6 8c-3-3 3-3 0-6M12 8c-3-3 3-3 0-6M18 8c-3-3 3-3 0-6"/>',
    independent_media: '<rect x="3" y="9" width="18" height="12" rx="2"/><path d="M4 9 18 3M6 13h7M6 17h7"/><circle cx="17" cy="15" r="2"/>',
    libraries_things: '<path d="M3 7h18v14H3zM3 12h18M7 7V3h10v4M8 16h8M8 19h8"/>',
    mutual_aid: '<circle cx="8" cy="7" r="3"/><circle cx="17" cy="8" r="2.5"/><path d="M2 21v-3c0-4 12-4 12 0v3M15 15c5-1 7 1 7 4v2"/>',
    repair_reuse: '<path d="m4 20 9-9M14 4a6 6 0 0 0-3 7l2 2a6 6 0 0 0 7-3l-5 1-2-2zM4 17l3 3M3 21l1-1"/>',
    shared_mobility: '<circle cx="5" cy="17" r="4"/><circle cx="19" cy="17" r="4"/><path d="m5 17 5-9 5 9H5M15 17l3-11h3M8 8h5"/>',
    // desenhados para o protótipo, no mesmo traço
    publishing_print: '<path d="M6 3h9l4 4v14H6zM15 3v4h4M9 11h7M9 14.5h7M9 18h4M3 7v14"/>',
    worker_coops: '<circle cx="12" cy="12" r="3"/><circle cx="12" cy="12" r="7"/><path d="M12 2v3M12 19v3M2 12h3M19 12h3M4.9 4.9 7 7M17 17l2.1 2.1M4.9 19.1 7 17M17 7l2.1-2.1"/>',
    housing_communities: '<path d="M2 12 8 7l6 5M4 11v10h8V11M12 9l4-3 6 5M16 21h4V10M7 21v-5h2v5"/>',
    gift_exchange: '<path d="M3 9h18v4H3zM5 13v8h14v-8M12 9v12M12 9C10 3 4 5 7.5 9M12 9c2-6 8-4 4.5 0"/>',
    health_care: '<path d="M12 20.5S4 15.5 4 9a4.5 4.5 0 0 1 8-2.8A4.5 4.5 0 0 1 20 9c0 6.5-8 11.5-8 11.5ZM12 9.5v5M9.5 12h5"/>',
    free_education: '<path d="m4 20 1-5L16 4l4 4L9 19zM14 6l4 4M5 15l4 4M13 21h8"/>',
    arts_culture: '<path d="M9 18V5l11-2v13"/><circle cx="6" cy="18" r="3"/><circle cx="17" cy="16" r="3"/><path d="M9 9l11-2"/>',
    commons_infrastructure: '<path d="M12 2.5c4 5 6.5 8.5 6.5 12a6.5 6.5 0 0 1-13 0c0-3.5 2.5-7 6.5-12ZM13 9l-3 4.5h4L11 18"/>',
    digital_commons: '<rect x="3" y="4" width="18" height="16" rx="2"/><path d="M3 8.5h18M9 12l-2.5 2.5L9 17M15 12l2.5 2.5L15 17M13 11.5l-2 6"/>',
    solidarity_finance: '<circle cx="12" cy="12" r="3"/><path d="M4 12a8 8 0 0 1 14-5.3M20 12a8 8 0 0 1-14 5.3M18.5 3v4h-4M5.5 21v-4h4"/>',
    conflict_care: '<path d="M3 4h11v8H8l-3 3v-3H3zM10 15v1h6l3 3v-3h2V8h-4"/>',
    labour_organising: '<path d="M3 10v4h3l8 4V6l-8 4zM17 9a4 4 0 0 1 0 6M19.5 6.5a8 8 0 0 1 0 11M7 14l1 6h3l-1-4.5"/>'
  };
  var UI = {
    search: '<circle cx="11" cy="11" r="7"/><path d="m20 20-4-4"/>',
    map: '<path d="M3 6.5 9 4l6 2.5L21 4v13.5L15 20l-6-2.5L3 20zM9 4v13.5M15 6.5V20"/>',
    list: '<path d="M8 6h12M8 12h12M8 18h12"/><circle cx="4" cy="6" r="1"/><circle cx="4" cy="12" r="1"/><circle cx="4" cy="18" r="1"/>',
    filter: '<path d="M3 5h18l-7 8.5V20l-4-2v-4.5z"/>',
    close: '<path d="M5 5l14 14M19 5 5 19"/>',
    menu: '<path d="M3 6h18M3 12h18M3 18h18"/>',
    'chev-right': '<path d="m9 5 7 7-7 7"/>',
    'chev-left': '<path d="m15 5-7 7 7 7"/>',
    'chev-down': '<path d="m5 9 7 7 7-7"/>',
    'arrow-right': '<path d="M4 12h16M14 6l6 6-6 6"/>',
    'arrow-left': '<path d="M20 12H4M10 6l-6 6 6 6"/>',
    globe: '<circle cx="12" cy="12" r="9"/><path d="M3 12h18M12 3c3 3 3 15 0 18M12 3c-3 3-3 15 0 18"/>',
    pin: '<path d="M12 21.5s-7-6.5-7-12a7 7 0 0 1 14 0c0 5.5-7 12-7 12Z"/><circle cx="12" cy="9.5" r="2.5"/>',
    ring: '<circle cx="12" cy="12" r="8.5" stroke-dasharray="3.2 2.6"/><circle cx="12" cy="12" r="1.2"/>',
    region: '<path d="M4 8c2-4 7-5 10-3s6 2 6 6-2 8-6 9-8-1-10-4-1-6 0-8Z" stroke-dasharray="3.2 2.6"/><path d="M8 10l6 6M11 8l5 5M7 13l4 4"/>',
    nomap: '<path d="M12 21.5s-7-6.5-7-12a7 7 0 0 1 14 0c0 5.5-7 12-7 12Z"/><path d="M4 3l16 18"/>',
    check: '<path d="m4 12.5 5 5L20 6.5"/>',
    'check-circle': '<circle cx="12" cy="12" r="9"/><path d="m7.5 12.5 3 3 6-6.5"/>',
    alert: '<path d="M12 3 2 20.5h20zM12 10v5M12 17.8v.2"/>',
    info: '<circle cx="12" cy="12" r="9"/><path d="M12 11v6M12 7.3v.2"/>',
    clock: '<circle cx="12" cy="12" r="9"/><path d="M12 7v5l3.5 2"/>',
    eye: '<path d="M2 12s3.5-7 10-7 10 7 10 7-3.5 7-10 7S2 12 2 12Z"/><circle cx="12" cy="12" r="3"/>',
    'eye-off': '<path d="M4 4l16 16M9.5 5.4A9.5 9.5 0 0 1 12 5c6.5 0 10 7 10 7a17 17 0 0 1-3.2 4M6.3 6.8C3.5 8.8 2 12 2 12s3.5 7 10 7c1.6 0 3-.4 4.3-1M10 10a3 3 0 0 0 4 4"/>',
    archive: '<path d="M3 4h18v5H3zM5 9v11h14V9M9.5 13h5"/>',
    user: '<circle cx="12" cy="8" r="4"/><path d="M4 21c0-5 4-7 8-7s8 2 8 7"/>',
    shield: '<path d="M12 3 4 6v6c0 5 3.5 8 8 9.5 4.5-1.5 8-4.5 8-9.5V6z"/>',
    edit: '<path d="m4 20 1-5L16 4l4 4L9 19zM14 6l4 4"/>',
    lock: '<rect x="5" y="11" width="14" height="10" rx="2"/><path d="M8 11V8a4 4 0 0 1 8 0v3"/>',
    send: '<path d="M21 3 3 10.5l7 3 3 7zM10 13.5 21 3"/>',
    sprout: '<path d="M12 21v-9M12 14C6 14 4 10 5 6c4 0 7 2 7 6M12 12c0-4 3-6 7-6 0 4-2 7-7 7"/>',
    flag: '<path d="M5 21V4M5 4c5-2 7 2 14 0v9c-7 2-9-2-14 0"/>',
    hourglass: '<path d="M6 3h12M6 21h12M7 3c0 5 5 6 5 9s-5 4-5 9M17 3c0 5-5 6-5 9s5 4 5 9"/>',
    refresh: '<path d="M20 12a8 8 0 1 1-2.5-5.8M20 4v5h-5"/>',
    trash: '<path d="M4 7h16M9 7V4h6v3M6 7l1 13h10l1-13M10 11v5M14 11v5"/>',
    plus: '<path d="M12 5v14M5 12h14"/>',
    source: '<path d="M5 3h10l4 4v14H5zM15 3v4h4M8.5 12h7M8.5 16h7"/>',
    translate: '<path d="M3 5h9M7.5 3v2M10.5 5c-.8 4-3.5 7-7 8.5M5.5 9c1.3 2.2 3.2 3.7 5.5 4.5M12 21l4.5-10L21 21M13.8 17.5h5.4"/>',
    key: '<circle cx="8" cy="15" r="4"/><path d="m11 12 9-9M16 7l3 3M14 9l2 2"/>',
    calendar: '<rect x="3" y="5" width="18" height="16" rx="2"/><path d="M3 10h18M8 3v4M16 3v4"/>',
    link: '<path d="M10 14a4.5 4.5 0 0 0 6.4 0l3-3a4.5 4.5 0 0 0-6.4-6.4L12 5.6M14 10a4.5 4.5 0 0 0-6.4 0l-3 3a4.5 4.5 0 0 0 6.4 6.4l1-1"/>',
    offer: '<path d="M3 15c3-2 5-2 7 0h4a2 2 0 0 1 0 4h-4M3 21h8l9-4a1.8 1.8 0 0 0-1.5-3.2L14 15M12 3c3 2 3 5 0 7-3-2-3-5 0-7Z"/>',
    need: '<path d="M12 21a9 9 0 1 1 9-9M12 7v5l3 2M17 17l4 4M21 17l-4 4" />',
    locate: '<circle cx="12" cy="12" r="6"/><circle cx="12" cy="12" r="1.5"/><path d="M12 2v4M12 18v4M2 12h4M18 12h4"/>',
    people: '<circle cx="12" cy="6" r="2.5"/><circle cx="5" cy="14" r="2.5"/><circle cx="19" cy="14" r="2.5"/><path d="M12 8.5v4M10.5 13.5 7 14.5M13.5 13.5l3.5 1M5 16.5V21M19 16.5V21M12 12.5V21"/>',
    stamp: '<path d="M9 13c0-2-2-3-2-6a5 5 0 0 1 10 0c0 3-2 4-2 6M5 13h14v4H5zM4 21h16"/>',
    doc: '<path d="M6 3h9l4 4v14H6zM15 3v4h4"/>',
    wand: '<path d="m4 20 11-11M13 5l1.5 1.5M17 3v2M21 7h-2M18.5 9.5 20 11M17 13v2"/>',
    scale: '<path d="M12 4v16M6 20h12M4 7h16M4 7l-2 6a3 3 0 0 0 6 0L6 7M18 7l-2 6a3 3 0 0 0 6 0l-2-6"/>',
    coin: '<circle cx="12" cy="12" r="9"/><path d="M15 9.5c-.5-1-1.6-1.5-3-1.5-1.7 0-3 .8-3 2s1 1.7 3 2 3 .8 3 2-1.3 2-3 2c-1.4 0-2.5-.5-3-1.5M12 6v12"/>',
    letter: '<rect x="3" y="5" width="18" height="14" rx="2"/><path d="m3 7 9 6.5L21 7"/>',
    compass: '<circle cx="12" cy="12" r="9"/><path d="m15.5 8.5-2 5-5 2 2-5z"/>'
  };
  RBC.ICONS = { family: FAMILY, ui: UI };
  RBC.icon = function (name, cls) {
    var body = UI[name] || FAMILY[name] || UI.info;
    return '<svg class="ic' + (cls ? ' ' + cls : '') + '" viewBox="0 0 24 24" width="24" height="24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true" focusable="false">' + body + '</svg>';
  };
})();
