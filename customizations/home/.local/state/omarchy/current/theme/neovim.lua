return {
  {
    "bjarneo/aether.nvim",
    branch = "v3",
    name = "aether",
    priority = 1000,
    opts = {
      colors = {
        bg = "#080a12",
        dark_bg = "#06070b",
        darker_bg = "#030409",
        lighter_bg = "#151b2b",

        fg = "#d8e4ef",
        dark_fg = "#8795ab",
        light_fg = "#ecf5ff",
        bright_fg = "#ffffff",
        muted = "#59647b",

        red = "#ff668c",
        yellow = "#ecdc70",
        orange = "#ff9b62",
        green = "#b6ff2e",
        cyan = "#65e7ef",
        blue = "#527cff",
        magenta = "#a875ef",
        brown = "#987b9d",

        bright_red = "#ff8eab",
        bright_yellow = "#fff19a",
        bright_green = "#d3ff7b",
        bright_cyan = "#9efaff",
        bright_blue = "#8ba5ff",
        bright_magenta = "#cca5ff",

        accent = "#b6ff2e",
        cursor = "#ffffff",
        foreground = "#d8e4ef",
        background = "#080a12",
        selection = "#25334b",
        selection_foreground = "#ffffff",
        selection_background = "#25334b",
      },
    },
  },
  {
    "LazyVim/LazyVim",
    opts = {
      colorscheme = "aether",
    },
  },
}
