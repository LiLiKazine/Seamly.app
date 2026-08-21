export interface AppIconProps {
  /** rendered edge length in px. The ladder that matters: 180/120/87/80/60/58/40/29 */
  size?: number;
  /** apply the iOS squircle (22.37% radius). The asset itself ships UNMASKED and full bleed */
  masked?: boolean;
  /** accessible name. Omitted renders the mark as decorative */
  title?: string;
  style?: React.CSSProperties;
}
export declare function AppIcon(props: AppIconProps): JSX.Element;
