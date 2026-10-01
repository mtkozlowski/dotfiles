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
      foreground: "#d4be98", // fg0
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

  const removeBoldStyle = injectBoldStyle();

  return () => {
    removeDark();
    removeLight();
    removeBoldStyle();
  };
}
