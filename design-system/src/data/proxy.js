/* Stand-in for captured content in mocks. Reads as body text at any scale.
   Replace with real screenshots before showing work externally. */
export const PROXY_PATTERN =
  "repeating-linear-gradient(180deg,#fff 0 11px,#b9c3d0 11px 16px,#fff 16px 30px," +
  "#c8d1dc 30px 35px,#fff 35px 58px,#e6ebf1 58px 96px)";
export const PROXY_PATTERN_DENSE =
  "repeating-linear-gradient(180deg,#fff 0 4px,#c8d1dc 4px 6px,#fff 6px 12px,#e6ebf1 12px 20px)";

/* Thin space, never a comma — a comma reads as a decimal in half the world. */
export const px = (n) => String(n).replace(/\B(?=(\d{3})+(?!\d))/g, " ");
