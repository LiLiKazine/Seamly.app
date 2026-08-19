export interface PositionScaleProps {
  heightPx?: number;
  viewportTopPct?: number;
  viewportPct?: number;
  marks?: Array<{atPct,kind,label}>;
  /** horizontal below --vp-short */
  orientation?: "vertical"|"horizontal";
  onScrub?: (pct:number)=>void;
  style?: React.CSSProperties;
}
export declare function PositionScale(props: PositionScaleProps): JSX.Element;
