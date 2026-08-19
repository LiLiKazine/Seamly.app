export interface CueCardProps {
  symbol?: string;
  /** before a session, or explaining it after */
  when?: "before"|"after";
  title?: string;
  body?: string;
  style?: React.CSSProperties;
}
export declare function CueCard(props: CueCardProps): JSX.Element;
