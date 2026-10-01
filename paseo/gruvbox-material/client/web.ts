import { Platform } from "react-native";

// The only module allowed to touch DOM globals. Declare just what it uses.
declare const document: {
  head: { appendChild(node: unknown): void };
  createElement(tag: "style"): { textContent: string | null; remove(): void };
};

// Paseo renders markdown bold at weight 500, which is hard to tell from regular
// 400 text. On web and desktop, Paseo tags bold spans with this data attribute,
// so one stylesheet can make them weight 700. The text sits in inner spans that
// set their own weight, so the rule covers descendants too. This depends on
// Paseo's internal markup. If an update drops the attribute, bold goes back to
// Paseo's default.
const CSS =
  '[data-paseo-markdown-tag="strong"], [data-paseo-markdown-tag="strong"] * { font-weight: 700 !important; }';

// Adds the stylesheet and returns its remover. A no-op on native.
export function injectBoldStyle(): () => void {
  if (Platform.OS !== "web") return () => {};
  const style = document.createElement("style");
  style.textContent = CSS;
  document.head.appendChild(style);
  return () => style.remove();
}
