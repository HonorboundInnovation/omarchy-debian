local active_border = {
  colors = { "rgba(b6ff2eee)", "rgba(245dffee)", "rgba(8f40eccc)" },
  angle = 45,
}
local inactive_border = "rgba(39445caa)"

hl.config({
  general = {
    gaps_in = 6,
    gaps_out = 12,
    border_size = 2,
    col = {
      active_border = active_border,
      inactive_border = inactive_border,
    },
  },
  group = {
    col = {
      border_active = active_border,
      border_inactive = inactive_border,
    },
  },
  decoration = {
    rounding = 8,
    shadow = {
      enabled = true,
      range = 10,
      render_power = 3,
      color = "rgba(2b105a77)",
      color_inactive = "rgba(06070b44)",
    },
  },
})
