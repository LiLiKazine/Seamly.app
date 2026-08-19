export interface SeamMarkProps {
  kind?: "confident"|"flagged"|"gap";
  /** position down the sheet */
  atPct?: number;
  /** required for gap — always label what was lost */
  lostPx?: number;
  style?: React.CSSProperties;
}
export declare function SeamMark(props: SeamMarkProps): JSX.Element;
