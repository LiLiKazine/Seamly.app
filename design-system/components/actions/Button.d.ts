export interface ButtonProps {
  /** filled is the one primary action */
  variant?: "filled"|"tonal"|"outline"|"plain"|"danger";
  /** 44pt floor at medium */
  size?: "small"|"medium"|"large";
  /** optional SF Symbol */
  symbol?: string;
  disabled?: boolean;
  style?: React.CSSProperties;
}
export declare function Button(props: ButtonProps): JSX.Element;
