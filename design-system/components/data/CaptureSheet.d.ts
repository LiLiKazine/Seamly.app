export interface CaptureSheetProps {
  image?: string;
  /** the whole capture squeezed, showing length */
  ribbon?: boolean;
  /** ticks on the ribbon */
  marks?: Array<{atPct,kind}>;
  style?: React.CSSProperties;
}
export declare function CaptureSheet(props: CaptureSheetProps): JSX.Element;
