export interface ProgressNoteProps {
  label?: string;
  /** 0–1; omit for indeterminate */
  value?: number;
  style?: React.CSSProperties;
}
export declare function ProgressNote(props: ProgressNoteProps): JSX.Element;
