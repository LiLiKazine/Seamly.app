export interface IconButtonProps {
  /** SF Symbol name */
  symbol?: string;
  /** accessible label, required */
  label?: string;
  /** renders a numeral, not a bare dot */
  count?: number;
  tone?: "ink"|"flag"|"gap"|"error";
  style?: React.CSSProperties;
}
export declare function IconButton(props: IconButtonProps): JSX.Element;
