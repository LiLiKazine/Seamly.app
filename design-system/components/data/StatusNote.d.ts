export interface StatusNoteProps {
  kind?: "ready"|"processing"|"flagged"|"gap"|"incomplete"|"bars"|"failed";
  count?: number;
  /** overrides the default word */
  label?: string;
  size?: "small"|"medium";
  style?: React.CSSProperties;
}
export declare function StatusNote(props: StatusNoteProps): JSX.Element;
