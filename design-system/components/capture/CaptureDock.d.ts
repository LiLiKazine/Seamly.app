export interface CaptureDockProps {
  onRecord?: ()=>void;
  onVideo?: ()=>void;
  onPhotos?: ()=>void;
  recording?: boolean;
  style?: React.CSSProperties;
}
export declare function CaptureDock(props: CaptureDockProps): JSX.Element;
