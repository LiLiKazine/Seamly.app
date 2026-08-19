export interface CaptureListRowProps {
  title?: string;
  widthPx?: number;
  heightPx?: number;
  flaggedCount?: number;
  gapCount?: number;
  incomplete?: boolean;
  style?: React.CSSProperties;
}
export declare function CaptureListRow(props: CaptureListRowProps): JSX.Element;
