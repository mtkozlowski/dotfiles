import type { PluginClientContext } from "@getpaseo/plugin/client";

import { injectBoldStyle } from "./client/web";

// Gruvbox Material with the "medium" background and "material" foreground,
// the same variant nvim uses. Colors come from sainnhe/gruvbox-material's
// gruvbox_material#get_palette().
export default function contribute(client: PluginClientContext) {
  const removeDark = client.addTheme({
    id: "dark",
    name: "Gruvbox Material Dark",
    appearance: "dark",
    colors: {
      background: "#282828", // bg0
      foreground: "#DBCCB3", // fg0
      raised: "#32302f", // bg1
      control: "#45403d", // bg3
      border: "#5a524c", // bg5
      accent: "#a9b665", // green
      mutedForeground: "#a89984", // grey2
      ring: "#7c6f64", // grey0
    },
  });

  const removeLight = client.addTheme({
    id: "light",
    name: "Gruvbox Material Light",
    appearance: "light",
    colors: {
      background: "#fbf1c7", // bg0
      foreground: "#654735", // fg0
      raised: "#f4e8be", // bg1
      control: "#e5d5ad", // bg4
      border: "#ddccab", // bg5
      accent: "#6c782e", // green
      mutedForeground: "#7c6f64", // grey2
      ring: "#a89984", // grey0
    },
  });

  // Rosé Pine Dawn, the light theme Ghostty uses. Colors come from Ghostty's
  // bundled "Rose Pine Dawn" theme and the Rosé Pine palette names.
  const removeRosePineDawn = client.addTheme({
    id: "rose-pine-dawn",
    name: "Rosé Pine Dawn",
    appearance: "light",
    colors: {
      background: "#faf4ed", // base
      foreground: "#575279", // text
      raised: "#fffaf3", // surface
      control: "#f2e9e1", // overlay
      border: "#dfdad9", // highlight med
      accent: "#286983", // pine
      mutedForeground: "#797593", // subtle
      ring: "#9893a5", // muted
    },
  });

  const removeBoldStyle = injectBoldStyle();

  return () => {
    removeDark();
    removeLight();
    removeRosePineDawn();
    removeBoldStyle();
  };
}
