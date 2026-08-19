export interface CaptureGridCardProps {
  title?: string;
  heightPx?: number;
  marks?: Array<{atPct,kind}>;
  selected?: boolean;
  style?: React.CSSProperties;
}
export declare function CaptureGridCard(props: CaptureGridCardProps): JSX.Element;
