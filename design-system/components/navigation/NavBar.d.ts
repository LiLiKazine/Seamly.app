export interface NavBarProps {
  title?: string;
  /** mono, tabular — dimensions go here */
  subtitle?: string;
  /** large-title variant */
  large?: boolean;
  backLabel?: string;
  /** sits on a protection gradient over a capture */
  over?: boolean;
  style?: React.CSSProperties;
}
export declare function NavBar(props: NavBarProps): JSX.Element;
