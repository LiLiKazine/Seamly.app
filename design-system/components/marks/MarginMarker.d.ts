export interface MarginMarkerProps {
  /** ties the mark to its row in the queue */
  n?: number;
  kind?: "flagged"|"gap"|"confident";
  atPct?: number;
  selected?: boolean;
  style?: React.CSSProperties;
}
export declare function MarginMarker(props: MarginMarkerProps): JSX.Element;
