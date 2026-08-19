export interface IconProps {
  /** SF Symbol name the Swift source uses */
  name?: string;
  /** px; tracks adjacent text size */
  size?: number;
  /** 1.6 default */
  strokeWidth?: number;
  style?: React.CSSProperties;
}
export declare function Icon(props: IconProps): JSX.Element;
