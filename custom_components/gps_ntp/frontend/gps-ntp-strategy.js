/**
 * Dashboard strategy for GPS & NTP Home Bridge.
 *
 *   strategy:
 *     type: custom:gps-ntp
 *     cards: [status, peers, sky_plot]   # optional, default: every card that can render
 *     hours: 24                 # optional, time span of the history charts
 *     device_id: abc123         # optional, when more than one bridge is set up
 *
 * Works as a view strategy and as a dashboard strategy. Cards that need a
 * custom card library are left out when that library is not installed.
 */

const DOMAIN = "gps_ntp";

const LIBS = {
  apex: { tag: "apexcharts-card", name: "apexcharts-card" },
  plotly: { tag: "plotly-graph", name: "plotly-graph-card" },
  mini: { tag: "mini-graph-card", name: "mini-graph-card" },
};

const GREEN = "#2e9e5b";
const GREY = "#9aa0a6";
const GNSS_LETTERS = "{0:'G',1:'S',2:'E',3:'C',5:'J',6:'R',7:'I'}";

const heading = (text) => ({ type: "heading", heading: text });

const trendTile = (entity, name, hours) => ({
  type: "tile",
  entity,
  name,
  features: [{ type: "trend-graph", hours_to_show: hours }],
  grid_options: { columns: 6 },
});

const apexHeader = (title) => ({
  show: true,
  title,
  show_states: true,
  colorize_states: true,
});

// Each card: the section it lands in, the library it needs (if any) and a
// builder returning one or more Lovelace cards. `e` maps sensor keys to
// entity IDs, `h` is the chart span in hours.
const CARDS = {
  status: {
    section: "overview",
    build: (e, h) => [
      { type: "tile", entity: e.stratum, name: "Stratum", grid_options: { columns: 6 } },
      { type: "tile", entity: e.synced_peer, name: "Synced peer", grid_options: { columns: 6 } },
      trendTile(e.offset, "Offset", h),
      trendTile(e.sys_jitter, "System jitter", h),
      trendTile(e.used_satellites, "Satellites used", h),
      trendTile(e.hdop, "HDOP", h),
    ],
  },
  history: {
    section: "history",
    build: (e, h) => [
      {
        type: "history-graph",
        hours_to_show: h,
        entities: [
          { entity: e.offset, name: "Offset" },
          { entity: e.sys_jitter, name: "System jitter" },
          { entity: e.clk_jitter, name: "Clock jitter" },
        ],
      },
      {
        type: "history-graph",
        hours_to_show: h,
        entities: [
          { entity: e.used_satellites, name: "Used" },
          { entity: e.total_satellites, name: "Visible" },
        ],
      },
    ],
  },
  gauges: {
    section: "overview",
    build: (e) => [
      {
        type: "gauge",
        entity: e.satellite_ratio,
        name: "Used %",
        min: 0,
        max: 100,
        needle: true,
        severity: { red: 0, yellow: 15, green: 30 },
        grid_options: { columns: 4 },
      },
      {
        type: "gauge",
        entity: e.avg_signal_strength,
        name: "Signal",
        min: 0,
        max: 50,
        needle: true,
        severity: { red: 0, yellow: 20, green: 28 },
        grid_options: { columns: 4 },
      },
      {
        type: "gauge",
        entity: e.hdop,
        name: "HDOP",
        min: 0,
        max: 10,
        needle: true,
        severity: { green: 0, yellow: 2, red: 5 },
        grid_options: { columns: 4 },
      },
    ],
  },
  peers: {
    section: "overview",
    build: (e) => [
      {
        type: "markdown",
        content: [
          "| | Peer | St | Reach | Offset | Jitter |",
          "|:-:|:--|--:|--:|--:|--:|",
          `{% for p in state_attr('${e.synced_peer}', 'peers') or [] -%}`,
          "| {{ p.tally if p.tally | trim else '·' }} | {{ p.remote }} | {{ p.st }} | {{ p.reach_pct | round(0) | int }}% | {{ p.offset }} | {{ p.jitter }} |",
          "{% endfor %}",
        ].join("\n"),
      },
    ],
  },
  offset_jitter: {
    section: "ntp",
    lib: "apex",
    build: (e, h) => [
      {
        type: "custom:apexcharts-card",
        header: apexHeader("Offset and jitter"),
        graph_span: `${h}h`,
        yaxis: [
          { id: "offset", decimals: 3, apex_config: { title: { text: "offset ms" } } },
          {
            id: "jitter",
            opposite: true,
            decimals: 3,
            min: 0,
            apex_config: { title: { text: "jitter ms" } },
          },
        ],
        series: [
          { entity: e.offset, name: "Offset", yaxis_id: "offset", stroke_width: 2, float_precision: 4 },
          {
            entity: e.sys_jitter,
            name: "System jitter",
            yaxis_id: "jitter",
            type: "area",
            opacity: 0.25,
            stroke_width: 1,
            float_precision: 4,
          },
          {
            entity: e.clk_jitter,
            name: "Clock jitter",
            yaxis_id: "jitter",
            type: "area",
            opacity: 0.25,
            stroke_width: 1,
            float_precision: 4,
          },
        ],
      },
    ],
  },
  frequency_wander: {
    section: "ntp",
    lib: "apex",
    build: (e, h) => [
      {
        type: "custom:apexcharts-card",
        header: apexHeader("Frequency and wander"),
        graph_span: `${h}h`,
        yaxis: [
          { id: "freq", decimals: 3, apex_config: { title: { text: "frequency ppm" } } },
          {
            id: "wander",
            opposite: true,
            decimals: 4,
            min: 0,
            apex_config: { title: { text: "wander ppm" } },
          },
        ],
        series: [
          { entity: e.frequency, name: "Frequency", yaxis_id: "freq", stroke_width: 2, float_precision: 4 },
          { entity: e.clk_wander, name: "Wander", yaxis_id: "wander", stroke_width: 2, float_precision: 5 },
        ],
      },
    ],
  },
  constellations: {
    section: "gps",
    lib: "apex",
    build: (e) => [
      {
        type: "custom:apexcharts-card",
        header: { show: true, title: "Constellations" },
        chart_type: "donut",
        all_series_config: { show: { legend_value: false } },
        apex_config: { chart: { height: 260 }, legend: { position: "bottom" } },
        // The per-constellation counts are attributes of the signal sensor.
        series: [
          ["gps", "GPS"],
          ["glonass", "GLONASS"],
          ["galileo", "Galileo"],
          ["beidou", "BeiDou"],
          ["sbas", "SBAS"],
        ].map(([attribute, name]) => ({
          entity: e.avg_signal_strength,
          attribute,
          name,
          unit: "sats",
        })),
      },
    ],
  },
  satellites: {
    section: "gps",
    lib: "apex",
    build: (e, h) => [
      {
        type: "custom:apexcharts-card",
        header: apexHeader("Satellites used vs visible"),
        graph_span: `${h}h`,
        yaxis: [{ min: 0, decimals: 0 }],
        series: [
          {
            entity: e.total_satellites,
            name: "Visible",
            type: "area",
            curve: "stepline",
            opacity: 0.2,
            stroke_width: 1,
            color: GREY,
          },
          {
            entity: e.used_satellites,
            name: "Used",
            type: "area",
            curve: "stepline",
            opacity: 0.5,
            stroke_width: 2,
            color: GREEN,
          },
        ],
      },
    ],
  },
  hdop_signal: {
    section: "gps",
    lib: "apex",
    build: (e, h) => [
      {
        type: "custom:apexcharts-card",
        header: apexHeader("HDOP and signal"),
        graph_span: `${h}h`,
        yaxis: [
          { id: "hdop", min: 0, max: 5, decimals: 1, apex_config: { title: { text: "HDOP" } } },
          {
            id: "ss",
            opposite: true,
            min: 0,
            max: 50,
            decimals: 0,
            apex_config: { title: { text: "dBHz" } },
          },
        ],
        series: [
          { entity: e.hdop, name: "HDOP", yaxis_id: "hdop", stroke_width: 2 },
          { entity: e.avg_signal_strength, name: "Signal", yaxis_id: "ss", stroke_width: 2 },
        ],
      },
    ],
  },
  sky_plot: {
    section: "gps",
    lib: "plotly",
    build: (e) => {
      const sats = (filter) =>
        `(hass.states['${e.total_satellites}'].attributes.satellites || []).filter(s => s.el != null && ${filter})`;
      const trace = (name, color, letter, filter) => ({
        entity: e.total_satellites,
        name,
        r: `$ex ${sats(filter)}.map(s => s.el)`,
        theta: `$ex ${sats(filter)}.map(s => s.az)`,
        text: `$ex ${sats(filter)}.map(s => '${letter}' + s.svid)`,
        marker: {
          color,
          size: `$ex ${sats(filter)}.map(s => 6 + s.ss / 3)`,
          symbol: `$ex ${sats(filter)}.map(s => s.used ? 'circle' : 'circle-open')`,
        },
      });
      return [
        {
          type: "custom:plotly-graph",
          title: "Sky plot",
          hours_to_show: 1,
          refresh_interval: 15,
          defaults: {
            entity: {
              type: "scatterpolar",
              mode: "markers+text",
              textposition: "top center",
              textfont: { size: 9 },
            },
          },
          entities: [
            trace("GPS", "#1f77b4", "G", "s.gnssid === 0"),
            trace("GLONASS", "#d62728", "R", "s.gnssid === 6"),
            trace("Galileo", "#2ca02c", "E", "s.gnssid === 2"),
            trace("Other", "#9467bd", "S", "![0, 2, 6].includes(s.gnssid)"),
          ],
          layout: {
            height: 420,
            margin: { t: 30, b: 30, l: 30, r: 30 },
            polar: {
              bgcolor: "rgba(0,0,0,0)",
              // Elevation 90° (overhead) at the centre, horizon at the rim.
              radialaxis: { range: [90, 0], tickvals: [0, 30, 60], ticksuffix: "°", angle: 90 },
              angularaxis: {
                direction: "clockwise",
                rotation: 90,
                tickvals: [0, 45, 90, 135, 180, 225, 270, 315],
                ticktext: ["N", "NE", "E", "SE", "S", "SW", "W", "NW"],
              },
            },
            legend: { orientation: "h" },
          },
        },
      ];
    },
  },
  offset_histogram: {
    section: "ntp",
    lib: "plotly",
    build: (e, h) => [
      {
        type: "custom:plotly-graph",
        title: "Offset distribution",
        hours_to_show: h,
        entities: [{ entity: e.offset, name: "Offset", type: "histogram", x: "$ex ys", nbinsx: 30 }],
        layout: {
          height: 300,
          margin: { b: 60 },
          xaxis: { title: { text: "offset ms" }, type: "linear", autorange: true },
          yaxis: { title: { text: "samples" } },
          showlegend: false,
        },
      },
    ],
  },
  peer_scatter: {
    section: "ntp",
    lib: "plotly",
    build: (e) => {
      const peers = `(hass.states['${e.synced_peer}'].attributes.peers || [])`;
      return [
        {
          type: "custom:plotly-graph",
          title: "Peers delay vs offset",
          hours_to_show: 1,
          refresh_interval: 60,
          entities: [
            {
              entity: e.synced_peer,
              name: "Peers",
              type: "scatter",
              mode: "markers+text",
              textposition: "top center",
              x: `$ex ${peers}.map(p => p.delay)`,
              y: `$ex ${peers}.map(p => p.offset)`,
              text: `$ex ${peers}.map(p => (p.tally.trim() || '·') + ' ' + p.remote)`,
              marker: {
                size: `$ex ${peers}.map(p => 8 + p.jitter * 3)`,
                color: `$ex ${peers}.map(p => p.tally === '*' ? '${GREEN}' : p.tally === '+' ? '#1f77b4' : '${GREY}')`,
              },
            },
          ],
          layout: {
            height: 320,
            margin: { b: 60 },
            xaxis: { title: { text: "delay ms" }, type: "linear", autorange: true },
            yaxis: { title: { text: "offset ms" } },
            showlegend: false,
          },
        },
      ];
    },
  },
  offset_zoom: {
    section: "ntp",
    lib: "plotly",
    build: (e, h) => [
      {
        type: "custom:plotly-graph",
        title: "Offset and jitter (zoomable)",
        hours_to_show: h,
        entities: [
          { entity: e.offset, name: "Offset" },
          { entity: e.sys_jitter, name: "System jitter" },
          { entity: e.clk_jitter, name: "Clock jitter" },
        ],
        layout: { height: 300, legend: { orientation: "h" } },
      },
    ],
  },
  satellite_signal: {
    section: "gps",
    lib: "plotly",
    build: (e) => {
      const sats = `(hass.states['${e.total_satellites}'].attributes.satellites || [])`;
      return [
        {
          type: "custom:plotly-graph",
          title: "Signal per satellite",
          hours_to_show: 1,
          refresh_interval: 15,
          entities: [
            {
              entity: e.total_satellites,
              name: "Signal",
              type: "bar",
              x: `$ex ${sats}.map(s => ((${GNSS_LETTERS})[s.gnssid] || '?') + s.svid)`,
              y: `$ex ${sats}.map(s => s.ss)`,
              marker: { color: `$ex ${sats}.map(s => s.used ? '${GREEN}' : '#b0b5ba')` },
            },
          ],
          layout: {
            height: 300,
            margin: { b: 60 },
            xaxis: { type: "category", tickangle: -90, tickfont: { size: 9 }, autorange: true },
            yaxis: { title: { text: "dBHz" }, range: [0, 50], autorange: false },
            showlegend: false,
          },
        },
      ];
    },
  },
  sparklines: {
    section: "history",
    lib: "mini",
    build: (e, h) => {
      const spark = (entity, name, extra = {}) => ({
        type: "custom:mini-graph-card",
        name,
        hours_to_show: h,
        points_per_hour: h > 6 ? 4 : 60,
        line_width: 2,
        entities: [entity],
        ...extra,
      });
      return [
        spark(e.offset, "Offset", { decimals: 4, grid_options: { columns: 6 } }),
        spark(e.sys_jitter, "System jitter", { decimals: 4, grid_options: { columns: 6 } }),
        spark(e.used_satellites, "Satellites", {
          show: { legend: true, fill: "fade" },
          entities: [
            { entity: e.used_satellites, name: "Used" },
            { entity: e.total_satellites, name: "Visible" },
          ],
        }),
        spark(e.hdop, "HDOP", {
          upper_bound: 5,
          lower_bound: 0,
          color_thresholds: [
            { value: 0, color: GREEN },
            { value: 2, color: "#e0a800" },
            { value: 4, color: "#d62728" },
          ],
        }),
      ];
    },
  },
};

const SECTIONS = [
  ["overview", "Overview"],
  ["ntp", "NTP"],
  ["gps", "GPS"],
  ["history", "History"],
];

const note = (content) => ({ type: "markdown", content });

/** Custom cards register asynchronously, so give them a moment to appear. */
async function libraryInstalled(tag) {
  if (customElements.get(tag)) return true;
  const timeout = new Promise((resolve) => setTimeout(resolve, 3000));
  await Promise.race([customElements.whenDefined(tag), timeout]);
  return Boolean(customElements.get(tag));
}

/** Map each sensor key (offset, hdop, ...) to its entity ID for one bridge. */
async function bridgeEntities(hass, deviceId) {
  const registry = await hass.callWS({ type: "config/entity_registry/list" });
  const ours = registry.filter((entry) => entry.platform === DOMAIN && entry.device_id);
  const device = deviceId || (ours[0] && ours[0].device_id);
  const entities = {};
  for (const entry of ours) {
    if (entry.device_id !== device) continue;
    // unique_id is "<config entry id>_<sensor key>"
    const prefix = `${entry.config_entry_id}_`;
    if (entry.unique_id.startsWith(prefix)) {
      entities[entry.unique_id.slice(prefix.length)] = entry.entity_id;
    }
  }
  return entities;
}

async function generateSections(config, hass) {
  const entities = await bridgeEntities(hass, config.device_id);
  if (!Object.keys(entities).length) {
    return [
      {
        type: "grid",
        cards: [note("No GPS & NTP Home Bridge device found. Add the integration first.")],
      },
    ];
  }

  const hours = Number(config.hours) > 0 ? Number(config.hours) : 24;
  const requested = (config.cards || Object.keys(CARDS)).map((id) => String(id).toLowerCase());
  const installed = {};
  for (const [key, lib] of Object.entries(LIBS)) {
    installed[key] = await libraryInstalled(lib.tag);
  }

  const bySection = {};
  const problems = [];
  for (const id of requested) {
    const card = CARDS[id];
    if (!card) {
      problems.push(`\`${id}\` is not a known card`);
      continue;
    }
    if (card.lib && !installed[card.lib]) {
      // Only complain about cards the user asked for by name.
      if (config.cards) problems.push(`\`${id}\` needs ${LIBS[card.lib].name}`);
      continue;
    }
    (bySection[card.section] = bySection[card.section] || []).push(...card.build(entities, hours));
  }

  const sections = SECTIONS.filter(([key]) => bySection[key]).map(([key, title]) => ({
    type: "grid",
    cards: [heading(title), ...bySection[key]],
  }));
  if (problems.length) {
    sections.push({
      type: "grid",
      cards: [note(`**Cards left out**\n\n${problems.map((p) => `- ${p}`).join("\n")}`)],
    });
  }
  return sections;
}

class GpsNtpViewStrategy extends HTMLElement {
  static async generate(config, hass) {
    return {
      type: "sections",
      max_columns: 4,
      sections: await generateSections(config, hass),
    };
  }
}

class GpsNtpDashboardStrategy extends HTMLElement {
  static async generate(config) {
    return {
      title: "GPS & NTP",
      views: [
        {
          title: "GPS & NTP",
          path: "gps-ntp",
          icon: "mdi:satellite-variant",
          strategy: { ...config, type: "custom:gps-ntp" },
        },
      ],
    };
  }
}

if (!customElements.get("ll-strategy-view-gps-ntp")) {
  customElements.define("ll-strategy-view-gps-ntp", GpsNtpViewStrategy);
}
if (!customElements.get("ll-strategy-dashboard-gps-ntp")) {
  customElements.define("ll-strategy-dashboard-gps-ntp", GpsNtpDashboardStrategy);
}
