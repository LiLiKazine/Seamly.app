export interface QueuePromptProps {
  index?: number;
  total?: number;
  kind?: "flagged"|"gap";
  question?: string;
  detail?: string;
  /** current dy */
  value?: number;
  onNudge?: (dir:-1|1)=>void;
  onAccept?: ()=>void;
  onSkipAll?: ()=>void;
  style?: React.CSSProperties;
}
export declare function QueuePrompt(props: QueuePromptProps): JSX.Element;
